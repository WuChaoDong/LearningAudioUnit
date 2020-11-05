//
//  FileAndFileController.m
//  LearningAudioUnitObjc
//
//  Created by starot_donglu on 2020/11/4.
//

#import "FileAndFileController.h"
#import <AVFoundation/AVFoundation.h>
#import "common.h"

#define IO_UNIT_INPUT_ELEMENT           1
#define IO_UNIT_OUTPUT_ELEMENT          0

#define MIXER_UNIT_INPUT_ELEMENT0         0
#define MIXER_UNIT_INPUT_ELEMENT1         1
#define MIXER_UNIT_OUTPUT_ELEMENT0        0

static OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData);

static OSStatus RecordCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

static OSStatus mixerRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

@interface FileAndFileObjectContainer : NSObject {
    @public
    AudioFileID audioFileID;
    AudioStreamBasicDescription audioFileFormat;
    UInt64 audioDataPacketCount;
    UInt32 bytesPerPacket;
    SInt64 readedAudioDataPacketCount;
    AudioConverterRef audioConverter;
    AudioStreamBasicDescription converterOutputFormat;
    AudioStreamPacketDescription *audioPacketDescription;
    Byte *ioDataBuffer;
    AudioBufferList *bufferList;
    BOOL finished;
}

@property (nonatomic, weak) FileAndFileController *controller;

@end

@implementation FileAndFileObjectContainer

@end

@interface FileAndFileController ()

@property (nonatomic, strong) NSMutableArray *objectContainerArray;
@property (nonatomic, copy) NSArray *fileArray;
@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, assign) LearningAudioType type;
@property (nonatomic, assign) BOOL playing;

@end

@implementation FileAndFileController {
    AudioUnit ioUnit;
    AudioUnit mixerUnit;
    AudioBufferList *bufferList;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.fileArray = @[@"story.wav", @"accompaniment.mp3"];
    self.objectContainerArray = [NSMutableArray array];
    for (int i=0; i<[self.fileArray count]; i++) {
        FileAndFileObjectContainer *objectContainer = [FileAndFileObjectContainer new];
        objectContainer.controller = self;
        [self.objectContainerArray addObject:objectContainer];
    }
    [self activeSession];
    [self setupAudioFileAndConverter];
    [self buildUnit];
//    [self buildGraph];
}

- (void)dealloc {
    [self stop];
}

- (void)stop {
    if (!self.playing) {
        return;
    }
    self.playing = NO;
    NSLog(@"stop");
    switch (self.type) {
        case LearningAudioTypeAudioUnit: {
            AudioOutputUnitStop(ioUnit);
            AudioUnitUninitialize(ioUnit);
            AudioUnitUninitialize(mixerUnit);
            AudioComponentInstanceDispose(ioUnit);
            AudioComponentInstanceDispose(mixerUnit);
            for (int i=0; i<[self.fileArray count]; i++) {
                FileAndFileObjectContainer *objectContainer = self.objectContainerArray[i];
                if (objectContainer->bufferList != NULL) {
                    if (objectContainer->bufferList->mBuffers[0].mData != NULL) {
                        free(objectContainer->bufferList->mBuffers[0].mData);
                    }
                    free(objectContainer->bufferList);
                }
    
                if (objectContainer->audioPacketDescription != NULL) {
                    free(objectContainer->audioPacketDescription);
                }
    
                if (objectContainer->ioDataBuffer != NULL) {
                    free(objectContainer->ioDataBuffer);
                }
            }

        }
            break;
            
        default:
            break;
    }
    if (self.fileHandle) {
        [self.fileHandle closeFile];
    }
}

- (void)activeSession {
    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionAllowBluetooth error:&error];
    if (error) {
        NSLog(@"setCategory error = %@", error);
    }
    [[AVAudioSession sharedInstance] setPreferredIOBufferDuration:0.02 error:NULL];
    if (error) {
        NSLog(@"setPreferredIOBufferDuration error = %@", error);
    }
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
}

