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


// number of frames for mpeg audio layer 2 & 3. constant.
#define	kMP3FrameSize		1152
// the samplerate in Hz. we can assume 44.1kHz here
#define kMP3SampleRate		44100

// http request timeout intervall (in seconds)
// 1st request has 2s, 2nd 4s, 3rd 8s and 4th has 16s and incrementing
#define kHTTPTimeOutIntervall		2

// lets get chunks of 128k size
#define kHTTPRangeChunkChunkSize	(512 * 1024)

@class SCAudioFileStreamParser, SCAudioBufferQueue, SCAudioStreamDataFetcher;
@protocol SCAudioFileStreamParserDelegate, SCAudioBufferQueueDelegate, SCAudioStreamDataFetcherDelegate;
@protocol SCAudioStreamDelegate;

typedef enum {
	SCAudioStreamState_Initialized = 0,
	SCAudioStreamState_Playing,
	SCAudioStreamState_Paused,
	SCAudioStreamState_Stopped
} SCAudioStreamState;

typedef enum {
	SCAudioStreamBufferState_Buffering = 0,
	SCAudioStreamBufferState_NotBuffering
} SCAudioStreamBufferState;

@interface SCAudioStream : NSObject <SCAudioFileStreamParserDelegate, SCAudioBufferQueueDelegate, SCAudioStreamDataFetcherDelegate> {
@protected
	id<SCAudioStreamDelegate>		delegate;
@private
	NSURL							*URL;
	SCAudioStreamState				playState;
	SCAudioStreamBufferState		bufferState;
	
	SCAudioFileStreamParser			*audioFileStreamParser;
	SCAudioBufferQueue				*audioBufferQueue;
	

	// is set to new value on seek
	// incremented when parser parses new packages
	NSUInteger						currentPackage;
	
	// is set to 0 on seek
	// incremented with the length of data the stream parser is feeded with
	long long						currentStreamOffset;
	
	// is set to currentPackage when the audioQueue has been created
	NSUInteger						packageAtQueueStart;
	
	// is set to YES when end of stream is about to be loaded
	BOOL							reachedEOF;
	// is set to YES if the end of the stream actually has been loaded
	BOOL							loadedEOF;
	
	long long						streamLength;
	
	long long						currentConnectionStillToFetch;
	
	
	SCAudioStreamDataFetcher		*dataFetcher;
}
@property (readonly) SCAudioStreamState playState;			// observable
@property (readonly) SCAudioStreamBufferState bufferState;	// observable
@property (readonly) NSUInteger playPosition;	// in milliseconds // not observable
@property (readonly) float bufferingProgress;	// not observable

- (id)initWithURL:(NSURL *)aURL delegate:(id<SCAudioStreamDelegate>)delegate;

- (void)seekToMillisecond:(NSUInteger)milli startPlaying:(BOOL)play;

- (void)play;
- (void)pause;


@end


#pragma mark -

@protocol SCAudioStreamDelegate
- (NSMutableURLRequest *)audioStream:(SCAudioStream *)audioStream needsSigningOfRequest:(NSURLRequest *)request;
@end

