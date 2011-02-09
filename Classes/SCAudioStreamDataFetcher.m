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


@implementation SCAudioStreamDataFetcher


#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request
			 delegate:(id<SCAudioStreamDataFetcherDelegate>)delegate;
{
	if (self = [super init]) {
		_connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
		_delegate = delegate;
		_statusCode = 0;
		_expectedContentLength = 0;
	}
	return self;
}

-(void)dealloc;
{
	[_connection release];
	[_data release];
	[_context release];
	[super dealloc];
}
	

#pragma mark Accessors

@synthesize context = _context;
@synthesize userInfo = _userInfo;
@synthesize statusCode = _statusCode;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize delegate = _delegate;


#pragma mark Publics

- (void)cancel;
{
	[_connection cancel];
}


#pragma mark NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
	_expectedContentLength = response.expectedContentLength;
	_statusCode = [(NSHTTPURLResponse *)response statusCode];
	
	if (!_data) {
		_data = [[NSMutableData alloc] init];
	} else {
		[_data setLength:0];
	}
	[_delegate scAudioStreamDataFetcher:self didReceiveResponse:response];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
	[_data appendData:data];
	[_delegate scAudioStreamDataFetcher:self didReceiveData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
	[_delegate scAudioStreamDataFetcher:self didFinishWithData:_data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)httpError;
{
	[_delegate scAudioStreamDataFetcher:self didFailWithError:httpError];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse {
    // Ran into some issues with multiple redirects when using OAuth with some providers
    NSRange found = [[[request URL] query] rangeOfString:@"Signature"];
    if (found.length <= 0) {
        return request;
    }
    NSMutableURLRequest *newRequest = [[[NSMutableURLRequest alloc] initWithURL:[request URL]] autorelease];
    [newRequest setHTTPMethod:[request HTTPMethod]];
    NSDictionary *headerFields = [request allHTTPHeaderFields];
    for (NSString *headerFieldKey in [headerFields allKeys]) {
        if ([headerFieldKey isEqualToString:@"Authorization"]) {
            continue;
        }
        [newRequest setValue:[request valueForHTTPHeaderField:headerFieldKey] forHTTPHeaderField:headerFieldKey];
    }
    return  newRequest;
}

@end
