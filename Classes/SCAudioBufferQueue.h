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


#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


@protocol SCAudioBufferQueueDelegate;
@class SCAudioStreamPacketDescriptions;


typedef enum {
	SCAudioBufferPlayState_WaitingOnQueueToPlay = 0,
	SCAudioBufferPlayState_Playing,
	SCAudioBufferPlayState_Paused,
	SCAudioBufferPlayState_PausedPlayWhenReady,
	SCAudioBufferPlayState_Stopping,
	SCAudioBufferPlayState_Stopped
} SCAudioBufferPlayState;

typedef enum {
	SCAudioBufferBufferState_BufferingNotReadyToPlay = 0,
	SCAudioBufferBufferState_BufferingReadyToPlay,
	SCAudioBufferBufferState_NotBuffering
} SCAudioBufferBufferState;

extern NSString * const SCAudioBufferPlayStateChangedNotification;
extern NSString * const SCAudioBufferBufferStateChangedNotification;

@interface SCAudioBufferQueue : NSObject {
@private
	AudioQueueRef					audioQueue;
	AudioQueueTimelineRef			audioQueueTimeline;
	
	SCAudioBufferPlayState				playState;
	SCAudioBufferBufferState			bufferState;

	NSObject<SCAudioBufferQueueDelegate>	*delegate;
	
	NSUInteger						buffersInQueue;
	BOOL							endOfData;
}
@property (assign)	NSObject<SCAudioBufferQueueDelegate> *delegate;
@property (readonly) float bufferingProgress;
@property (readonly) NSUInteger playedSamples; // in milliseconds
@property (readonly) SCAudioBufferPlayState playState;
@property (readonly) SCAudioBufferBufferState bufferState;

- (id)initWithBasicDescription:(AudioStreamBasicDescription)basicDescription
			   magicCookieData:(NSData *)magicCookieData;

- (void)enqueueData:(NSData *)data withPacketDescriptions:(SCAudioStreamPacketDescriptions *)packetDescriptions endOfStream:(BOOL)eos;

- (void)playWhenReady;
- (void)pause;

@end



@protocol SCAudioBufferQueueDelegate
- (void)audioBufferQueueNeedsDataEnqueued:(SCAudioBufferQueue *)queue;

@optional
// if not implemented [NSThread mainThread] is assumed
- (NSThread *)threadToReceiveAudioBufferQueueCalls;
@end