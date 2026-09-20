#import "NFBMediaPreviewView.h"

#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import "NFBMediaPresentationPolicy.h"
#import "NFBMediaAudioSession.h"
#import "NFBComposerMediaLayout.h"

#import "NFBTheme.h"
#import "NFBMediaAttachmentPolicy.h"

static NSString *const NFBMediaTypePhoto = @"photo";
static NSString *const NFBMediaTypeGIF = @"gif";
static NSString *const NFBMediaTypeVideo = @"video";
static CGFloat const NFBMediaComposerRailTileGap = 8.0;
static CGFloat const NFBMediaComposerRailTileCornerRadius = 12.0;

static UIImage *NFBAnimatedImageWithData(NSData *data);

@interface NFBMediaOverlayButton : UIButton
@end
@implementation NFBMediaOverlayButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  CGFloat dx = MAX(0, (44 - CGRectGetWidth(self.bounds)) / 2);
  CGFloat dy = MAX(0, (44 - CGRectGetHeight(self.bounds)) / 2);
  return !self.hidden && self.alpha > .01 && self.enabled && CGRectContainsPoint(CGRectInset(self.bounds, -dx, -dy), point);
}
@end

@interface NFBMediaPreviewTile : UIControl

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *shadeView;
@property (nonatomic, strong) UIView *playCircleView;
@property (nonatomic, strong) UIImageView *playIconView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UILabel *moreLabel;
@property (nonatomic, strong) UILabel *positionLabel;
@property (nonatomic, strong) UIVisualEffectView *warningBlurView;
@property (nonatomic, strong) UIView *warningScrimView;
@property (nonatomic, strong) UILabel *warningTitleLabel;
@property (nonatomic, strong) UILabel *warningSubtitleLabel;
@property (nonatomic, strong) UILabel *warningActionLabel;
@property (nonatomic, strong) UIButton *removeButton;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UIButton *altButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, assign) BOOL userRequestedPlayback;
@property (nonatomic, copy) NSString *imageURLString;
@property (nonatomic, copy) NSString *warningKey;
@property (nonatomic, assign) NSUInteger mediaIndex;
@property (nonatomic, assign) BOOL showsRemoveButton;
@property (nonatomic, assign) BOOL warningActive;
@property (nonatomic, strong) AVPlayer *inlinePlayer;
@property (nonatomic, strong) AVPlayerLayer *inlineLayer;
@property (nonatomic, strong) AVURLAsset *durationAsset;
@property (nonatomic, copy) NSString *videoURLString;
@property (nonatomic, assign) NSTimeInterval videoDuration;
@property (nonatomic, assign) BOOL videoIsGIF;
@property (nonatomic, assign) BOOL inlineEnded;
@property (nonatomic, assign) BOOL hideQuoteAlt;
@property (nonatomic, copy) NSString *altText;
- (CGFloat)visibleVideoFraction;
- (void)loadVideoDurationIfNeeded;
- (void)startInlinePlayback;
- (void)stopInlinePlayback;
- (void)updateVideoBadge;
- (void)setDisplayedImage:(UIImage *)image;
- (void)updateGIFAnimation;

- (void)configureWithItem:(NSDictionary *)item extraCount:(NSUInteger)extraCount warningRevealed:(BOOL)warningRevealed warningKey:(NSString *)warningKey;
- (void)applyTheme;

@end

