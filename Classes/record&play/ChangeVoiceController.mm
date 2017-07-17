//
//  ChangeVoiceController.m
//  SpeakHere
//
//  Created by mindonglin on 12-6-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "ChangeVoiceController.h"
#import <AVFoundation/AVFoundation.h>

@interface ChangeVoiceController ()

@end

@implementation ChangeVoiceController

@synthesize player;
@synthesize recorder;
@synthesize lvlMeter_in;
@synthesize playButton;				
@synthesize recordButton;			
@synthesize statusSign;	
@synthesize audioLevels;

#pragma mark Playback routines

-(void)stopPlayQueue{
	player->StopQueue();
    
    //启动
    isRecordOn = 1;
    recorder->StartQuareRecord(); 
	[lvlMeter_in setAq: recorder->Queue()];
    
	recordButton.enabled = YES;
}

-(void)pausePlayQueue{
	player->PauseQueue();
	playbackWasPaused = YES;
}

- (void)stopRecord{
	recorder->StopRecord();
	
	// dispose the previous playback queue
	player->DisposeQueue(true);
    
	// now create a new queue for the recorded file
	recordFilePath = (CFStringRef)[NSTemporaryDirectory() stringByAppendingPathComponent: @"recordedFile.caf"];
	player->CreateQueueForFile(recordFilePath);
    
	// Set the button's state back to "record"
	recordButton.title = @"Record";
	playButton.enabled = YES;
}

- (IBAction)play{
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error: nil];
    
	if (player->IsRunning()){
		if (playbackWasPaused) {
			OSStatus result = player->StartQueue(true);
			if (result == noErr)
				[[NSNotificationCenter defaultCenter] postNotificationName:@"playbackQueueResumed" object:self];
		} else {
			[self stopPlayQueue];
        }
        isRecordOn = 1;
	} else {
        isRecordOn = 3;		
		OSStatus result = player->StartQueue(false);
		if (result == noErr)
			[[NSNotificationCenter defaultCenter] postNotificationName:@"playbackQueueResumed" object:self];
	}
}

- (IBAction)record{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error: nil];
    
    if (recorder->IsRunning()) {
        isRecordOn = 1;
		[self stopRecord];
	} else {
		//recorder->StopQuareRecord();  
        isRecordOn = 2;
		playButton.enabled = NO;		
		recordButton.title = @"Stop";        
		// Start the recorder
		recorder->StartRecord(CFSTR("recordedFile.caf"));     
	}	
}

#pragma mark AudioSession listeners
void interruptionListener(void *inClientData, UInt32 inInterruptionState){
	ChangeVoiceController *THIS = (ChangeVoiceController*)inClientData;
	if (inInterruptionState == kAudioSessionBeginInterruption){
		if (THIS->recorder->IsRunning()) {
			[THIS stopRecord];
		} 
        else if (THIS->player->IsRunning()) {
			//the queue will stop itself on an interruption, we just need to update the UI
			[[NSNotificationCenter defaultCenter] postNotificationName:@"playbackQueueStopped" object:THIS];
			THIS->playbackWasInterrupted = YES;
		}
	}
	else if ((inInterruptionState == kAudioSessionEndInterruption) && THIS->playbackWasInterrupted)
	{
		// we were playing back when we were interrupted, so reset and resume now
		THIS->player->StartQueue(true);
		[[NSNotificationCenter defaultCenter] postNotificationName:@"playbackQueueResumed" object:THIS];
		THIS->playbackWasInterrupted = NO;
	}
}

