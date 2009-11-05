//
//  SCDemoAppDelegate.h
//  SCAudioStream
//
//  Created by Ullrich Schäfer on 05.11.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SCAudioStream.h"


@interface SCDemoAppDelegate : NSObject <UIApplicationDelegate, SCAudioStreamDelegate> {
@public
	IBOutlet UIWindow			*window;
	IBOutlet UIViewController	*viewController;
	
	IBOutlet UIProgressView		*bufferProgressView;
	
	IBOutlet UIButton			*playPauseButton;
	
	IBOutlet UILabel			*playStateLabel;
	IBOutlet UILabel			*playPositionLabel;
	
@protected
	SCAudioStream *stream;
	
	NSTimer *updateTimer;
}

- (IBAction)play:(id)sender;

@end