@interface NFBInlineVideoCoordinator : NSObject
@property (nonatomic, strong) NSHashTable<NFBMediaPreviewTile *> *tiles;
@property (nonatomic, weak) NFBMediaPreviewTile *activeTile;
@property (nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)addTile:(NFBMediaPreviewTile *)tile;
- (void)removeTile:(NFBMediaPreviewTile *)tile;
- (void)pauseAll;
- (void)resumeMonitoring;
- (void)selectTileForPlayback:(NFBMediaPreviewTile *)tile;
@end
@implementation NFBInlineVideoCoordinator
+ (instancetype)shared {
  static NFBInlineVideoCoordinator *coordinator; static dispatch_once_t once;
  dispatch_once(&once, ^{ coordinator = [self new]; coordinator.tiles = [NSHashTable weakObjectsHashTable];
    [[NSNotificationCenter defaultCenter] addObserver:coordinator selector:@selector(pauseAll) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:coordinator selector:@selector(resumeMonitoring) name:UIApplicationDidBecomeActiveNotification object:nil];
  });
  return coordinator;
}
- (void)resumeMonitoring {
  if (self.timer || !self.tiles.count || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
  self.timer = [NSTimer timerWithTimeInterval:0.2 target:self selector:@selector(update) userInfo:nil repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)addTile:(NFBMediaPreviewTile *)tile { [self.tiles addObject:tile]; [self resumeMonitoring]; }
- (void)removeTile:(NFBMediaPreviewTile *)tile {
  if (self.activeTile == tile) { [tile stopInlinePlayback]; self.activeTile = nil; }
  [self.tiles removeObject:tile];
  if (!self.tiles.count) { [self.timer invalidate]; self.timer = nil; }
}
- (void)pauseAll {
  [self.activeTile stopInlinePlayback]; self.activeTile = nil;
  for (NFBMediaPreviewTile *tile in self.tiles.allObjects) [tile.imageView stopAnimating];
  [self.timer invalidate]; self.timer = nil;
}
- (void)selectTileForPlayback:(NFBMediaPreviewTile *)tile {
  if (self.activeTile != tile) [self.activeTile stopInlinePlayback];
  self.activeTile = tile;
  tile.userRequestedPlayback = YES;
  if (tile.inlineEnded) [tile.inlinePlayer seekToTime:kCMTimeZero];
  tile.inlineEnded = NO;
  [tile startInlinePlayback];
}
- (void)update {
  BOOL foreground = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
  BOOL playback = !UIAccessibilityIsVoiceOverRunning() && !UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled;
  NFBMediaPreviewTile *best = nil; CGFloat bestScore = -CGFLOAT_MAX;
  for (NFBMediaPreviewTile *tile in self.tiles.allObjects) {
    [tile updateGIFAnimation];
    if (!tile.videoURLString.length) continue;
    CGFloat visible = [tile visibleVideoFraction];
    if (visible > 0) [tile loadVideoDurationIfNeeded];
    if (tile.inlineEnded && !tile.inlinePlayer) {
      NSDictionary *state = [NFBMediaPreviewView playbackStateForVideoURL:tile.videoURLString];
      // A fullscreen replay/seek can move a previously finished inline video
      // back into its playable range without reusing or reconfiguring the tile.
      if (NFBInlineVideoCanResumeEnded([state[@"position"] doubleValue], [state[@"duration"] doubleValue])) tile.inlineEnded = NO;
    }
    BOOL preference = ![NSUserDefaults.standardUserDefaults boolForKey:tile.videoIsGIF ? @"nfb_gif_autoplay_disabled" : @"nfb_video_autoplay_disabled"];
    BOOL eligible = NFBInlineAutoplayEligible(visible, tile == self.activeTile, foreground, playback && preference,
                                             tile.warningActive, tile.showsRemoveButton && !tile.videoIsGIF, visible == 0);
    if (tile.userRequestedPlayback && foreground && visible > 0 && !tile.warningActive && !tile.showsRemoveButton) eligible = YES;
    if (!eligible || (tile.inlineEnded && !tile.videoIsGIF)) continue;
    CGRect frame = [tile convertRect:tile.bounds toView:tile.window];
    CGFloat distance = fabs(CGRectGetMidY(frame) - CGRectGetMidY(tile.window.bounds));
    CGFloat score = visible * 10000.0 - distance + (tile == self.activeTile ? 500.0 : 0.0) + (tile.userRequestedPlayback ? 20000.0 : 0.0);
    if (score > bestScore) { best = tile; bestScore = score; }
  }
  if (best != self.activeTile) { [self.activeTile stopInlinePlayback]; self.activeTile = best; [best startInlinePlayback]; }
  if (best && !best.inlinePlayer) [best startInlinePlayback];
  [best updateVideoBadge];
}
@end

@implementation NFBMediaPreviewTile

- (void)didMoveToWindow {
  [super didMoveToWindow];
  if (self.window) [[NFBInlineVideoCoordinator shared] addTile:self];
  else { [self.imageView stopAnimating]; [self stopInlinePlayback]; [[NFBInlineVideoCoordinator shared] removeTile:self]; }
}
- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NFBMediaAudioSession stopPlayer:_inlinePlayer];
  [_durationAsset cancelLoading];
}
- (CGFloat)visibleVideoFraction {
  if (!self.window || self.hidden || (!self.videoURLString.length && !self.imageView.animationImages.count) || self.warningActive || (self.showsRemoveButton && !self.videoIsGIF)) return 0;
  CGRect frame = [self convertRect:self.bounds toView:self.window];
  if (CGRectIsEmpty(frame)) return 0;
  CGRect visible = CGRectIntersection(frame, UIEdgeInsetsInsetRect(self.window.bounds, self.window.safeAreaInsets));
  for (UIView *ancestor = self.superview; ancestor; ancestor = ancestor.superview) {
    if (ancestor.hidden || ancestor.alpha < 0.01) return 0;
    if (ancestor.clipsToBounds) visible = CGRectIntersection(visible, [ancestor convertRect:ancestor.bounds toView:self.window]);
  }
  if (CGRectIsNull(visible) || CGRectIsEmpty(visible)) return 0;
  // Includes navigation bars, other tabs, sheets, drawers and fullscreen media.
  CGPoint center = CGPointMake(CGRectGetMidX(visible), CGRectGetMidY(visible));
  UIView *hit = [self.window hitTest:center withEvent:nil];
  if (hit != self && ![hit isDescendantOfView:self]) return 0;
  return (CGRectGetHeight(visible) / CGRectGetHeight(frame)) * (CGRectGetWidth(visible) / CGRectGetWidth(frame));
}
- (void)loadVideoDurationIfNeeded {
  if (self.videoDuration > 0 || self.durationAsset || !self.videoURLString.length) return;
  NSDictionary *state = [NFBMediaPreviewView playbackStateForVideoURL:self.videoURLString];
  self.videoDuration = [state[@"duration"] doubleValue];
  if (self.videoDuration > 0) { [self updateVideoBadge]; return; }
  NSURL *url = [NSURL URLWithString:self.videoURLString];
  if (!url) return;
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
  self.durationAsset = asset;
  NSString *requestedURL = self.videoURLString;
  __weak typeof(self) weakSelf = self;
  [asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
    double duration = CMTimeGetSeconds(asset.duration);
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) self = weakSelf;
      if (!self || ![self.videoURLString isEqual:requestedURL]) return;
      if (isfinite(duration) && duration > 0) {
        self.videoDuration = duration;
        NSDictionary *latestState = [NFBMediaPreviewView playbackStateForVideoURL:requestedURL];
        [NFBMediaPreviewView recordVideoURL:requestedURL position:[latestState[@"position"] doubleValue] duration:duration];
        [self updateVideoBadge];
      }
    });
  }];
}
- (void)startInlinePlayback {
  if (!self.inlinePlayer) {
    NSURL *url = [NSURL URLWithString:self.videoURLString];
    if (!url) return;
    [NFBMediaAudioSession prepareMutedPlayback];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    item.preferredForwardBufferDuration = 3.0;
    self.inlinePlayer = [AVPlayer playerWithPlayerItem:item];
    self.inlinePlayer.muted = YES;
    self.inlinePlayer.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    self.inlineLayer = [AVPlayerLayer playerLayerWithPlayer:self.inlinePlayer];
    self.inlineLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.inlineLayer.frame = self.imageView.bounds;
    [self.imageView.layer addSublayer:self.inlineLayer];
    NSDictionary *state = [NFBMediaPreviewView playbackStateForVideoURL:self.videoURLString];
    double position = [state[@"position"] doubleValue], duration = [state[@"duration"] doubleValue];
    if (position > 0 && (duration <= 0 || position < duration - 0.2))
      [self.inlinePlayer seekToTime:CMTimeMakeWithSeconds(position, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inlinePlaybackEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
  }
  if (self.inlineEnded && !self.videoIsGIF) return;
  [self.inlinePlayer play];
  [self updateVideoBadge];
}
- (void)stopInlinePlayback {
  self.userRequestedPlayback = NO;
  if (!self.inlinePlayer) return;
  [self updateVideoBadge];
  [NFBMediaAudioSession stopPlayer:self.inlinePlayer];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.inlinePlayer.currentItem];
  [self.inlineLayer removeFromSuperlayer];
  self.inlineLayer = nil;
  self.inlinePlayer = nil;
  self.playCircleView.hidden = self.warningActive;
  [self updateMuteButton];
}
- (void)muteTapped {
  if (!self.videoURLString.length || self.warningActive || self.showsRemoveButton) return;
  BOOL muted = self.inlinePlayer ? self.inlinePlayer.muted : YES;
  if (muted) [[NFBInlineVideoCoordinator shared] selectTileForPlayback:self];
  [NFBMediaAudioSession setMuted:!muted forPlayer:self.inlinePlayer];
  [self updateMuteButton];
}
- (void)updateMuteButton {
  BOOL hasAudio = !self.inlinePlayer || [NFBMediaAudioSession hasAudioForPlayer:self.inlinePlayer];
  self.muteButton.hidden = !self.videoURLString.length || self.videoIsGIF || self.warningActive || self.showsRemoveButton || !hasAudio;
  BOOL muted = !self.inlinePlayer || self.inlinePlayer.muted;
  [self.muteButton setImage:NFBTemplateIcon(muted ? @"nfb_sound_off" : @"nfb_sound") forState:UIControlStateNormal];
  self.muteButton.accessibilityLabel = muted ? @"Unmute video" : @"Mute video";
}
- (void)inlinePlaybackEnded:(NSNotification *)notification {
  if (notification.object != self.inlinePlayer.currentItem) return;
  if (NFBInlineVideoShouldLoop(self.videoIsGIF, self.videoDuration)) { [self.inlinePlayer seekToTime:kCMTimeZero]; [self.inlinePlayer play]; }
  else { self.inlineEnded = YES; [NFBMediaAudioSession stopPlayer:self.inlinePlayer]; self.playCircleView.hidden = NO; }
  [self updateVideoBadge];
}
- (void)updateVideoBadge {
  if (!self.videoURLString.length) return;
  double position = [[NFBMediaPreviewView playbackStateForVideoURL:self.videoURLString][@"position"] doubleValue];
  if (self.inlinePlayer) {
    double duration = CMTimeGetSeconds(self.inlinePlayer.currentItem.duration);
    if (isfinite(duration) && duration > 0) self.videoDuration = duration;
    double current = CMTimeGetSeconds(self.inlinePlayer.currentTime);
    if (isfinite(current)) position = current;
    self.playCircleView.hidden = self.warningActive || (self.inlineLayer.readyForDisplay && !self.inlineEnded);
    [NFBMediaPreviewView recordVideoURL:self.videoURLString position:position duration:self.videoDuration];
  }
  char time[32];
  NFBMediaRemainingTime(self.videoDuration, position, time, sizeof(time));
  self.badgeLabel.text = self.videoIsGIF ? @"GIF" : [NSString stringWithUTF8String:time];
  self.badgeLabel.hidden = self.warningActive || !self.badgeLabel.text.length;
  [self updateMuteButton];
  [self setNeedsLayout];
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.clipsToBounds = YES;
    self.backgroundColor = NFBColorElevatedBackground();

    self.imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    self.imageView.userInteractionEnabled = NO;
    [self addSubview:self.imageView];

    self.shadeView = [[UIView alloc] initWithFrame:self.bounds];
    self.shadeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.shadeView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.0];
    self.shadeView.userInteractionEnabled = NO;
    [self addSubview:self.shadeView];

    self.playCircleView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 54.0, 54.0)];
    self.playCircleView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.48];
    self.playCircleView.layer.cornerRadius = 27.0;
    self.playCircleView.userInteractionEnabled = NO;
    self.playCircleView.hidden = YES;
    [self addSubview:self.playCircleView];

	    self.playIconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_play")];
    self.playIconView.tintColor = UIColor.whiteColor;
    self.playIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.playIconView.frame = CGRectMake(18.0, 15.0, 22.0, 24.0);
    self.playIconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.playIconView.userInteractionEnabled = NO;
    [self.playCircleView addSubview:self.playIconView];

    self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.badgeLabel.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.74];
    self.badgeLabel.textColor = UIColor.whiteColor;
    self.badgeLabel.font = NFBFont(12.0, NFBFontWeightHeavy);
    self.badgeLabel.textAlignment = NSTextAlignmentCenter;
    self.badgeLabel.layer.cornerRadius = 4.0;
    self.badgeLabel.clipsToBounds = YES;
    self.badgeLabel.userInteractionEnabled = NO;
    self.badgeLabel.hidden = YES;
    [self addSubview:self.badgeLabel];

    self.moreLabel = [[UILabel alloc] initWithFrame:self.bounds];
    self.moreLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.moreLabel.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.42];
    self.moreLabel.textColor = UIColor.whiteColor;
    self.moreLabel.font = NFBFont(26.0, NFBFontWeightHeavy);
    self.moreLabel.textAlignment = NSTextAlignmentCenter;
    self.moreLabel.userInteractionEnabled = NO;
    self.moreLabel.hidden = YES;
    [self addSubview:self.moreLabel];
    self.positionLabel = [[UILabel alloc] init];
    self.positionLabel.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.65];
    self.positionLabel.textColor = UIColor.whiteColor;
    self.positionLabel.font = NFBFont(12.0, NFBFontWeightBold);
    self.positionLabel.textAlignment = NSTextAlignmentCenter;
    self.positionLabel.layer.cornerRadius = 10.0;
    self.positionLabel.clipsToBounds = YES;
    self.positionLabel.hidden = YES;
    [self addSubview:self.positionLabel];

	    self.warningBlurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.warningBlurView.frame = self.bounds;
    self.warningBlurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.warningBlurView.userInteractionEnabled = NO;
    self.warningBlurView.hidden = YES;
    [self addSubview:self.warningBlurView];

    self.warningScrimView = [[UIView alloc] initWithFrame:self.bounds];
    self.warningScrimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.warningScrimView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.24];
    self.warningScrimView.userInteractionEnabled = NO;
    self.warningScrimView.hidden = YES;
    [self addSubview:self.warningScrimView];

    self.warningTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.warningTitleLabel.textColor = UIColor.whiteColor;
    self.warningTitleLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
    self.warningTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.warningTitleLabel.numberOfLines = 2;
    self.warningTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.warningTitleLabel.userInteractionEnabled = NO;
    self.warningTitleLabel.hidden = YES;
    [self addSubview:self.warningTitleLabel];

    self.warningSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.warningSubtitleLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.86];
    self.warningSubtitleLabel.font = NFBFont(12.0, NFBFontWeightRegular);
    self.warningSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.warningSubtitleLabel.numberOfLines = 2;
    self.warningSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.warningSubtitleLabel.userInteractionEnabled = NO;
    self.warningSubtitleLabel.hidden = YES;
    [self addSubview:self.warningSubtitleLabel];

    self.warningActionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.warningActionLabel.textColor = NFBColorAccent();
    self.warningActionLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
    self.warningActionLabel.textAlignment = NSTextAlignmentCenter;
    self.warningActionLabel.layer.cornerRadius = 0.0;
    self.warningActionLabel.layer.borderWidth = 0.0;
    self.warningActionLabel.backgroundColor = UIColor.clearColor;
    self.warningActionLabel.clipsToBounds = NO;
    self.warningActionLabel.userInteractionEnabled = NO;
    self.warningActionLabel.hidden = YES;
    [self addSubview:self.warningActionLabel];

    self.removeButton = [NFBMediaOverlayButton buttonWithType:UIButtonTypeCustom];
    self.removeButton.frame = CGRectMake(0.0, 0.0, 24.0, 24.0);
    self.removeButton.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.72];
    self.removeButton.layer.cornerRadius = 12.0;
    self.removeButton.tintColor = UIColor.whiteColor;
    self.removeButton.hidden = YES;
    self.removeButton.adjustsImageWhenHighlighted = NO;
    [self.removeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
    self.removeButton.imageEdgeInsets = UIEdgeInsetsMake(6.0, 6.0, 6.0, 6.0);
    [self addSubview:self.removeButton];

    self.editButton = [NFBMediaOverlayButton buttonWithType:UIButtonTypeCustom];
    self.editButton.frame = CGRectMake(0.0, 0.0, 28.0, 24.0);
    self.editButton.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.72];
    self.editButton.layer.cornerRadius = 12.0;
    self.editButton.tintColor = UIColor.whiteColor;
    self.editButton.hidden = YES;
    self.editButton.adjustsImageWhenHighlighted = NO;
    [self.editButton setImage:NFBTemplateIcon(@"nfb_paintbrush_stroke") forState:UIControlStateNormal];
    self.editButton.imageEdgeInsets = UIEdgeInsetsMake(8, 8, 8, 8);
    [self addSubview:self.editButton];

    self.altButton = [NFBMediaOverlayButton buttonWithType:UIButtonTypeCustom];
    self.altButton.frame = CGRectMake(0.0, 0.0, 32.0, 20.0);
    self.altButton.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.72];
    self.altButton.layer.cornerRadius = 4.0;
    self.altButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.altButton.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.92].CGColor;
    self.altButton.hidden = YES;
    self.altButton.adjustsImageWhenHighlighted = NO;
    [self.altButton setTitle:@"ALT" forState:UIControlStateNormal];
    [self.altButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.altButton.titleLabel.font = NFBFont(10.0, NFBFontWeightHeavy);
    [self addSubview:self.altButton];
    self.muteButton = [NFBMediaOverlayButton buttonWithType:UIButtonTypeCustom];
    NFBIPAApplyOnMediaFloatingButtonAppearance(self.muteButton, 12.0);
    self.muteButton.imageEdgeInsets = UIEdgeInsetsMake(4, 4, 4, 4);
    self.muteButton.hidden = YES;
    [self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.muteButton];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGSize positionSize = [self.positionLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 22.0)];
  CGFloat positionWidth = MAX(38.0, ceil(positionSize.width) + 14.0);
  self.positionLabel.frame = CGRectMake(CGRectGetWidth(self.bounds) - positionWidth - 8.0, 8.0, positionWidth, 22.0);
  CGFloat shortSide = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
  CGFloat playSize = shortSide < 120.0 ? 38.0 : 54.0;
  self.playCircleView.bounds = CGRectMake(0.0, 0.0, playSize, playSize);
  self.playCircleView.layer.cornerRadius = playSize / 2.0;
  self.playCircleView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
  CGFloat iconWidth = shortSide < 120.0 ? 15.0 : 22.0;
  CGFloat iconHeight = shortSide < 120.0 ? 17.0 : 24.0;
  self.playIconView.frame = CGRectMake((playSize - iconWidth) * 0.5 + 1.0,
                                       (playSize - iconHeight) * 0.5,
                                       iconWidth,
                                       iconHeight);
  self.inlineLayer.frame = self.imageView.bounds;
  CGFloat badgeWidth = MAX(38.0, ceil([self.badgeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 21)].width) + 12.0);
  self.badgeLabel.frame = CGRectMake(7.0, CGRectGetHeight(self.bounds) - 28.0, badgeWidth, 21.0);
  self.warningBlurView.frame = self.bounds;
  self.warningScrimView.frame = self.bounds;
  CGFloat warningInset = shortSide < 130.0 ? 10.0 : 16.0;
  CGFloat warningWidth = MAX(0.0, CGRectGetWidth(self.bounds) - warningInset * 2.0);
  BOOL compactWarning = shortSide < 130.0 || CGRectGetHeight(self.bounds) < 128.0;
  self.warningTitleLabel.font = NFBFont(compactWarning ? 13.0 : 15.0, NFBFontWeightHeavy);
  self.warningSubtitleLabel.font = NFBFont(compactWarning ? 11.0 : 12.0, NFBFontWeightRegular);
  self.warningActionLabel.font = NFBFont(compactWarning ? 13.0 : 14.0, NFBFontWeightHeavy);
  BOOL showSubtitle = self.warningActive && !compactWarning;
  self.warningSubtitleLabel.hidden = !showSubtitle;
  CGFloat titleHeight = compactWarning ? 34.0 : 38.0;
  CGFloat subtitleHeight = showSubtitle ? 34.0 : 0.0;
  CGFloat actionHeight = 22.0;
  CGFloat gap = compactWarning ? 2.0 : 6.0;
  CGFloat totalHeight = titleHeight + (showSubtitle ? gap + subtitleHeight : 0.0) + gap + actionHeight;
  CGFloat startY = floor((CGRectGetHeight(self.bounds) - totalHeight) * 0.5);
  self.warningTitleLabel.frame = CGRectMake(warningInset, startY, warningWidth, titleHeight);
  CGFloat actionY = startY + titleHeight + gap;
  if (showSubtitle) {
    self.warningSubtitleLabel.frame = CGRectMake(warningInset, actionY, warningWidth, subtitleHeight);
    actionY += subtitleHeight + gap;
  }
  CGFloat actionWidth = MIN(88.0, MAX(44.0, warningWidth));
  self.warningActionLabel.frame = CGRectMake(floor((CGRectGetWidth(self.bounds) - actionWidth) * 0.5), actionY, actionWidth, actionHeight);
  self.removeButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 29.0, 5.0, 24.0, 24.0);
  self.editButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 33.0, CGRectGetHeight(self.bounds) - 29.0, 28.0, 24.0);
  self.altButton.frame = CGRectMake(6.0, self.showsRemoveButton ? 6.0 : MAX(6.0, CGRectGetHeight(self.bounds) - 26.0), 32.0, 20.0);
  if (self.showsRemoveButton) {
    self.removeButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 37, 8, 29, 29);
    self.removeButton.layer.cornerRadius = 14.5;
    self.editButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 42, CGRectGetHeight(self.bounds) - 42, 34, 34);
    self.editButton.layer.cornerRadius = 17;
    self.altButton.frame = CGRectMake(8, CGRectGetHeight(self.bounds) - 42, 34, 34);
    self.altButton.layer.cornerRadius = 17;
  }
  CGFloat muteX = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? 8 : CGRectGetWidth(self.bounds) - 32;
  self.muteButton.frame = CGRectMake(MAX(6.0, muteX), MAX(6.0, CGRectGetHeight(self.bounds) - 32.0), 24.0, 24.0);
}

