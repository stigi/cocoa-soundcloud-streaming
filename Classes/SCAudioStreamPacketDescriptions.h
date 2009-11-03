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

@interface SCAudioStreamPacketDescriptions : NSObject {
@private
	AudioStreamPacketDescription	*descriptionsArray;
	UInt32							numberOfDescriptions;
}
@property (readonly)	AudioStreamPacketDescription*	descriptionsArray;
@property (readonly)	UInt32		numberOfDescriptions;

+ (id)audioStreamPacketDescriptionsWithCArray:(AudioStreamPacketDescription *)packetDescriptions
						 numberOfDescriptions:(UInt32)numberOfDescriptions;
- (id)initWithCArray:(AudioStreamPacketDescription *)packetDescriptions
numberOfDescriptions:(UInt32)numberOfDescriptions;

- (AudioStreamPacketDescription)packetDescriptionWithIndex:(UInt32)index;


@end