- (void)setupAudioFileAndConverter {
    for (int i=0; i<[self.fileArray count]; i++) {
        NSString *filePath = self.fileArray[i];
        FileAndFileObjectContainer *objectContainer = self.objectContainerArray[i];
        objectContainer->audioPacketDescription = NULL;
        objectContainer->ioDataBuffer = NULL;

        OSStatus status;
        UInt32 size;
        NSURL *url = [[NSBundle mainBundle] URLForResource:[filePath stringByDeletingPathExtension] withExtension:[filePath pathExtension]];
        status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &objectContainer->audioFileID);
        CheckStatus((int)status, @"AudioFileOpenURL");

        size = sizeof(AudioStreamBasicDescription);
        status = AudioFileGetProperty(objectContainer->audioFileID, kAudioFilePropertyDataFormat, &size, &objectContainer->audioFileFormat); // get audio file format
        CheckStatus((int)status, @"kAudioFilePropertyDataFormat");

        size = sizeof(objectContainer->audioDataPacketCount);
        status = AudioFileGetProperty(objectContainer->audioFileID, kAudioFilePropertyAudioDataPacketCount, &size, &objectContainer->audioDataPacketCount);

        objectContainer->bytesPerPacket = objectContainer->audioFileFormat.mFramesPerPacket * objectContainer->audioFileFormat.mBytesPerFrame;
        if (objectContainer->bytesPerPacket == 0) {
            //vbr
            size = sizeof(objectContainer->bytesPerPacket);
            status = AudioFileGetProperty(objectContainer->audioFileID, kAudioFilePropertyMaximumPacketSize, &size, &objectContainer->bytesPerPacket);
            CheckStatus((int)status, @"kAudioFilePropertyDataFormat");
        }

        memset(&objectContainer->converterOutputFormat, 0, sizeof(objectContainer->converterOutputFormat));
        objectContainer->converterOutputFormat.mSampleRate       = objectContainer->audioFileFormat.mSampleRate;
        objectContainer->converterOutputFormat.mFormatID         = kAudioFormatLinearPCM;
        objectContainer->converterOutputFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger;
        objectContainer->converterOutputFormat.mChannelsPerFrame = 2;
        objectContainer->converterOutputFormat.mBitsPerChannel   = 16;
        objectContainer->converterOutputFormat.mFramesPerPacket  = 1;
        objectContainer->converterOutputFormat.mBytesPerFrame    = objectContainer->converterOutputFormat.mBitsPerChannel * objectContainer->converterOutputFormat.mChannelsPerFrame/8;
        objectContainer->converterOutputFormat.mBytesPerPacket   = objectContainer->converterOutputFormat.mBytesPerFrame * objectContainer->converterOutputFormat.mFramesPerPacket;
        status = AudioConverterNew(&objectContainer->audioFileFormat, &objectContainer->converterOutputFormat, &objectContainer->audioConverter);
        
        //if you want to play from the start please comment the code below
        objectContainer->readedAudioDataPacketCount = objectContainer->audioDataPacketCount*9/10;
    }
}

- (void)buildUnit {
    bufferList = NULL;
    OSStatus status;
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType          = kAudioUnitType_Output;
    ioUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    ioUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags         = 0;
    ioUnitDescription.componentFlagsMask     = 0;

    AudioComponent component = AudioComponentFindNext(NULL, &ioUnitDescription);

    status = AudioComponentInstanceNew(component, &ioUnit);
    CheckStatus((int)status, @"AudioComponentInstanceNew");

    UInt32 one = 1;
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, IO_UNIT_INPUT_ELEMENT, &one, sizeof(one));
    CheckStatus((int)status, @"kAudioOutputUnitProperty_EnableIO");

//    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, IO_UNIT_OUTPUT_ELEMENT, &one, sizeof(one));
//    CheckStatus((int)status, @"kAudioOutputUnitProperty_EnableIO");
    