- (void)setShowsRemoveButton:(BOOL)showsRemoveButton {
  _showsRemoveButton = showsRemoveButton;
  self.removeButton.hidden = !showsRemoveButton;
}

- (void)configureWithItem:(NSDictionary *)item extraCount:(NSUInteger)extraCount warningRevealed:(BOOL)warningRevealed warningKey:(NSString *)warningKey {
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : NFBMediaTypePhoto;
  NSString *thumbnailURL = [item[@"thumbnailURL"] isKindOfClass:NSString.class] ? item[@"thumbnailURL"] : @"";
  if ([type isEqual:NFBMediaTypeGIF] && ![item[@"videoURL"] length] && [item[@"fullsizeURL"] length]) thumbnailURL = item[@"fullsizeURL"];
  if (thumbnailURL.length == 0) thumbnailURL = [item[@"fullsizeURL"] isKindOfClass:NSString.class] ? item[@"fullsizeURL"] : @"";

  self.imageURLString = thumbnailURL;
  self.warningKey = warningKey ?: @"";
  [self setDisplayedImage:nil];
  UIImage *localImage = [item[@"image"] isKindOfClass:UIImage.class] ? item[@"image"] : nil;
  NSData *imageData = [item[@"data"] isKindOfClass:NSData.class] ? item[@"data"] : nil;
  if (imageData.length > 0 && (!localImage || ([type isEqual:NFBMediaTypeGIF] && ![item[@"videoURL"] length]))) localImage = NFBAnimatedImageWithData(imageData) ?: localImage;
  self.playCircleView.hidden = !([type isEqualToString:NFBMediaTypeVideo] || [type isEqualToString:NFBMediaTypeGIF]);
  self.badgeLabel.hidden = !([type isEqualToString:NFBMediaTypeVideo] || [type isEqualToString:NFBMediaTypeGIF]);
  NSString *videoURL = [item[@"videoURL"] isKindOfClass:NSString.class] ? item[@"videoURL"] : @"";
  if (![self.videoURLString isEqual:videoURL]) {
    [self stopInlinePlayback]; [self.durationAsset cancelLoading]; self.durationAsset = nil;
    self.videoURLString = videoURL; self.inlineEnded = NO; self.videoDuration = [item[@"duration"] doubleValue];
  }
  self.videoIsGIF = [type isEqual:NFBMediaTypeGIF];
  self.badgeLabel.text = [type isEqual:NFBMediaTypeGIF] ? @"GIF" : @"";
  [self updateVideoBadge];
  BOOL composerChrome = self.showsRemoveButton && extraCount == 0;
  self.editButton.hidden = !composerChrome || [type isEqualToString:NFBMediaTypeGIF];
  NSString *alt = [item[@"alt"] isKindOfClass:NSString.class] ? item[@"alt"] : @"";
  self.altText = [alt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  self.altButton.hidden = !NFBMediaShowsAltBadge([type isEqual:NFBMediaTypePhoto] || (composerChrome && [type isEqual:NFBMediaTypeGIF]), self.altText.length > 0, composerChrome, NO, self.hideQuoteAlt, NO);
  [self.altButton setTitle:composerChrome ? nil : @"ALT" forState:UIControlStateNormal];
  [self.altButton setImage:composerChrome ? NFBTemplateIcon(alt.length ? @"nfb_alt_compose_pip" : @"nfb_alt_compose") : nil forState:UIControlStateNormal];
  self.altButton.imageEdgeInsets = composerChrome ? UIEdgeInsetsMake(8, 8, 8, 8) : UIEdgeInsetsZero;
  self.altButton.tintColor = UIColor.whiteColor;
  self.altButton.layer.borderWidth = composerChrome ? 0 : 1.0 / UIScreen.mainScreen.scale;
  self.altButton.accessibilityLabel = composerChrome ? (alt.length ? @"Edit image description" : @"Add image description") : @"View image description";
  self.altButton.alpha = 1;
  self.shadeView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:extraCount > 0 ? 0.42 : 0.0];
  self.moreLabel.hidden = extraCount == 0;
  self.moreLabel.text = extraCount > 0 ? [NSString stringWithFormat:@"+%lu", (unsigned long)extraCount] : @"";
  NSDictionary *warning = [item[@"moderationWarning"] isKindOfClass:NSDictionary.class] ? item[@"moderationWarning"] : nil;
  self.warningActive = warning.count > 0 && !warningRevealed && !composerChrome;
  self.warningBlurView.hidden = !self.warningActive;
  self.warningScrimView.hidden = !self.warningActive;
  self.warningTitleLabel.hidden = !self.warningActive;
  self.warningSubtitleLabel.hidden = !self.warningActive;
  self.warningActionLabel.hidden = !self.warningActive;
  if (self.warningActive) {
    self.warningTitleLabel.text = [warning[@"title"] isKindOfClass:NSString.class] ? warning[@"title"] : @"This Tweet might include sensitive content.";
    self.warningSubtitleLabel.text = [warning[@"subtitle"] isKindOfClass:NSString.class] ? warning[@"subtitle"] : @"";
    self.warningActionLabel.text = [warning[@"action"] isKindOfClass:NSString.class] ? warning[@"action"] : @"Show";
    self.playCircleView.hidden = YES;
    self.badgeLabel.hidden = YES;
    self.altButton.hidden = YES;
    [self stopInlinePlayback];
  }
  self.removeButton.hidden = !self.showsRemoveButton;
  [self updateMuteButton];
  if (localImage) [self setDisplayedImage:localImage];
  else [self loadImageURL:thumbnailURL];
  [self setNeedsLayout];
}

