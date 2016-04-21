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

AudioBufferList *AEAllocateAndInitAudioBufferList(AudioStreamBasicDescription audioFormat, int frameCount);
void AEFreeAudioBufferList(AudioBufferList *bufferList );

void MyMIDIReadProc(const MIDIPacketList* pktlist, void* refCon, void* connRefCon)
{
    AVAudioUnitMIDISynth* synth = (__bridge AVAudioUnitMIDISynth*)refCon;
    
    MIDIPacket* packet = (MIDIPacket*)pktlist->packet;
    for (int i = 0; i < pktlist->numPackets; i++) {
        Byte midiStatus = (packet->length >= 1 ? packet->data[0] : 0);
        Byte midiData1 = (packet->length >= 2 ? packet->data[1] : 0);
        Byte midiData2 = (packet->length >= 3 ? packet->data[2] : 0);
        
        MusicDeviceMIDIEvent(synth.audioUnit, midiStatus, midiData1, midiData2, 0);
        
        packet = MIDIPacketNext(packet);
    }
}

@interface ViewController ()
@property (nonatomic) AVAudioEngine* engine;
@property (nonatomic) MusicPlayer player;
@property (nonatomic) NSArray <AVAudioUnitMIDISynth*> * synths;
@property (nonatomic) AVAudioSequencer* sequencer;
@property (nonatomic) NSArray <AVMusicTrack*> * tracks;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    
    // audio graph
    {
        self.engine = [[AVAudioEngine alloc] init];
        
        AVAudioUnitMIDISynth* synth1 = [[AVAudioUnitMIDISynth alloc] init];
        AVAudioUnitMIDISynth* synth2 = [[AVAudioUnitMIDISynth alloc] init];
        AVAudioUnitMIDISynth* synth3 = [[AVAudioUnitMIDISynth alloc] init];
        
        self.synths = @[ synth1, synth2, synth3 ];
        
        [self.engine attachNode:synth1];
        [self.engine attachNode:synth2];
        [self.engine attachNode:synth3];
        
        [self.engine connect:synth1 to:self.engine.mainMixerNode format:nil];
        [self.engine connect:synth2 to:self.engine.mainMixerNode format:nil];
        [self.engine connect:synth3 to:self.engine.mainMixerNode format:nil];
        
        [self.engine startAndReturnError:NULL];
        
        [self setupSoundbanks];
    }
    
    // player
    {
        MIDIClientRef virtualClient;
        NSString* endpointName = @"Virtual MIDI Client";
        MIDIClientCreate((__bridge CFStringRef)endpointName, NULL, NULL, &virtualClient);
        
        MusicPlayer player;
        NewMusicPlayer(&player);
        
        MusicSequence sequence;
        NewMusicSequence(&sequence);
        MusicPlayerSetSequence(player, sequence);
        
        MIDIEndpointRef virtualEndpoint;
        
        NSString* name = [NSString stringWithFormat:@"Virtual MIDI Endpoint %d (%lu)", 1, (long)self];
        MIDIDestinationCreate(virtualClient, (__bridge CFStringRef)name, MyMIDIReadProc, (__bridge void * _Nullable)(self.synths[0]), &virtualEndpoint);
        MusicTrack track1;
        MusicSequenceNewTrack(sequence, &track1);
        MusicTrackSetDestMIDIEndpoint(track1, virtualEndpoint);
        
        name = [NSString stringWithFormat:@"Virtual MIDI Endpoint %d (%lu)", 2, (long)self];
        MIDIDestinationCreate(virtualClient, (__bridge CFStringRef)name, MyMIDIReadProc, (__bridge void * _Nullable)(self.synths[1]), &virtualEndpoint);
        MusicTrack track2;
        MusicSequenceNewTrack(sequence, &track2);
        MusicTrackSetDestMIDIEndpoint(track2, virtualEndpoint);
        
        name = [NSString stringWithFormat:@"Virtual MIDI Endpoint %d (%lu)", 3, (long)self];
        MIDIDestinationCreate(virtualClient, (__bridge CFStringRef)name, MyMIDIReadProc, (__bridge void * _Nullable)(self.synths[2]), &virtualEndpoint);
        MusicTrack track3;
        MusicSequenceNewTrack(sequence, &track3);
        MusicTrackSetDestMIDIEndpoint(track3, virtualEndpoint);
        
        // simple scale
        int scalar = 2;
        for (int i = 0; i < 8; i++) {
            MIDINoteMessage msg;
            msg.channel = i;
            msg.duration = 0.75 * scalar;
            msg.velocity = 0xff;
            
            //msg.note = 50 + i * 2;
            //MusicTrackNewMIDINoteEvent(track1, i * scalar, &msg);
            //
            //msg.note = 50 + i * 2 + 4;
            //MusicTrackNewMIDINoteEvent(track2, (i + 0.1) * scalar, &msg);
            
            msg.note = 50 + i * 2 + 4 + 5;
            MusicTrackNewMIDINoteEvent(track3, (i + 0.2) * scalar, &msg);
            
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
                    
                    MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage);
                    
                    channelMessage.data1 = 0x64;
                    channelMessage.data2 = 0x00;
                    
                    MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage);
                    
                    channelMessage.data1 = 0x06;
                    channelMessage.data2 = semitones;
                    
                    MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage);
                    
                    channelMessage.data1 = 0x26;
                    channelMessage.data2 = cents;
                    
                    MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage);
                    
                    channelMessage.data1 = 0x65;
                    channelMessage.data2 = 0x7F;
                    
                    MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage);
                    
                    channelMessage.data1 = 0x64;
                    channelMessage.data2 = 0x7F;
                    
                    MusicTrackNewMIDIChannelEvent(track3, 0, &channelMessage);
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
                    
                    MusicTrackNewMIDIChannelEvent(track3, (i + 0.2) * scalar + scalar * fraction, &channelMessage);
                }
            }
        }
        
        // new obj-c style player, initialized from the c-style player
        {
            self.player = player;
            
            self.sequencer = [[AVAudioSequencer alloc] initWithAudioEngine:self.engine];
            
            // thanks to http://www.rockhoppertech.com/blog/multi-timbral-avaudiounitmidiinstrument/
            CFDataRef data;
            MusicSequenceFileCreateData(sequence, kMusicSequenceFile_MIDIType, kMusicSequenceFileFlags_EraseFile, 480, &data);
            [self.sequencer loadFromData:(__bridge NSData*)data options:AVMusicSequenceLoadSMF_PreserveTracks error:NULL];
            
            // still gotta update the output nodes
            int i = 0;
            for (AVMusicTrack* track in self.sequencer.tracks) {
                track.destinationAudioUnit = self.synths[i];
                i++;
            }
        }
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

