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


#import "SCAudioStreamPacketDescriptions.h"


@implementation SCAudioStreamPacketDescriptions


#pragma mark Lifecycle
+ (id)audioStreamPacketDescriptionsWithCArray:(AudioStreamPacketDescription *)_packetDescriptions  numberOfDescriptions:(UInt32)_numberOfDescriptions;
{
	return [[[self alloc] initWithCArray:_packetDescriptions numberOfDescriptions:_numberOfDescriptions] autorelease];
}

- (id)initWithCArray:(AudioStreamPacketDescription *)_packetDescriptions numberOfDescriptions:(UInt32)_numberOfDescriptions;
{
	if (self = [super init]) {
		descriptionsArray = _packetDescriptions;
		numberOfDescriptions = _numberOfDescriptions;
	}
	return self;
}


#pragma mark Accessors
@synthesize descriptionsArray, numberOfDescriptions;

#pragma mark Publics
- (AudioStreamPacketDescription)packetDescriptionWithIndex:(UInt32)index;
{
	return descriptionsArray[index];
}

@end