- (void)applyTheme {
  self.backgroundColor = NFBColorElevatedBackground();
  self.warningActionLabel.textColor = NFBColorAccent();
}

- (void)setDisplayedImage:(UIImage *)image {
  [self.imageView stopAnimating];
  self.imageView.animationImages = image.images;
  self.imageView.animationDuration = image.duration;
  self.imageView.animationRepeatCount = 0;
  self.imageView.image = image.images.firstObject ?: image;
  [self updateGIFAnimation];
}

- (void)updateGIFAnimation {
  if (!self.imageView.animationImages.count) return;
  BOOL eligible = self.videoIsGIF && !self.videoURLString.length && [self visibleVideoFraction] >= .01 &&
      UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
      !UIAccessibilityIsReduceMotionEnabled() && !UIAccessibilityIsVoiceOverRunning() &&
      !NSProcessInfo.processInfo.lowPowerModeEnabled &&
      ![NSUserDefaults.standardUserDefaults boolForKey:@"nfb_gif_autoplay_disabled"];
  if (eligible && !self.imageView.isAnimating) [self.imageView startAnimating];
  else if (!eligible) [self.imageView stopAnimating];
  self.playCircleView.hidden = self.warningActive || eligible;
}

- (void)loadImageURL:(NSString *)urlString {
  if (urlString.length == 0) return;
  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    [self setDisplayedImage:cached];
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;

  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = NFBAnimatedImageWithData(data);
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.imageURLString isEqualToString:urlString]) [self setDisplayedImage:image];
    });
  }];
  [task resume];
}

