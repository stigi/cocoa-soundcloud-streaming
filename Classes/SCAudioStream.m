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


#import "SCAudioStreamDataFetcher.h"
#import "SCAudioFileStreamParser.h"
#import "SCAudioBufferQueue.h"

#import "SCAudioStream.h"

#import "SCAudioStreamPacketDescriptions.h"

#define SCAudioStreamRetryCount				10

#define SCAudioStream_HTTPRetryRequest		@"retryRequest"
#define SCAudioStream_HTTPRetryCount		@"retryCount"
#define SCAudioStream_HTTPRetryTimeout		@"timoutIntervall"

#define SCAudioStream_HTTPHeadContext		@"head"
#define SCAudioStream_HTTPStreamContext		@"stream"




@interface SCAudioStream (Private)
- (void)_fetchNextData;
- (void)_bufferFromByteOffset:(NSUInteger)dataByteOffset;
- (void)_createNewAudioQueue;
- (void)queueBufferStateChanged:(NSNotification *)notification;
- (void)queuePlayStateChanged:(NSNotification *)notification;
@end


@implementation SCAudioStream
#pragma mark Lifecycle
- (id)initWithURL:(NSURL *)aURL delegate:(id<SCAudioStreamDelegate>)aDelegate;
{
	if (!aURL)
		return nil;
	
	if (self = [super init]) {
		currentStreamOffset = 0;
		currentPackage = 0;
		packageAtQueueStart = 0;
		reachedEOF = NO;
		loadedEOF = NO;
		streamLength = -1;
		currentConnectionStillToFetch = 0;
		
		URL = [aURL retain];
		delegate = aDelegate;
		
		playState = SCAudioStreamState_Initialized;
		bufferState = SCAudioStreamBufferState_Buffering;
		
		// gathering initial information 
		// the signing of HEAD requests on media.soundcloud.com is currently buggy. so we fake a head request by a very small GET request
		int timeout = kHTTPTimeOutIntervall;
		NSMutableURLRequest *headRequest = [[[NSMutableURLRequest alloc] initWithURL:URL
																		 cachePolicy:NSURLRequestUseProtocolCachePolicy
																	 timeoutInterval:timeout] autorelease];
		[headRequest setHTTPMethod:@"GET"];
		[headRequest setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"];
		//[headRequest addValue:@"head" forHTTPHeaderField:@"X-DEBUG"];
		headRequest = [delegate audioStream:self needsSigningOfRequest:headRequest];
		[headRequest setTimeoutInterval:timeout];
		dataFetcher = [[SCAudioStreamDataFetcher alloc] initWithRequest:headRequest
															  delegate:self];
		dataFetcher.context = SCAudioStream_HTTPHeadContext;
		dataFetcher.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							   headRequest, SCAudioStream_HTTPRetryRequest,
							   [NSNumber numberWithInt:timeout], SCAudioStream_HTTPRetryTimeout,
							   [NSNumber numberWithInt:0], SCAudioStream_HTTPRetryCount,
							   nil];
		
		
		audioFileStreamParser = [[SCAudioFileStreamParser alloc] init];
		audioFileStreamParser.delegate = self;
	}
	return self;
}

- (void)dealloc;
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[dataFetcher cancel];
	dataFetcher.delegate = nil;
	[dataFetcher release];
	audioFileStreamParser.delegate = nil;
	[audioFileStreamParser release];
	audioBufferQueue.delegate = nil;
	[audioBufferQueue release];
	[URL release];
	[super dealloc];
}


#pragma mark Accessors
@synthesize playState, bufferState;

- (NSUInteger)playPosition;
{
	assert([NSThread isMainThread]);
	if (self.playState == SCAudioStreamState_Stopped)
		return 0;
	unsigned long long samples = 0;
	samples = packageAtQueueStart * kMP3FrameSize;
	NSUInteger playedSamples = audioBufferQueue.playedSamples;
	if (playedSamples == NSUIntegerMax)
		return NSUIntegerMax;
	samples += playedSamples;
	return samples / (kMP3SampleRate / 1000);
}

- (float)bufferingProgress;
{
	if (audioBufferQueue.bufferState == SCAudioBufferBufferState_NotBuffering)
		return 1.0;
	return audioBufferQueue.bufferingProgress;
}

