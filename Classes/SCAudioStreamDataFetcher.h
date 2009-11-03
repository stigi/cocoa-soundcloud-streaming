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


@protocol SCAudioStreamDataFetcherDelegate;


@interface SCAudioStreamDataFetcher : NSObject {
@protected
	NSURLConnection *_connection;
	unsigned long long _expectedContentLength;
	NSInteger _statusCode;
	
	NSMutableData *_data;
	
	id<SCAudioStreamDataFetcherDelegate> _delegate;
	id _context;
	id _userInfo;
}

@property (nonatomic, retain) id userInfo;
@property (nonatomic, retain) id context;
@property (readonly) NSInteger statusCode;
@property (readonly) unsigned long long expectedContentLength;
@property (assign) id<SCAudioStreamDataFetcherDelegate> delegate;

- (id)initWithRequest:(NSURLRequest *)request
			 delegate:(id<SCAudioStreamDataFetcherDelegate>)delegate;

- (void)cancel;

@end


#pragma mark -

@protocol SCAudioStreamDataFetcherDelegate <NSObject>
-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didFinishWithData:(NSData *)data;
-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didFailWithError:(NSError *)error;
-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didReceiveData:(NSData *)data;
-(void)scAudioStreamDataFetcherDidCancel:(SCAudioStreamDataFetcher *)fetcher;
-(void)scAudioStreamDataFetcher:(SCAudioStreamDataFetcher *)fetcher didReceiveResponse:(NSURLResponse *)response;
@end
