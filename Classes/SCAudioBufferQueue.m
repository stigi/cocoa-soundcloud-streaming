/*
 * Copyright 2009 Ullrich Schäfer for SoundCloud Ltd.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not
 * use this file except in compliance with the License. You may obtain a copy of
 * the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 * 
 */


#import "SCAudioBufferQueue.h"

#import "SCAudioStreamPacketDescriptions.h"


#define kBuffersFilledRunningLow	50
#define kBuffersFilledEnoughToPlay	(2 * kBuffersFilledRunningLow)
#define kBuffersFilledMax			300


NSString * const SCAudioBufferPlayStateChangedNotification = @"SCAudioBufferPlayStateChangedNotification";
NSString * const SCAudioBufferBufferStateChangedNotification = @"SCAudioBufferBufferStateChangedNotification";


@interface SCAudioBufferQueue (Private)
- (void)_invokeSelectorOnDelegate:(SEL)selector withObject:(id)object waitUntilDone:(BOOL)waitUntilDone;
- (void)_postNotificationOnDelegateThread:(NSNotification *)notification;
- (void)_updateInternalBufferState;

- (void)_doRequestMoreData;
- (void)_doStop;
- (void)_doPlay;
- (void)_doPlayWhenReady;
- (void)_doPause:(BOOL)playWhenReadyAgain;
@end


@interface SCAudioBufferQueue (AudioToolboxHooks)
- (void)audioQueue:(AudioQueueRef)inAudioQueue
   propertyChanged:(AudioFileStreamPropertyID)propertyID;

- (void)audioQueueReadyToReuseBuffer;

- (void)audioSessionRouteChangedWithChangeDict:(NSDictionary *)routeChangeDictionary;
@end



// Called from the AudioQueue when playback of specific buffers completes. This
// function signals from the AudioQueue thread to the AudioStream thread that
// the buffer is ready to be reused.
void SCAudioQueueOutputCallback(void* clientData, 
								AudioQueueRef inAudioQueue, 
								AudioQueueBufferRef buffer)
{
	AudioQueueFreeBuffer(inAudioQueue, buffer);
	@synchronized(clientData) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		SCAudioBufferQueue *queue = (SCAudioBufferQueue *)clientData;
		[queue retain];
		[queue audioQueueReadyToReuseBuffer];
		[queue release];
		[pool release];
	}
}

// invoked by the audio queue whenever one of its properties change
void SCQueuePropertyListenerProc(void *clientData,
								 AudioQueueRef inAudioQueue,
								 AudioQueuePropertyID propertyID)
{	
	@synchronized(clientData) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		SCAudioBufferQueue *queue = (SCAudioBufferQueue *)clientData;
		[queue retain];
		[queue audioQueue:inAudioQueue propertyChanged:propertyID];
		[queue release];
		[pool release];
	}
}

// invoked by the audio session whenever its route changes
void SCAudioRouteChangedCallback(void *clientData,
								 AudioSessionPropertyID propertyID,
								 UInt32 propertySize,
								 const void *propertyValue)
{
	@synchronized(clientData) {
		if (propertyID != kAudioSessionProperty_AudioRouteChange) return;
		
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		SCAudioBufferQueue *queue = (SCAudioBufferQueue *)clientData;
		[queue retain];
		[queue audioSessionRouteChangedWithChangeDict:(NSDictionary *)propertyValue];
		[queue release];
		[pool release];
	}
}