- (void)setPlayState:(SCAudioStreamState)value;
{
	if (playState == value)
		return;
	[self willChangeValueForKey:@"playState"];
	playState = value;
	[self didChangeValueForKey:@"playState"];
}

- (void)setBufferState:(SCAudioStreamBufferState)value;
{
	if (bufferState == value)
		return;
	[self willChangeValueForKey:@"bufferState"];
	bufferState = value;
	[self didChangeValueForKey:@"bufferState"];
}


#pragma mark Publics
- (void)seekToMillisecond:(NSUInteger)milli startPlaying:(BOOL)play;
{
	assert([NSThread isMainThread]);
	if (streamLength < 0) {
		NSLog(@"illigal state for seeking in the stream");
		return;
	}
	
	[audioFileStreamParser flushParser];
	
	NSUInteger packet = (milli * (kMP3SampleRate / 1000)) / kMP3FrameSize;
	currentPackage = packet;
	
	if (streamLength < 0) {
		// we don't got info yet, so lets wait till the headConnection callback calls us again
		NSLog(@"wait on package: %d", packet);
		return;
	}
	
	// we create a new bufferQueue since this seems toe only way to reset its timeline object
	if (audioBufferQueue) {
		[self _createNewAudioQueue];
	}
	
	
	if (dataFetcher) {
		[dataFetcher cancel];
	}
	
	SInt64 dataByteOffset = [audioFileStreamParser offsetForPacket:packet];
	currentStreamOffset = dataByteOffset;
	
	[self _bufferFromByteOffset:dataByteOffset];
	if (play)
		[self play];
}

- (void)play;
{
	if (self.playState == SCAudioStreamState_Stopped) {
		[self seekToMillisecond:0 startPlaying:YES];
	}
	
	if (!audioBufferQueue) {
		[self performSelector:@selector(play)
				   withObject:nil
				   afterDelay:0.5];
		return;
	}
	[audioBufferQueue playWhenReady];
}

- (void)pause;
{
	if (!audioBufferQueue) {
		return;
	}
	[audioBufferQueue pause];
}


#pragma mark Privates
- (void)_bufferFromByteOffset:(NSUInteger)dataByteOffset;
{
	assert([NSThread isMainThread]);
	assert(streamLength >= 0);
	long long rangeEnd = dataByteOffset + kHTTPRangeChunkChunkSize;
	
	rangeEnd = MIN(streamLength, rangeEnd);
	
	if (dataByteOffset == streamLength) {
		NSLog(@"blala");
		return;
	}
	
	if (rangeEnd >= streamLength) {
		reachedEOF = YES;
	} else {
		reachedEOF = NO;
	}
	
	NSString *rangeString = [NSString stringWithFormat:@"bytes=%u-%qi", dataByteOffset, (rangeEnd - 1)];
	
	int timeout = kHTTPTimeOutIntervall;
	NSMutableURLRequest *streamRequest = [[[NSMutableURLRequest alloc] initWithURL:URL
																	   cachePolicy:NSURLRequestUseProtocolCachePolicy
																   timeoutInterval:timeout] autorelease];
	[streamRequest setHTTPMethod:@"GET"];
	[streamRequest addValue:rangeString
		 forHTTPHeaderField:@"Range"];
//	[streamRequest addValue:[NSString stringWithFormat:@"bufferingProgress: %f", [self bufferingProgress]]
//		 forHTTPHeaderField:@"X-DEBUG"];
	streamRequest = [delegate audioStream:self needsSigningOfRequest:streamRequest];
	[streamRequest setTimeoutInterval:timeout];
	dataFetcher = [[SCAudioStreamDataFetcher alloc] initWithRequest:streamRequest
														  delegate:self];
	dataFetcher.context = SCAudioStream_HTTPStreamContext;
	dataFetcher.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
						   streamRequest, SCAudioStream_HTTPRetryRequest,
						   [NSNumber numberWithInt:timeout], SCAudioStream_HTTPRetryTimeout,
						   [NSNumber numberWithInt:0], SCAudioStream_HTTPRetryCount,
						   nil];
	
	[self queuePlayStateChanged:nil];
	[self queueBufferStateChanged:nil];
}