static UIImage *NFBAnimatedImageWithData(NSData *data) {
  if (data.length == 0) return nil;
  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
  if (!source) return [UIImage imageWithData:data];
  size_t count = CGImageSourceGetCount(source);
  if (count <= 1) {
    CFRelease(source);
    return [UIImage imageWithData:data];
  }

  NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:count];
  NSTimeInterval duration = 0.0;
  for (size_t index = 0; index < count; index++) {
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, index, NULL);
    if (!imageRef) continue;
    NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    NSDictionary *gifProperties = [properties[(NSString *)kCGImagePropertyGIFDictionary] isKindOfClass:NSDictionary.class] ? properties[(NSString *)kCGImagePropertyGIFDictionary] : @{};
    NSNumber *delay = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
    NSTimeInterval frameDuration = delay.doubleValue > 0.011 ? delay.doubleValue : 0.1;
    duration += frameDuration;
    [frames addObject:[UIImage imageWithCGImage:imageRef scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]];
    CGImageRelease(imageRef);
  }
  CFRelease(source);
  if (frames.count == 0) return [UIImage imageWithData:data];
  return [UIImage animatedImageWithImages:frames duration:MAX(duration, 0.1)];
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 240;
  });
  return cache;
}

@end

@interface NFBMediaPreviewView () <UIScrollViewDelegate>

