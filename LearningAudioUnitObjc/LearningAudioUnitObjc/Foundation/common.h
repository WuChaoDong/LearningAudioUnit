//
//  common.h
//  LearningAudioUnitObjc
//
//  Created by oxape on 2020/10/30.
//

#ifndef common_h
#define common_h

typedef NS_ENUM(NSUInteger, LearningAudioType) {
    LearningAudioTypeAudioUnit,
    LearningAudioTypeAUGraph,
    LearningAudioTypeAVAudioEngine
};

#define CheckStatus(err, msg) do {\
    if(noErr != err) {\
        NSLog(@"error code = %d %@ at %d", err, (msg), __LINE__);\
        return ;\
    }\
} while(0)

#define CheckStatusReturnResult(err, msg, result) do {\
    if(noErr != err) {\
        NSLog(@"error code = %d %@ at %d", err, (msg), __LINE__);\
        return result;\
    }\
} while(0)

#endif /* common_h */