- (void)_createNewAudioQueue;
{
	assert([NSThread isMainThread]);
		if (audioBufferQueue) {
			[[NSNotificationCenter defaultCenter] removeObserver:self];
			audioBufferQueue.delegate = nil;
			[audioBufferQueue release]; audioBufferQueue = nil;
		}
		
		packageAtQueueStart = currentPackage;
		audioBufferQueue = [[SCAudioBufferQueue alloc] initWithBasicDescription:audioFileStreamParser.basicDescription
																magicCookieData:audioFileStreamParser.magicCookieData];
		audioBufferQueue.delegate = self;
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(queuePlayStateChanged:)
													 name:SCAudioBufferPlayStateChangedNotification
												   object:audioBufferQueue];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(queueBufferStateChanged:)
													 name:SCAudioBufferBufferStateChangedNotification
												   object:audioBufferQueue];
}

- (void)_fetchNextData;
{
	assert([NSThread isMainThread]);
	if (dataFetcher) {
		NSLog(@"invalid state");
	}
	if (audioBufferQueue.bufferState != SCAudioBufferBufferState_NotBuffering
		&& !reachedEOF) {
		[self _bufferFromByteOffset:currentStreamOffset];
	}
}


#pragma mark SCAudioStreamDataFetcherDelegate

-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didReceiveData:(NSData *)data;
{
	assert([NSThread isMainThread]);
	assert(fetcher == dataFetcher);
	
	BOOL connectionDidSucceed = (dataFetcher.statusCode >= 200 && dataFetcher.statusCode < 300);
	id context = [dataFetcher.context retain];
	
	if (connectionDidSucceed) {
		if ([context isEqualToString:SCAudioStream_HTTPHeadContext]) {
			// set head info
			
		} else if ([context isEqualToString:SCAudioStream_HTTPStreamContext]) {
			currentConnectionStillToFetch -= [data length];
			loadedEOF = currentConnectionStillToFetch == 0;
			
			[audioFileStreamParser parseData:data];
			currentStreamOffset += [data length];
			
		} else {
			NSLog(@"invalid state");
		}
	}
	
	[context release];
}

-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didFinishWithData:(NSData *)data;
{
	assert([NSThread isMainThread]);
	assert(fetcher == dataFetcher);
	
	BOOL connectionDidSucceed = (dataFetcher.statusCode >= 200 && dataFetcher.statusCode < 300);
	id context = [dataFetcher.context retain];
	
	dataFetcher.delegate = nil;
	[dataFetcher release]; dataFetcher = nil;
	
	if (connectionDidSucceed) {
		if ([context isEqualToString:SCAudioStream_HTTPHeadContext]) {
			assert(streamLength >= 0);
			
			//streamLength = _connection.expectedContentLength; // HEAD & media.soundcloud.com bug -> streamlength set with response
			
			[self _bufferFromByteOffset:0];
			
		} else if ([context isEqualToString:SCAudioStream_HTTPStreamContext]) {
			[self _fetchNextData];
			
		} else {
			NSLog(@"invalid state");
		}
	}
	
	[context release];
}

-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didReceiveResponse:(NSURLResponse *)response;
{
	assert([NSThread isMainThread]);
	assert(fetcher == dataFetcher);
	
	BOOL connectionDidSucceed = (dataFetcher.statusCode >= 200 && dataFetcher.statusCode < 300);
	id context = [dataFetcher.context retain];
	
	currentConnectionStillToFetch = dataFetcher.expectedContentLength;
	
	if (connectionDidSucceed) {
		if ([context isEqualToString:SCAudioStream_HTTPHeadContext]) {
			NSString *contentRange = [[(NSHTTPURLResponse *)response allHeaderFields] valueForKey:@"Content-Range"];
			if (contentRange) {
				NSArray *rangeComponents = [contentRange componentsSeparatedByString:@"/"];
				if (rangeComponents.count == 2)
					streamLength = [(NSString *)[rangeComponents objectAtIndex:1] longLongValue];
			}
			
		} else if ([context isEqualToString:SCAudioStream_HTTPStreamContext]) {
			// nothing to be done here
			
		} else {
			NSLog(@"invalid state");
		}
	}
	
	[context release];
}

