//
//  FaRecorder.cpp
//  SpeakHere
//
//  Created by mindonglin on 12-6-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//
#import "FaRecorder.h"

int FaRecorder::ComputeRecordBufferSize(const AudioStreamBasicDescription *format, float seconds)
{
	int packets, frames, bytes = 0;
	try {
		frames = (int)ceil(seconds * format->mSampleRate);
		
		if (format->mBytesPerFrame > 0)
			bytes = frames * format->mBytesPerFrame;
		else {
			UInt32 maxPacketSize;
			if (format->mBytesPerPacket > 0)
				maxPacketSize = format->mBytesPerPacket;	// constant packet size
			else {
				UInt32 propertySize = sizeof(maxPacketSize);
				XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize,
                                                    &propertySize), "couldn't get queue's maximum output packet size");
			}
			if (format->mFramesPerPacket > 0)
				packets = frames / format->mFramesPerPacket;
			else
				packets = frames;	// worst-case scenario: 1 frame in a packet
			if (packets == 0)		// sanity check
				packets = 1;
			bytes = packets * maxPacketSize;
		}
	} catch (CAXException e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		return 0;
	}	
	return bytes;
}

// ____________________________________________________________________________________
// AudioQueue callback function, called when an input buffers has been filled.
void FaRecorder::MyInputBufferHandler(	void *								inUserData,
                                      AudioQueueRef						inAQ,
                                      AudioQueueBufferRef					inBuffer,
                                      const AudioTimeStamp *				inStartTime,
                                      UInt32								inNumPackets,
                                      const AudioStreamPacketDescription*	inPacketDesc)
{
	FaRecorder *aqr = (FaRecorder *)inUserData;
    try {
        if (inNumPackets > 0) {
            UInt32 audioDataByteSize = inBuffer->mAudioDataByteSize;
            CAStreamBasicDescription queueFormat = aqr->DataFormat();
            SoundTouch *soundTouch = aqr->GetSoundTouch();
            
            uint nSamples = audioDataByteSize/queueFormat.mBytesPerPacket;
            soundTouch->putSamples((const SAMPLETYPE *)inBuffer->mAudioData,nSamples);
            
            SAMPLETYPE *samples = (SAMPLETYPE *)malloc(audioDataByteSize);
            UInt32 numSamples;
            do {
                memset(samples, 0, audioDataByteSize);
                numSamples = soundTouch->receiveSamples((SAMPLETYPE *)samples, nSamples);
                // write packets to file
                XThrowIfError(AudioFileWritePackets(aqr->mRecordFile,
                                                    FALSE,
                                                    numSamples*queueFormat.mBytesPerPacket,
                                                    NULL,
                                                    aqr->mRecordPacket,
                                                    &numSamples,
                                                    samples),
                              "AudioFileWritePackets failed");
                aqr->mRecordPacket += numSamples;
            } while (numSamples!=0);
            free(samples);
            
            //            // write packets to file
            //			XThrowIfError(AudioFileWritePackets(aqr->mRecordFile, FALSE, inBuffer->mAudioDataByteSize,
            //                                                inPacketDesc, aqr->mRecordPacket, &inNumPackets, inBuffer->mAudioData),
            //                          "AudioFileWritePackets failed");
            //			aqr->mRecordPacket += inNumPackets;
        } 
		
        // if we're not stopping, re-enqueue the buffe so that it gets filled again
        if (aqr->IsRunning())
            XThrowIfError(AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL), "AudioQueueEnqueueBuffer failed");
	} catch (CAXException e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
}

FaRecorder::FaRecorder()
{
	mIsRunning = false;
	mRecordPacket = 0;
}

FaRecorder::~FaRecorder()
{
	AudioQueueDispose(mQueue, TRUE);
	AudioFileClose(mRecordFile);
	if (mFileName) CFRelease(mFileName);
}

// ____________________________________________________________________________________
// Copy a queue's encoder's magic cookie to an audio file.
void FaRecorder::CopyEncoderCookieToFile()
{
	UInt32 propertySize;
	// get the magic cookie, if any, from the converter		
	OSStatus err = AudioQueueGetPropertySize(mQueue, kAudioQueueProperty_MagicCookie, &propertySize);
	
	// we can get a noErr result and also a propertySize == 0
	// -- if the file format does support magic cookies, but this file doesn't have one.
	if (err == noErr && propertySize > 0) {
		Byte *magicCookie = new Byte[propertySize];
		UInt32 magicCookieSize;
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize), "get audio converter's magic cookie");
		magicCookieSize = propertySize;	// the converter lies and tell us the wrong size
		
		// now set the magic cookie on the output file
		UInt32 willEatTheCookie = false;
		// the converter wants to give us one; will the file take it?
		err = AudioFileGetPropertyInfo(mRecordFile, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
		if (err == noErr && willEatTheCookie) {
			err = AudioFileSetProperty(mRecordFile, kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
			XThrowIfError(err, "set audio file's magic cookie");
		}
		delete[] magicCookie;
	}
}