@implementation SCAudioBufferQueue
#pragma mark Lifecycle
- (id)initWithBasicDescription:(AudioStreamBasicDescription)basicDescription
			   magicCookieData:(NSData *)magicCookieData;
{
	if (self = [super init]) {
		// initializing primitives
		playState = SCAudioBufferPlayState_Paused;
		bufferState = SCAudioBufferBufferState_BufferingNotReadyToPlay;
		buffersInQueue = 0;
		endOfData = NO;
		
		// setting autio session category yo media playback
		AudioSessionInitialize(NULL, NULL, NULL, NULL);
		
		UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
        OSStatus err = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
											   sizeof(sessionCategory),
											   &sessionCategory);
		AudioSessionSetActive(TRUE);
		if (err) {
			NSLog(@"AudioSessionSetProperty kAudioSessionProperty_AudioCategory failed: %d", err);
		}
		
		// attach audio route change listener
		err = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange,
										SCAudioRouteChangedCallback,
										self);
		if (err) {
			NSLog(@"AudioSessionAddPropertyListener kAudioSessionProperty_AudioRouteChange failed: %d", err);
		}
		
		// create audio queue object
		err = AudioQueueNewOutput(&basicDescription,
								  SCAudioQueueOutputCallback,
								  self,
								  NULL, //CFRunLoopGetCurrent(),
								  NULL,
								  0,
								  &audioQueue);
		if (err) {
			NSLog(@"AudioQueueNewOutput failed: %d", err);
			return nil;
		}
		
		// create timeline object
		err = AudioQueueCreateTimeline(audioQueue,
									   &audioQueueTimeline);
		if (err) {
			NSLog(@"AudioQueueCreateTimeline failed: %d", err);
			return nil;
		}
		
		// add property listener(s)
		err = AudioQueueAddPropertyListener(audioQueue,
											kAudioQueueProperty_IsRunning,
											SCQueuePropertyListenerProc,
											self);
		if (err) {
			NSLog(@"AudioQueueAddPropertyListener failed: %d", err);
			return nil;
		}
		
		if (magicCookieData) {
			const void *cookie = [magicCookieData bytes];
			UInt32 cookieDataSize = [magicCookieData length];
			OSStatus err = AudioQueueSetProperty(audioQueue,
												 kAudioQueueProperty_MagicCookie,
												 cookie,
												 cookieDataSize);
			if (err) {
				NSLog(@"AudioQueueSetProperty kAudioQueueProperty_MagicCookie failed: %d", err);
				return nil;
			}
		}
	}
	return self;
}

- (void)dealloc;
{
	delegate = nil;
	AudioSessionRemovePropertyListenerWithUserData(kAudioSessionProperty_AudioRouteChange,
												   SCAudioRouteChangedCallback,
												   self);
	AudioQueueRemovePropertyListener(audioQueue,
									 kAudioQueueProperty_IsRunning,
									 SCQueuePropertyListenerProc,
									 self);
	AudioQueueDisposeTimeline(audioQueue, audioQueueTimeline);
	AudioQueueDispose(audioQueue, YES);
	[super dealloc];
}


#pragma mark Accessors
@synthesize delegate;
@synthesize playState, bufferState;

- (NSUInteger)playedSamples;
{
	if (!audioQueue
		|| !audioQueueTimeline)
		return 0;
	
	AudioTimeStamp timeStamp;
	Boolean discontinuity = false;
	OSStatus err = AudioQueueGetCurrentTime(audioQueue,
											audioQueueTimeline,
											&timeStamp,
											&discontinuity);
	if (err != noErr) {
//		if (err != kAudioQueueErr_InvalidRunState)
//			NSLog(@"AudioQueueGetCurrentTime failed: %d", err);
		return NSUIntegerMax;
	}
	return timeStamp.mSampleTime;
}

- (float)bufferingProgress;
{
	float ret = (float)buffersInQueue / kBuffersFilledRunningLow;
	return fminf(1.0f, fmaxf(0.0f, ret));
}

- (void)setPlayState:(SCAudioBufferPlayState)value;
{
	if (playState == value)
		return;
	playState = value;
	
	NSNotification *notification = [NSNotification notificationWithName:SCAudioBufferPlayStateChangedNotification
																 object:self];
	[self _postNotificationOnDelegateThread:notification];
}


- (void)setBufferState:(SCAudioBufferPlayState)value;
{
	if (bufferState == value)
		return;
	bufferState = value;
	
	NSNotification *notification = [NSNotification notificationWithName:SCAudioBufferBufferStateChangedNotification
																 object:self];
	[self _postNotificationOnDelegateThread:notification];
}


#pragma mark AutioToolboxHooks
- (void)audioQueueReadyToReuseBuffer;
{
	buffersInQueue--;
	[self _updateInternalBufferState];
}

