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


#import "SCSoundCloudAPI+Streaming.h"

#import "OAMutableURLRequest.h"
#import "OAMutableURLRequest+Streaming.h"
#import "OAToken.h"

@interface SCSoundCloudAPI (StreamingWeGotThese)
- (OAToken *)accessToken;
@end


@implementation SCSoundCloudAPI (Streaming)

- (NSMutableURLRequest *)signedStreamingURLRequestForURLRequest:(NSURLRequest *)inRequest;
{
	OAMutableURLRequest *request = [[[OAMutableURLRequest alloc] initWithURL:[inRequest URL]
																	consumer:_oauthConsumer
																	   token:[self accessToken]
																	   realm:nil
														   signatureProvider:nil] autorelease];
	[request setHTTPMethod:[inRequest HTTPMethod]];
	NSDictionary *headerFields = [inRequest allHTTPHeaderFields];
	for (NSString *headerFieldKey in [headerFields allKeys]) {
		[request setValue:[inRequest valueForHTTPHeaderField:headerFieldKey] forHTTPHeaderField:headerFieldKey];
	}
	[request prepareQueryString];
	
	return request;
}

@end