-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didFailWithError:(NSError *)error;
{
	assert([NSThread isMainThread]);
	assert(fetcher == dataFetcher);
	
	id context = [dataFetcher.context retain];
	NSMutableURLRequest *retryRequest = [[dataFetcher.userInfo objectForKey:SCAudioStream_HTTPRetryRequest] retain];
	int retryCount = [[dataFetcher.userInfo objectForKey:SCAudioStream_HTTPRetryCount] intValue];
	int timeout = [[dataFetcher.userInfo objectForKey:SCAudioStream_HTTPRetryTimeout] intValue];
	retryCount++;
	timeout *= 2;
	timeout = MAX(timeout, 10);
	
	dataFetcher.delegate = nil;
	[dataFetcher release]; dataFetcher = nil;
	
	if (retryRequest) {
		[retryRequest setTimeoutInterval:timeout];
		dataFetcher = [[SCAudioStreamDataFetcher alloc] initWithRequest:[delegate audioStream:self needsSigningOfRequest:retryRequest]
															   delegate:self];
		dataFetcher.context = context;
		dataFetcher.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							   retryRequest, SCAudioStream_HTTPRetryRequest,
							   [NSNumber numberWithInt:timeout], SCAudioStream_HTTPRetryTimeout,
							   [NSNumber numberWithInt:retryCount], SCAudioStream_HTTPRetryCount,
							   nil];
	}
	
	[context release];
	[retryRequest release];
}

-(void)scAudioStreamDataFetcherDidCancel:(SCAudioStreamDataFetcher *)fetcher;
{
	assert([NSThread isMainThread]);
	assert(fetcher == dataFetcher);
	
	dataFetcher.delegate = nil;
	[dataFetcher release]; dataFetcher = nil;
}


#pragma mark SCAudioFileStreamParserDelegate
- (void)audioFileStreamParserIsReadyToProducePackages:(SCAudioFileStreamParser *)fileStreamParser;
{
	assert([NSThread isMainThread]);
	if (!audioBufferQueue) {
		[self _createNewAudioQueue];
	} else {
		NSLog(@"invalid state");
	}
}

- (void)audioFileStreamParser:(SCAudioFileStreamParser *)fileStreamParser
			  parsedAudioData:(NSData *)data
		   packetDescriptions:(SCAudioStreamPacketDescriptions *)packetDescriptions;
{
	assert([NSThread isMainThread]);
	[audioBufferQueue enqueueData:data
		   withPacketDescriptions:packetDescriptions
					  endOfStream:(loadedEOF && reachedEOF)];// && !fileStreamParser.hasBytesToParse];
	currentPackage += packetDescriptions.numberOfDescriptions;
	if (!audioBufferQueue)
		NSLog(@"STOP");
}


#pragma mark SCAudioBufferQueueDelegate
- (void)audioBufferQueueNeedsDataEnqueued:(SCAudioBufferQueue *)queue;
{
	if (!dataFetcher)
		[self _fetchNextData];
}


#pragma mark SCAudioBufferQueue Notifications
- (void)queuePlayStateChanged:(NSNotification *)notification;
{
	if (!audioBufferQueue) {
		self.playState = SCAudioStreamState_Initialized;
		return;
	}
	switch (audioBufferQueue.playState) {
		case SCAudioBufferPlayState_Paused:
		case SCAudioBufferPlayState_PausedPlayWhenReady:
			self.playState = SCAudioStreamState_Paused;
			break;
		case SCAudioBufferPlayState_WaitingOnQueueToPlay:
		case SCAudioBufferPlayState_Playing:
			self.playState = SCAudioStreamState_Playing;
			break;
		case SCAudioBufferPlayState_Stopping:
			break;
		case SCAudioBufferPlayState_Stopped:
			self.playState = SCAudioStreamState_Stopped;
			break;
		default:
			NSLog(@"invalid state");
			break;
	}
}

- (void)queueBufferStateChanged:(NSNotification *)notification;
{
	if (audioBufferQueue.bufferState == SCAudioBufferBufferState_BufferingNotReadyToPlay) {
		self.bufferState = SCAudioStreamBufferState_Buffering;
	} else {
		self.bufferState = SCAudioStreamBufferState_NotBuffering;
	}
}


@end