@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *mediaItems;
@property (nonatomic, strong) NSMutableArray<NFBMediaPreviewTile *> *tiles;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) CGFloat carouselLayoutWidth;
@property (nonatomic, weak) NFBMediaPreviewTile *draggingTile;
@property (nonatomic, assign) NSUInteger draggingFromIndex;
@property (nonatomic, assign) NSUInteger draggingTargetIndex;
@property (nonatomic, assign) CGPoint draggingTouchOffset;
@property (nonatomic, assign) BOOL suppressNextTap;
@property (nonatomic, strong) NSMutableSet<NSString *> *revealedWarningKeys;

@end

@implementation NFBMediaPreviewView
+ (NSCache *)videoPlaybackCache {
  static NSCache *cache; static dispatch_once_t once;
  dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 128; });
  return cache;
}
+ (NSDictionary *)playbackStateForVideoURL:(NSString *)url {
  return url.length ? ([self.videoPlaybackCache objectForKey:url] ?: @{}) : @{};
}
+ (void)recordVideoURL:(NSString *)url position:(NSTimeInterval)position duration:(NSTimeInterval)duration {
  if (!url.length || !isfinite(position) || !isfinite(duration)) return;
  NSDictionary *old = [self playbackStateForVideoURL:url];
  if (duration <= 0) duration = [old[@"duration"] doubleValue];
  [self.videoPlaybackCache setObject:@{@"position": @(MAX(0, position)), @"duration": @(MAX(0, duration))} forKey:url];
}
+ (void)pauseInlinePlayback { [[NFBInlineVideoCoordinator shared] pauseAll]; }
+ (void)resumeInlinePlayback { [[NFBInlineVideoCoordinator shared] resumeMonitoring]; }


- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _mediaItems = @[];
    _tiles = [NSMutableArray array];
    _revealedWarningKeys = [NSMutableSet set];
    self.clipsToBounds = YES;
    // T1StatusViewAttachmentLayoutSpec photoVideoCornerRadiusForOptions:.
    self.layer.cornerRadius = 12.0;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.delegate = self;
    self.scrollView.directionalLockEnabled = YES;
    self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.scrollView.alwaysBounceHorizontal = YES;
    self.scrollView.hidden = YES;
    [self addSubview:self.scrollView];
    [self applyTheme];
  }
  return self;
}

- (void)setComposerRailStyle:(BOOL)composerRailStyle {
  if (_composerRailStyle == composerRailStyle) return;
  _composerRailStyle = composerRailStyle;
  [self applyTheme];
  [self configureWithMediaItems:self.mediaItems];
}

- (void)setQuotedCardStyle:(BOOL)quotedCardStyle {
  if (_quotedCardStyle == quotedCardStyle) return;
  _quotedCardStyle = quotedCardStyle;
  [self configureWithMediaItems:self.mediaItems];
  [self applyTheme];
  [self setNeedsLayout];
}

