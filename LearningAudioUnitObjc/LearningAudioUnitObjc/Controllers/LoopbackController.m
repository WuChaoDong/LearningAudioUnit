//
//  ViewController.m
//  LearningAudioUnitObjc
//
//  Created by oxape on 2020/10/30.
//

#import "LoopbackController.h"
#import <AVFoundation/AVFoundation.h>
#import "common.h"

#define IO_UNIT_INPUT_ELEMENT           1
#define IO_UNIT_OUTPUT_ELEMENT          0

@interface LoopbackController ()

@property (nonatomic, assign) LearningAudioType type;
@property (nonatomic, assign) BOOL playing;

@end

@implementation LoopbackController {
    //AudioUnit
    AudioUnit ioUnit;
    
    //AUGraph
    AUGraph graph;
    
    //AVAudioEngine
    AVAudioEngine *engine;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self activeSession];
    [self buildUnit];
//    [self buildGraph];
//    [self buildEngine];
}

- (void)dealloc {
    [self stop];
}

- (void)stop {
    if (!self.playing) {
        return;
    }
    NSLog(@"stop");
    switch (self.type) {
        case LearningAudioTypeAudioUnit: {
            AudioOutputUnitStop(ioUnit);
            AudioUnitUninitialize(ioUnit);
            AudioComponentInstanceDispose(ioUnit);
        }
            break;
        case LearningAudioTypeAUGraph: {
            AUGraphStop(graph);
            AUGraphUninitialize(graph);
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
        NSLog(@"overrideOutputAudioPort error = %@", error);
    }
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
}

- (void)buildUnit {
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
    
    struct AudioStreamBasicDescription inFmt;
    inFmt.mFormatID = kAudioFormatLinearPCM;
    inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    inFmt.mBitsPerChannel = 16;
    inFmt.mChannelsPerFrame = 2;
    inFmt.mSampleRate = 16000;
    inFmt.mFramesPerPacket = 1;
    inFmt.mBytesPerFrame =inFmt.mBitsPerChannel*inFmt.mChannelsPerFrame/8;
    inFmt.mBytesPerPacket = inFmt.mBytesPerFrame * inFmt.mFramesPerPacket;
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, IO_UNIT_INPUT_ELEMENT, &inFmt, sizeof(inFmt));
    CheckStatus((int)status, @"kAudioUnitProperty_StreamFormat");

    struct AudioStreamBasicDescription outFmt = inFmt;
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, IO_UNIT_OUTPUT_ELEMENT, &outFmt, sizeof(outFmt));
    CheckStatus((int)status, @"kAudioUnitProperty_StreamFormat");
    
    AudioUnitConnection inputIOUnitConnection;
    inputIOUnitConnection.sourceAudioUnit    = ioUnit;
    inputIOUnitConnection.sourceOutputNumber = 1;
    inputIOUnitConnection.destInputNumber    = 0;
    
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, IO_UNIT_OUTPUT_ELEMENT, &inputIOUnitConnection, sizeof(AudioUnitConnection));
    CheckStatus((int)status, @"kAudioUnitProperty_MakeConnection");
    
    status = AudioUnitInitialize(ioUnit);
    CheckStatus((int)status, @"AudioUnitInitialize");
    
    status = AudioOutputUnitStart(ioUnit);
    CheckStatus((int)status, @"AudioOutputUnitStart");
    
    self.type = LearningAudioTypeAudioUnit;
    self.playing = YES;
    NSLog(@"play");
}

- (void)buildGraph {
    OSStatus status;
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType          = kAudioUnitType_Output;
    ioUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    ioUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags         = 0;
    ioUnitDescription.componentFlagsMask     = 0;
    
    status = NewAUGraph(&graph);
    
    AUNode ioNode;
    status = AUGraphAddNode(graph, &ioUnitDescription, &ioNode);
    CheckStatus((int)status, @"AUGraphAddNode");
    
    status = AUGraphOpen(graph);
    CheckStatus((int)status, @"AUGraphOpen");
    
    AudioUnit ioAudioUnit;
    status = AUGraphNodeInfo(graph, ioNode, &ioUnitDescription, &ioAudioUnit);
    CheckStatus((int)status, @"AUGraphNodeInfo");
    
    UInt32 one = 1;
    status = AudioUnitSetProperty(ioAudioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, IO_UNIT_INPUT_ELEMENT, &one, sizeof(one));
    CheckStatus((int)status, @"kAudioOutputUnitProperty_EnableIO");
    status = AudioUnitSetProperty(ioAudioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, IO_UNIT_OUTPUT_ELEMENT, &one, sizeof(one));
    CheckStatus((int)status, @"kAudioOutputUnitProperty_EnableIO");
    
    AudioStreamBasicDescription inFmt;
    inFmt.mFormatID = kAudioFormatLinearPCM; // pcm data
    inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    inFmt.mBitsPerChannel = 16; // 16bit
    inFmt.mChannelsPerFrame = 2; // double channel
    inFmt.mSampleRate = 16000; // 44.1kbps sample rate
    inFmt.mFramesPerPacket = 1;
    inFmt.mBytesPerFrame = inFmt.mBitsPerChannel*inFmt.mChannelsPerFrame/8;
    inFmt.mBytesPerPacket = inFmt.mBytesPerFrame * inFmt.mFramesPerPacket;
    status = AudioUnitSetProperty(ioAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, IO_UNIT_INPUT_ELEMENT, &inFmt, sizeof(inFmt));
    CheckStatus((int)status, @"kAudioUnitProperty_StreamFormat");

    struct AudioStreamBasicDescription outFmt = inFmt;
    status = AudioUnitSetProperty(ioAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, IO_UNIT_OUTPUT_ELEMENT, &outFmt, sizeof(outFmt));
    CheckStatus((int)status, @"kAudioUnitProperty_StreamFormat");
    
    AUGraphConnectNodeInput(graph, ioNode, IO_UNIT_INPUT_ELEMENT, ioNode, IO_UNIT_OUTPUT_ELEMENT);
    CheckStatus((int)status, @"AUGraphConnectNodeInput");
    
    AUGraphInitialize(graph);
    CheckStatus((int)status, @"AUGraphInitialize");
    
    status = AUGraphStart(graph);
    CheckStatus((int)status, @"AUGraphStart");
    
    self.type = LearningAudioTypeAUGraph;
    self.playing = YES;
    NSLog(@"play");
}

- (void)buildEngine {
    engine = [[AVAudioEngine alloc] init];
    AVAudioIONode *IONode = [[AVAudioIONode alloc] init];

    [engine attachNode:IONode];
    
    struct AudioStreamBasicDescription inFmt;
    inFmt.mFormatID = kAudioFormatLinearPCM; // pcm data
    inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    inFmt.mBitsPerChannel = 16;
    inFmt.mChannelsPerFrame = 2;
    inFmt.mSampleRate = 16000;
    inFmt.mFramesPerPacket = 1;
    inFmt.mBytesPerFrame = inFmt.mBitsPerChannel*inFmt.mChannelsPerFrame/8;
    inFmt.mBytesPerPacket = inFmt.mBytesPerFrame * inFmt.mFramesPerPacket;
    AVAudioFormat *audioFormat = [[AVAudioFormat alloc] initWithStreamDescription:&inFmt channelLayout:nil];
    [engine connect:IONode to:IONode fromBus:1 toBus:0 format:audioFormat];
    NSError *error;
    if (![engine startAndReturnError:&error]) {
        NSLog(@"startAndReturnError error = %@", error);
    }
}

@end
