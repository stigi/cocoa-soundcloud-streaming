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


#import "OAMutableURLRequest+Streaming.h"
#import "NSMutableURLRequest+SoundCloudAPI.h"


@interface OAMutableURLRequest (StreamingWeGotThese)
- (NSString *)_signatureBaseString;
@end


@implementation OAMutableURLRequest (Streaming)

- (void)prepareQueryString;
{
 	if ([token.key isEqualToString:@""]) {
		return;
	}
	
	NSString *baseString = [self _signatureBaseString];
    signature = [signatureProvider signClearText:baseString
									  withSecret:[NSString stringWithFormat:@"%@&%@",
												  [consumer.secret URLEncodedString],
												  [token.secret URLEncodedString]]];
	
	NSDictionary *oAuthParams = [NSDictionary dictionaryWithObjectsAndKeys:
								 nonce, @"oauth_nonce",
								 [signatureProvider name], @"oauth_signature_method",
								 token.key, @"oauth_token",
								 timestamp, @"oauth_timestamp",
								 consumer.key, @"oauth_consumer_key",
								 @"1.0", @"oauth_version",
								 signature , @"oauth_signature",
								 nil];
	

    [self setParameterDictionary:oAuthParams];
}
@end
