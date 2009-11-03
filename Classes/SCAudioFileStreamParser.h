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


@protocol SCAudioFileStreamParserDelegate;
@class SCAudioStreamPacketDescriptions;
@class SCAudioStreamBasicDescription;

@interface SCAudioFileStreamParser : NSObject {
@private
	AudioFileStreamID audioFileStream;
	long long dataOffset;
	id<SCAudioFileStreamParserDelegate> delegate;
	
	BOOL discontinuous;
	
	BOOL isParsing;
}
@property (assign) id<SCAudioFileStreamParserDelegate>	delegate;
@property (readonly) AudioStreamBasicDescription		basicDescription;
@property (readonly) NSData								*magicCookieData;
@property (readonly) BOOL isParsing;

- (void)parseData:(NSData *)data;
- (SInt64)offsetForPacket:(SInt64)packet;

- (void)flushParser;
@end



@protocol SCAudioFileStreamParserDelegate
- (void)audioFileStreamParserIsReadyToProducePackages:(SCAudioFileStreamParser *)fileStreamParser;
- (void)audioFileStreamParser:(SCAudioFileStreamParser *)fileStreamParser
			  parsedAudioData:(NSData *)data
		   packetDescriptions:(SCAudioStreamPacketDescriptions *)packetDescriptions;
@end
