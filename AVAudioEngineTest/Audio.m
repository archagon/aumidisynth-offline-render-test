//
//  Audio.m
//  AVAudioEngineTest
//
//  Created by Alexei Baboulevitch on 2016-4-20.
//  Copyright © 2016 Alexei Baboulevitch. All rights reserved.
//

#import "Audio.h"

@implementation AVAudioUnitMIDISynth

-(instancetype) init {
    AudioComponentDescription description;
    description.componentType         = kAudioUnitType_MusicDevice;
    description.componentSubType      = kAudioUnitSubType_MIDISynth;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;
    description.componentFlags        = 0;
    description.componentFlagsMask    = 0;
    
    return [super initWithAudioComponentDescription:description];
}

@end