- (void)audioQueue:(AudioQueueRef)inAudioQueue
   propertyChanged:(AudioFileStreamPropertyID)propertyID;
{	
	OSStatus err = noErr;
	
	switch (propertyID) {
		case kAudioQueueProperty_IsRunning: // is the audio queue playing?
		{
			UInt32 isRunning = 0;
			UInt32 isRunningSize = sizeof(UInt32);
			
			err = AudioQueueGetProperty(inAudioQueue,
										kAudioQueueProperty_IsRunning,
										&isRunning,
										&isRunningSize);
			if (err) {
				NSLog(@"get kAudioQueueProperty_IsRunning failed: %d", err);
				return;
			}
			
			// isRunning is 0 when stoped
			if (isRunning == 0 && self.playState == SCAudioBufferPlayState_Stopping) {
				self.playState = SCAudioBufferPlayState_Stopped;
			} else if (isRunning > 0 && self.playState == SCAudioBufferPlayState_WaitingOnQueueToPlay) {
				// workaraound for bug reported by cocoawithlove in http://cocoawithlove.com/2009/06/revisiting-old-post-streaming-and.html
				// cite:
				
				//
				// Note about this bug avoidance quirk:
				//
				// On cleanup of the AudioQueue thread, on rare occasions, there would
				// be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
				// removed from the CFRunLoop.
				//
				// After lots of testing, it appeared that the audio thread was
				// attempting to remove CFRunLoop observers from the CFRunLoop after the
				// thread had already deallocated the run loop.
				//
				// By creating an NSRunLoop for the AudioQueue thread, it changes the
				// thread destruction order and seems to avoid this crash bug -- or
				// at least I haven't had it since (nasty hard to reproduce error!)
				//
				//[NSRunLoop currentRunLoop];// commented out, atm. remove comment when bug occures...
				self.playState = SCAudioBufferPlayState_Playing;
			} else {
				NSLog(@"Audio queue changed state in unexpected way.");
			}
			break;
		}
			
		default:
		{
			NSLog(@"Audio queue unhandled property change: %d",propertyID);
		}
	}
}

- (void)audioSessionRouteChangedWithChangeDict:(NSDictionary *)routeChangeDictionary;
{
	NSNumber *changeReason = [routeChangeDictionary valueForKey:(NSString *)CFSTR(kAudioSession_AudioRouteChangeKey_Reason)];
	NSString *oldDevice = [routeChangeDictionary valueForKey:(NSString *)CFSTR(kAudioSession_AudioRouteChangeKey_OldRoute)];
	if (!changeReason || !oldDevice)
		return;
	
	// kAudioSessionRouteChangeReason_OldDeviceUnavailable - headphone have been unplugged
	if ([changeReason intValue] == kAudioSessionRouteChangeReason_OldDeviceUnavailable
		&& [oldDevice isEqualToString:@"Headphone"]) {
		[self pause];
	}
}


#pragma mark Publics
- (void)enqueueData:(NSData *)data withPacketDescriptions:(SCAudioStreamPacketDescriptions *)packetDescriptions endOfStream:(BOOL)eos;
{
		AudioQueueBufferRef buffer = nil;
		OSStatus err = AudioQueueAllocateBuffer(audioQueue,
												[data length],
												&buffer);
	if (err) {
		NSLog(@"AudioQueueAllocateBuffer failed");
		return;
	}
	
	long long bufferSize = 0;
	
	for (UInt32 packetIndex = 0; packetIndex < packetDescriptions.numberOfDescriptions; packetIndex++) {
		AudioStreamPacketDescription packetDescription = [packetDescriptions packetDescriptionWithIndex:packetIndex];
		SInt64 packetOffset = packetDescription.mStartOffset;	// the offset of the packet data inside the audioData
		SInt64 packetSize = packetDescription.mDataByteSize;	// the length of the packet data
		
		memcpy((char *)buffer->mAudioData + bufferSize,		// the destination. the offset within the buffer
			   (const char *)[data bytes] + packetOffset,		// the beginning of the package data within the audioData chunk
			   packetSize);
		bufferSize += packetSize;
	}
	
	buffer->mAudioDataByteSize = bufferSize;

	// enqueue the buffer
	err = AudioQueueEnqueueBuffer(audioQueue,								// the queue
								  buffer,									// the buffer
								  packetDescriptions.numberOfDescriptions,	// number of packets in buffer
								  packetDescriptions.descriptionsArray);	// pointer to packet descriptions
	if (err) {
		NSLog(@"AudioQueueenqueueCurrentFillBuffer failed");
		return;
	}

	buffersInQueue++;
	//NSLog(@"Buffers filled: %d", buffersInQueue);
	
	endOfData = eos;
	
	[self _updateInternalBufferState];
}

- (void)playWhenReady;
{
	[self _doPlayWhenReady];
}

- (void)pause;
{
	[self _doPause:NO];
}


