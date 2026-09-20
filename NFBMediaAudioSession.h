#import <AVFoundation/AVFoundation.h>

// Muted playback mixes with other apps. Only an explicit unmute owns audio.
@interface NFBMediaAudioSession : NSObject
+ (void)prepareMutedPlayback;
+ (BOOL)hasAudioForPlayer:(AVPlayer *)player;
+ (BOOL)setMuted:(BOOL)muted forPlayer:(AVPlayer *)player;
+ (void)stopPlayer:(AVPlayer *)player;
@end
