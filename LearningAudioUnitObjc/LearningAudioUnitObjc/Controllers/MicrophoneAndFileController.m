//
//  MicrophoneAndFileViewController.m
//  LearningAudioUnitObjc
//
//  Created by oxape on 2020/11/2.
//

#import "MicrophoneAndFileController.h"
#import <AVFoundation/AVFoundation.h>
#import "common.h"

#define IO_UNIT_INPUT_ELEMENT           1
#define IO_UNIT_OUTPUT_ELEMENT          0

#define MIXER_UNIT_INPUT_ELEMENT0         0
#define MIXER_UNIT_INPUT_ELEMENT1         1
#define MIXER_UNIT_OUTPUT_ELEMENT0        0

static OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData);

static OSStatus mixerRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

@interface MicrophoneAndFileController ()

@property (nonatomic, assign) LearningAudioType type;
@property (nonatomic, assign) BOOL playing;

@end

@implementation MicrophoneAndFileController {
    AudioFileID audioFileID;
    AudioStreamBasicDescription audioFileFormat;
    UInt64 audioDataPacketCount;
    UInt32 bytesPerPacket;
    AudioConverterRef audioConverter;
    AudioStreamBasicDescription converterOutputFormat;
    AudioStreamPacketDescription *audioPacketDescription;
    Byte *ioDataBuffer;
    SInt64 readedAudioDataPacketCount;
    
    AudioUnit ioUnit;
    AudioUnit mixerUnit;
    AudioBufferList *bufferList;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self activeSession];
    [self setupAudioFileAndConverter];
    [self buildUnit];
}

- (void)dealloc {
    [self stop];
}

- (void)stop {
    if (!self.playing) {
        return;
    }
    self.playing = YES;
    NSLog(@"stop");
    switch (self.type) {
        case LearningAudioTypeAudioUnit: {
            AudioOutputUnitStop(ioUnit);
            AudioUnitUninitialize(ioUnit);
            AudioUnitUninitialize(mixerUnit);
            AudioComponentInstanceDispose(ioUnit);
            AudioComponentInstanceDispose(mixerUnit);
            
            MicrophoneAndFileController *controller = self;
            if (controller->bufferList != NULL) {
                if (controller->bufferList->mBuffers[0].mData != NULL) {
                    free(controller->bufferList->mBuffers[0].mData);
                }
                free(controller->bufferList);
            }
            
            if (controller->audioPacketDescription != NULL) {
                free(controller->audioPacketDescription);
            }
            
            if (controller->ioDataBuffer != NULL) {
                free(controller->ioDataBuffer);
            }
            
            AudioFileClose(audioFileID);
            AudioConverterDispose(audioConverter);
        }
            break;
            
        default:
            break;
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
    audioPacketDescription = NULL;
    ioDataBuffer = NULL;
    
    OSStatus status;
    UInt32 size;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"accompaniment" withExtension:@"mp3"];
    status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID);
    CheckStatus((int)status, @"AudioFileOpenURL");
    
    size = sizeof(AudioStreamBasicDescription);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioFileFormat); // get audio file format
    CheckStatus((int)status, @"kAudioFilePropertyDataFormat");
    
    size = sizeof(audioDataPacketCount);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyAudioDataPacketCount, &size, &audioDataPacketCount);
    
    bytesPerPacket = audioFileFormat.mFramesPerPacket * audioFileFormat.mBytesPerFrame;
    if (bytesPerPacket == 0) {
        //vbr
        size = sizeof(bytesPerPacket);
        status = AudioFileGetProperty(audioFileID, kAudioFilePropertyMaximumPacketSize, &size, &bytesPerPacket);
        CheckStatus((int)status, @"kAudioFilePropertyDataFormat");
    }
    
    memset(&converterOutputFormat, 0, sizeof(converterOutputFormat));
    converterOutputFormat.mSampleRate       = audioFileFormat.mSampleRate;
    converterOutputFormat.mFormatID         = kAudioFormatLinearPCM;
    converterOutputFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger;
    converterOutputFormat.mChannelsPerFrame = 2;
    converterOutputFormat.mBitsPerChannel   = 16;
    converterOutputFormat.mFramesPerPacket  = 1;
    converterOutputFormat.mBytesPerFrame    = converterOutputFormat.mBitsPerChannel * converterOutputFormat.mChannelsPerFrame/8;
    converterOutputFormat.mBytesPerPacket   = converterOutputFormat.mBytesPerFrame * converterOutputFormat.mFramesPerPacket;
    status = AudioConverterNew(&audioFileFormat, &converterOutputFormat, &audioConverter);
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
    
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, IO_UNIT_OUTPUT_ELEMENT, &one, sizeof(one));
    CheckStatus((int)status, @"kAudioOutputUnitProperty_EnableIO");
    
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
    
    AURenderCallbackStruct renderCallbackStruct;
    renderCallbackStruct.inputProc = mixerRenderCallback;
    renderCallbackStruct.inputProcRefCon = (__bridge void *)self;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT0, &renderCallbackStruct, sizeof(AURenderCallbackStruct));
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT0, &converterOutputFormat, sizeof(AudioStreamBasicDescription));
    
    streamBasicDescription.mSampleRate = 16000;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT1, &streamBasicDescription, sizeof(AudioStreamBasicDescription));
    
    streamBasicDescription.mSampleRate = 44100;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, MIXER_UNIT_OUTPUT_ELEMENT0, &streamBasicDescription, sizeof(AudioStreamBasicDescription));
    
    UInt32 maxFramesPerSlice = 4096;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFramesPerSlice, sizeof(maxFramesPerSlice));
    
    AudioUnitParameterValue volume = 0.3;
    AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT0, volume, 0);
    AudioUnitGetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT0, &volume);
    NSLog(@"mixer element0 volume = %.2f", volume);
    
    volume = 1.5;
    AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT1, volume, 0);
    AudioUnitGetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT1, &volume);
    NSLog(@"mixer element1 volume = %.2f", volume);
    
    AudioUnitConnection ioUnitConnection;
    ioUnitConnection.sourceAudioUnit    = ioUnit;
    ioUnitConnection.sourceOutputNumber = IO_UNIT_INPUT_ELEMENT;
    ioUnitConnection.destInputNumber    = MIXER_UNIT_INPUT_ELEMENT1;
    AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, MIXER_UNIT_INPUT_ELEMENT1, &ioUnitConnection, sizeof(AudioUnitConnection));

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

