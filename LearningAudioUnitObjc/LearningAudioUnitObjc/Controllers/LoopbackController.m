//
//  ViewController.m
//  LearningAudioUnitObjc
//
//  Created by oxape on 2020/10/30.
//

#import "LoopbackController.h"
#import <AVFoundation/AVFoundation.h>
#import "common.h"

#define INPUT_BUS       1
#define OUTPUT_BUS      0

#define INPUT_ELEMENT       1
#define OUTPUT_ELEMENT      0

//上面bus和ELEMENT只是不同的语义指的是相同的物理设备

#define CONST_BUFFER_SIZE 2048*2*10


@interface LoopbackController () {
    AudioUnit audioUnit;
    AudioBufferList *buffList;
    
    NSInputStream *inputSteam;
    Byte *buffer;
}

@property (nonatomic, strong) AVAudioEngine *engine;

@end

@implementation LoopbackController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self activeSession];
//    [self demo];
    [self buildGraph];
}

- (void)activeSession {
    NSError *error;
#if 1
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    [[AVAudioSession sharedInstance] setPreferredIOBufferDuration:0.05 error:&error];
    if (error) {
        NSLog(@"overrideOutputAudioPort error = %@", error);
    }
#else
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionAllowBluetoothA2DP error:&error];
    [[AVAudioSession sharedInstance] setPreferredInput:[AVAudioSession sharedInstance].availableInputs.firstObject error:&error];
    if (error) {
        NSLog(@"setPreferredInput error = %@", error);
    }
    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
    if (error) {
        NSLog(@"overrideOutputAudioPort error = %@", error);
    }
//    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortHeadphones error:&error];
//    if (error) {
//        NSLog(@"overrideOutputAudioPort error = %@", error);
//    }
#endif
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
}

- (void)demo {
    OSStatus status;
    
    uint32_t numberBuffers = 1;
    buffList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + (numberBuffers - 1) * sizeof(AudioBuffer));
    buffList->mNumberBuffers = numberBuffers;
    buffList->mBuffers[0].mNumberChannels = 1;
    buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
    buffList->mBuffers[0].mData = malloc(CONST_BUFFER_SIZE);
    
    for (int i =1; i < numberBuffers; ++i) {
        buffList->mBuffers[i].mNumberChannels = 1;
        buffList->mBuffers[i].mDataByteSize = CONST_BUFFER_SIZE;
        buffList->mBuffers[i].mData = malloc(CONST_BUFFER_SIZE);
    }
    
    buffer = malloc(CONST_BUFFER_SIZE);
    
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType          = kAudioUnitType_Output;
    ioUnitDescription.componentSubType       = kAudioUnitSubType_VoiceProcessingIO;
    ioUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags         = 0;
    ioUnitDescription.componentFlagsMask     = 0;
    
    AudioComponent component = AudioComponentFindNext(NULL, &ioUnitDescription);
    AudioUnit ioUnitInstance;
    status = AudioComponentInstanceNew(component, &ioUnitInstance);
    VStatus((int)status, @"AudioComponentInstanceNew");
    self->audioUnit = ioUnitInstance;
    
    UInt32 one = 1;
    status = AudioUnitSetProperty(ioUnitInstance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, INPUT_ELEMENT, &one, sizeof(one));
    VStatus((int)status, @"could not enable input on AURemoteIO");
    status = AudioUnitSetProperty(ioUnitInstance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, OUTPUT_ELEMENT, &one, sizeof(one));
    VStatus((int)status, @"could not enable output on AURemoteIO");
    
    struct AudioStreamBasicDescription inFmt;
    inFmt.mFormatID = kAudioFormatLinearPCM; // pcm data
    inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    inFmt.mBitsPerChannel = 16; // 16bit
    inFmt.mChannelsPerFrame = 2; // double channel
    inFmt.mSampleRate = 16000; // 44.1kbps sample rate
    inFmt.mFramesPerPacket = 1;
    inFmt.mBytesPerFrame =inFmt.mBitsPerChannel*inFmt.mChannelsPerFrame/8;
    inFmt.mBytesPerPacket = inFmt.mBytesPerFrame * inFmt.mFramesPerPacket;
    status = AudioUnitSetProperty(ioUnitInstance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, INPUT_ELEMENT, &inFmt, sizeof(inFmt));
    VStatus((int)status, @"set kAudioUnitProperty_StreamFormat of input error");

    struct AudioStreamBasicDescription outFmt = inFmt;
    status = AudioUnitSetProperty(ioUnitInstance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, OUTPUT_ELEMENT, &outFmt, sizeof(outFmt));
    VStatus((int)status, @"set kAudioUnitProperty_StreamFormat of output error");
    
    AudioUnitConnection mixerOutToIoUnitIn;
    mixerOutToIoUnitIn.sourceAudioUnit    = ioUnitInstance;
    mixerOutToIoUnitIn.sourceOutputNumber = 1;
    mixerOutToIoUnitIn.destInputNumber    = 0;
    
    status = AudioUnitSetProperty(ioUnitInstance, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, OUTPUT_ELEMENT, &mixerOutToIoUnitIn, sizeof(AudioUnitConnection));
    VStatus((int)status, @"kAudioUnitProperty_MakeConnection");
    