//    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, IO_UNIT_OUTPUT_ELEMENT, &one, sizeof(one));
//    CheckStatus((int)status, @"kAudioOutputUnitProperty_EnableIO");

    AudioStreamBasicDescription streamBasicDescription;
    streamBasicDescription.mFormatID = kAudioFormatLinearPCM;
    streamBasicDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    streamBasicDescription.mSampleRate = 16000;
    streamBasicDescription.mChannelsPerFrame = 2;
    streamBasicDescription.mBitsPerChannel = 16;
    streamBasicDescription.mFramesPerPacket = 1;
    streamBasicDescription.mBytesPerFrame = streamBasicDescription.mBitsPerChannel * streamBasicDescription.mChannelsPerFrame/8;
    streamBasicDescription.mBytesPerPacket = streamBasicDescription.mBytesPerFrame * streamBasicDescription.mFramesPerPacket;
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, IO_UNIT_INPUT_ELEMENT, &streamBasicDescription, sizeof(streamBasicDescription));
    CheckStatus((int)status, @"kAudioUnitProperty_StreamFormat");

    streamBasicDescription.mSampleRate = 44100;
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, IO_UNIT_OUTPUT_ELEMENT, &streamBasicDescription, sizeof(streamBasicDescription));
    CheckStatus((int)status, @"kAudioUnitProperty_StreamFormat");

    AudioComponentDescription mixUnitDescription;
    mixUnitDescription.componentType          = kAudioUnitType_Mixer;
    mixUnitDescription.componentSubType       = kAudioUnitSubType_MultiChannelMixer;
    mixUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    mixUnitDescription.componentFlags         = 0;
    mixUnitDescription.componentFlagsMask     = 0;

    component = AudioComponentFindNext(NULL, &mixUnitDescription);

    status = AudioComponentInstanceNew(component, &mixerUnit);
    CheckStatus((int)status, @"AudioComponentInstanceNew");

    UInt32 mixerUnitElementCount = (UInt32)[self.fileArray count]+1;
    if (mixerUnitElementCount > 8) {
        //https://stackoverflow.com/questions/19213990/why-cant-i-change-the-number-of-elements-buses-in-the-input-scope-of-au-multi
        UInt32 mixerUnitSize = sizeof(UInt32);
        status = AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &mixerUnitElementCount, sizeof(UInt32)); // fourth parameter always use 0 here
        CheckStatus((int)status, @"kAudioUnitProperty_ElementCount");

        status = AudioUnitGetProperty(mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT0, &mixerUnitElementCount, &mixerUnitSize);
        CheckStatus((int)status, @"kAudioUnitProperty_ElementCount");
        NSLog(@"mixUnit elementCount = %u", (unsigned int)mixerUnitElementCount); // no effect after set element count
    }

    int i=0;
    for (; i<[self.fileArray count]; i++) {
        FileAndFileObjectContainer *objectContainer = self.objectContainerArray[i];
        objectContainer->bufferList = NULL;
        AURenderCallbackStruct renderCallbackStruct;
        renderCallbackStruct.inputProc = mixerRenderCallback;
        renderCallbackStruct.inputProcRefCon = (__bridge void *)objectContainer;
        AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, i, &renderCallbackStruct, sizeof(AURenderCallbackStruct));
        AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i, &objectContainer->converterOutputFormat, sizeof(AudioStreamBasicDescription));
        
        AudioUnitParameterValue volume = 0.3;
        AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, i, volume, 0);
        AudioUnitGetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, i, &volume);
        NSLog(@"mixer element%d volume = %.2f", i, volume);
    }
    
    UInt32 maxFramesPerSlice = 4096;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFramesPerSlice, sizeof(maxFramesPerSlice));
    
    streamBasicDescription.mSampleRate = 44100;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, MIXER_UNIT_OUTPUT_ELEMENT0, &streamBasicDescription, sizeof(AudioStreamBasicDescription));
    
    streamBasicDescription.mSampleRate = 16000;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i, &streamBasicDescription, sizeof(AudioStreamBasicDescription));

    AudioUnitParameterValue volume = 2.0;
    AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, i, volume, 0);
    AudioUnitGetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, i, &volume);
    NSLog(@"mixer element%d volume = %.2f", i, volume);
    
    AURenderCallbackStruct recordCallback;
    recordCallback.inputProc = RecordCallback;
    recordCallback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Input, MIXER_UNIT_OUTPUT_ELEMENT0, &recordCallback, sizeof(recordCallback));
    CheckStatus((int)status, @"kAudioOutputUnitProperty_SetInputCallback");

    AudioUnitConnection ioUnitConnection;
    ioUnitConnection.sourceAudioUnit    = ioUnit;
    ioUnitConnection.sourceOutputNumber = IO_UNIT_INPUT_ELEMENT;
    ioUnitConnection.destInputNumber    = i;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, i, &ioUnitConnection, sizeof(AudioUnitConnection));

    AudioUnitConnection mixerUnitConnection;
    mixerUnitConnection.sourceAudioUnit    = mixerUnit;
    mixerUnitConnection.sourceOutputNumber = MIXER_UNIT_OUTPUT_ELEMENT0;
    mixerUnitConnection.destInputNumber    = IO_UNIT_OUTPUT_ELEMENT;
    AudioUnitSetProperty(ioUnit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, IO_UNIT_OUTPUT_ELEMENT, &mixerUnitConnection, sizeof(AudioUnitConnection));
    
    status = AudioUnitInitialize(ioUnit);
    CheckStatus((int)status, @"AudioUnitInitialize");

    status = AudioUnitInitialize(mixerUnit);
    CheckStatus((int)status, @"AudioUnitInitialize");

    status = AudioOutputUnitStart(ioUnit);
    CheckStatus((int)status, @"AudioOutputUnitStart");

    self.type = LearningAudioTypeAudioUnit;
    self.playing = YES;
    NSLog(@"play");
}