void FaRecorder::SetupAudioFormat(UInt32 inFormatID)
{
	memset(&mRecordFormat, 0, sizeof(mRecordFormat));
    
	UInt32 size = sizeof(mRecordFormat.mSampleRate);
	XThrowIfError(AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareSampleRate,
                                          &size, 
                                          &mRecordFormat.mSampleRate), "couldn't get hardware sample rate");
    
	size = sizeof(mRecordFormat.mChannelsPerFrame);
	XThrowIfError(AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareInputNumberChannels, 
                                          &size, 
                                          &mRecordFormat.mChannelsPerFrame), "couldn't get input channel count");
    
	mRecordFormat.mFormatID = inFormatID;
	if (inFormatID == kAudioFormatLinearPCM)
	{
		// if we want pcm, default to signed 16-bit little-endian
		mRecordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
		mRecordFormat.mBitsPerChannel = 16;
		mRecordFormat.mBytesPerPacket = mRecordFormat.mBytesPerFrame = (mRecordFormat.mBitsPerChannel / 8) * mRecordFormat.mChannelsPerFrame;
		mRecordFormat.mFramesPerPacket = 1;
        mRecordFormat.mSampleRate = 16000;
	}
}

void FaRecorder::StartQuareRecord()
{
    try {	
		// specify the recording format
		SetupAudioFormat(kAudioFormatLinearPCM);
		
		// create the queue
		XThrowIfError(AudioQueueNewInput(
                                         &mRecordFormat,
                                         MyInputBufferHandler,
                                         this /* userData */,
                                         NULL /* run loop */, NULL /* run loop mode */,
                                         0 /* flags */, &mQueue), "AudioQueueNewInput failed");
        
        
		XThrowIfError(AudioQueueStart(mQueue, NULL), "AudioQueueStart failed");
    }
    
    catch (CAXException &e) {
		char buf[256];
		fprintf(stderr, "Error111: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
}

void FaRecorder::StopQuareRecord()
{
    XThrowIfError(AudioQueueStop(mQueue, true), "AudioQueueStop failed");	
	// a codec may update its cookie at the end of an encoding session, so reapply it to the file now
	//CopyEncoderCookieToFile();
	AudioQueueDispose(mQueue, true);
}

void FaRecorder::StartRecord(CFStringRef inRecordFile)
{
    mSoundTouch.setSampleRate(16000);//mRecordFormat.mSampleRate 44100
    mSoundTouch.setChannels(1);//mRecordFormat.mChannelsPerFrame 1
    mSoundTouch.setTempoChange(1.0);
    mSoundTouch.setPitchSemiTones(9);
    mSoundTouch.setRateChange(-0.7);
    
    mSoundTouch.setSetting(SETTING_SEQUENCE_MS, 40);
    mSoundTouch.setSetting(SETTING_SEEKWINDOW_MS, 16);
    mSoundTouch.setSetting(SETTING_OVERLAP_MS, 8); 
	
    //Only use one of the following two options
    //	mSoundTouch.setSetting(SETTING_USE_QUICKSEEK, 0);
    //	mSoundTouch.setSetting(SETTING_USE_AA_FILTER, !(0));
    //	mSoundTouch.setSetting(SETTING_AA_FILTER_LENGTH, 32);
    //    
    //	mSoundTouch.setSetting(SETTING_SEQUENCE_MS, 40);
    //	mSoundTouch.setSetting(SETTING_SEEKWINDOW_MS, 16);
    //	mSoundTouch.setSetting(SETTING_OVERLAP_MS, 8);
	
	
	int i, bufferByteSize;
	UInt32 size;
	CFURLRef url;
	
	try {		
		mFileName = CFStringCreateCopy(kCFAllocatorDefault, inRecordFile);
        
		// specify the recording format
		SetupAudioFormat(kAudioFormatLinearPCM);
		
		// create the queue
		XThrowIfError(AudioQueueNewInput(
                                         &mRecordFormat,
                                         MyInputBufferHandler,
                                         this /* userData */,
                                         NULL /* run loop */, NULL /* run loop mode */,
                                         0 /* flags */, &mQueue), "AudioQueueNewInput failed");
		
		// get the record format back from the queue's audio converter --
		// the file may require a more specific stream description than was necessary to create the encoder.
		mRecordPacket = 0;
        
		size = sizeof(mRecordFormat);
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,	
                                            &mRecordFormat, &size), "couldn't get queue's format");
        
		NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)inRecordFile];	
        
		url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)recordFile, NULL);
		
		// create the audio file
		XThrowIfError(AudioFileCreateWithURL(url, kAudioFileCAFType, &mRecordFormat, kAudioFileFlags_EraseFile,
                                             &mRecordFile), "AudioFileCreateWithURL failed");
		CFRelease(url);
		
		// copy the cookie first to give the file object as much info as we can about the data going in
		// not necessary for pcm, but required for some compressed audio
		CopyEncoderCookieToFile();
		
		// allocate and enqueue buffers
		bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);	// enough bytes for half a second
		for (i = 0; i < kNumberRecordBuffers; ++i) {
			XThrowIfError(AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]),
                          "AudioQueueAllocateBuffer failed");
			XThrowIfError(AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL),
                          "AudioQueueEnqueueBuffer failed");
		}
		// start the queue
		mIsRunning = true;
		XThrowIfError(AudioQueueStart(mQueue, NULL), "AudioQueueStart failed");
	}
	catch (CAXException &e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
	catch (...) {
		fprintf(stderr, "An unknown error occurred\n");
	}	
    
}

void FaRecorder::StopRecord()
{
	// end recording
	mIsRunning = false;
	XThrowIfError(AudioQueueStop(mQueue, true), "AudioQueueStop failed");	
	// a codec may update its cookie at the end of an encoding session, so reapply it to the file now
	CopyEncoderCookieToFile();
	if (mFileName)
	{
		CFRelease(mFileName);
		mFileName = NULL;
	}
	AudioQueueDispose(mQueue, true);
	AudioFileClose(mRecordFile);
}