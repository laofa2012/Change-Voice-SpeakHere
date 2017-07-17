//
//  FaRecorder.h
//  SpeakHere
//
//  Created by mindonglin on 12-6-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#include <AudioToolbox/AudioToolbox.h>
#include <Foundation/Foundation.h>
#include <libkern/OSAtomic.h>

#include "CAStreamBasicDescription.h"
#include "CAXException.h"

#include "SoundTouch.h"
#include "BPMDetect.h"
using namespace soundtouch;

#define kNumberRecordBuffers	3

class FaRecorder 
{
public:
    FaRecorder();
    ~FaRecorder();
    
    UInt32						GetNumberChannels() const	{ return mRecordFormat.NumberChannels(); }
    CFStringRef					GetFileName() const			{ return mFileName; }
    AudioQueueRef				Queue() const				{ return mQueue; }
    CAStreamBasicDescription	DataFormat() const			{ return mRecordFormat; }
    
    void			StartQuareRecord();
    void			StopQuareRecord();	
    void			StartRecord(CFStringRef inRecordFile);
    void			StopRecord();		
    Boolean			IsRunning() const			{ return mIsRunning; }
    
    UInt64			startTime;
    
    SoundTouch* GetSoundTouch() { return &mSoundTouch; }
    
    SoundTouch mSoundTouch;
private:
    CFStringRef					mFileName;
    AudioQueueRef				mQueue;
    AudioQueueBufferRef			mBuffers[kNumberRecordBuffers];
    AudioFileID					mRecordFile;
    SInt64						mRecordPacket; // current packet number in record file
    CAStreamBasicDescription	mRecordFormat;
    Boolean						mIsRunning;
    
    void			CopyEncoderCookieToFile();
    void			SetupAudioFormat(UInt32 inFormatID);
    int				ComputeRecordBufferSize(const AudioStreamBasicDescription *format, float seconds);
    
    static void MyInputBufferHandler(	void *								inUserData,
                                     AudioQueueRef						inAQ,
                                     AudioQueueBufferRef					inBuffer,
                                     const AudioTimeStamp *				inStartTime,
                                     UInt32								inNumPackets,
                                     const AudioStreamPacketDescription*	inPacketDesc);
};