- (void)buildGraph {
    
}

- (void)buildEngine {

}

- (void)writePCMData:(Byte *)buffer size:(int)size {
    if (!self.fileHandle) {
        self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"record.pcm"]];
        [self.fileHandle truncateFileAtOffset:0];
    }
    [self.fileHandle writeData:[NSData dataWithBytes:buffer length:size]];
}

#pragma mark - callback

static OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    FileAndFileObjectContainer *objectContainer = (__bridge FileAndFileObjectContainer *)(inUserData);
    if (objectContainer->audioPacketDescription != NULL) {
        free(objectContainer->audioPacketDescription);
    }
    if (objectContainer->ioDataBuffer != NULL) {
        free(objectContainer->ioDataBuffer);
    }
    UInt32 byteSize = *ioNumberDataPackets * objectContainer->bytesPerPacket * objectContainer->converterOutputFormat.mFramesPerPacket * objectContainer->converterOutputFormat.mBytesPerFrame * objectContainer->converterOutputFormat.mChannelsPerFrame;
    objectContainer->ioDataBuffer = malloc(byteSize);
    objectContainer->audioPacketDescription = malloc(sizeof(AudioStreamPacketDescription) * (*ioNumberDataPackets));
    OSStatus status = AudioFileReadPacketData(objectContainer->audioFileID, NO, &byteSize, objectContainer->audioPacketDescription, objectContainer->readedAudioDataPacketCount, ioNumberDataPackets, objectContainer->ioDataBuffer);

    if (status != noErr) {
        NSLog(@"AudioFileReadPacketData failed");
        return -1;
    } else {
        NSLog(@"AudioFileReadPacketData byteSize = %u", (unsigned int)byteSize);
        if (ioNumberDataPackets <= 0) {
            NSLog(@"AudioFileReadPacketData Read Finish");
        }
    }

    if (outDataPacketDescription) {
        *outDataPacketDescription = objectContainer->audioPacketDescription;
    }

    ioData->mBuffers[0].mDataByteSize = byteSize;
    ioData->mBuffers[0].mData = objectContainer->ioDataBuffer;
    objectContainer->readedAudioDataPacketCount += *ioNumberDataPackets;
    return noErr;
}

static OSStatus RecordCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    FileAndFileController *controller = (__bridge FileAndFileController *)inRefCon;
    if (controller->bufferList != NULL) {
        if (controller->bufferList->mBuffers[0].mData != NULL) {
            free(controller->bufferList->mBuffers[0].mData);
        }
        free(controller->bufferList);
    }
    UInt32 byteSize = inNumberFrames * 2 * 2;
    controller->bufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    AudioBufferList *bufferList = controller->bufferList;
    bufferList->mNumberBuffers = 1;
    bufferList->mBuffers[0].mNumberChannels = 2;
    bufferList->mBuffers[0].mDataByteSize = byteSize;
    bufferList->mBuffers[0].mData = malloc(byteSize*2);
    OSStatus status = AudioUnitRender(controller->ioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, controller->bufferList);
    CheckStatusReturnResult((int)status, @"AudioConverterFillComplexBuffer", noErr);
    
    NSLog(@"RecordCallback size = %d", controller->bufferList->mBuffers[0].mDataByteSize);
    [controller writePCMData:controller->bufferList->mBuffers[0].mData size:controller->bufferList->mBuffers[0].mDataByteSize];
    
    return noErr;
}