void propListener(void *inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void *inData){
	ChangeVoiceController *THIS = (ChangeVoiceController*)inClientData;
	if (inID == kAudioSessionProperty_AudioRouteChange){
		CFDictionaryRef routeDictionary = (CFDictionaryRef)inData;			
		//CFShow(routeDictionary);
		CFNumberRef reason = (CFNumberRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
		SInt32 reasonVal;
		CFNumberGetValue(reason, kCFNumberSInt32Type, &reasonVal);
        
		if (reasonVal != kAudioSessionRouteChangeReason_CategoryChange){            
			if (reasonVal == kAudioSessionRouteChangeReason_OldDeviceUnavailable){			
				if (THIS->player->IsRunning()) {
					[THIS pausePlayQueue];
					[[NSNotificationCenter defaultCenter] postNotificationName:@"playbackQueueStopped" object:THIS];
				}		
			}
            
			// stop the queue if we had a non-policy route change
			if (THIS->recorder->IsRunning()) {
				[THIS stopRecord];
			}
		}	
	}
	else if (inID == kAudioSessionProperty_AudioInputAvailable){
		if (inDataSize == sizeof(UInt32)) {
			UInt32 isAvailable = *(UInt32*)inData;
			// disable recording if input is not available
			THIS->recordButton.enabled = (isAvailable > 0) ? YES : NO;
		}
	}
}

#pragma mark Initialization routines
- (void)awakeFromNib
{	
    NSLog(@"awakeFromNib...");
	
	// Allocate our singleton instance for the recorder & player object
	recorder = new FaRecorder();
	player = new FaPlayer();
    isRecordOn = 1;
    
    FaLevelMeter *tempLevel = [[FaLevelMeter alloc] init];
    self.lvlMeter_in = tempLevel;
    [tempLevel release];
    self.lvlMeter_in.delegate = self;
    
	OSStatus error = AudioSessionInitialize(NULL, NULL, interruptionListener, self);
	if (error) printf("ERROR INITIALIZING AUDIO SESSION! %d\n", (int)error);
	else 
	{
		UInt32 category = kAudioSessionCategory_PlayAndRecord;	
		error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
		if (error) printf("couldn't set audio category!");
        
		error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, propListener, self);
		if (error) printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %d\n", (int)error);
		UInt32 inputAvailable = 0;
		UInt32 size = sizeof(inputAvailable);
		
		// we do not want to allow recording if input is not available
		error = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &size, &inputAvailable);
		if (error) printf("ERROR GETTING INPUT AVAILABILITY! %d\n", (int)error);
		recordButton.enabled = (inputAvailable) ? YES : NO;
		
		// we also need to listen to see if input availability changes
		error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable, propListener, self);
		if (error) printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %d\n", (int)error);
        
		error = AudioSessionSetActive(true); 
		if (error) printf("AudioSessionSetActive (true) failed");
	}
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackQueueStopped:) name:@"playbackQueueStopped" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackQueueResumed:) name:@"playbackQueueResumed" object:nil];
    
	// disable the play button since we have no recording to play yet
	playButton.enabled = NO;
	playbackWasInterrupted = NO;
	playbackWasPaused = NO;
    
    //启动
    recorder->StartQuareRecord(); 
	[lvlMeter_in setAq: recorder->Queue()];
}

# pragma mark Notification routines
- (void)playbackQueueStopped:(NSNotification *)note{
	playButton.title = @"Play";
	recordButton.enabled = YES;
    
    //启动
    isRecordOn = 1;
    recorder->StartQuareRecord(); 
	[lvlMeter_in setAq: recorder->Queue()];
}

- (void)playbackQueueResumed:(NSNotification *)note
{
    playButton.title = @"Stop";
	recordButton.enabled = NO;    
	[lvlMeter_in setAq: nil];
    //recorder->StopQuareRecord();
}

#pragma mark FaLevelMeterDelegate
- (void)Fa_StartRecord{
    [self record];
}

- (void)Fa_SopRecord{
    [self record];
    [self play];
}

- (NSInteger)Fa_GetIfRecordOn{
    return isRecordOn;
}

#pragma mark Cleanup
- (void) dealloc {
	[recordButton release];
	[playButton release];	
	[statusSign release];
	[lvlMeter_in release];
    
	delete player;
	delete recorder;
    
	[super dealloc];
}

@end
