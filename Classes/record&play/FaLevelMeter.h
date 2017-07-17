//
//  FaLevelMeter.h
//  SpeakHere
//
//  Created by mindonglin on 12-6-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioQueue.h>
#import "CAXException.h"
@protocol FaLevelMeterDelegate;

@interface FaLevelMeter : NSObject{
	AudioQueueRef				_aq;
	AudioQueueLevelMeterState	*_chan_lvls;
	NSArray						*_channelNumbers;
	NSTimer						*_updateTimer;
	CGFloat						_refreshHz;
	id <FaLevelMeterDelegate>   delegate;
}

@property			AudioQueueRef aq; // The AudioQueue object
@property			CGFloat refreshHz; // How many times per second to redraw
@property (retain)	NSArray *channelNumbers; // The indices of the channels to display in this meter
@property (nonatomic, assign) id <FaLevelMeterDelegate> delegate;

@end@protocol FaLevelMeterDelegate
- (void)Fa_StartRecord;
- (void)Fa_SopRecord;
- (NSInteger)Fa_GetIfRecordOn;
@end
