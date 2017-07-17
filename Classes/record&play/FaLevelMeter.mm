//
//  FaLevelMeter.m
//  SpeakHere
//
//  Created by mindonglin on 12-6-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "FaLevelMeter.h"
#import "CAStreamBasicDescription.h"
#define HOMANYTIMESONESECOND 4.0f

@interface FaLevelMeter (FaLevelMeter_priv)
- (float)ValueAt:(float)inDecibels;
@end

@implementation FaLevelMeter
@synthesize delegate;

- (id)init {
	if (self = [super init]) {
		_refreshHz = 1. / HOMANYTIMESONESECOND;
		_channelNumbers = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
		_chan_lvls = (AudioQueueLevelMeterState*)malloc(sizeof(AudioQueueLevelMeterState) * [_channelNumbers count]);
	}
	return self;
}

- (float)ValueAt:(float)inDecibels{
    float mMinDecibels = -80.;
    size_t inTableSize = 400;
    float inRoot = 2.0;
    float mDecibelResolution = mMinDecibels / (inTableSize - 1);
    float mScaleFactor = 1. / mDecibelResolution;    
    
    if (inDecibels < mMinDecibels) return  0.;
    if (inDecibels >= 0.) return 1.;
    
    float	*mTable = (float*)malloc(inTableSize*sizeof(float));
    double minAmp = pow(10., 0.05 * mMinDecibels);
	double ampRange = 1. - minAmp;
	double invAmpRange = 1. / ampRange;
	
	double rroot = 1. / inRoot;
	for (size_t i = 0; i < inTableSize; ++i) {
		double decibels = i * mDecibelResolution;
		double amp = pow(10., 0.05 * decibels);
		double adjAmp = (amp - minAmp) * invAmpRange;
		mTable[i] = pow(adjAmp, rroot);
	}
    
    int index = (int)(inDecibels * mScaleFactor);
    return mTable[index];
    return 0;
}

- (void)_refresh{
    BOOL success = NO;
    
	if (_aq == NULL){
        [_updateTimer invalidate];
        _updateTimer = nil;
        success = YES;
	} else {
		UInt32 data_sz = sizeof(AudioQueueLevelMeterState) * [_channelNumbers count];
		OSErr status = AudioQueueGetProperty(_aq, kAudioQueueProperty_CurrentLevelMeterDB, _chan_lvls, &data_sz);
		if (status != noErr) goto bail;
        
		for (int i=0; i<[_channelNumbers count]; i++){
			NSInteger channelIdx = [(NSNumber *)[_channelNumbers objectAtIndex:i] intValue];		
			if (channelIdx >= [_channelNumbers count]) goto bail;
			if (channelIdx > 127) goto bail;
			
			if (_chan_lvls){
                //NSLog (@"%d_Average:%f, Peak:%f",i,[self ValueAt:(float)(_chan_lvls[channelIdx].mAveragePower)],[self ValueAt:(float)(_chan_lvls[channelIdx].mPeakPower)]);
                
                float average_Peak = [self ValueAt:(float)(_chan_lvls[channelIdx].mPeakPower)]-[self ValueAt:(float)(_chan_lvls[channelIdx].mAveragePower)];
                
                NSLog (@"%d_(Average-Peak):%f",[self.delegate Fa_GetIfRecordOn],average_Peak);
                
                if ([self.delegate Fa_GetIfRecordOn]==2) {
                    if (average_Peak<0.2) {
                        [self.delegate Fa_SopRecord];
                    } 
                } else if ([self.delegate Fa_GetIfRecordOn]==1) {
                    if (average_Peak>0.3) {
                        [self.delegate Fa_StartRecord];
                    }
                }
                success = YES;
			}			
		}
	}	
bail:
    if (!success){
        printf("ERROR: metering failed\n");
    }
}

- (AudioQueueRef)aq { return _aq; }
- (void)setAq:(AudioQueueRef)v{	
    NSLog(@"setAqsetAqsetAq...");
	if (v == NULL)
	{
		if (_updateTimer) {
            [_updateTimer invalidate];	
            _updateTimer = nil;
        }	
	} else if (_aq == NULL){
        if (_updateTimer) [_updateTimer invalidate];		
		_updateTimer = [NSTimer 
						scheduledTimerWithTimeInterval:_refreshHz 
						target:self 
						selector:@selector(_refresh) 
						userInfo:nil 
						repeats:YES
						];
    }
	
	_aq = v;
	
	if (_aq)
	{
		try {
			UInt32 val = 1;
			XThrowIfError(AudioQueueSetProperty(_aq, kAudioQueueProperty_EnableLevelMetering, &val, sizeof(UInt32)), "couldn't enable metering");
			
			// now check the number of channels in the new queue, we will need to reallocate if this has changed
			CAStreamBasicDescription queueFormat;
			UInt32 data_sz = sizeof(queueFormat);
			XThrowIfError(AudioQueueGetProperty(_aq, kAudioQueueProperty_StreamDescription, &queueFormat, &data_sz), "couldn't get stream description");
            
			if (queueFormat.NumberChannels() != [_channelNumbers count]){
				NSArray *chan_array;
				if (queueFormat.NumberChannels() < 2)
					chan_array = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
				else
					chan_array = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:1], nil];
                
				[self setChannelNumbers:chan_array];
				[chan_array release];
				
				_chan_lvls = (AudioQueueLevelMeterState*)realloc(_chan_lvls, queueFormat.NumberChannels() * sizeof(AudioQueueLevelMeterState));
			}
		}
		catch (CAXException e) {
			char buf[256];
			fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		}
	} else {
		if (_updateTimer) {
            [_updateTimer invalidate];	
            _updateTimer = nil;
        }
	}
}

- (CGFloat)refreshHz { return _refreshHz; }
- (void)setRefreshHz:(CGFloat)v{
	_refreshHz = v;
	if (_updateTimer)
	{
		[_updateTimer invalidate];
		_updateTimer = [NSTimer 
						scheduledTimerWithTimeInterval:_refreshHz 
						target:self 
						selector:@selector(_refresh) 
						userInfo:nil 
						repeats:YES
						];
	}
}


- (NSArray *)channelNumbers { return _channelNumbers; }
- (void)setChannelNumbers:(NSArray *)v{
	[v retain];
	[_channelNumbers release];
	_channelNumbers = v;
}

- (void)dealloc{
    self.delegate = nil;
	[_updateTimer invalidate];
	[_channelNumbers release];	
	[super dealloc];
}

@end