static OSStatus mixerRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    FileAndFileObjectContainer *objectContainer = (__bridge FileAndFileObjectContainer *)(inRefCon);
    UInt32 byteSize = inNumberFrames * objectContainer->converterOutputFormat.mBytesPerFrame * objectContainer->converterOutputFormat.mChannelsPerFrame;
    if (objectContainer->bufferList != NULL) {
        if (objectContainer->bufferList->mBuffers[0].mData != NULL) {
            free(objectContainer->bufferList->mBuffers[0].mData);
        }
        free(objectContainer->bufferList);
    }
    objectContainer->bufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    AudioBufferList *bufferList = objectContainer->bufferList;
    bufferList->mNumberBuffers = 1;
    bufferList->mBuffers[0].mNumberChannels = objectContainer->converterOutputFormat.mChannelsPerFrame;
    bufferList->mBuffers[0].mDataByteSize = byteSize;
    bufferList->mBuffers[0].mData = malloc(byteSize);
    OSStatus status = AudioConverterFillComplexBuffer(objectContainer->audioConverter, inInputDataProc, inRefCon, &inNumberFrames, bufferList, NULL);
    CheckStatusReturnResult((int)status, @"AudioConverterFillComplexBuffer", noErr);
    NSLog(@"out size: %u", (unsigned int)bufferList->mBuffers[0].mDataByteSize);

    if (objectContainer->bufferList->mBuffers[0].mDataByteSize <= 0) {
        objectContainer->finished = YES;
        BOOL allFinished = YES;
        for (FileAndFileObjectContainer *container in objectContainer.controller.objectContainerArray) {
            if (!container->finished) {
                allFinished = NO;
            }
        }
        if (allFinished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [objectContainer.controller stop];
            });
        }
        memset(ioData->mBuffers[0].mData, 0, byteSize);
        ioData->mBuffers[0].mDataByteSize = byteSize;
        return noErr;
    }
    
    memcpy(ioData->mBuffers[0].mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = bufferList->mBuffers[0].mDataByteSize;
    return noErr;
}

/*
 following code only convert to audio with extension "m4a"
 AVMutableComposition *composition = [AVMutableComposition composition];
 NSArray* tracks = [NSArray arrayWithObjects:@"story.wav", @"accompaniment.mp3", nil];
 
 for (NSString* trackName in tracks) {
     AVURLAsset* audioAsset = [[AVURLAsset alloc]initWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:[trackName stringByDeletingPathExtension] ofType:[trackName pathExtension]]]options:nil];
     AVMutableCompositionTrack* audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
     NSError* error;
     [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioAsset.duration) ofTrack:[[audioAsset tracksWithMediaType:AVMediaTypeAudio]objectAtIndex:0] atTime:kCMTimeZero error:&error];
     if (error) {
         NSLog(@"%@", [error localizedDescription]);
     }
 }
 AVAssetExportSession* assetExport = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetAppleM4A];

 NSString* mixedAudio = @"mixed_audio.m4a";

 NSString *exportPath = [NSTemporaryDirectory() stringByAppendingString:mixedAudio];
 NSURL *exportURL = [NSURL fileURLWithPath:exportPath];

 if ([[NSFileManager defaultManager] fileExistsAtPath:exportPath]) {
     [[NSFileManager defaultManager] removeItemAtPath:exportPath error:nil];
 }
 assetExport.outputFileType = AVFileTypeAppleM4A;
 assetExport.outputURL = exportURL;
 assetExport.shouldOptimizeForNetworkUse = YES;

 [assetExport exportAsynchronouslyWithCompletionHandler:^{
     NSLog(@"Completed Sucessfully");
 }];
 
 */

@end
