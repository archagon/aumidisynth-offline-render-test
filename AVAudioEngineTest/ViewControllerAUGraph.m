//
//  ViewController.m
//  AVAudioEngineTest
//
//  Created by Alexei Baboulevitch on 2016-4-20.
//  Copyright © 2016 Alexei Baboulevitch. All rights reserved.
//

#import "ViewController.h"
#import "Audio.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

OSStatus OSSTATUS = noErr;
#define OSSTATUS_CHECK if (OSSTATUS != 0) [NSException raise:NSInternalInconsistencyException format:@"OSStatus error: %d", (int)OSSTATUS];

AudioBufferList *AEAllocateAndInitAudioBufferList(AudioStreamBasicDescription audioFormat, int frameCount);
void AEFreeAudioBufferList(AudioBufferList *bufferList );

@interface ViewController ()

@property (nonatomic) AUGraph graph;
@property (nonatomic) AudioUnit ioUnit;
@property (nonatomic) AudioUnit mixerUnit;
@property (nonatomic) AUNode ioNode;
@property (nonatomic) AUNode mixerNode;
@property (nonatomic) MusicPlayer player;
@property (nonatomic) NSArray <NSValue*> * synths;
@property (nonatomic) NSArray <NSNumber*> * synthNodes;

@property (nonatomic) Float64 sampleRate;
@property (nonatomic) SInt32 framesPerSlice;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    [[AVAudioSession sharedInstance] setPreferredSampleRate:44100 error:NULL];
    self.sampleRate = [[AVAudioSession sharedInstance] preferredSampleRate];
    
    // audio graph
    {
        // create initial graph
        {
            AUGraph graph;
            AUNode ioNode, mixerNode;
            
            AudioComponentDescription cd = {};
            cd.componentManufacturer     = kAudioUnitManufacturer_Apple;
            cd.componentFlags            = 0;
            cd.componentFlagsMask        = 0;
            
            OSSTATUS = NewAUGraph (&graph); OSSTATUS_CHECK
            
            cd.componentType = kAudioUnitType_Mixer;
            cd.componentSubType = kAudioUnitSubType_MultiChannelMixer;
            
            OSSTATUS = AUGraphAddNode (graph, &cd, &mixerNode); OSSTATUS_CHECK
            
            cd.componentType = kAudioUnitType_Output;
            cd.componentSubType = kAudioUnitSubType_RemoteIO;
            
            OSSTATUS = AUGraphAddNode (graph, &cd, &ioNode); OSSTATUS_CHECK
            
            // in most examples, this function is called after nodes are added; not sure if we can call it before
            // however, it does have to be called before we make connections or set properties
            OSSTATUS = AUGraphOpen (graph); OSSTATUS_CHECK
            
            OSSTATUS = AUGraphConnectNodeInput (graph, mixerNode, 0, ioNode, 0); OSSTATUS_CHECK
            
            self.graph = graph;
            self.mixerNode = mixerNode;
            self.ioNode = ioNode;
        }
        
        // setup initial units
        {
            AudioUnit ioUnit, mixerUnit;
            
            OSSTATUS = AUGraphNodeInfo (self.graph, self.mixerNode, 0, &mixerUnit); OSSTATUS_CHECK
            OSSTATUS = AUGraphNodeInfo (self.graph, self.ioNode, 0, &ioUnit); OSSTATUS_CHECK

            UInt32 framesPerSlice = 0;
            UInt32 framesPerSlicePropertySize = sizeof (framesPerSlice);

            // global frames per slice
            OSSTATUS = AudioUnitGetProperty (ioUnit,
                                             kAudioUnitProperty_MaximumFramesPerSlice,
                                             kAudioUnitScope_Global,
                                             0,
                                             &framesPerSlice,
                                             &framesPerSlicePropertySize); OSSTATUS_CHECK
            self.framesPerSlice = framesPerSlice;
            
            // this is necessary so that we can set the output unit's sample rate
            OSSTATUS = AudioUnitInitialize(ioUnit); OSSTATUS_CHECK
            
            [self configureAudioUnit:ioUnit];
            [self configureAudioUnit:mixerUnit];
            
            UInt32 busCount = 50;
            OSSTATUS = AudioUnitSetProperty(mixerUnit,
                                 kAudioUnitProperty_ElementCount,
                                 kAudioUnitScope_Input,
                                 0,
                                 &busCount,
                                 sizeof(busCount)); OSSTATUS_CHECK
            
            self.mixerUnit = mixerUnit;
            self.ioUnit = ioUnit;
        }
        
        // create samplers
        NSMutableArray* synths = [NSMutableArray array];
        NSMutableArray* synthNodes = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            AUNode samplerNode;
            AudioUnit samplerUnit;
            
            AudioComponentDescription cd = {};
            cd.componentManufacturer     = kAudioUnitManufacturer_Apple;
            cd.componentFlags            = 0;
            cd.componentFlagsMask        = 0;
            cd.componentType = kAudioUnitType_MusicDevice;
            cd.componentSubType = kAudioUnitSubType_MIDISynth;
            
            OSSTATUS = AUGraphAddNode(self.graph, &cd, &samplerNode); OSSTATUS_CHECK
            
            OSSTATUS = AUGraphConnectNodeInput(self.graph, samplerNode, 0, self.mixerNode, 1 + i); OSSTATUS_CHECK
            
            OSSTATUS = AUGraphNodeInfo (self.graph, samplerNode, 0, &samplerUnit); OSSTATUS_CHECK
        
            [self configureAudioUnit:samplerUnit];
            
            [synths addObject:[NSValue valueWithPointer:samplerUnit]];
            [synthNodes addObject:@(samplerNode)];
        }
        self.synths = synths;
        self.synthNodes = synthNodes;
      
        // create the whole shebang
        AUGraphInitialize(self.graph);
        
        // this should only be called after the samplers are initialized
        [self setupSoundbanks];
    }
    
    // player
    {
        // note: offline rendering does not seem to work with a virtual MIDI endpoint
        
        MusicPlayer player;
        OSSTATUS = NewMusicPlayer(&player); OSSTATUS_CHECK
        
        MusicSequence sequence;
        OSSTATUS = NewMusicSequence(&sequence); OSSTATUS_CHECK
        OSSTATUS = MusicPlayerSetSequence(player, sequence); OSSTATUS_CHECK
        OSSTATUS = MusicSequenceSetAUGraph(sequence, self.graph); OSSTATUS_CHECK
        
        MusicTrack track1;
        OSSTATUS = MusicSequenceNewTrack(sequence, &track1); OSSTATUS_CHECK
        OSSTATUS = MusicTrackSetDestNode(track1, [self.synthNodes[0] integerValue]); OSSTATUS_CHECK
        
        MusicTrack track2;
        OSSTATUS = MusicSequenceNewTrack(sequence, &track2); OSSTATUS_CHECK
        OSSTATUS = MusicTrackSetDestNode(track2, [self.synthNodes[1] integerValue]); OSSTATUS_CHECK
        
        MusicTrack track3;
        OSSTATUS = MusicSequenceNewTrack(sequence, &track3); OSSTATUS_CHECK
        OSSTATUS = MusicTrackSetDestNode(track3, [self.synthNodes[2] integerValue]); OSSTATUS_CHECK
        
        // simple scale
        int scalar = 2;
        for (int i = 0; i < 8; i++) {
            MIDINoteMessage msg;
            msg.channel = i;
            msg.duration = 0.75 * scalar;
            msg.velocity = 0xff;
            
            msg.note = 50 + i * 2;
            OSSTATUS = MusicTrackNewMIDINoteEvent(track1, i * scalar, &msg); OSSTATUS_CHECK
            
            msg.note = 50 + i * 2 + 4;
            OSSTATUS = MusicTrackNewMIDINoteEvent(track2, (i + 0.1) * scalar, &msg); OSSTATUS_CHECK
            
            msg.note = 50 + i * 2 + 4 + 5;
            OSSTATUS = MusicTrackNewMIDINoteEvent(track3, (i + 0.2) * scalar, &msg); OSSTATUS_CHECK
            
            // pitch bends for track 3
            {
                UInt8 semitones = 0x2000 / 100;
                UInt8 cents = 0x2000 % 100;
                
                MIDIChannelMessage channelMessage = {0};
                
                // range (each tick == 1 cent)
                for (int c = 0; c < 16; c++) {
                    channelMessage.status = 0xB0 | c;
                    
                    channelMessage.data1 = 0x65;
                    channelMessage.data2 = 0x00 >> 7;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage); OSSTATUS_CHECK
                    
                    channelMessage.data1 = 0x64;
                    channelMessage.data2 = 0x00;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage); OSSTATUS_CHECK
                    
                    channelMessage.data1 = 0x06;
                    channelMessage.data2 = semitones;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage); OSSTATUS_CHECK
                    
                    channelMessage.data1 = 0x26;
                    channelMessage.data2 = cents;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage); OSSTATUS_CHECK
                    
                    channelMessage.data1 = 0x65;
                    channelMessage.data2 = 0x7F;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage); OSSTATUS_CHECK
                    
                    channelMessage.data1 = 0x64;
                    channelMessage.data2 = 0x7F;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage); OSSTATUS_CHECK
                }
                
                // actual pitch bend commands
                int divisionsPerNote = 128;
                int ocillations = 3;
                CGFloat totalLength = ocillations * M_PI * 2;
                for (int d = 0; d < divisionsPerNote; d++) {
                    CGFloat fraction = d / (CGFloat)(divisionsPerNote - 1);
                    int cents = 200 * sin(fraction * totalLength);
                    
                    cents = MIN(cents, (0x2000 - 1));
                    
                    NSUInteger bendValue = 0x2000 + cents;
                    NSUInteger bendMSB = (bendValue >> 7) & 0x7F;
                    NSUInteger bendLSB = bendValue & 0x7F;
                    
                    UInt32 noteCommand = 0xE0 | i;
                    
                    MIDIChannelMessage channelMessage = {0};
                    
                    channelMessage.status = noteCommand;
                    channelMessage.data1 = bendLSB;
                    channelMessage.data2 = bendMSB;
                    
                    OSSTATUS = MusicTrackNewMIDIChannelEvent(track3, (i + 0.2) * scalar + scalar * fraction, &channelMessage); OSSTATUS_CHECK
                }
            }
        }
        
        self.player = player;
    }
    
    // buttons
    {
        UIButton* start = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButton* render = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButton* stop = [UIButton buttonWithType:UIButtonTypeSystem];
        
        start.translatesAutoresizingMaskIntoConstraints = NO;
        render.translatesAutoresizingMaskIntoConstraints = NO;
        stop.translatesAutoresizingMaskIntoConstraints = NO;
        
        [start setTitle:@"Start" forState:UIControlStateNormal];
        [render setTitle:@"Start (Offline Render)" forState:UIControlStateNormal];
        [stop setTitle:@"Stop" forState:UIControlStateNormal];
        
        [self.view addSubview:start];
        [self.view addSubview:render];
        [self.view addSubview:stop];
        
        [start addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
        [render addTarget:self action:@selector(render) forControlEvents:UIControlEventTouchUpInside];
        [stop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
        
        NSArray* vConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(100)-[start]-[render]-[stop]" options:0 metrics:nil views:@{ @"start":start, @"render":render, @"stop":stop }];
        [NSLayoutConstraint activateConstraints:vConstraints];
        
        for (int i = 0; i < 3; i++) {
            UIView* view = @[ start, render, stop ][i];
            
            NSLayoutConstraint* centerX = [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:view.superview attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
            centerX.active = YES;
        }
    }
}

-(void) start {
    [self stop];
    
    [self setRegularOutput];
    
    [self setupInstruments];

    OSSTATUS = MusicPlayerSetTime(self.player, 0); OSSTATUS_CHECK
    OSSTATUS = MusicPlayerStart(self.player); OSSTATUS_CHECK
    
    // note: graph automatically starts running when the music player starts and stops when it stops
}

-(void) render {
    [self stop];
    
    [self setGenericOutput];
    
    [self setupInstruments];
    
    OSSTATUS = MusicPlayerSetTime(self.player, 0); OSSTATUS_CHECK
    OSSTATUS = MusicPlayerStart(self.player); OSSTATUS_CHECK
    
    [self renderAudioAndWriteToFile];
    
    OSSTATUS = MusicPlayerStop(self.player); OSSTATUS_CHECK
}

-(void) stop {
    OSSTATUS = MusicPlayerStop(self.player); OSSTATUS_CHECK
}

// TODO: do we need to set the frames-per-slice for our mixer?

// for some units, these can only be done when they're uninitialized
-(void) configureAudioUnit:(AudioUnit)unit {
    OSSTATUS = AudioUnitSetProperty (unit,
                                     kAudioUnitProperty_SampleRate,
                                     kAudioUnitScope_Output,
                                     0,
                                     &_sampleRate,
                                     sizeof(_sampleRate)); OSSTATUS_CHECK
    OSSTATUS = AudioUnitSetProperty (unit,
                                     kAudioUnitProperty_MaximumFramesPerSlice,
                                     kAudioUnitScope_Global,
                                     0,
                                     &_framesPerSlice,
                                     sizeof(_framesPerSlice)); OSSTATUS_CHECK
}

-(void) setupSoundbanks {
    for (int i = 0; i < self.synths.count; i++) {
        NSURL* aUrl = [[NSBundle mainBundle] URLForResource:@"GeneralUser GS MuseScore v1.442" withExtension:@"sf2"];
        
        CFURLRef url = (__bridge CFURLRef)aUrl;
        OSSTATUS = AudioUnitSetProperty([self.synths[i] pointerValue],
                                        kMusicDeviceProperty_SoundBankURL,
                                        kAudioUnitScope_Global,
                                        0,
                                        &url,
                                        sizeof(url)); OSSTATUS_CHECK
    }
}

-(void) setupInstruments {
    // random instrument each time
    for (int i = 0; i < self.synths.count; i++) {
        UInt32 actualPreset = arc4random_uniform(100);
        
        for (int j = 0; j < 16; j++) {
            UInt32 enabled = 1;
            OSSTATUS = AudioUnitSetProperty([self.synths[i] pointerValue],
                                            kAUMIDISynthProperty_EnablePreload,
                                            kAudioUnitScope_Global,
                                            0,
                                            &enabled,
                                            sizeof(enabled)); OSSTATUS_CHECK
            
            UInt32 instrumentMSB = kAUSampler_DefaultMelodicBankMSB;
            UInt32 instrumentLSB = kAUSampler_DefaultBankLSB;
            //UInt32 percussionMSB = kAUSampler_DefaultPercussionBankMSB;
            //UInt32 percussionLSB = kAUSampler_DefaultBankLSB;
            OSSTATUS = MusicDeviceMIDIEvent([self.synths[i] pointerValue], 0xB0 | j, 0x00, instrumentMSB, 0); OSSTATUS_CHECK
            OSSTATUS = MusicDeviceMIDIEvent([self.synths[i] pointerValue], 0xB0 | j, 0x20, instrumentLSB, 0); OSSTATUS_CHECK
            
            OSSTATUS = MusicDeviceMIDIEvent([self.synths[i] pointerValue], 0xC0 | j, (UInt32)actualPreset, 0, 0); OSSTATUS_CHECK
            
            enabled = 0;
            OSSTATUS = AudioUnitSetProperty([self.synths[i] pointerValue],
                                            kAUMIDISynthProperty_EnablePreload,
                                            kAudioUnitScope_Global,
                                            0,
                                            &enabled,
                                            sizeof(enabled)); OSSTATUS_CHECK
            
            OSSTATUS = MusicDeviceMIDIEvent([self.synths[i] pointerValue], 0xC0 | j, (UInt32)actualPreset, 0, 0); OSSTATUS_CHECK
        }
    }
}

// swap out the output unit for a regular one and hook everything back up
-(void) setRegularOutput {
    AUNode node = self.ioNode;
    AudioUnit unit = NULL;
    
    AudioComponentDescription desc;
    OSSTATUS = AUGraphNodeInfo(self.graph, self.ioNode, &desc, &unit); OSSTATUS_CHECK
    
    if (desc.componentSubType != kAudioUnitSubType_RemoteIO) {
        OSSTATUS = AudioUnitUninitialize(unit); OSSTATUS_CHECK
        OSSTATUS = AUGraphRemoveNode (self.graph, node); OSSTATUS_CHECK
        
        desc.componentSubType = kAudioUnitSubType_RemoteIO;
        OSSTATUS = AUGraphAddNode (self.graph, &desc, &node); OSSTATUS_CHECK
        OSSTATUS = AUGraphNodeInfo(self.graph, node, NULL, &unit); OSSTATUS_CHECK
        
        OSSTATUS = AUGraphConnectNodeInput (self.graph, self.mixerNode, 0, node, 0); OSSTATUS_CHECK
        
        [self configureAudioUnit:unit];
        
        OSSTATUS = AUGraphUpdate(self.graph, NULL); OSSTATUS_CHECK
        
        self.ioUnit = unit;
        self.ioNode = node;
    }
}

// swap out the output unit for a generic one and hook everything back up
-(void) setGenericOutput {
    CAShow(self.graph);
    
    AUNode node = self.ioNode;
    AudioUnit unit = NULL;
    
    AudioComponentDescription desc;
    OSSTATUS = AUGraphNodeInfo(self.graph, self.ioNode, &desc, &unit); OSSTATUS_CHECK
    
    if (desc.componentSubType != kAudioUnitSubType_GenericOutput) {
        OSSTATUS = AudioUnitUninitialize(unit); OSSTATUS_CHECK
        OSSTATUS = AUGraphRemoveNode (self.graph, node); OSSTATUS_CHECK
        
        desc.componentSubType = kAudioUnitSubType_GenericOutput;
        OSSTATUS = AUGraphAddNode (self.graph, &desc, &node); OSSTATUS_CHECK
        OSSTATUS = AUGraphNodeInfo(self.graph, node, NULL, &unit); OSSTATUS_CHECK
        
        OSSTATUS = AUGraphConnectNodeInput (self.graph, self.mixerNode, 0, node, 0); OSSTATUS_CHECK
        
        [self configureAudioUnit:unit];
        
        OSSTATUS = AUGraphUpdate(self.graph, NULL); OSSTATUS_CHECK
        
        self.ioUnit = unit;
        self.ioNode = node;
    }
}

// from http://stackoverflow.com/questions/30679061/can-i-use-avaudioengine-to-read-from-a-file-process-with-an-audio-unit-and-writ

- (void)renderAudioAndWriteToFile {
    UInt32 size;
    AudioStreamBasicDescription clientFormat;
    memset (&clientFormat, 0, sizeof(AudioStreamBasicDescription));
    size = sizeof(clientFormat);
    AudioUnitGetProperty (self.ioUnit,
                          kAudioUnitProperty_StreamFormat,
                          kAudioUnitScope_Output, 0,
                          &clientFormat, &size);
    
    AudioStreamBasicDescription const *audioDescription = &clientFormat;
    NSString *path = [self filePath];
    ExtAudioFileRef audioFile = [self createAndSetupExtAudioFileWithASBD:audioDescription andFilePath:path];
    if (!audioFile)
        return;
    NSTimeInterval duration = 20;
    NSUInteger lengthInFrames = duration * audioDescription->mSampleRate;
    const NSUInteger kBufferLength = 512;
    AudioBufferList *bufferList = AEAllocateAndInitAudioBufferList(*audioDescription, kBufferLength);
    AudioTimeStamp timeStamp;
    memset (&timeStamp, 0, sizeof(timeStamp));
    timeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    OSStatus status = noErr;
    for (NSUInteger i = kBufferLength; i < lengthInFrames; i += kBufferLength) {
        status = [self renderToBufferList:bufferList writeToFile:audioFile bufferLength:kBufferLength timeStamp:&timeStamp];
        if (status != noErr)
            break;
    }
    if (status == noErr && timeStamp.mSampleTime < lengthInFrames) {
        NSUInteger restBufferLength = (NSUInteger) (lengthInFrames - timeStamp.mSampleTime);
        AudioBufferList *restBufferList = AEAllocateAndInitAudioBufferList(*audioDescription, restBufferLength);
        status = [self renderToBufferList:restBufferList writeToFile:audioFile bufferLength:restBufferLength timeStamp:&timeStamp];
        AEFreeAudioBufferList(restBufferList);
    }
    AEFreeAudioBufferList(bufferList);
    ExtAudioFileDispose(audioFile);
    if (status != noErr)
        NSLog(@"An error has occurred");
    else
        NSLog(@"Finished writing to file at path: %@", path);
}

- (NSString *)filePath {
    NSArray *documentsFolders =
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *fileName = [NSString stringWithFormat:@"%@.m4a", [[NSUUID UUID] UUIDString]];
    NSString *path = [documentsFolders[0] stringByAppendingPathComponent:fileName];
    return path;
}

- (ExtAudioFileRef)createAndSetupExtAudioFileWithASBD:(AudioStreamBasicDescription const *)audioDescription
                                          andFilePath:(NSString *)path {
    AudioStreamBasicDescription destinationFormat;
    memset(&destinationFormat, 0, sizeof(destinationFormat));
    destinationFormat.mChannelsPerFrame = audioDescription->mChannelsPerFrame;
    destinationFormat.mSampleRate = audioDescription->mSampleRate;
    destinationFormat.mFormatID = kAudioFormatMPEG4AAC;
    ExtAudioFileRef audioFile;
    OSStatus status = ExtAudioFileCreateWithURL(
                                                (__bridge CFURLRef) [NSURL fileURLWithPath:path],
                                                kAudioFileM4AType,
                                                &destinationFormat,
                                                NULL,
                                                kAudioFileFlags_EraseFile,
                                                &audioFile
                                                );
    if (status != noErr) {
        NSLog(@"Can not create ext audio file");
        return nil;
    }
    UInt32 codecManufacturer = kAppleSoftwareAudioCodecManufacturer;
    status = ExtAudioFileSetProperty(
                                     audioFile, kExtAudioFileProperty_CodecManufacturer, sizeof(UInt32), &codecManufacturer
                                     );
    status = ExtAudioFileSetProperty(
                                     audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), audioDescription
                                     );
    status = ExtAudioFileWriteAsync(audioFile, 0, NULL);
    if (status != noErr) {
        NSLog(@"Can not setup ext audio file");
        return nil;
    }
    return audioFile;
}

- (OSStatus)renderToBufferList:(AudioBufferList *)bufferList
                   writeToFile:(ExtAudioFileRef)audioFile
                  bufferLength:(NSUInteger)bufferLength
                     timeStamp:(AudioTimeStamp *)timeStamp {
    [self clearBufferList:bufferList];
    AudioUnit outputUnit = self.ioUnit;
    
    OSStatus status = AudioUnitRender(outputUnit, 0, timeStamp, 0, bufferLength, bufferList);
    if (status != noErr) {
        NSLog(@"Can not render audio unit");
        return status;
    }
    timeStamp->mSampleTime += bufferLength;
    status = ExtAudioFileWrite(audioFile, bufferLength, bufferList);
    if (status != noErr)
        NSLog(@"Can not write audio to file");
    return status;
}

- (void)clearBufferList:(AudioBufferList *)bufferList {
    for (int bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; bufferIndex++) {
        memset(bufferList->mBuffers[bufferIndex].mData, 0, bufferList->mBuffers[bufferIndex].mDataByteSize);
    }
}

@end

AudioBufferList *AEAllocateAndInitAudioBufferList(AudioStreamBasicDescription audioFormat, int frameCount) {
    int numberOfBuffers = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? audioFormat.mChannelsPerFrame : 1;
    int channelsPerBuffer = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? 1 : audioFormat.mChannelsPerFrame;
    int bytesPerBuffer = audioFormat.mBytesPerFrame * frameCount;
    AudioBufferList *audio = malloc(sizeof(AudioBufferList) + (numberOfBuffers-1)*sizeof(AudioBuffer));
    if ( !audio ) {
        return NULL;
    }
    audio->mNumberBuffers = numberOfBuffers;
    for ( int i=0; i<numberOfBuffers; i++ ) {
        if ( bytesPerBuffer > 0 ) {
            audio->mBuffers[i].mData = calloc(bytesPerBuffer, 1);
            if ( !audio->mBuffers[i].mData ) {
                for ( int j=0; j<i; j++ ) free(audio->mBuffers[j].mData);
                free(audio);
                return NULL;
            }
        } else {
            audio->mBuffers[i].mData = NULL;
        }
        audio->mBuffers[i].mDataByteSize = bytesPerBuffer;
        audio->mBuffers[i].mNumberChannels = channelsPerBuffer;
    }
    return audio;
}

void AEFreeAudioBufferList(AudioBufferList *bufferList ) {
    for ( int i=0; i<bufferList->mNumberBuffers; i++ ) {
        if ( bufferList->mBuffers[i].mData ) free(bufferList->mBuffers[i].mData);
    }
    free(bufferList);
}
