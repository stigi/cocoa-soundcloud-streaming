//
//  SCDemoAppDelegate.m
//  SCAudioStream
//
//  Created by Ullrich Schäfer on 05.11.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "SCDemoAppDelegate.h"


@implementation SCDemoAppDelegate

#pragma mark UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
	[window addSubview:viewController.view];
	[window makeKeyAndVisible];
	
	// the stream url to the track of our choice. we get this from the soundcloud api
	// we also get the duration of the track (406431 ms in this case) from the api
	NSURL *fluteURL = [NSURL URLWithString:@"http://media.soundcloud.com/stream/xWq32MOb2jre"];
	
	stream = [[SCAudioStream alloc] initWithURL:fluteURL delegate:self];
	
	
	// let's observe the playState property. this way we get notified about, well, playState changes
	// you may observe the bufferState as well to find out if you can start playing the stream.
	// don't forget to remove the observers once you're done with the stream
	[stream addObserver:self forKeyPath:@"playState" options:0 context:nil];
	
	
	// the updateTimer is important to update your UI according to the state of the stream
	// making the playPosition and bufferingProgress properties observable is not feasable
	// this way you can decide your self when to update your UI and when to query the stream for information
	updateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.2f target:self selector:@selector(update) userInfo:nil repeats:YES] retain];
	
	return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
	[updateTimer invalidate];
}


#pragma mark UI Updating

- (void)update;
{
	bufferProgressView.progress = stream.bufferingProgress;
	
	
	// the stream will return NSUIntegerMax if the current playPosition can't be determined
	if (stream.playPosition != NSUIntegerMax) {
		playPositionLabel.text = [NSString stringWithFormat:@"%d / 406 s", stream.playPosition / 1000]; // 406431 ms is the duration we 
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == stream 
		&& [keyPath isEqualToString:@"playState"]) {
		switch (stream.playState) {
			case SCAudioStreamState_Playing:
				[playPauseButton setTitle:@"Pause" forState:UIControlStateNormal];
				playStateLabel.text = @"playing";
				break;
			case SCAudioStreamState_Paused:
				[playPauseButton setTitle:@"Play" forState:UIControlStateNormal];
				playStateLabel.text = @"paused";
				break;
			case SCAudioStreamState_Stopped:
				[playPauseButton setTitle:@"Fin" forState:UIControlStateNormal];
				// track has played till end. you may start playing the nxt track now.
				playStateLabel.text = @"track ended";
				break;
			case SCAudioStreamState_Initialized:
			default:
				break;
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


#pragma mark Action

- (IBAction)play:(id)sender;
{
	if ([playPauseButton.titleLabel.text isEqualToString:@"Play"]) {
		[stream play];
	} else if ([playPauseButton.titleLabel.text isEqualToString:@"Pause"]) {
		[stream pause];
	} else if ([playPauseButton.titleLabel.text isEqualToString:@"Fin"]) {
		// play from beginning
		[stream seekToMillisecond:0 startPlaying:YES];
	}
}


#pragma mark SCAudioStreamDelegate

- (NSMutableURLRequest *)audioStream:(SCAudioStream *)audioStream needsSigningOfRequest:(NSMutableURLRequest *)request;
{
	// no signing in the demo
	// use the soundcloud cocoa api wrapper and
	// - (NSMutableURLRequest *)signedStreamingURLRequestForURLRequest:(NSURLRequest *)request;
	// in the SCSoundCloudAPI+Streaming.h category to sign your streams with your api object
	return request;
}


#pragma mark Lifecycle

- (void)dealloc;
{
	[updateTimer release];
	[stream removeObserver:self forKeyPath:@"playState"];
	[stream release];
	[super dealloc];
}

@end
