//
//  ChangeVoiceController.h
//  SpeakHere
//
//  Created by mindonglin on 12-6-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FaRecorder.h"
#import "FaPlayer.h"
#import "FaLevelMeter.h"

@interface ChangeVoiceController : NSObject<FaLevelMeterDelegate>{    
	FaPlayer					*player;
	FaRecorder					*recorder;    
    
	FaLevelMeter                *lvlMeter_in;
    
    NSInteger                   isRecordOn;
    
	UITextField                 *statusSign;
	UIBarButtonItem             *recordButton;
	UIBarButtonItem             *playButton;
    
	BOOL						playbackWasInterrupted;
	BOOL						playbackWasPaused;
    
	CFStringRef					recordFilePath;	
    
	AudioQueueLevelMeterState	*audioLevels;
}

@property (readonly)			FaPlayer			*player;
@property (readonly)			FaRecorder			*recorder;
@property (nonatomic, retain)	IBOutlet UITextField		*statusSign;
@property (nonatomic, retain)	IBOutlet UIBarButtonItem	*recordButton;
@property (nonatomic, retain)	IBOutlet UIBarButtonItem	*playButton;
@property (nonatomic, retain)	FaLevelMeter		*lvlMeter_in;
@property (readwrite)			AudioQueueLevelMeterState	*audioLevels; 

@end
