//
//  common.h
//  LearningAudioUnitObjc
//
//  Created by starot_donglu on 2020/10/30.
//

#ifndef common_h
#define common_h

#define VStatus(err, msg) do {\
    if(noErr != err) {\
        NSLog(@"[ERR-%d]:%@ at %d", err, (msg), __LINE__);\
        return ;\
    }\
} while(0)

#endif /* common_h */