//    AURenderCallbackStruct recordCallback;
//    recordCallback.inputProc = RecordCallback;
//    recordCallback.inputProcRefCon = (__bridge void *)self;
//    status = AudioUnitSetProperty(audioUnit,
//                         kAudioOutputUnitProperty_SetInputCallback,
//                         kAudioUnitScope_Output,
//                         INPUT_BUS,
//                         &recordCallback,
//                         sizeof(recordCallback));
//    VStatus((int)status, @"kAudioOutputUnitProperty_SetInputCallback");
    
//    AURenderCallbackStruct playCallback;
//    playCallback.inputProc = PlayCallback;
//    playCallback.inputProcRefCon = (__bridge void *)self;
//    status = AudioUnitSetProperty(audioUnit,
//                         kAudioUnitProperty_SetRenderCallback,
//                         kAudioUnitScope_Input,
//                         OUTPUT_BUS,
//                         &playCallback,
//                         sizeof(playCallback));
//    VStatus((int)status, @"kAudioOutputUnitProperty_SetInputCallback");
    
    status = AudioUnitInitialize(ioUnitInstance);
    VStatus((int)status, @"AudioUnitInitialize");
    
    status = AudioOutputUnitStart(ioUnitInstance);
    VStatus((int)status, @"AudioOutputUnitStart");
}

- (void)buildGraph {
    OSStatus status;
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType          = kAudioUnitType_Output;
    ioUnitDescription.componentSubType       = kAudioUnitSubType_VoiceProcessingIO;
    ioUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags         = 0;
    ioUnitDescription.componentFlagsMask     = 0;
    
    AUGraph outGraph;
    status = NewAUGraph(&outGraph);
    
    AUNode outNode;
    status = AUGraphAddNode(outGraph, &ioUnitDescription, &outNode);
    VStatus((int)status, @"AUGraphAddNode");
    
    status = AUGraphOpen(outGraph);
    VStatus((int)status, @"AUGraphOpen");
    
    AudioUnit outAudioUnit;
    status = AUGraphNodeInfo(outGraph, outNode, &ioUnitDescription, &outAudioUnit);
    VStatus((int)status, @"AUGraphNodeInfo");
    
    UInt32 one = 1;
    status = AudioUnitSetProperty(outAudioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, INPUT_ELEMENT, &one, sizeof(one));
    VStatus((int)status, @"could not enable input on AURemoteIO");
    status = AudioUnitSetProperty(outAudioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, OUTPUT_ELEMENT, &one, sizeof(one));
    VStatus((int)status, @"could not enable output on AURemoteIO");
    
    struct AudioStreamBasicDescription inFmt;
    inFmt.mFormatID = kAudioFormatLinearPCM; // pcm data
    inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    inFmt.mBitsPerChannel = 16; // 16bit
    inFmt.mChannelsPerFrame = 2; // double channel
    inFmt.mSampleRate = 16000; // 44.1kbps sample rate
    inFmt.mFramesPerPacket = 1;
    inFmt.mBytesPerFrame = inFmt.mBitsPerChannel*inFmt.mChannelsPerFrame/8;
    inFmt.mBytesPerPacket = inFmt.mBytesPerFrame * inFmt.mFramesPerPacket;
    status = AudioUnitSetProperty(outAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, INPUT_ELEMENT, &inFmt, sizeof(inFmt));
    VStatus((int)status, @"set kAudioUnitProperty_StreamFormat of input error");

    struct AudioStreamBasicDescription outFmt = inFmt;
    status = AudioUnitSetProperty(outAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, OUTPUT_ELEMENT, &outFmt, sizeof(outFmt));
    VStatus((int)status, @"set kAudioUnitProperty_StreamFormat of output error");
    
    AUGraphConnectNodeInput(outGraph, outNode, INPUT_ELEMENT, outNode, OUTPUT_ELEMENT);
    VStatus((int)status, @"AUGraphConnectNodeInput");
    
    AUGraphInitialize(outGraph);
    VStatus((int)status, @"AUGraphInitialize");
    
    status = AUGraphStart(outGraph);
    VStatus((int)status, @"AUGraphStart");
}

