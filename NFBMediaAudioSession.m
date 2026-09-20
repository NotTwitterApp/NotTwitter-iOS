#import "NFBMediaAudioSession.h"

@implementation NFBMediaAudioSession
static __weak AVPlayer *NFBAudiblePlayer;
+ (BOOL)hasAudioForPlayer:(AVPlayer *)player {
  if (!player) return NO;
  if (player.currentItem.status != AVPlayerItemStatusReadyToPlay) return YES;
  for (AVPlayerItemTrack *track in player.currentItem.tracks)
    if ([track.assetTrack.mediaType isEqual:AVMediaTypeAudio]) return YES;
  return NO;
}
+ (void)prepareMutedPlayback {
  if (NFBAudiblePlayer) return;
  AVAudioSession *session = AVAudioSession.sharedInstance;
  if (![session.category isEqual:AVAudioSessionCategoryAmbient])
    [session setCategory:AVAudioSessionCategoryAmbient mode:AVAudioSessionModeDefault options:0 error:nil];
  // Do not activate a nonmixable session merely to show a muted video.
}
+ (BOOL)setMuted:(BOOL)muted forPlayer:(AVPlayer *)player {
  if (!player) return NO;
  AVAudioSession *session = AVAudioSession.sharedInstance;
  if (muted) {
    player.muted = YES;
    if (NFBAudiblePlayer == player) {
      BOOL resume = player.timeControlStatus != AVPlayerTimeControlStatusPaused;
      float rate = player.rate > 0 ? player.rate : 1.0;
      [player pause];
      NFBAudiblePlayer = nil;
      [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
      [self prepareMutedPlayback];
      if (resume) [player playImmediatelyAtRate:rate];
    } else [self prepareMutedPlayback];
    return YES;
  }
  if (NFBAudiblePlayer == player && !player.muted) return YES;
  if (NFBAudiblePlayer) [self stopPlayer:NFBAudiblePlayer];
  // This path is called only by an explicit sound-on action.
  if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:nil] ||
      ![session setActive:YES error:nil]) {
    player.muted = YES;
    [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    [self prepareMutedPlayback];
    return NO;
  }
  NFBAudiblePlayer = player;
  player.muted = NO;
  return YES;
}
+ (void)stopPlayer:(AVPlayer *)player {
  if (!player) return;
  [player pause];
  [self setMuted:YES forPlayer:player];
}
@end