#pragma mark - callback

static OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    MicrophoneAndFileController *controller = (__bridge MicrophoneAndFileController *)(inUserData);
    if (controller->audioPacketDescription != NULL) {
        free(controller->audioPacketDescription);
    }
    if (controller->ioDataBuffer != NULL) {
        free(controller->ioDataBuffer);
    }
    UInt32 byteSize = *ioNumberDataPackets * controller->bytesPerPacket * controller->converterOutputFormat.mFramesPerPacket * controller->converterOutputFormat.mBytesPerFrame * controller->converterOutputFormat.mChannelsPerFrame;
    controller->ioDataBuffer = malloc(byteSize);
    controller->audioPacketDescription = malloc(sizeof(AudioStreamPacketDescription) * (*ioNumberDataPackets));
    OSStatus status = AudioFileReadPacketData(controller->audioFileID, NO, &byteSize, controller->audioPacketDescription, controller->readedAudioDataPacketCount, ioNumberDataPackets, controller->ioDataBuffer);
    
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
        *outDataPacketDescription = controller->audioPacketDescription;
    }
    
    ioData->mBuffers[0].mDataByteSize = byteSize;
    ioData->mBuffers[0].mData = controller->ioDataBuffer;
    controller->readedAudioDataPacketCount += *ioNumberDataPackets;
    return noErr;
}

static OSStatus mixerRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    MicrophoneAndFileController *controller = (__bridge MicrophoneAndFileController *)inRefCon;
    UInt32 byteSize = inNumberFrames * controller->converterOutputFormat.mBytesPerFrame * controller->converterOutputFormat.mChannelsPerFrame;
    if (controller->bufferList != NULL) {
        if (controller->bufferList->mBuffers[0].mData != NULL) {
            free(controller->bufferList->mBuffers[0].mData);
        }
        free(controller->bufferList);
    }
    controller->bufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    AudioBufferList *bufferList = controller->bufferList;
    bufferList->mNumberBuffers = 1;
    bufferList->mBuffers[0].mNumberChannels = controller->converterOutputFormat.mChannelsPerFrame;
    bufferList->mBuffers[0].mDataByteSize = byteSize;
    bufferList->mBuffers[0].mData = malloc(byteSize);
    OSStatus status = AudioConverterFillComplexBuffer(controller->audioConverter, inInputDataProc, inRefCon, &inNumberFrames, bufferList, NULL);
    CheckStatusReturnResult((int)status, @"AudioConverterFillComplexBuffer", noErr);
    NSLog(@"out size: %u", (unsigned int)bufferList->mBuffers[0].mDataByteSize);
    
    if (controller->bufferList->mBuffers[0].mDataByteSize <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller stop];
        });
        return -1;
    }
    
    memcpy(ioData->mBuffers[0].mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = bufferList->mBuffers[0].mDataByteSize;
    return noErr;
}

@end