- (void)buildEngine {
//    // 1. Create engine (example only, needs to be strong   reference)
//    self.engine = [[AVAudioEngine alloc] init];
//    // 2. Create a player node
//    AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];
//    // 3. Attach node to the engine
//    [engine attachNode:player];
//    // 4. Connect player node to engine's main mixer
//    AVAudioMixerNode *mixer = engine.mainMixerNode;
//    [engine connect:player to:mixer format:[mixer outputFormatForBus:0]];
//    // 5. Start engine
//    NSError *error;
//    if (![engine startAndReturnError:&error]) {
//      // handle error
//    }
}

#pragma mark - callback

static OSStatus RecordCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData)
{
    LoopbackController *vc = (__bridge LoopbackController *)inRefCon;
    vc->buffList->mNumberBuffers = 1;
    OSStatus status = AudioUnitRender(vc->audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, vc->buffList);
    if (status != noErr) {
        NSLog(@"AudioUnitRender error:%d", status);
    }
    
    NSLog(@"size1 = %d", vc->buffList->mBuffers[0].mDataByteSize);
    [vc writePCMData:vc->buffList->mBuffers[0].mData size:vc->buffList->mBuffers[0].mDataByteSize];
    
    return noErr;
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    LoopbackController *vc = (__bridge LoopbackController *)inRefCon;
    memcpy(ioData->mBuffers[0].mData, vc->buffList->mBuffers[0].mData, vc->buffList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = vc->buffList->mBuffers[0].mDataByteSize;
    
    NSInteger bytes = CONST_BUFFER_SIZE < ioData->mBuffers[1].mDataByteSize * 2 ? CONST_BUFFER_SIZE : ioData->mBuffers[1].mDataByteSize * 2; //
    bytes = [vc->inputSteam read:vc->buffer maxLength:bytes];
    
    for (int i = 0; i < bytes; ++i) {
        ((Byte*)ioData->mBuffers[1].mData)[i/2] = vc->buffer[i];
    }
    ioData->mBuffers[1].mDataByteSize = (UInt32)bytes / 2;
    
    if (ioData->mBuffers[1].mDataByteSize < ioData->mBuffers[0].mDataByteSize) {
        ioData->mBuffers[0].mDataByteSize = ioData->mBuffers[1].mDataByteSize;
    }
    
    NSLog(@"size2 = %d", ioData->mBuffers[0].mDataByteSize);
    
    return noErr;
}

- (void)writePCMData:(Byte *)buffer size:(int)size {
    static FILE *file = NULL;
    NSString *path = [NSTemporaryDirectory() stringByAppendingString:@"/record.pcm"];
    if (!file) {
        file = fopen(path.UTF8String, "w");
    }
    fwrite(buffer, size, 1, file);
}

@end
