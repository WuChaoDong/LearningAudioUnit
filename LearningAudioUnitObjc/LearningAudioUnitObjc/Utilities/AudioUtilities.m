//
//  AudioUtilities.m
//  AudioDemo
//
//  Created by oxape on 2020/10/30.
//

#import "AudioUtilities.h"
#import <AVFoundation/AVFoundation.h>

@implementation AudioUtilities

+ (void)printInfo {
    NSLog(@"availableCategories\n%@", [AVAudioSession sharedInstance].availableCategories);
    NSLog(@"availableModes\n%@", [AVAudioSession sharedInstance].availableModes);
    NSLog(@"availableInputs\n%@", [AVAudioSession sharedInstance].availableInputs);
    
    NSLog(@"inputDataSources\n%@", [AVAudioSession sharedInstance].inputDataSources);
    NSLog(@"outputDataSources\n%@", [AVAudioSession sharedInstance].outputDataSources);
    for (AVAudioSessionDataSourceDescription *sourceDescription in [AVAudioSession sharedInstance].inputDataSources) {
        NSLog(@"sourceDescription name = %@", sourceDescription.dataSourceName);
    }
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    NSArray<AVAudioSessionPortDescription *> *outputs = audioSession.currentRoute.outputs;
    for(AVAudioSessionPortDescription *desc in outputs){
        NSLog(@"outputName %@",desc.portName);
    }
    
    NSArray<AVAudioSessionPortDescription *> *inputs = audioSession.currentRoute.inputs;
    for(AVAudioSessionPortDescription *desc in inputs) {
        NSLog(@"inputName %@",desc.portName);
    }
}

@end