-(void) setupSoundbanks {
    for (int i = 0; i < self.synths.count; i++) {
        NSURL* aUrl = [[NSBundle mainBundle] URLForResource:@"GeneralUser GS MuseScore v1.442" withExtension:@"sf2"];
        
        CFURLRef url = CFBridgingRetain(aUrl);
        AudioUnitSetProperty(self.synths[i].audioUnit,
                             kMusicDeviceProperty_SoundBankURL,
                             kAudioUnitScope_Global,
                             0,
                             &url,
                             sizeof(url));
        //CFBridgingRelease((__bridge CFTypeRef _Nullable)(aUrl));
    }
}

-(void) setupInstruments {
    // random instrument each time
    for (int i = 0; i < self.synths.count; i++) {
        UInt32 actualPreset = arc4random_uniform(100);
        
        for (int j = 0; j < 16; j++) {
            UInt32 enabled = 1;
            AudioUnitSetProperty(self.synths[i].audioUnit, kAUMIDISynthProperty_EnablePreload, kAudioUnitScope_Global, 0, &enabled, sizeof(enabled));

            UInt32 instrumentMSB = kAUSampler_DefaultMelodicBankMSB;
            UInt32 instrumentLSB = kAUSampler_DefaultBankLSB;
            UInt32 percussionMSB = kAUSampler_DefaultPercussionBankMSB;
            UInt32 percussionLSB = kAUSampler_DefaultBankLSB;
            MusicDeviceMIDIEvent(self.synths[i].audioUnit, 0xB0 | j, 0x00, instrumentMSB, 0);
            MusicDeviceMIDIEvent(self.synths[i].audioUnit, 0xB0 | j, 0x20, instrumentLSB, 0);

            MusicDeviceMIDIEvent(self.synths[i].audioUnit, 0xC0 | j, (UInt32)actualPreset, 0, 0);

            enabled = 0;
            AudioUnitSetProperty(self.synths[i].audioUnit, kAUMIDISynthProperty_EnablePreload, kAudioUnitScope_Global, 0, &enabled, sizeof(enabled));

            MusicDeviceMIDIEvent(self.synths[i].audioUnit, 0xC0 | j, (UInt32)actualPreset, 0, 0);
        }
    }
}

-(void) start {
    [self stop];
    
    [self.engine startAndReturnError:NULL];
    
    [self setupInstruments];

    //MusicPlayerSetTime(self.player, 0);
    //MusicPlayerStart(self.player);
    
    self.sequencer.currentPositionInSeconds = 0;
    [self.sequencer startAndReturnError:NULL];
}

-(void) render {
    [self start];
    
    [self renderAudioAndWriteToFile];
}

-(void) stop {
    //MusicPlayerStop(self.player);
    
    [self.sequencer stop];
}

// from http://stackoverflow.com/questions/30679061/can-i-use-avaudioengine-to-read-from-a-file-process-with-an-audio-unit-and-writ

- (void)renderAudioAndWriteToFile {
    [self.engine pause];
    
    AVAudioOutputNode *outputNode = self.engine.outputNode;
    AudioStreamBasicDescription const *audioDescription = [outputNode outputFormatForBus:0].streamDescription;
    NSString *path = [self filePath];
    ExtAudioFileRef audioFile = [self createAndSetupExtAudioFileWithASBD:audioDescription andFilePath:path];
    if (!audioFile)
        return;
    NSTimeInterval duration = 20;
    NSUInteger lengthInFrames = duration * audioDescription->mSampleRate;
    const NSUInteger kBufferLength = 4096;
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
    AudioUnit outputUnit = self.engine.outputNode.audioUnit;
    
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
