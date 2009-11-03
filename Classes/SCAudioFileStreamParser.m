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


#import "SCAudioFileStreamParser.h"

#import "SCAudioStreamPacketDescriptions.h"


@interface SCAudioFileStreamParser (AudioToolboxHooks)
- (void)audioFileStream:(AudioFileStreamID)inAudioFileStream
		propertyChanged:(AudioFileStreamPropertyID)propertyID
				  flags:(UInt32 *)flags;

- (void)processAudioData:(const void*)data
		 numberOfPackets:(UInt32)numPackets
		   numberOfBytes:(UInt32)numBytes
	  packetDescriptions:(AudioStreamPacketDescription*)packetDescriptions;
@end


#pragma mark C Hooks

// invoked by the audio stream parser whenever it finds property information in the data stream
void SCFileStreamPropertyListenerProc(void *clientData,
									  AudioFileStreamID inAudioFileStream,
									  AudioFileStreamPropertyID propertyID, // UInt32
									  UInt32 *flags)
{
	if (![NSThread isMainThread])
		NSLog(@"nooo");
	SCAudioFileStreamParser *fileStreamParser = (SCAudioFileStreamParser *)clientData;
	[fileStreamParser audioFileStream:inAudioFileStream
					  propertyChanged:propertyID
								flags:flags];
}


// invoked by the audio file stream parser whenever it finds audio data packets in the data stream
void SCFileStreamFoundPacketsProc(void *clientData,
								  UInt32 numberBytes,
								  UInt32 numberPackets,
								  const void *inputData,
								  AudioStreamPacketDescription *packetDescriptions)
{
	if (![NSThread isMainThread])
		NSLog(@"nooo");
	SCAudioFileStreamParser *fileStreamParser = (SCAudioFileStreamParser *)clientData;
	[fileStreamParser processAudioData:inputData 
					   numberOfPackets:numberPackets
						 numberOfBytes:numberBytes
					packetDescriptions:packetDescriptions];
}





@implementation SCAudioFileStreamParser

- (id)init;
{
	if (self = [super init]) {
		dataOffset = 0;
		isParsing = NO;
		discontinuous = YES;
		// creates and opens
		audioFileStream = 0;
		OSStatus err = AudioFileStreamOpen(self,
										   SCFileStreamPropertyListenerProc,
										   SCFileStreamFoundPacketsProc,
										   kAudioFileMP3Type, // we're quite sure soundcloud gives us MP3 atm
										   &audioFileStream);
		if (err)
			NSLog(@"AudioFileStreamOpen failed: %d", err);
		
	}
	return self;
}

- (void)dealloc;
{
	if (audioFileStream) {
		//closes and deallocs
		AudioFileStreamClose(audioFileStream);
		audioFileStream = nil;
	}
	[super dealloc];
}


#pragma mark Accessors

@synthesize delegate;
@synthesize isParsing;

- (AudioStreamBasicDescription)basicDescription;
{	
	assert([NSThread isMainThread]);
	UInt32 asBasicDescriptionSize = sizeof(AudioStreamBasicDescription);
	AudioStreamBasicDescription asBasicDescription;
	OSStatus err = AudioFileStreamGetProperty(audioFileStream,
											  kAudioFileStreamProperty_DataFormat,
											  &asBasicDescriptionSize,
											  &asBasicDescription);
	if (err)
		NSLog(@"get kAudioFileStreamProperty_DataFormat failed: %d", err);
	return asBasicDescription;
}

- (NSData *)magicCookieData;
{
	NSData *ret = nil;
	
	assert([NSThread isMainThread]);
	UInt32 cookieDataSize = 0;
	OSStatus err = AudioFileStreamGetPropertyInfo(audioFileStream,
												  kAudioFileStreamProperty_MagicCookieData,
												  &cookieDataSize,
												  nil);
	if (err != kAudioFileStreamError_ValueUnknown) {
		if (err) {
			NSLog(@"AudioFileStreamGetPropertyInfo kAudioFileStreamProperty_MagicCookieData failed: %d", err);
		} else if (cookieDataSize > 0) {	
			char *cookie;
			cookie = malloc(sizeof(char) * cookieDataSize);
			OSStatus err = AudioFileStreamGetProperty(audioFileStream,
													  kAudioFileStreamProperty_MagicCookieData,
													  &cookieDataSize,
													  cookie);
			if (err) {
				NSLog(@"AudioFileStreamGetProperty kAudioFileStreamProperty_MagicCookieData failed: %d", err);
			} else {
				ret = [NSData dataWithBytes:cookie length:cookieDataSize];
			}
		}
	}
	return ret;
}


