#import <AVFoundation/AVFoundation.h>

// Muted previews mix with other apps. Fullscreen video and sound-on actions own audio.
@interface NFBMediaAudioSession : NSObject
+ (void)prepareMutedPlayback;
+ (BOOL)hasAudioForPlayer:(AVPlayer *)player;
+ (BOOL)setMuted:(BOOL)muted forPlayer:(AVPlayer *)player;
+ (void)stopPlayer:(AVPlayer *)player;
@end