- (void)configureWithMediaItems:(NSArray<NSDictionary *> *)mediaItems {
  NSArray *items = [mediaItems isKindOfClass:NSArray.class] ? mediaItems : @[];
  BOOL changed = ![self.mediaItems isEqualToArray:items];
  self.mediaItems = items;
  if (changed && !self.composerRailStyle) {
    self.scrollView.contentOffset = CGPointZero;
    [self.revealedWarningKeys removeAllObjects];
  }
  NSUInteger visibleCount = self.mediaItems.count;
  BOOL carousel = !self.composerRailStyle && NFBMediaUsesGallery(visibleCount);
  UIView *hostView = (self.composerRailStyle || carousel) ? (UIView *)self.scrollView : (UIView *)self;
  while (self.tiles.count < visibleCount) {
    NFBMediaPreviewTile *tile = [[NFBMediaPreviewTile alloc] initWithFrame:CGRectZero];
    [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
    [tile.removeButton addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [tile.editButton addTarget:self action:@selector(tileAccessoryTapped:) forControlEvents:UIControlEventTouchUpInside];
    [tile.altButton addTarget:self action:@selector(tileAccessoryTapped:) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tileLongPressed:)];
    longPress.minimumPressDuration = 0.24;
    [tile addGestureRecognizer:longPress];
    [self.tiles addObject:tile];
    [hostView addSubview:tile];
  }

  for (NSUInteger index = 0; index < self.tiles.count; index++) {
    NFBMediaPreviewTile *tile = self.tiles[index];
    tile.hidden = index >= visibleCount;
    if (tile.hidden) continue;
    if (tile.superview != hostView) {
      [tile removeFromSuperview];
      [hostView addSubview:tile];
    }
    tile.mediaIndex = index;
    // Twitter 9.67 ships ios_images_hide_multiphoto_qt_alt_text_badge_enabled=false.
    tile.hideQuoteAlt = NO;
    tile.showsRemoveButton = self.composerRailStyle;
    tile.positionLabel.hidden = !carousel;
    tile.positionLabel.text = carousel ? [NSString stringWithFormat:@"%lu/%lu", (unsigned long)index + 1, (unsigned long)visibleCount] : @"";
    tile.accessibilityHint = carousel ? [NSString stringWithFormat:@"Photo %lu of %lu. Swipe horizontally for more photos.", (unsigned long)index + 1, (unsigned long)visibleCount] : nil;
    NSUInteger extra = 0;
    NSString *warningKey = [self warningKeyForItem:self.mediaItems[index] index:index];
    [tile configureWithItem:self.mediaItems[index]
                 extraCount:extra
            warningRevealed:[self.revealedWarningKeys containsObject:warningKey]
                 warningKey:warningKey];
  }
  self.hidden = self.mediaItems.count == 0;
  self.scrollView.hidden = !(self.composerRailStyle || carousel);
  [self applyTheme];
  [self setNeedsLayout];
}

- (void)applyTheme {
  if (self.composerRailStyle) {
    self.backgroundColor = UIColor.clearColor;
    self.layer.borderColor = UIColor.clearColor.CGColor;
    self.layer.borderWidth = 0.0;
    self.layer.cornerRadius = 0.0;
    self.scrollView.backgroundColor = UIColor.clearColor;
  } else if (self.quotedCardStyle) {
    self.backgroundColor = NFBColorBorder();
    self.layer.borderColor = UIColor.clearColor.CGColor;
    self.layer.borderWidth = 0.0;
    self.layer.cornerRadius = 0.0;
    self.scrollView.backgroundColor = UIColor.clearColor;
  } else {
    self.backgroundColor = NFBColorBorder();
    self.layer.borderColor = NFBColorBorder().CGColor;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.layer.cornerRadius = 12.0;
  }
  if (!self.composerRailStyle && NFBMediaUsesGallery(self.mediaItems.count)) {
    self.backgroundColor = UIColor.clearColor;
    self.layer.borderWidth = 0.0;
  }
  for (NFBMediaPreviewTile *tile in self.tiles) {
    [tile applyTheme];
    tile.layer.borderColor = NFBColorBorder().CGColor;
  }
}

- (void)layoutSubviews {
  [super layoutSubviews];
  self.scrollView.frame = self.bounds;
  if (self.composerRailStyle) {
    [self layoutRailTilesAnimated:NO];
    return;
  }

  if (NFBMediaUsesGallery(self.mediaItems.count)) {
    [self layoutCarouselTiles];
    return;
  }
  NSUInteger count = MIN(self.mediaItems.count, self.tiles.count);
  if (count == 0) return;
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat gap = count > 1 ? (self.quotedCardStyle ? 1.0 : 2.0) : 0.0;

  if (count == 1) {
    self.tiles[0].frame = self.bounds;
  } else if (count == 2) {
    CGFloat itemWidth = floor((width - gap) / 2.0);
    self.tiles[0].frame = CGRectMake(0.0, 0.0, itemWidth, height);
    self.tiles[1].frame = CGRectMake(itemWidth + gap, 0.0, width - itemWidth - gap, height);
  } else if (count == 3) {
    CGFloat leftWidth = floor((width - gap) / 2.0);
    CGFloat rightWidth = width - leftWidth - gap;
    CGFloat rightHeight = floor((height - gap) / 2.0);
    self.tiles[0].frame = CGRectMake(0.0, 0.0, leftWidth, height);
    self.tiles[1].frame = CGRectMake(leftWidth + gap, 0.0, rightWidth, rightHeight);
    self.tiles[2].frame = CGRectMake(leftWidth + gap, rightHeight + gap, rightWidth, height - rightHeight - gap);
  } else if (count >= 4) {
    CGFloat itemWidth = floor((width - gap) / 2.0);
    CGFloat itemHeight = floor((height - gap) / 2.0);
    self.tiles[0].frame = CGRectMake(0.0, 0.0, itemWidth, itemHeight);
    self.tiles[1].frame = CGRectMake(itemWidth + gap, 0.0, width - itemWidth - gap, itemHeight);
    self.tiles[2].frame = CGRectMake(0.0, itemHeight + gap, itemWidth, height - itemHeight - gap);
    self.tiles[3].frame = CGRectMake(itemWidth + gap, itemHeight + gap, width - itemWidth - gap, height - itemHeight - gap);
  }
  for (NSUInteger index = 0; index < count; index++) {
    NFBMediaPreviewTile *tile = self.tiles[index];
    tile.layer.cornerRadius = 0.0;
    tile.layer.borderWidth = 0.0;
  }
}

- (void)layoutCarouselTiles {
  CGFloat width = CGRectGetWidth(self.bounds);
  NFBMediaCarouselGeometry previous = NFBMediaCarouselLayout(self.carouselLayoutWidth, self.mediaItems.count);
  NSUInteger current = previous.stride > 0 ? (NSUInteger)MAX(0, llround(self.scrollView.contentOffset.x / previous.stride)) : 0;
  NFBMediaCarouselGeometry geometry = NFBMediaCarouselLayout(width, self.mediaItems.count);
  for (NSUInteger index = 0; index < self.mediaItems.count; index++) {
    NFBMediaPreviewTile *tile = self.tiles[index];
    tile.frame = CGRectMake(index * geometry.stride, 0, geometry.itemWidth, CGRectGetHeight(self.bounds));
    tile.layer.cornerRadius = self.quotedCardStyle ? 0.0 : 12.0;
    tile.layer.borderWidth = self.quotedCardStyle ? 0.0 : 1.0 / UIScreen.mainScreen.scale;
  }
  self.scrollView.contentSize = CGSizeMake(geometry.contentWidth, CGRectGetHeight(self.bounds));
  if (fabs(self.carouselLayoutWidth - width) > 0.5) {
    self.scrollView.contentOffset = CGPointMake(NFBMediaCarouselSnapOffset(geometry, current * geometry.stride), 0);
  }
  self.carouselLayoutWidth = width;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
  if (self.composerRailStyle || !NFBMediaUsesGallery(self.mediaItems.count)) return;
  NFBMediaCarouselGeometry geometry = NFBMediaCarouselLayout(CGRectGetWidth(self.bounds), self.mediaItems.count);
  targetContentOffset->x = NFBMediaCarouselSnapOffset(geometry, targetContentOffset->x);
}

- (CGRect)railFrameForIndex:(NSUInteger)index {
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat tileSize = NFBComposerMediaPageWidth(CGRectGetWidth(self.bounds), self.mediaItems.count);
  CGFloat gap = NFBMediaComposerRailTileGap;
  return CGRectMake((tileSize + gap) * index, 0, tileSize, height);
}

- (NSUInteger)targetRailIndexForCenterX:(CGFloat)x {
  NSUInteger count = self.mediaItems.count;
  if (count == 0) return 0;
  CGFloat width = CGRectGetWidth([self railFrameForIndex:0]);
  return NFBComposerMediaReorderIndex(x, width, count);
}

- (NSUInteger)visualRailIndexForTile:(NFBMediaPreviewTile *)tile {
  NSUInteger index = tile.mediaIndex;
  if (!self.draggingTile || tile == self.draggingTile || self.draggingFromIndex == self.draggingTargetIndex) return index;
  if (self.draggingFromIndex < self.draggingTargetIndex) {
    if (index > self.draggingFromIndex && index <= self.draggingTargetIndex) return index - 1;
  } else {
    if (index >= self.draggingTargetIndex && index < self.draggingFromIndex) return index + 1;
  }
  return index;
}

- (void)layoutRailTilesAnimated:(BOOL)animated {
  NSUInteger count = MIN(self.mediaItems.count, self.tiles.count);
  CGRect lastFrame = CGRectZero;
  for (NSUInteger index = 0; index < count; index++) {
    NFBMediaPreviewTile *tile = self.tiles[index];
    if (tile.hidden || tile == self.draggingTile) continue;
    CGRect frame = [self railFrameForIndex:[self visualRailIndexForTile:tile]];
    lastFrame = CGRectUnion(lastFrame, frame);
    void (^changes)(void) = ^{
      tile.frame = frame;
      tile.layer.cornerRadius = NFBMediaComposerRailTileCornerRadius;
      tile.layer.borderWidth = 0.0;
    };
    if (animated) [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil];
    else changes();
  }
  if (count > 0) lastFrame = CGRectUnion(lastFrame, [self railFrameForIndex:count - 1]);
  self.scrollView.contentSize = CGSizeMake(MAX(CGRectGetMaxX(lastFrame), CGRectGetWidth(self.scrollView.bounds) + 1.0), CGRectGetHeight(self.scrollView.bounds));
}

- (void)tileTapped:(NFBMediaPreviewTile *)tile {
  if (self.suppressNextTap) {
    self.suppressNextTap = NO;
    return;
  }
  if (tile.warningActive) {
    if (tile.warningKey.length > 0) [self.revealedWarningKeys addObject:tile.warningKey];
    NSUInteger index = tile.mediaIndex;
    if (index < self.mediaItems.count) {
      [tile configureWithItem:self.mediaItems[index]
                   extraCount:0
              warningRevealed:YES
                   warningKey:tile.warningKey ?: @""];
    }
    return;
  }
  if ([self.delegate respondsToSelector:@selector(mediaPreviewView:didSelectItemAtIndex:)]) {
    [self.delegate mediaPreviewView:self didSelectItemAtIndex:tile.mediaIndex];
  }
}

- (NSString *)warningKeyForItem:(NSDictionary *)item index:(NSUInteger)index {
  NSString *key = [item[@"fullsizeURL"] isKindOfClass:NSString.class] ? item[@"fullsizeURL"] : @"";
  if (key.length == 0) key = [item[@"thumbnailURL"] isKindOfClass:NSString.class] ? item[@"thumbnailURL"] : @"";
  if (key.length == 0) key = [item[@"videoURL"] isKindOfClass:NSString.class] ? item[@"videoURL"] : @"";
  return key.length > 0 ? key : [NSString stringWithFormat:@"%lu", (unsigned long)index];
}

- (void)removeTapped:(UIButton *)button {
  UIView *view = button.superview;
  while (view && ![view isKindOfClass:NFBMediaPreviewTile.class]) view = view.superview;
  NFBMediaPreviewTile *tile = (NFBMediaPreviewTile *)view;
  if (!tile || tile.mediaIndex >= self.mediaItems.count) return;
  if ([self.delegate respondsToSelector:@selector(mediaPreviewView:didTapRemoveItemAtIndex:)]) {
    [self.delegate mediaPreviewView:self didTapRemoveItemAtIndex:tile.mediaIndex];
  }
}

- (void)tileAccessoryTapped:(UIButton *)button {
  UIView *view = button.superview;
  while (view && ![view isKindOfClass:NFBMediaPreviewTile.class]) view = view.superview;
  NFBMediaPreviewTile *tile = (NFBMediaPreviewTile *)view;
  if (!tile || tile.mediaIndex >= self.mediaItems.count) return;
  if (button == tile.altButton && self.composerRailStyle && [self.delegate respondsToSelector:@selector(mediaPreviewView:didTapAltForItemAtIndex:)]) {
    [self.delegate mediaPreviewView:self didTapAltForItemAtIndex:tile.mediaIndex];
  } else if (button == tile.altButton && !self.composerRailStyle && tile.altText.length) {
    UIResponder *responder = self;
    while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
    UIViewController *controller = (UIViewController *)responder;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Image description" message:tile.altText preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    if (controller && !controller.presentedViewController) [controller presentViewController:alert animated:YES completion:nil];
  } else [self tileTapped:tile];
}

- (void)tileLongPressed:(UILongPressGestureRecognizer *)recognizer {
  if (!self.composerRailStyle || self.mediaItems.count < 2) return;
  NFBMediaPreviewTile *tile = (NFBMediaPreviewTile *)recognizer.view;
  if (![tile isKindOfClass:NFBMediaPreviewTile.class] || tile.mediaIndex >= self.mediaItems.count) return;
  CGPoint location = [recognizer locationInView:self.scrollView];

  if (recognizer.state == UIGestureRecognizerStateBegan) {
    self.suppressNextTap = YES;
    self.draggingTile = tile;
    self.draggingFromIndex = tile.mediaIndex;
    self.draggingTargetIndex = tile.mediaIndex;
    self.draggingTouchOffset = CGPointMake(location.x - CGRectGetMidX(tile.frame), location.y - CGRectGetMidY(tile.frame));
    [self.scrollView bringSubviewToFront:tile];
    [UIView animateWithDuration:0.16 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
      tile.transform = CGAffineTransformMakeScale(1.045, 1.045);
      tile.alpha = 0.92;
    } completion:nil];
    return;
  }

  if (!self.draggingTile) return;
  if (recognizer.state == UIGestureRecognizerStateChanged) {
    CGFloat centerX = location.x - self.draggingTouchOffset.x;
    CGFloat centerY = CGRectGetMidY([self railFrameForIndex:self.draggingFromIndex]);
    tile.center = CGPointMake(centerX, centerY);
    NSUInteger target = [self targetRailIndexForCenterX:centerX];
    if (target != self.draggingTargetIndex) {
      self.draggingTargetIndex = target;
      [self layoutRailTilesAnimated:YES];
    }
    return;
  }

  if (recognizer.state == UIGestureRecognizerStateEnded ||
      recognizer.state == UIGestureRecognizerStateCancelled ||
      recognizer.state == UIGestureRecognizerStateFailed) {
    NSUInteger from = self.draggingFromIndex;
    NSUInteger target = recognizer.state == UIGestureRecognizerStateEnded ? self.draggingTargetIndex : from;
    self.draggingTile = nil;
    [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
      tile.transform = CGAffineTransformIdentity;
      tile.alpha = 1.0;
      tile.frame = [self railFrameForIndex:target];
    } completion:^(BOOL finished) {
      (void)finished;
      if (from != target && target < self.mediaItems.count && [self.delegate respondsToSelector:@selector(mediaPreviewView:moveItemAtIndex:toIndex:)]) {
        [self.delegate mediaPreviewView:self moveItemAtIndex:from toIndex:target];
      } else {
        [self layoutRailTilesAnimated:YES];
      }
    }];
  }
}

@end