#pragma mark Publics

- (void)flushParser;
{
	discontinuous = YES;
}

- (void)parseData:(NSData *)data;
{
	assert(audioFileStream);
	
	isParsing = YES;
	OSStatus err = AudioFileStreamParseBytes(audioFileStream,
											 [data length],
											 [data bytes],
											 discontinuous ? kAudioFileStreamParseFlag_Discontinuity : 0);
	isParsing = NO;
	if (err) 
		NSLog(@"AudioFileStreamParseBytes failed: %d", err);
}

- (SInt64)offsetForPacket:(SInt64)packet;
{
	return dataOffset + (packet * 417) + (packet / 20);
	/*
	UInt32 ioFlags = 0;
	SInt64 dataByteOffset = 0;
	@synchronized(self) {
		AudioFileStreamSeek(audioFileStream,
							packet,
							&dataByteOffset,
							&ioFlags);
		
		if (ioFlags == kAudioFileStreamSeekFlag_OffsetIsEstimated) {
//			NSLog(@"seeking offset is estimated");
		}
	}
	
	if (packet == 0)
		return 0; // late bail because we still want AudioFileStreamSeek to be called

	return dataByteOffset;
	*/
}


#pragma mark AudioToolboxHooks

- (void)audioFileStream:(AudioFileStreamID)inAudioFileStream
		propertyChanged:(AudioFileStreamPropertyID)propertyID
				  flags:(UInt32 *)flags;
{
	OSStatus err = noErr;
	
	switch (propertyID) {
		case kAudioFileStreamProperty_ReadyToProducePackets: // 1 if parser reached the 1st audio data
		{
			[delegate audioFileStreamParserIsReadyToProducePackages:self];
			break;
		}
		case kAudioFileStreamProperty_DataOffset:
		{
			SInt64 offset;
			UInt32 offsetSize = sizeof(offset);
			
			err = AudioFileStreamGetProperty(inAudioFileStream,
											 kAudioFileStreamProperty_DataOffset,
											 &offsetSize,
											 &offset);
			if (dataOffset == 0) {
				dataOffset = offset;
			} else {
				NSLog(@"offset");
			}

			if (err)
				NSLog(@"get kAudioFileStreamProperty_DataOffset failed: %d", err);
			break;
		}
			
		// we don't care about these guys
		case kAudioFileStreamProperty_DataFormat:
		case kAudioFileStreamProperty_FileFormat:
			break;

		default:
		{
			/*NSLog(@"Audio stream unhandled property change: %c%c%c%c",
				  (propertyID>>24)&255, 
				  (propertyID>>16)&255, 
				  (propertyID>>8)&255,
				  propertyID&255);*/
		}
	}
}

- (void)processAudioData:(const void*)audioData
		 numberOfPackets:(UInt32)numPackets
		   numberOfBytes:(UInt32)numBytes
	  packetDescriptions:(AudioStreamPacketDescription*)packetDescriptionsC;
{
	assert([NSThread isMainThread]);
	//NSLog(@"data parsed (%d bytes, %d packets)", numBytes, numPackets);
	
	// we got our first package so lets clear the discontinuous flag
	if (discontinuous)
		discontinuous = NO;
	
	NSData *data = [NSData dataWithBytes:audioData length:numBytes];
	SCAudioStreamPacketDescriptions *descriptions = [SCAudioStreamPacketDescriptions audioStreamPacketDescriptionsWithCArray:packetDescriptionsC
																										numberOfDescriptions:numPackets];
	
	[delegate audioFileStreamParser:self parsedAudioData:data packetDescriptions:descriptions];
}


@end