#pragma mark Privates
// audio queue logic? find it here!
-(void)_updateInternalBufferState;
{
	BOOL enoughBuffersToPlay = endOfData || buffersInQueue >= kBuffersFilledEnoughToPlay;
	BOOL doBufferMore = !endOfData && (buffersInQueue <= kBuffersFilledMax);
	BOOL bufferEmpty = buffersInQueue == 0;
	
	
	if (!doBufferMore) {
		self.bufferState = SCAudioBufferBufferState_NotBuffering;
	} else if (doBufferMore && enoughBuffersToPlay) {
		self.bufferState = SCAudioBufferBufferState_BufferingReadyToPlay;
	} else if (doBufferMore && !enoughBuffersToPlay) {
		self.bufferState = SCAudioBufferBufferState_BufferingNotReadyToPlay;
	}
	if (bufferEmpty) {
		if (self.playState = SCAudioBufferPlayState_Playing) {
			if (endOfData) {
				self.playState = SCAudioBufferPlayState_Stopping;
				[self _doStop];
			} else {
				[self _doPause:YES];
			}
		} else {
			NSLog(@"invalid state");
		}
		
	}
	
	if (enoughBuffersToPlay
		&& self.playState == SCAudioBufferPlayState_PausedPlayWhenReady) {
		[self _doPlay];
	}
	
	if (doBufferMore) {
		[self _doRequestMoreData];
	}	
	
}

// figueres out on which thread the delegate is running and invokes the selector on it
- (NSThread *)_delegateThreadOrMain;
{
	NSThread *thread = nil;
	if ([delegate respondsToSelector:@selector(threadToReceiveAudioBufferQueueCalls)]) {
		thread = [delegate threadToReceiveAudioBufferQueueCalls];
	} else {
		thread = [NSThread mainThread];
	}
	return thread;
}

- (void)_invokeSelectorOnDelegate:(SEL)selector
					   withObject:(id)object
					waitUntilDone:(BOOL)waitUntilDone;
{
	@synchronized (self) {
		[delegate performSelector:selector
						 onThread:[self _delegateThreadOrMain]
					   withObject:object
					waitUntilDone:waitUntilDone];
	}
}

- (void)_postNotificationOnDelegateThread:(NSNotification *)notification;
{
	@synchronized (self) {
		[self performSelector:@selector(_doPostNotification:)
					 onThread:[self _delegateThreadOrMain]
				   withObject:notification
				waitUntilDone:NO];
	}
}

// called on delegates thread since each thread has its own notification center
- (void)_doPostNotification:(NSNotification *)notification;
{
	[[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)_doRequestMoreData;
{
	[self _invokeSelectorOnDelegate:@selector(audioBufferQueueNeedsDataEnqueued:)
						 withObject:self
					  waitUntilDone:NO];
}

- (void)_doStop;
{
	AudioQueueStop(audioQueue, NO);
}

- (void)_doPause:(BOOL)playWhenReadyAgain;
{
	OSStatus err = AudioQueuePause(audioQueue);
	if (err != noErr)
		NSLog(@"AudioQueuePause failed: %d", err);
	
	if (!playWhenReadyAgain) {
		self.playState = SCAudioBufferPlayState_Paused;
	} else {
		self.playState = SCAudioBufferPlayState_PausedPlayWhenReady;
	}

}

- (void)_doPlayWhenReady;
{
	if (self.playState == SCAudioBufferPlayState_Paused) {
		self.playState = SCAudioBufferPlayState_PausedPlayWhenReady;
		[self _updateInternalBufferState];
	}
}	

- (void)_doPlay;
{
	if (self.bufferState == SCAudioBufferBufferState_BufferingNotReadyToPlay) {
		//play when buffering is done.
		if (self.playState == SCAudioBufferPlayState_Paused) {
			self.playState = SCAudioBufferPlayState_PausedPlayWhenReady;
		} else if (self.playState == SCAudioBufferPlayState_PausedPlayWhenReady) {
		} else {
			NSLog(@"invalid state");
		}
		return;
	}
	
	// prime max 20 frames but not more than we actually have enqued
	UInt32 inFramesPrepared = fminf(buffersInQueue, 20);
	UInt32 outFramesPrepared = 0;
	OSStatus err = AudioQueuePrime(audioQueue,
								   inFramesPrepared,
								   &outFramesPrepared);
	if (err != noErr)
		NSLog(@"AudioQueuePrime failed: %d", err);
	
	err = AudioQueueStart(audioQueue, NULL);
	if (err != noErr)
		NSLog(@"AudioQueueStart failed: %d", err);
	self.playState = SCAudioBufferPlayState_WaitingOnQueueToPlay;
}


@end
