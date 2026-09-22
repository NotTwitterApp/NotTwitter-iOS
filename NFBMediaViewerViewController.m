#import "NFBInteractiveSheet.h"
#import "NFBMediaViewerViewController.h"
#import "NFBMediaPreviewView.h"
#import "NFBMediaAudioSession.h"
#import "NFBMediaPresentationPolicy.h"
#import "NFBMediaTransitionGeometry.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBComposeViewController.h"
#import "NFBLinkRouter.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBPostActionCoordinator.h"
#import "NFBTheme.h"
#import "NFBTweetDetailViewController.h"

static UIImage *NFBViewerAnimatedImageWithData(NSData *data);

static CGFloat NFBViewerClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
  return MIN(maximum, MAX(minimum, value));
}

static CGFloat NFBViewerSmoothProgress(CGFloat progress) {
  CGFloat clamped = NFBViewerClamp(progress, 0.0, 1.0);
  return clamped * clamped * (3.0 - 2.0 * clamped);
}

@interface NFBPlayerSurfaceView : UIView
@property (nonatomic, strong, nullable) AVPlayer *player;
@end

@implementation NFBPlayerSurfaceView

+ (Class)layerClass {
  return AVPlayerLayer.class;
}

- (AVPlayerLayer *)playerLayer {
  return (AVPlayerLayer *)self.layer;
}

- (AVPlayer *)player {
  return self.playerLayer.player;
}

- (void)setPlayer:(AVPlayer *)player {
  self.playerLayer.player = player;
  self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
}

@end

@interface NFBMediaViewerPage : UIView <UIScrollViewDelegate>

@property (nonatomic, strong) NSDictionary *item;
@property (nonatomic, strong) UIView *mediaContentView;
@property (nonatomic, strong) UIScrollView *zoomScrollView;
@property (nonatomic, copy) void (^zoomStateChanged)(BOOL zoomed);
@property (nonatomic, assign) CGSize zoomViewportSize;
@property (nonatomic, strong) NSURLSessionDataTask *imageTask;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIImageView *activityView;
@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) NFBPlayerSurfaceView *playerView;
@property (nonatomic, copy) NSString *imageURLString;
@property (nonatomic, assign) BOOL loadedFullImage;
@property (nonatomic, assign) CGRect restingContentFrame;

- (void)configureWithItem:(NSDictionary *)item parent:(UIViewController *)parent;
- (void)playIfNeeded;
- (void)loadImageIfNeeded;
- (void)unloadImage;
- (void)toggleZoomAtPoint:(CGPoint)point;
- (void)pause;
- (void)applyDismissTranslation:(CGFloat)translationY progress:(CGFloat)progress;
- (void)resetDismissTransform;

@end

@implementation NFBMediaViewerPage

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.blackColor;

    self.mediaContentView = [[UIView alloc] initWithFrame:self.bounds];
    self.mediaContentView.backgroundColor = UIColor.clearColor;
    self.mediaContentView.clipsToBounds = YES;
    self.zoomScrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    self.zoomScrollView.delegate = self;
    self.zoomScrollView.minimumZoomScale = 1.0;
    self.zoomScrollView.maximumZoomScale = 4.0;
    self.zoomScrollView.showsHorizontalScrollIndicator = NO;
    self.zoomScrollView.showsVerticalScrollIndicator = NO;
    self.zoomScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.zoomScrollView.panGestureRecognizer.enabled = NO;
    [self addSubview:self.zoomScrollView];
    [self.zoomScrollView addSubview:self.mediaContentView];

    self.imageView = [[UIImageView alloc] initWithFrame:self.mediaContentView.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
    [self.mediaContentView addSubview:self.imageView];

    self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    NFBIPAApplyOnMediaLabelPillAppearance(self.badgeLabel, 4.0);
    self.badgeLabel.font = NFBFont(12.0, NFBFontWeightHeavy);
    self.badgeLabel.textAlignment = NSTextAlignmentCenter;
    self.badgeLabel.hidden = YES;
    [self.mediaContentView addSubview:self.badgeLabel];

    self.activityView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    self.activityView.tintColor = NFBIPAOnMediaPrimaryTextColor();
    self.activityView.contentMode = UIViewContentModeScaleAspectFit;
    self.activityView.hidden = YES;
    [self addSubview:self.activityView];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  if (!CGSizeEqualToSize(self.zoomViewportSize, self.bounds.size)) {
    self.zoomViewportSize = self.bounds.size;
    self.zoomScrollView.frame = self.bounds;
    [self.zoomScrollView setZoomScale:1.0 animated:NO];
  }
  CGRect frame = [self mediaContentFrameForBounds:self.bounds];
  self.restingContentFrame = frame;
  if (self.zoomScrollView.zoomScale <= 1.01) {
    self.mediaContentView.frame = frame;
    self.zoomScrollView.contentSize = frame.size;
  }
  self.imageView.frame = self.mediaContentView.bounds;
  self.imageView.layer.cornerRadius = [self.item[@"profileAvatar"] boolValue] ? CGRectGetWidth(self.imageView.bounds) / 2.0 : 0.0;
  self.playerView.frame = self.mediaContentView.bounds;
  self.activityView.bounds = CGRectMake(0.0, 0.0, 28.0, 28.0);
  self.activityView.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
  self.badgeLabel.frame = CGRectMake(12.0, MAX(12.0, CGRectGetHeight(self.mediaContentView.bounds) - 34.0), 38.0, 22.0);
}

- (void)configureWithItem:(NSDictionary *)item parent:(UIViewController *)parent {
  (void)parent;
  self.item = item ?: @{};
  NSString *type = [self.item[@"type"] isKindOfClass:NSString.class] ? self.item[@"type"] : @"photo";
  NSString *videoURL = [self.item[@"videoURL"] isKindOfClass:NSString.class] ? self.item[@"videoURL"] : @"";
  NSString *imageURL = [self.item[@"fullsizeURL"] isKindOfClass:NSString.class] ? self.item[@"fullsizeURL"] : @"";
  if (imageURL.length == 0) imageURL = [self.item[@"thumbnailURL"] isKindOfClass:NSString.class] ? self.item[@"thumbnailURL"] : @"";

  [NFBMediaAudioSession stopPlayer:self.player];
  self.playerView.player = nil;
  [self.playerView removeFromSuperview];
  self.playerView = nil;
  self.player = nil;

  self.imageView.image = [self.item[@"previewImage"] isKindOfClass:UIImage.class] ? self.item[@"previewImage"] : nil;
  self.loadedFullImage = NO;
  self.imageView.contentMode = [self.item[@"profileAvatar"] boolValue] ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
  self.imageView.hidden = NO;
  [self resetDismissTransform];
  self.badgeLabel.hidden = ![type isEqualToString:@"gif"];
  self.badgeLabel.text = [type isEqualToString:@"gif"] ? @"GIF" : @"";
  self.imageURLString = imageURL;
  self.zoomScrollView.pinchGestureRecognizer.enabled = [type isEqualToString:@"photo"] || [type isEqualToString:@"video"];

  BOOL playableVideo = ([type isEqualToString:@"video"] || [type isEqualToString:@"gif"]) && videoURL.length > 0;
  if (playableVideo) {
    NSURL *url = [NSURL URLWithString:videoURL];
    if (url) {
      [NFBMediaAudioSession prepareMutedPlayback];
      AVPlayer *player = [AVPlayer playerWithURL:url];
      NSDictionary *state = [NFBMediaPreviewView playbackStateForVideoURL:videoURL];
      double position = [state[@"position"] doubleValue], duration = [state[@"duration"] doubleValue];
      if (position > 0 && (duration <= 0 || position < duration - 0.2)) [player seekToTime:CMTimeMakeWithSeconds(position, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
      player.muted = YES;
      if (@available(iOS 10.0, *)) player.automaticallyWaitsToMinimizeStalling = YES;
      NFBPlayerSurfaceView *playerView = [[NFBPlayerSurfaceView alloc] initWithFrame:self.mediaContentView.bounds];
      playerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      playerView.backgroundColor = UIColor.clearColor;
      playerView.player = player;
      [self.mediaContentView insertSubview:playerView aboveSubview:self.imageView];
      self.playerView = playerView;
      self.player = player;
    }
  }
  [self setNeedsLayout];
}

- (void)loadImageIfNeeded {
  if (!self.loadedFullImage && !self.imageURLString.length) {
    NSData *data = [self.item[@"data"] isKindOfClass:NSData.class] ? self.item[@"data"] : nil;
    UIImage *image = [self.item[@"previewImage"] isKindOfClass:UIImage.class] ? self.item[@"previewImage"] : nil;
    if (data.length && [self.item[@"type"] isEqual:@"gif"] && !self.player) image = NFBViewerAnimatedImageWithData(data) ?: image;
    self.imageView.image = image;
    self.loadedFullImage = image != nil;
  }
  if (!self.loadedFullImage && !self.imageTask && self.imageURLString.length > 0) [self loadImageURL:self.imageURLString];
}

- (void)dealloc {
  [self.imageTask cancel];
  [NFBMediaAudioSession stopPlayer:_player];
}

- (void)unloadImage {
  [self.imageTask cancel];
  self.imageTask = nil;
  [self.zoomScrollView setZoomScale:1.0 animated:NO];
  self.imageView.image = nil;
  self.loadedFullImage = NO;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
  return self.zoomScrollView.pinchGestureRecognizer.enabled ? self.mediaContentView : nil;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
  CGSize bounds = scrollView.bounds.size;
  CGSize content = scrollView.contentSize;
  self.mediaContentView.center = CGPointMake(MAX(bounds.width, content.width) / 2.0, MAX(bounds.height, content.height) / 2.0);
  BOOL zoomed = scrollView.zoomScale > 1.01;
  scrollView.panGestureRecognizer.enabled = zoomed;
  if (self.zoomStateChanged) self.zoomStateChanged(zoomed);
}

- (void)toggleZoomAtPoint:(CGPoint)point {
  if (!self.imageView.image && !self.player) return;
  if (self.zoomScrollView.zoomScale > 1.01) { [self.zoomScrollView setZoomScale:1.0 animated:YES]; return; }
  CGPoint center = [self convertPoint:point toView:self.mediaContentView];
  CGFloat targetScale = self.player ? MAX(CGRectGetWidth(self.bounds) / MAX(1.0, CGRectGetWidth(self.restingContentFrame)), CGRectGetHeight(self.bounds) / MAX(1.0, CGRectGetHeight(self.restingContentFrame))) : 2.5;
  CGFloat scale = MIN(self.zoomScrollView.maximumZoomScale, targetScale);
  CGSize size = CGSizeMake(CGRectGetWidth(self.zoomScrollView.bounds) / scale, CGRectGetHeight(self.zoomScrollView.bounds) / scale);
  [self.zoomScrollView zoomToRect:CGRectMake(center.x - size.width / 2.0, center.y - size.height / 2.0, size.width, size.height) animated:YES];
}

- (void)loadImageURL:(NSString *)urlString {
  self.imageURLString = urlString ?: @"";
  if (urlString.length == 0) return;
  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    self.imageView.image = cached;
    self.loadedFullImage = YES;
    [self setNeedsLayout];
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  NFBStartLoadingAnimation(self.activityView);
  self.imageTask = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error.code == NSURLErrorCancelled) return;
    if (error || data.length == 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.imageTask = nil;
        NFBStopLoadingAnimation(self.activityView);
        self.activityView.hidden = YES;
      });
      return;
    }
    UIImage *image = NFBViewerAnimatedImageWithData(data);
    if (!image) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.imageTask = nil;
        NFBStopLoadingAnimation(self.activityView);
        self.activityView.hidden = YES;
      });
      return;
    }
    [[self.class imageCache] setObject:image forKey:urlString cost:(NSUInteger)(image.size.width * image.scale * image.size.height * image.scale * 4.0)];
    dispatch_async(dispatch_get_main_queue(), ^{
      NFBStopLoadingAnimation(self.activityView);
      self.activityView.hidden = YES;
      if ([self.imageURLString isEqualToString:urlString] && self.imageTask) {
        self.imageTask = nil;
        self.imageView.image = image;
        self.loadedFullImage = YES;
        [self setNeedsLayout];
      }
    });
  }];
  [self.imageTask resume];
}

- (CGRect)mediaContentFrameForBounds:(CGRect)bounds {
  if (CGRectIsEmpty(bounds)) return CGRectZero;
  CGFloat ratio = [self.item[@"profileAvatar"] boolValue] ? 1.0 : [self mediaAspectRatio];
  if (ratio <= 0.0) return bounds;
  CGFloat maxWidth = CGRectGetWidth(bounds);
  CGFloat maxHeight = CGRectGetHeight(bounds);
  if ([self.item[@"profileAvatar"] boolValue]) {
    // T1ProfileHeaderSlideshowDataSource: avatar zoom is 0.85; cover is 1.0.
    CGFloat side = floor(MIN(maxWidth, maxHeight) * 0.85);
    return CGRectMake(CGRectGetMidX(bounds) - side / 2.0, CGRectGetMidY(bounds) - side / 2.0, side, side);
  }
  CGFloat width = maxWidth;
  CGFloat height = width / ratio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ratio;
  }
  width = MIN(maxWidth, MAX(1.0, floor(width)));
  height = MIN(maxHeight, MAX(1.0, floor(height)));
  return CGRectIntegral(CGRectMake(CGRectGetMidX(bounds) - width / 2.0,
                                   CGRectGetMidY(bounds) - height / 2.0,
                                   width,
                                   height));
}

- (CGFloat)mediaAspectRatio {
  NSDictionary *aspect = [self.item[@"aspectRatio"] isKindOfClass:NSDictionary.class] ? self.item[@"aspectRatio"] : nil;
  NSNumber *widthNumber = [aspect[@"width"] respondsToSelector:@selector(doubleValue)] ? aspect[@"width"] : nil;
  NSNumber *heightNumber = [aspect[@"height"] respondsToSelector:@selector(doubleValue)] ? aspect[@"height"] : nil;
  if (!widthNumber || !heightNumber) {
    widthNumber = [self.item[@"width"] respondsToSelector:@selector(doubleValue)] ? self.item[@"width"] : nil;
    heightNumber = [self.item[@"height"] respondsToSelector:@selector(doubleValue)] ? self.item[@"height"] : nil;
  }
  CGFloat width = widthNumber.doubleValue;
  CGFloat height = heightNumber.doubleValue;
  if (width > 0.0 && height > 0.0) return MIN(4.0, MAX(0.25, width / height));
  if (self.imageView.image.size.width > 0.0 && self.imageView.image.size.height > 0.0) {
    return MIN(4.0, MAX(0.25, self.imageView.image.size.width / self.imageView.image.size.height));
  }
  NSString *type = [self.item[@"type"] isKindOfClass:NSString.class] ? self.item[@"type"] : @"";
  if ([type isEqualToString:@"video"]) return 16.0 / 9.0;
  return 0.0;
}

- (void)applyDismissTranslation:(CGFloat)translationY progress:(CGFloat)progress {
  (void)translationY;
  (void)progress;
  [self resetDismissTransform];
}

- (void)resetDismissTransform {
  if (self.zoomScrollView.zoomScale <= 1.01) self.mediaContentView.transform = CGAffineTransformIdentity;
  self.mediaContentView.alpha = 1.0;
  self.mediaContentView.layer.cornerRadius = 0.0;
  self.mediaContentView.layer.zPosition = 0.0;
}

static UIImage *NFBViewerAnimatedImageWithData(NSData *data) {
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
  return frames.count > 0 ? [UIImage animatedImageWithImages:frames duration:MAX(duration, 0.1)] : [UIImage imageWithData:data];
}

- (void)playIfNeeded {
  AVPlayer *player = self.player;
  if (!player) return;
  [player playImmediatelyAtRate:1.0];
}

- (void)pause {
  [NFBMediaAudioSession stopPlayer:self.player];
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 8;
    cache.totalCostLimit = 64 * 1024 * 1024;
  });
  return cache;
}

@end

typedef void (^NFBVideoOptionsSelectionHandler)(NSString *identifier);

@interface NFBVideoOptionsSheetViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSDictionary *> *)items
                    selection:(NFBVideoOptionsSelectionHandler)selection;
@end

@implementation NFBVideoOptionsSheetViewController {
  NSString *_sheetTitle;
  NSArray<NSDictionary *> *_items;
  NFBVideoOptionsSelectionHandler _selection;
  UIButton *_backdropButton;
  UIView *_sheetView;
}

- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSDictionary *> *)items
                    selection:(NFBVideoOptionsSelectionHandler)selection {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _sheetTitle = [title copy] ?: @"";
    _items = [items copy] ?: @[];
    _selection = [selection copy];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.clearColor;

  _backdropButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _backdropButton.backgroundColor = NFBIPAModalSheetScrimColor();
  [_backdropButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_backdropButton];

  _sheetView = [[UIView alloc] init];
  NFBIPAApplyOnMediaBarAppearance(_sheetView);
  NFBInstallSheetDismissGesture(_sheetView, _backdropButton, self, @selector(cancelTapped));
  _sheetView.layer.cornerRadius = NFBIPAModalSheetCornerRadius();
  if (@available(iOS 11.0, *)) _sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
  [self.view addSubview:_sheetView];

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaSeparatorAppearance(grabber);
  grabber.layer.cornerRadius = 2.5;
  [_sheetView addSubview:grabber];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = _sheetTitle;
  titleLabel.textColor = NFBIPAOnMediaPrimaryTextColor();
  titleLabel.font = NFBFont(17.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;
  [_sheetView addSubview:titleLabel];

  UIStackView *rows = [[UIStackView alloc] init];
  rows.translatesAutoresizingMaskIntoConstraints = NO;
  rows.axis = UILayoutConstraintAxisVertical;
  rows.spacing = 0.0;
  UIScrollView *optionsScroll = [UIScrollView new];
  optionsScroll.translatesAutoresizingMaskIntoConstraints = NO;
  optionsScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  [_sheetView addSubview:optionsScroll];
  [optionsScroll addSubview:rows];

  for (NSDictionary *item in _items) {
    [rows addArrangedSubview:[self rowForItem:item]];
  }

  [NSLayoutConstraint activateConstraints:@[
    [grabber.topAnchor constraintEqualToAnchor:_sheetView.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:_sheetView.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],
    [titleLabel.topAnchor constraintEqualToAnchor:_sheetView.topAnchor constant:22.0],
    [titleLabel.centerXAnchor constraintEqualToAnchor:_sheetView.centerXAnchor],
    [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_sheetView.leadingAnchor constant:64.0],
    [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_sheetView.trailingAnchor constant:-64.0],
    [optionsScroll.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor],
    [optionsScroll.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor],
    [optionsScroll.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14.0],
    [optionsScroll.bottomAnchor constraintEqualToAnchor:_sheetView.safeAreaLayoutGuide.bottomAnchor constant:-12.0],
    [rows.leadingAnchor constraintEqualToAnchor:optionsScroll.contentLayoutGuide.leadingAnchor],
    [rows.trailingAnchor constraintEqualToAnchor:optionsScroll.contentLayoutGuide.trailingAnchor],
    [rows.topAnchor constraintEqualToAnchor:optionsScroll.contentLayoutGuide.topAnchor],
    [rows.bottomAnchor constraintEqualToAnchor:optionsScroll.contentLayoutGuide.bottomAnchor],
    [rows.widthAnchor constraintEqualToAnchor:optionsScroll.frameLayoutGuide.widthAnchor]
  ]];
}

- (UIButton *)rowForItem:(NSDictionary *)item {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  button.accessibilityIdentifier = [item[@"id"] isKindOfClass:NSString.class] ? item[@"id"] : @"";
  [button.heightAnchor constraintEqualToConstant:NFBIPAModalSheetRowHeight()].active = YES;
  [button addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];

  NSString *iconName = [item[@"icon"] isKindOfClass:NSString.class] ? item[@"icon"] : @"";
  UIImageView *iconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  iconView.translatesAutoresizingMaskIntoConstraints = NO;
  iconView.contentMode = UIViewContentModeScaleAspectFit;
  iconView.tintColor = NFBIPAOnMediaPrimaryTextColor();
  [button addSubview:iconView];

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"";
  label.textColor = [button.accessibilityIdentifier isEqualToString:@"cancel"] ? NFBColorAccent() : NFBIPAOnMediaPrimaryTextColor();
  label.font = NFBFont(18.0, NFBFontWeightRegular);
  [button addSubview:label];

  UIImageView *check = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_check")];
  check.translatesAutoresizingMaskIntoConstraints = NO;
  check.tintColor = NFBColorAccent();
  check.hidden = !([item[@"checked"] respondsToSelector:@selector(boolValue)] && [item[@"checked"] boolValue]);
  [button addSubview:check];

  [NSLayoutConstraint activateConstraints:@[
    [iconView.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:24.0],
    [iconView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    [iconView.widthAnchor constraintEqualToConstant:24.0],
    [iconView.heightAnchor constraintEqualToConstant:24.0],
    [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:20.0],
    [label.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    [label.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor constant:-16.0],
    [check.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-24.0],
    [check.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    [check.widthAnchor constraintEqualToConstant:21.0],
    [check.heightAnchor constraintEqualToConstant:21.0]
  ]];
  return button;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  _backdropButton.frame = self.view.bounds;
  CGFloat sheetHeight = 44.0 + 14.0 + (NFBIPAModalSheetRowHeight() * _items.count) + self.view.safeAreaInsets.bottom + 12.0;
  sheetHeight = MIN(sheetHeight, CGRectGetHeight(self.view.bounds) - self.view.safeAreaInsets.top - 12.0);
  _sheetView.frame = CGRectMake(0.0,
                                CGRectGetHeight(self.view.bounds) - sheetHeight,
                                CGRectGetWidth(self.view.bounds),
                                sheetHeight);
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  _sheetView.transform = CGAffineTransformMakeTranslation(0.0, CGRectGetHeight(_sheetView.bounds) + 12.0);
  [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.18 options:UIViewAnimationOptionCurveEaseOut animations:^{
    self->_sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)rowTapped:(UIButton *)sender {
  NSString *identifier = sender.accessibilityIdentifier ?: @"";
  if ([identifier isEqualToString:@"cancel"]) {
    [self cancelTapped];
    return;
  }
  NFBVideoOptionsSelectionHandler selection = [_selection copy];
  [self dismissViewControllerAnimated:YES completion:^{
    if (selection) selection(identifier);
  }];
}

- (void)cancelTapped {
  [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface NFBVideoProgressSlider : UISlider
@end
@implementation NFBVideoProgressSlider
- (CGRect)trackRectForBounds:(CGRect)bounds {
  CGRect track = [super trackRectForBounds:bounds];
  return CGRectMake(track.origin.x, CGRectGetMidY(bounds) - 1.5, track.size.width, 3.0);
}
@end

@interface NFBMediaViewerViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate>

@property (nonatomic, copy) NSArray<NSDictionary *> *mediaItems;
@property (nonatomic, assign) NSUInteger initialIndex;
@property (nonatomic, strong) UIView *dismissContentView;
@property (nonatomic, strong) UIView *mediaContainerView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UIButton *altTextButton;
@property (nonatomic, strong) NSLayoutConstraint *altPhotoBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *altControlsTopConstraint;
@property (nonatomic, weak) UIImageView *profileSourceImageView;
@property (nonatomic, strong) NSMutableArray<NFBMediaViewerPage *> *pages;
@property (nonatomic, strong) NSDictionary *post;
@property (nonatomic, strong) UIView *bottomGradientView;
@property (nonatomic, strong) CAGradientLayer *bottomGradientLayer;
@property (nonatomic, strong) UIView *tweetOverlayView;
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) UIVisualEffectView *actionBlurView;
@property (nonatomic, strong) UIImageView *overlayAvatarView;
@property (nonatomic, strong) UIView *overlayAuthorTextView;
@property (nonatomic, strong) UILabel *overlayNameLabel;
@property (nonatomic, strong) UILabel *overlayHandleLabel;
@property (nonatomic, strong) NFBInteractiveTextLabel *overlayBodyLabel;
@property (nonatomic, strong) UIButton *overlayFollowButton;
@property (nonatomic, strong) UIButton *overlayMoreButton;
@property (nonatomic, strong) UIView *videoControlsView;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *playbackTimeLabel;
@property (nonatomic, strong) UILabel *seekFeedbackLabel;
@property (nonatomic, strong) UITapGestureRecognizer *mediaDoubleTap;
@property (nonatomic, strong) UILongPressGestureRecognizer *mediaLongPress;
@property (nonatomic, strong) NSTimer *chromeHideTimer;
@property (nonatomic, assign) BOOL resumeAfterScrubbing;
@property (nonatomic, assign) NSTimeInterval lastSeekGestureTime;
@property (nonatomic, assign) CGFloat pagerLayoutWidth;
@property (nonatomic, strong) NSLayoutConstraint *videoControlsLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *videoControlsTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *videoControlsBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *muteButtonTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *muteButtonBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tweetOverlayLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tweetOverlayTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tweetOverlayBottomConstraint;
@property (nonatomic, strong) UIImageView *replyIconView;
@property (nonatomic, strong) UIImageView *repostIconView;
@property (nonatomic, strong) UIImageView *likeIconView;
@property (nonatomic, strong) UIImageView *bookmarkIconView;
@property (nonatomic, strong) UIImageView *shareIconView;
@property (nonatomic, strong) UILabel *replyCountLabel;
@property (nonatomic, strong) UILabel *repostCountLabel;
@property (nonatomic, strong) UILabel *likeCountLabel;
@property (nonatomic, strong) AVPlayer *observedPlayer;
@property (nonatomic, strong) id playerTimeObserver;
@property (nonatomic, assign) BOOL trackingProgressSlider;
@property (nonatomic, assign) CGFloat playbackRate;
@property (nonatomic, copy) NSString *overlayAvatarURLString;
@property (nonatomic, strong) NFBPostActionCoordinator *postActionCoordinator;
@property (nonatomic, strong) UIPanGestureRecognizer *verticalDismissGesture;
@property (nonatomic, strong) UITapGestureRecognizer *chromeToggleTapGesture;
@property (nonatomic, assign) BOOL verticalDismissTracking;
@property (nonatomic, assign) BOOL verticalDismissChromeDropped;
@property (nonatomic, assign) BOOL viewerChromeHidden;
@property (nonatomic, assign) BOOL overlayBodyExpanded;
@property (nonatomic, assign) BOOL positionedInitialPage;
@property (nonatomic, assign) NSInteger lastPlaybackIndex;
@property (nonatomic, assign) BOOL userPausedCurrentVideo;
@property (nonatomic, assign) BOOL userForcedPlayback;
@property (nonatomic, assign) BOOL userChangedMute;
@property (nonatomic, assign) BOOL wasPlayingBeforeBackground;

@end

@interface NFBProfilePhotoAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, weak) NFBMediaViewerViewController *viewer;
@property (nonatomic, assign) BOOL presenting;
@end
@implementation NFBProfilePhotoAnimator
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
  (void)context;
  return UIAccessibilityIsReduceMotionEnabled() ? 0.0 : 0.175;
}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
  NFBMediaViewerViewController *viewer = self.viewer;
  UIView *container = context.containerView;
  UIView *viewerView = viewer.view;
  if (self.presenting) {
    viewerView.frame = [context finalFrameForViewController:viewer];
    [container addSubview:viewerView];
  }
  [viewerView setNeedsLayout];
  [viewerView layoutIfNeeded];
  NFBMediaViewerPage *page = viewer.pages.firstObject;
  [page setNeedsLayout]; [page layoutIfNeeded];
  UIImageView *source = viewer.profileSourceImageView;
  CGRect sourceFrame = source.window ? [source convertRect:source.bounds toView:container] : CGRectZero;
  CGRect fullFrame = [page.imageView convertRect:page.imageView.bounds toView:container];
  UIImageView *snapshot = [[UIImageView alloc] initWithImage:page.imageView.image ?: source.image];
  snapshot.contentMode = UIViewContentModeScaleAspectFill;
  snapshot.clipsToBounds = YES;
  BOOL hasSource = source.window && !CGRectIsEmpty(sourceFrame) && snapshot.image;
  BOOL sourceHidden = source.hidden;
  CGFloat smallRadius = source.layer.cornerRadius;
  CGFloat largeRadius = [page.item[@"profileAvatar"] boolValue] ? CGRectGetWidth(fullFrame) / 2.0 : 0;
  snapshot.frame = self.presenting ? sourceFrame : fullFrame;
  snapshot.layer.cornerRadius = self.presenting ? smallRadius : largeRadius;
  if (hasSource) { source.hidden = YES; page.imageView.hidden = YES; [container addSubview:snapshot]; }
  viewerView.alpha = self.presenting ? 0 : 1;
  [UIView animateWithDuration:[self transitionDuration:context] delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
    viewerView.alpha = self.presenting ? 1 : 0;
    if (hasSource) {
      snapshot.frame = self.presenting ? fullFrame : sourceFrame;
      snapshot.layer.cornerRadius = self.presenting ? largeRadius : smallRadius;
    }
  } completion:^(BOOL finished) {
    (void)finished;
    source.hidden = sourceHidden;
    page.imageView.hidden = NO;
    [snapshot removeFromSuperview];
    viewerView.alpha = 1;
    [context completeTransition:!context.transitionWasCancelled];
  }];
}
@end

// Tweet photos, GIFs and video use TFNFullscreenMediaTransition's source-to-fit
// geometry, 0.25-second default duration and ease-out curve (options 0x20001).
@interface NFBMediaOpeningAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, weak) NFBMediaViewerViewController *viewer;
@end
@implementation NFBMediaOpeningAnimator
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
  (void)context;
  return UIAccessibilityIsReduceMotionEnabled() ? 0.15 : NFBMediaOpeningDuration;
}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
  NFBMediaViewerViewController *viewer = self.viewer;
  NFBMediaTransitionSource *source = viewer.transitionSource;
  UIView *container = context.containerView;
  UIView *viewerView = viewer.view;
  viewerView.frame = [context finalFrameForViewController:viewer];
  [container addSubview:viewerView];
  [viewerView setNeedsLayout]; [viewerView layoutIfNeeded];
  NSUInteger index = viewer.initialIndex;
  NFBMediaViewerPage *page = index < viewer.pages.count ? viewer.pages[index] : nil;
  [page setNeedsLayout]; [page layoutIfNeeded];
  UIView *origin = source.view;
  CGRect tileFrame = origin.window ? [origin convertRect:origin.bounds toView:container] : CGRectZero;
  CGRect visibleFrame = CGRectIntersection(tileFrame, container.bounds);
  for (UIView *ancestor = origin.superview; ancestor; ancestor = ancestor.superview) {
    if (ancestor.clipsToBounds) visibleFrame = CGRectIntersection(visibleFrame, [ancestor convertRect:ancestor.bounds toView:container]);
  }
  CGRect fullFrame = [page.mediaContentView convertRect:page.mediaContentView.bounds toView:container];
  BOOL zoom = !UIAccessibilityIsReduceMotionEnabled() && source.isStillValid && source.isStillValid() &&
      (source.image || source.player) && !CGRectIsEmpty(visibleFrame) && !CGRectIsNull(visibleFrame) && !CGRectIsEmpty(fullFrame);
  UIView *clip = nil;
  UIImageView *image = nil;
  AVPlayerLayer *video = nil;
  BOOL originHidden = origin.hidden, mediaHidden = page.mediaContentView.hidden;
  if (zoom) {
    clip = [[UIView alloc] initWithFrame:visibleFrame];
    clip.clipsToBounds = YES;
    clip.layer.cornerRadius = source.cornerRadius;
    NFBMediaTransitionRect crop = NFBMediaOpeningImageRect(
        (NFBMediaTransitionRect){tileFrame.origin.x,tileFrame.origin.y,tileFrame.size.width,tileFrame.size.height},
        (NFBMediaTransitionRect){visibleFrame.origin.x,visibleFrame.origin.y,visibleFrame.size.width,visibleFrame.size.height},
        fullFrame.size.width / fullFrame.size.height);
    image = [[UIImageView alloc] initWithImage:source.image];
    image.contentMode = UIViewContentModeScaleToFill;
    image.frame = CGRectMake(crop.x,crop.y,crop.width,crop.height);
    [clip addSubview:image];
    if (source.player) {
      video = [AVPlayerLayer playerLayerWithPlayer:source.player];
      video.videoGravity = AVLayerVideoGravityResizeAspect;
      video.frame = image.bounds;
      [image.layer addSublayer:video];
    }
    [container addSubview:clip];
    origin.hidden = YES;
    page.mediaContentView.hidden = YES;
    CABasicAnimation *corners = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
    corners.fromValue = @(source.cornerRadius); corners.toValue = @0;
    corners.duration = [self transitionDuration:context];
    corners.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [clip.layer addAnimation:corners forKey:@"mediaOpeningCorners"];
    clip.layer.cornerRadius = 0;
  }
  viewerView.alpha = 0;
  [UIView animateWithDuration:[self transitionDuration:context] delay:0
      options:UIViewAnimationOptionLayoutSubviews | UIViewAnimationOptionCurveEaseOut animations:^{
    viewerView.alpha = 1;
    clip.frame = fullFrame;
    image.frame = clip.bounds;
    video.frame = image.bounds;
  } completion:^(BOOL finished) {
    (void)finished;
    if (zoom) origin.hidden = originHidden;
    page.mediaContentView.hidden = mediaHidden;
    [clip removeFromSuperview];
    viewerView.alpha = 1;
    source.player = nil;
    viewer.transitionSource = nil;
    [context completeTransition:!context.transitionWasCancelled];
  }];
}
@end

@implementation NFBMediaViewerViewController

- (void)setTransitionSource:(NFBMediaTransitionSource *)transitionSource {
  _transitionSource = transitionSource;
  if (!transitionSource.image || self.initialIndex >= self.mediaItems.count) return;
  NSMutableArray *items = [self.mediaItems mutableCopy];
  NSMutableDictionary *item = [items[self.initialIndex] mutableCopy];
  item[@"previewImage"] = transitionSource.image;
  items[self.initialIndex] = item;
  self.mediaItems = items;
}

- (instancetype)initWithProfileImageURL:(NSString *)url previewImage:(UIImage *)image avatar:(BOOL)avatar sourceImageView:(UIImageView *)source {
  NSMutableDictionary *item = [@{@"type": @"photo", @"fullsizeURL": url ?: @"", @"profileAvatar": @(avatar), @"profilePhoto": @YES} mutableCopy];
  if (image) item[@"previewImage"] = image;
  if ((self = [self initWithMediaItems:@[item] initialIndex:0 post:nil])) {
    self.profileSourceImageView = source;
    self.transitioningDelegate = self;
    self.modalPresentationStyle = UIModalPresentationCustom;
  }
  return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
  (void)presented; (void)presenting; (void)source;
  if (self.profileSourceImageView) {
    NFBProfilePhotoAnimator *animator = [NFBProfilePhotoAnimator new]; animator.viewer = self; animator.presenting = YES; return animator;
  }
  NFBMediaOpeningAnimator *animator = [NFBMediaOpeningAnimator new]; animator.viewer = self; return animator;
}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
  (void)dismissed;
  if (!self.profileSourceImageView) return nil;
  NFBProfilePhotoAnimator *animator = [NFBProfilePhotoAnimator new]; animator.viewer = self; animator.presenting = NO; return animator;
}

- (instancetype)initWithMediaItems:(NSArray<NSDictionary *> *)mediaItems initialIndex:(NSUInteger)initialIndex {
  return [self initWithMediaItems:mediaItems initialIndex:initialIndex post:nil];
}

- (instancetype)initWithMediaItems:(NSArray<NSDictionary *> *)mediaItems
                      initialIndex:(NSUInteger)initialIndex
                              post:(NSDictionary *)post {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _mediaItems = [mediaItems copy] ?: @[];
    _initialIndex = MIN(initialIndex, _mediaItems.count > 0 ? _mediaItems.count - 1 : 0);
    _pages = [NSMutableArray array];
    _post = [post copy] ?: @{};
    _playbackRate = 1.0;
    _lastPlaybackIndex = -1;
    self.transitioningDelegate = self;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalPresentationCapturesStatusBarAppearance = YES;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  }
  return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  return [self initWithMediaItems:@[] initialIndex:0 post:nil];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  return [self initWithMediaItems:@[] initialIndex:0 post:nil];
}

- (NFBPostActionCoordinator *)postActionCoordinator {
  if (!_postActionCoordinator) {
    _postActionCoordinator = [[NFBPostActionCoordinator alloc] initWithPresentingViewController:self];
    __weak typeof(self) weakSelf = self;
    _postActionCoordinator.postUpdateHandler = ^(NSDictionary *updatedPost, NSDictionary *originalPost) {
      [weakSelf applyUpdatedPost:updatedPost originalPost:originalPost];
    };
    _postActionCoordinator.profileUpdateHandler = ^(NSDictionary *updatedProfile, NSDictionary *originalProfile) {
      (void)originalProfile;
      [weakSelf applyUpdatedAuthorProfile:updatedProfile];
    };
  }
  _postActionCoordinator.presentingViewController = self;
  return _postActionCoordinator;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self removeObservedPlayerTimeObserver];
  [self.chromeHideTimer invalidate];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [NFBMediaPreviewView pauseInlinePlayback];
  self.view.backgroundColor = UIColor.blackColor;

  self.dismissContentView = [[UIView alloc] initWithFrame:self.view.bounds];
  self.dismissContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.dismissContentView.backgroundColor = UIColor.clearColor;
  [self.view addSubview:self.dismissContentView];

  self.mediaContainerView = [[UIView alloc] initWithFrame:self.dismissContentView.bounds];
  self.mediaContainerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.mediaContainerView.backgroundColor = UIColor.blackColor;
  self.mediaContainerView.clipsToBounds = YES;
  [self.dismissContentView addSubview:self.mediaContainerView];

  self.scrollView = [[UIScrollView alloc] initWithFrame:self.mediaContainerView.bounds];
  self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.scrollView.pagingEnabled = YES;
  self.scrollView.panGestureRecognizer.maximumNumberOfTouches = 1;
  self.scrollView.directionalLockEnabled = YES;
  self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  self.scrollView.showsHorizontalScrollIndicator = NO;
  self.scrollView.delegate = self;
  self.scrollView.backgroundColor = UIColor.blackColor;
  [self.mediaContainerView addSubview:self.scrollView];

  self.verticalDismissGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(verticalDismissPanned:)];
  self.verticalDismissGesture.delegate = self;
  self.verticalDismissGesture.maximumNumberOfTouches = 1;
  self.verticalDismissGesture.cancelsTouchesInView = YES;
  [self.view addGestureRecognizer:self.verticalDismissGesture];

  self.chromeToggleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chromeToggleTapped:)];
  self.chromeToggleTapGesture.delegate = self;
  self.chromeToggleTapGesture.cancelsTouchesInView = NO;
  [self.view addGestureRecognizer:self.chromeToggleTapGesture];
  self.mediaDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mediaDoubleTapped:)];
  self.mediaDoubleTap.numberOfTapsRequired = 2;
  self.mediaDoubleTap.delegate = self;
  [self.view addGestureRecognizer:self.mediaDoubleTap];
  [self.chromeToggleTapGesture requireGestureRecognizerToFail:self.mediaDoubleTap];
  self.mediaLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mediaLongPressed:)];
  self.mediaLongPress.delegate = self;
  [self.view addGestureRecognizer:self.mediaLongPress];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(autoplayConditionsDidChange:) name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
  if (@available(iOS 9.0, *)) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(autoplayConditionsDidChange:) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
  }

  for (NSDictionary *item in self.mediaItems) {
    NFBMediaViewerPage *page = [[NFBMediaViewerPage alloc] initWithFrame:CGRectZero];
    [page configureWithItem:item parent:self];
    __weak typeof(self) weakSelf = self;
    __weak typeof(page) weakPage = page;
    page.zoomStateChanged = ^(BOOL zoomed) {
      if ([weakSelf currentPage] != weakPage) return;
      weakSelf.scrollView.scrollEnabled = !zoomed && !weakSelf.verticalDismissTracking;
      if (zoomed) [weakSelf setViewerChromeHidden:YES animated:YES];
    };
    [self.pages addObject:page];
    [self.scrollView addSubview:page];
  }

  self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.closeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  NFBIPAApplyOnMediaFloatingButtonAppearance(self.closeButton, 18.0);
  self.closeButton.accessibilityLabel = @"Close";
  [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.closeButton];

  self.pageLabel = [[UILabel alloc] init];
  self.pageLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.pageLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
  self.pageLabel.textAlignment = NSTextAlignmentCenter;
  NFBIPAApplyOnMediaLabelPillAppearance(self.pageLabel, 14.0);
  self.pageLabel.hidden = self.mediaItems.count <= 1;
  [self.view addSubview:self.pageLabel];

  [self buildActionBarIfNeeded];
  [self buildVideoControlsIfNeeded];

  self.altTextButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.altTextButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.altTextButton.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.58];
  self.altTextButton.layer.cornerRadius = 5.0;
  self.altTextButton.layer.borderWidth = 1.0;
  self.altTextButton.layer.borderColor = NFBIPAOnMediaSecondaryTextColor().CGColor;
  self.altTextButton.titleLabel.font = NFBFont(12.0, NFBFontWeightHeavy);
  [self.altTextButton setTitle:@"ALT" forState:UIControlStateNormal];
  [self.altTextButton setTitleColor:NFBIPAOnMediaPrimaryTextColor() forState:UIControlStateNormal];
  [self.altTextButton addTarget:self action:@selector(altTextTapped) forControlEvents:UIControlEventTouchUpInside];
  self.altTextButton.hidden = YES;
  [self.view addSubview:self.altTextButton];

  NSMutableArray<NSLayoutConstraint *> *constraints = [@[
    [self.closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10.0],
    [self.closeButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
    [self.closeButton.widthAnchor constraintEqualToConstant:36.0],
    [self.closeButton.heightAnchor constraintEqualToConstant:36.0],
    [self.pageLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
    [self.pageLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.pageLabel.widthAnchor constraintEqualToConstant:58.0],
    [self.pageLabel.heightAnchor constraintEqualToConstant:28.0],
    [self.altTextButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
    [self.altTextButton.widthAnchor constraintEqualToConstant:42.0],
    [self.altTextButton.heightAnchor constraintEqualToConstant:26.0]
  ] mutableCopy];
  self.altPhotoBottomConstraint = self.tweetOverlayView ? [self.altTextButton.bottomAnchor constraintEqualToAnchor:self.tweetOverlayView.topAnchor constant:-12.0] : [self.altTextButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20.0];
  [constraints addObject:self.altPhotoBottomConstraint];
  if (self.videoControlsView) self.altControlsTopConstraint = [self.altTextButton.bottomAnchor constraintEqualToAnchor:self.videoControlsView.topAnchor constant:-12.0];
  [NSLayoutConstraint activateConstraints:constraints];
}

- (void)buildActionBarIfNeeded {
  if (self.post.count == 0) return;

  self.bottomGradientView = [[UIView alloc] init];
  self.bottomGradientView.translatesAutoresizingMaskIntoConstraints = NO;
  self.bottomGradientView.userInteractionEnabled = NO;
  self.bottomGradientLayer = [CAGradientLayer layer];
  self.bottomGradientLayer.colors = @[
    (__bridge id)[UIColor.clearColor CGColor],
    (__bridge id)[[UIColor.blackColor colorWithAlphaComponent:0.58] CGColor],
    (__bridge id)[[UIColor.blackColor colorWithAlphaComponent:0.88] CGColor]
  ];
  self.bottomGradientLayer.locations = @[@0.0, @0.48, @1.0];
  [self.bottomGradientView.layer addSublayer:self.bottomGradientLayer];
  [self.view addSubview:self.bottomGradientView];

  self.tweetOverlayView = [[UIView alloc] init];
  self.tweetOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tweetOverlayView.backgroundColor = UIColor.clearColor;
  [self.view addSubview:self.tweetOverlayView];

  NSDictionary *author = [self.post[@"author"] isKindOfClass:NSDictionary.class] ? self.post[@"author"] : @{};
  self.overlayAvatarView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage() ?: NFBBrandIconImage()];
  self.overlayAvatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.overlayAvatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.overlayAvatarView.clipsToBounds = YES;
  self.overlayAvatarView.layer.cornerRadius = 20.0;
  self.overlayAvatarView.userInteractionEnabled = YES;
  [self.overlayAvatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)]];

  self.overlayNameLabel = [[UILabel alloc] init];
  self.overlayNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.overlayNameLabel.text = [NFBAtprotoClient displayNameForProfile:author];
  self.overlayNameLabel.textColor = NFBIPAOnMediaPrimaryTextColor();
  self.overlayNameLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
  self.overlayNameLabel.numberOfLines = 1;
  self.overlayNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.overlayHandleLabel = [[UILabel alloc] init];
  self.overlayHandleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.overlayHandleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:author]];
  self.overlayHandleLabel.textColor = NFBIPAOnMediaSecondaryTextColor();
  self.overlayHandleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  self.overlayHandleLabel.numberOfLines = 1;
  self.overlayHandleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *authorText = [[UIStackView alloc] initWithArrangedSubviews:@[self.overlayNameLabel, self.overlayHandleLabel]];
  authorText.translatesAutoresizingMaskIntoConstraints = NO;
  authorText.axis = UILayoutConstraintAxisVertical;
  authorText.alignment = UIStackViewAlignmentLeading;
  authorText.spacing = 0.0;
  authorText.userInteractionEnabled = YES;
  [authorText addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)]];
  self.overlayAuthorTextView = authorText;

  self.overlayFollowButton = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  self.overlayFollowButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.overlayFollowButton setTitle:@"Follow" forState:UIControlStateNormal];
  [self.overlayFollowButton addTarget:self action:@selector(followTapped) forControlEvents:UIControlEventTouchUpInside];
  [NFBPostActionCoordinator configureFollowButton:self.overlayFollowButton profile:author overDarkBackground:YES];

  self.overlayMoreButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.overlayMoreButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.overlayMoreButton setImage:NFBTemplateIcon(@"nfb_more") forState:UIControlStateNormal];
  NFBIPAApplyOnMediaIconButtonAppearance(self.overlayMoreButton, NO, 17.0);
  [self.overlayMoreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];

  self.overlayBodyLabel = [[NFBInteractiveTextLabel alloc] init];
  self.overlayBodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.overlayBodyLabel.font = NFBFont(16.0, NFBFontWeightRegular);
  self.overlayBodyLabel.textColor = NFBIPAOnMediaPrimaryTextColor();
  self.overlayBodyLabel.attributedText = [self overlayBodyAttributedString];
  self.overlayBodyLabel.numberOfLines = 4;
  self.overlayBodyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  __weak typeof(self) weakSelf = self;
  self.overlayBodyLabel.linkTapHandler = ^(NSURL *url) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    NFBOpenTweetTextURL(url, strongSelf);
  };
  self.overlayBodyLabel.plainTapHandler = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    [strongSelf overlayBodyTapped];
  };

  self.actionBar = [[UIView alloc] init];
  self.actionBar.translatesAutoresizingMaskIntoConstraints = NO;
  self.actionBar.backgroundColor = UIColor.clearColor;

  self.replyCountLabel = [self actionCountLabel];
  self.repostCountLabel = [self actionCountLabel];
  self.likeCountLabel = [self actionCountLabel];

  UIControl *replyItem = [self actionButtonWithIcon:@"nfb_reply" label:self.replyCountLabel selector:@selector(replyTapped)];
  UIControl *repostItem = [self actionButtonWithIcon:@"nfb_retweet" label:self.repostCountLabel selector:@selector(repostTapped)];
  UIControl *likeItem = [self actionButtonWithIcon:@"nfb_like" label:self.likeCountLabel selector:@selector(likeTapped)];
  UIControl *bookmarkItem = [self actionButtonWithIcon:@"nfb_bookmark" label:nil selector:@selector(bookmarkTapped)];
  UIControl *shareItem = [self actionButtonWithIcon:@"nfb_share" label:nil selector:@selector(shareTapped)];
  self.replyIconView = [self iconViewInActionButton:replyItem];
  self.repostIconView = [self iconViewInActionButton:repostItem];
  self.likeIconView = [self iconViewInActionButton:likeItem];
  self.bookmarkIconView = [self iconViewInActionButton:bookmarkItem];
  self.shareIconView = [self iconViewInActionButton:shareItem];

  UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[replyItem, repostItem, likeItem, bookmarkItem, shareItem]];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.axis = UILayoutConstraintAxisHorizontal;
  row.alignment = UIStackViewAlignmentCenter;
  row.distribution = UIStackViewDistributionFillEqually;
  row.spacing = 0.0;
  [self.actionBar addSubview:row];

  [self.tweetOverlayView addSubview:self.overlayAvatarView];
  [self.tweetOverlayView addSubview:authorText];
  [self.tweetOverlayView addSubview:self.overlayFollowButton];
  [self.tweetOverlayView addSubview:self.overlayMoreButton];
  [self.tweetOverlayView addSubview:self.overlayBodyLabel];
  [self.tweetOverlayView addSubview:self.actionBar];

  self.tweetOverlayLeadingConstraint = [self.tweetOverlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0];
  self.tweetOverlayTrailingConstraint = [self.tweetOverlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0];
  self.tweetOverlayBottomConstraint = [self.tweetOverlayView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0];

  [NSLayoutConstraint activateConstraints:@[
    [self.bottomGradientView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.bottomGradientView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.bottomGradientView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.bottomGradientView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.46],
    self.tweetOverlayLeadingConstraint,
    self.tweetOverlayTrailingConstraint,
    self.tweetOverlayBottomConstraint,
    [self.overlayAvatarView.leadingAnchor constraintEqualToAnchor:self.tweetOverlayView.leadingAnchor],
    [self.overlayAvatarView.topAnchor constraintEqualToAnchor:self.tweetOverlayView.topAnchor],
    [self.overlayAvatarView.widthAnchor constraintEqualToConstant:40.0],
    [self.overlayAvatarView.heightAnchor constraintEqualToConstant:40.0],
    [authorText.leadingAnchor constraintEqualToAnchor:self.overlayAvatarView.trailingAnchor constant:12.0],
    [authorText.centerYAnchor constraintEqualToAnchor:self.overlayAvatarView.centerYAnchor],
    [authorText.trailingAnchor constraintLessThanOrEqualToAnchor:self.overlayFollowButton.leadingAnchor constant:-10.0],
    [self.overlayMoreButton.trailingAnchor constraintEqualToAnchor:self.tweetOverlayView.trailingAnchor],
    [self.overlayMoreButton.centerYAnchor constraintEqualToAnchor:self.overlayAvatarView.centerYAnchor],
    [self.overlayMoreButton.widthAnchor constraintEqualToConstant:34.0],
    [self.overlayMoreButton.heightAnchor constraintEqualToConstant:34.0],
    [self.overlayFollowButton.trailingAnchor constraintEqualToAnchor:self.overlayMoreButton.leadingAnchor constant:-8.0],
    [self.overlayFollowButton.centerYAnchor constraintEqualToAnchor:self.overlayAvatarView.centerYAnchor],
    [self.overlayFollowButton.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],
    [self.overlayFollowButton.heightAnchor constraintEqualToConstant:30.0],
    [self.overlayBodyLabel.leadingAnchor constraintEqualToAnchor:self.tweetOverlayView.leadingAnchor],
    [self.overlayBodyLabel.trailingAnchor constraintEqualToAnchor:self.tweetOverlayView.trailingAnchor],
    [self.overlayBodyLabel.topAnchor constraintEqualToAnchor:self.overlayAvatarView.bottomAnchor constant:14.0],
    [self.actionBar.topAnchor constraintEqualToAnchor:self.overlayBodyLabel.bottomAnchor constant:14.0],
    [self.actionBar.leadingAnchor constraintEqualToAnchor:self.tweetOverlayView.leadingAnchor],
    [self.actionBar.trailingAnchor constraintEqualToAnchor:self.tweetOverlayView.trailingAnchor],
    [self.actionBar.heightAnchor constraintEqualToConstant:34.0],
    [row.topAnchor constraintEqualToAnchor:self.actionBar.topAnchor],
    [row.leadingAnchor constraintEqualToAnchor:self.actionBar.leadingAnchor],
    [row.trailingAnchor constraintEqualToAnchor:self.actionBar.trailingAnchor],
    [row.bottomAnchor constraintEqualToAnchor:self.actionBar.bottomAnchor],
    [self.actionBar.bottomAnchor constraintEqualToAnchor:self.tweetOverlayView.bottomAnchor]
  ]];
  [self loadOverlayAvatarURL:[NFBAtprotoClient avatarURLForProfile:author]];
  [self updateActionState];
}

- (UILabel *)actionCountLabel {
  UILabel *label = [[UILabel alloc] init];
  label.font = NFBFont(14.0, NFBFontWeightRegular);
  label.textColor = NFBIPAOnMediaSecondaryTextColor();
  label.numberOfLines = 1;
  return label;
}

- (UIControl *)actionButtonWithIcon:(NSString *)iconName label:(UILabel *)label selector:(SEL)selector {
  UIControl *control = [[UIControl alloc] init];
  control.translatesAutoresizingMaskIntoConstraints = NO;
  [control addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];

  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.userInteractionEnabled = NO;
  icon.contentMode = UIViewContentModeScaleAspectFit;
  icon.tintColor = NFBIPAOnMediaSecondaryTextColor();

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:label ? @[icon, label] : @[icon]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 6.0;
  stack.userInteractionEnabled = NO;
  [control addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:control.leadingAnchor],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:control.trailingAnchor],
    [icon.widthAnchor constraintEqualToConstant:24.0],
    [icon.heightAnchor constraintEqualToConstant:24.0],
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:34.0]
  ]];
  return control;
}

- (UIImageView *)iconViewInActionButton:(UIView *)button {
  for (UIView *subview in button.subviews) {
    if ([subview isKindOfClass:UIImageView.class]) return (UIImageView *)subview;
    if ([subview isKindOfClass:UIStackView.class]) {
      UIStackView *stack = (UIStackView *)subview;
      return [stack.arrangedSubviews.firstObject isKindOfClass:UIImageView.class] ? (UIImageView *)stack.arrangedSubviews.firstObject : nil;
    }
  }
  return nil;
}

- (void)buildVideoControlsIfNeeded {
  if (self.videoControlsView) return;
  self.videoControlsView = [[UIView alloc] init];
  self.videoControlsView.translatesAutoresizingMaskIntoConstraints = NO;
  self.videoControlsView.hidden = YES;
  [self.view addSubview:self.videoControlsView];

  self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.playPauseButton setImage:NFBTemplateIcon(@"nfb_pause") forState:UIControlStateNormal];
  NFBIPAApplyOnMediaIconButtonAppearance(self.playPauseButton, NO, 0.0);
  [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];

  self.progressSlider = [[NFBVideoProgressSlider alloc] init];
  self.progressSlider.translatesAutoresizingMaskIntoConstraints = NO;
  self.progressSlider.minimumValue = 0.0;
  self.progressSlider.maximumValue = 1.0;
  self.progressSlider.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
  self.progressSlider.minimumTrackTintColor = UIColor.whiteColor;
  self.progressSlider.maximumTrackTintColor = [UIColor.whiteColor colorWithAlphaComponent:0.35];
  [self.progressSlider setThumbImage:[self sliderThumbImageWithDiameter:16.0 color:UIColor.whiteColor] forState:UIControlStateNormal];
  self.progressSlider.accessibilityLabel = @"Playback position";
  [self.progressSlider addTarget:self action:@selector(progressTouchDown:) forControlEvents:UIControlEventTouchDown];
  [self.progressSlider addTarget:self action:@selector(progressValueChanged:) forControlEvents:UIControlEventValueChanged];
  [self.progressSlider addTarget:self action:@selector(progressTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

  self.playbackTimeLabel = [[UILabel alloc] init];
  self.playbackTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.playbackTimeLabel.textColor = UIColor.whiteColor;
  self.playbackTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:NFBFont(15.0, NFBFontWeightRegular).pointSize weight:UIFontWeightRegular];
  self.playbackTimeLabel.text = @"0:00 / 0:00";
  [self.playbackTimeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  self.playbackTimeLabel.isAccessibilityElement = NO;

  self.muteButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.muteButton.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaFloatingButtonAppearance(self.muteButton, 18.0);
  self.muteButton.hidden = YES;
  [self.muteButton setImage:NFBTemplateIcon(@"nfb_sound_off") forState:UIControlStateNormal];
  [self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];

  [self.videoControlsView addSubview:self.playPauseButton];
  [self.videoControlsView addSubview:self.progressSlider];
  [self.videoControlsView addSubview:self.playbackTimeLabel];
  [self.view addSubview:self.muteButton];
  self.videoControlsLeadingConstraint = [self.videoControlsView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor];
  self.videoControlsTrailingConstraint = [self.videoControlsView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor];
  self.videoControlsBottomConstraint = self.tweetOverlayView
    ? [self.videoControlsView.bottomAnchor constraintEqualToAnchor:self.tweetOverlayView.topAnchor constant:-8.0]
    : [self.videoControlsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0];
  self.muteButtonTrailingConstraint = [self.muteButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12.0];
  self.muteButtonBottomConstraint = [self.muteButton.bottomAnchor constraintEqualToAnchor:self.videoControlsView.topAnchor constant:-8.0];
  [NSLayoutConstraint activateConstraints:@[
    self.videoControlsLeadingConstraint, self.videoControlsTrailingConstraint, self.videoControlsBottomConstraint,
    [self.videoControlsView.heightAnchor constraintEqualToConstant:48.0],
    [self.playPauseButton.leadingAnchor constraintEqualToAnchor:self.videoControlsView.leadingAnchor],
    [self.playPauseButton.centerYAnchor constraintEqualToAnchor:self.videoControlsView.centerYAnchor],
    [self.playPauseButton.widthAnchor constraintEqualToConstant:48.0],
    [self.playPauseButton.heightAnchor constraintEqualToConstant:48.0],
    [self.progressSlider.leadingAnchor constraintEqualToAnchor:self.playPauseButton.trailingAnchor constant:-4.0],
    [self.progressSlider.trailingAnchor constraintEqualToAnchor:self.playbackTimeLabel.leadingAnchor constant:-8.0],
    [self.progressSlider.centerYAnchor constraintEqualToAnchor:self.videoControlsView.centerYAnchor],
    [self.progressSlider.heightAnchor constraintEqualToConstant:44.0],
    [self.playbackTimeLabel.trailingAnchor constraintEqualToAnchor:self.videoControlsView.trailingAnchor constant:-12.0],
    [self.playbackTimeLabel.centerYAnchor constraintEqualToAnchor:self.videoControlsView.centerYAnchor],
    self.muteButtonTrailingConstraint, self.muteButtonBottomConstraint,
    [self.muteButton.widthAnchor constraintEqualToConstant:36.0],
    [self.muteButton.heightAnchor constraintEqualToConstant:36.0]
  ]];
  self.seekFeedbackLabel = [[UILabel alloc] init];
  self.seekFeedbackLabel.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.6];
  self.seekFeedbackLabel.textColor = UIColor.whiteColor;
  self.seekFeedbackLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.seekFeedbackLabel.textAlignment = NSTextAlignmentCenter;
  self.seekFeedbackLabel.layer.cornerRadius = 28.0;
  self.seekFeedbackLabel.clipsToBounds = YES;
  self.seekFeedbackLabel.alpha = 0.0;
  self.seekFeedbackLabel.userInteractionEnabled = NO;
  [self.view addSubview:self.seekFeedbackLabel];
}

- (UIImage *)sliderThumbImageWithDiameter:(CGFloat)diameter color:(UIColor *)color {
  CGSize size = CGSizeMake(diameter, diameter);
  UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGContextSetFillColorWithColor(context, color.CGColor);
  CGContextFillEllipseInRect(context, CGRectMake(0.0, 0.0, diameter, diameter));
  UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return image;
}

- (NSString *)playbackTimeString:(Float64)seconds {
  NSInteger value = isfinite(seconds) ? (NSInteger)MAX(0, floor(seconds)) : 0;
  if (value >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(value / 3600), (long)(value / 60 % 60), (long)(value % 60)];
  return [NSString stringWithFormat:@"%ld:%02ld", (long)(value / 60), (long)(value % 60)];
}

- (void)updateVideoProgressVisual {
  Float64 duration = CMTimeGetSeconds([self currentPlayer].currentItem.duration);
  if (!isfinite(duration) || duration < 0.0) duration = 0.0;
  self.playbackTimeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self playbackTimeString:self.progressSlider.value * duration], [self playbackTimeString:duration]];
  self.progressSlider.accessibilityValue = self.playbackTimeLabel.text;
}

- (void)loadOverlayAvatarURL:(NSString *)urlString {
  self.overlayAvatarURLString = urlString ?: @"";
  if (urlString.length == 0) return;
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.overlayAvatarURLString isEqualToString:urlString]) self.overlayAvatarView.image = image;
    });
  }] resume];
}

- (AVPlayer *)currentPlayer {
  NSUInteger index = [self currentIndex];
  if (index >= self.pages.count) return nil;
  return self.pages[index].player;
}

- (void)removeObservedPlayerTimeObserver {
  if (self.observedPlayer && self.playerTimeObserver) {
    [self.observedPlayer removeTimeObserver:self.playerTimeObserver];
  }
  self.playerTimeObserver = nil;
  self.observedPlayer = nil;
}

- (void)observeCurrentPlayerIfNeeded {
  AVPlayer *player = [self currentPlayer];
  self.videoControlsView.hidden = player == nil;
  self.muteButton.hidden = player == nil;
  if (!player) {
    [self removeObservedPlayerTimeObserver];
    return;
  }
  if (self.observedPlayer == player && self.playerTimeObserver) return;
  [self removeObservedPlayerTimeObserver];
  self.observedPlayer = player;
  __weak typeof(self) weakSelf = self;
  self.playerTimeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, NSEC_PER_SEC)
                                                                 queue:dispatch_get_main_queue()
                                                            usingBlock:^(CMTime time) {
    (void)time;
    [weakSelf updateVideoControlState];
  }];
  [self updateVideoControlState];
}

- (void)updateVideoControlState {
  AVPlayer *player = [self currentPlayer];
  self.videoControlsView.hidden = player == nil;
  self.muteButton.hidden = ![NFBMediaAudioSession hasAudioForPlayer:player] || [[self currentMediaItem][@"type"] isEqual:@"gif"];
  if (!player) return;
  if (self.verticalDismissTracking) return;
  CGFloat chromeAlpha = self.viewerChromeHidden ? 0.0 : 1.0;
  self.videoControlsView.alpha = chromeAlpha;
  self.muteButton.alpha = chromeAlpha;
  [self updateVideoChromeLayout];
  UIImage *playPause = NFBTemplateIcon(player.rate == 0.0 ? @"nfb_play" : @"nfb_pause");
  [self.playPauseButton setImage:playPause forState:UIControlStateNormal];
  self.playPauseButton.accessibilityLabel = player.rate == 0.0 ? @"Play" : @"Pause";
  self.muteButton.accessibilityLabel = player.muted ? @"Unmute" : @"Mute";
  UIImage *mute = NFBTemplateIcon(player.muted ? @"nfb_sound_off" : @"nfb_sound");
  [self.muteButton setImage:mute forState:UIControlStateNormal];
  if (self.trackingProgressSlider) return;
  Float64 duration = CMTimeGetSeconds(player.currentItem.duration);
  Float64 current = CMTimeGetSeconds(player.currentTime);
  if (isfinite(duration) && duration > 0.0 && isfinite(current)) {
    self.progressSlider.value = (float)MIN(1.0, MAX(0.0, current / duration));
  } else {
    self.progressSlider.value = 0.0;
  }
  NSString *url = [self currentPage].item[@"videoURL"];
  [NFBMediaPreviewView recordVideoURL:url position:CMTimeGetSeconds(player.currentTime) duration:CMTimeGetSeconds(player.currentItem.duration)];
  [self updateVideoProgressVisual];
}

- (void)playPauseTapped {
  AVPlayer *player = [self currentPlayer];
  if (!player) return;
  if (player.rate == 0.0) {
    Float64 duration = CMTimeGetSeconds(player.currentItem.duration);
    if (isfinite(duration) && CMTimeGetSeconds(player.currentTime) >= duration - 0.1) [player seekToTime:kCMTimeZero];
    self.userPausedCurrentVideo = NO;
    self.userForcedPlayback = YES;
    [player playImmediatelyAtRate:self.playbackRate > 0.0 ? self.playbackRate : 1.0];
  } else {
    self.userPausedCurrentVideo = YES;
    self.userForcedPlayback = NO;
    [player pause];
  }
  [self updateVideoControlState];
  [self scheduleChromeAutoHide];
}

- (void)muteTapped {
  AVPlayer *player = [self currentPlayer];
  if (!player) return;
  self.userChangedMute = YES;
  [NFBMediaAudioSession setMuted:!player.muted forPlayer:player];
  [self updateVideoControlState];
}

- (void)setPlaybackRateFromIdentifier:(NSString *)identifier {
  NSDictionary<NSString *, NSNumber *> *rates = @{
    @"speed-0.5": @(0.5),
    @"speed-0.75": @(0.75),
    @"speed-1.0": @(1.0),
    @"speed-1.25": @(1.25),
    @"speed-1.5": @(1.5),
    @"speed-1.75": @(1.75),
    @"speed-2.0": @(2.0)
  };
  NSNumber *rateNumber = rates[identifier ?: @""];
  if (!rateNumber) return;
  self.playbackRate = rateNumber.doubleValue;
  AVPlayer *player = [self currentPlayer];
  if (player && player.rate != 0.0) [player setRate:self.playbackRate];
  [self updateVideoControlState];
}

- (void)presentVideoOptionsSheet {
  AVPlayer *player = [self currentPlayer];
  if (!player) return;
  BOOL muted = player.muted;
  NSMutableArray<NSDictionary *> *items = [@[
    @{@"id": @"playback-speed", @"title": @"Playback speed", @"icon": @"nfb_playback_speed"}
  ] mutableCopy];
  if (!self.muteButton.hidden) [items addObject:@{@"id": @"toggle-mute", @"title": muted ? @"Unmute" : @"Mute", @"icon": muted ? @"nfb_sound" : @"nfb_sound_off"}];
  if ([self currentAltText].length > 0) [items addObject:@{@"id": @"alt", @"title": @"View description", @"icon": @"nfb_alt_compose"}];
  if (self.post.count) {
    [items addObject:@{@"id": @"profile", @"title": @"Go to profile", @"icon": @"nfb_profile"}];
    [items addObject:@{@"id": @"share", @"title": @"Share Tweet", @"icon": @"nfb_share"}];
  }
  [items addObject:@{@"id": @"cancel", @"title": @"Cancel", @"icon": @"nfb_close"}];
  __weak typeof(self) weakSelf = self;
  NFBVideoOptionsSheetViewController *sheet = [[NFBVideoOptionsSheetViewController alloc] initWithTitle:@"Video options" items:items selection:^(NSString *identifier) {
    __strong typeof(weakSelf) self = weakSelf;
    if ([identifier isEqual:@"playback-speed"]) [self presentPlaybackSpeedSheet];
    else if ([identifier isEqual:@"toggle-mute"]) [self muteTapped];
    else if ([identifier isEqual:@"alt"]) [self altTextTapped];
    else if ([identifier isEqual:@"profile"]) [self authorTapped];
    else if ([identifier isEqual:@"share"]) [self shareTapped];
  }];
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)presentPlaybackSpeedSheet {
  NSArray<NSDictionary *> *items = @[
    @{@"id": @"speed-0.5", @"title": @"0.5x", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 0.5) < 0.01)},
    @{@"id": @"speed-0.75", @"title": @"0.75x", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 0.75) < 0.01)},
    @{@"id": @"speed-1.0", @"title": @"1x (Normal)", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 1.0) < 0.01)},
    @{@"id": @"speed-1.25", @"title": @"1.25x", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 1.25) < 0.01)},
    @{@"id": @"speed-1.5", @"title": @"1.5x", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 1.5) < 0.01)},
    @{@"id": @"speed-1.75", @"title": @"1.75x", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 1.75) < 0.01)},
    @{@"id": @"speed-2.0", @"title": @"2x", @"icon": @"nfb_playback_speed", @"checked": @(fabs(self.playbackRate - 2.0) < 0.01)},
    @{@"id": @"cancel", @"title": @"Cancel", @"icon": @"nfb_close"}
  ];
  __weak typeof(self) weakSelf = self;
  NFBVideoOptionsSheetViewController *sheet = [[NFBVideoOptionsSheetViewController alloc] initWithTitle:@"Playback speed" items:items selection:^(NSString *identifier) {
    [weakSelf setPlaybackRateFromIdentifier:identifier];
  }];
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)progressTouchDown:(UISlider *)slider {
  (void)slider;
  self.trackingProgressSlider = YES;
  self.resumeAfterScrubbing = [self currentPlayer].rate > 0.0;
  [[self currentPlayer] pause];
  [self.chromeHideTimer invalidate];
  self.chromeHideTimer = nil;
}

- (void)progressValueChanged:(UISlider *)slider {
  Float64 duration = CMTimeGetSeconds([self currentPlayer].currentItem.duration);
  if (isfinite(duration) && duration > 0) [[self currentPlayer] seekToTime:CMTimeMakeWithSeconds(duration * slider.value, 600) toleranceBefore:CMTimeMakeWithSeconds(0.1, 600) toleranceAfter:CMTimeMakeWithSeconds(0.1, 600)];
  [self updateVideoProgressVisual];
}

- (void)progressTouchUp:(UISlider *)slider {
  AVPlayer *player = [self currentPlayer];
  self.trackingProgressSlider = NO;
  if (!player) return;
  Float64 duration = CMTimeGetSeconds(player.currentItem.duration);
  if (!isfinite(duration) || duration <= 0.0) return;
  CMTime target = CMTimeMakeWithSeconds(duration * slider.value, NSEC_PER_SEC);
  BOOL resume = self.resumeAfterScrubbing;
  [player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (finished && resume && self.view.window && player == [self currentPlayer]) [player playImmediatelyAtRate:self.playbackRate];
      [self updateVideoControlState];
      [self scheduleChromeAutoHide];
    });
  }];
  [self updateVideoProgressVisual];
  [self updateVideoControlState];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGSize size = self.view.bounds.size;
  NSUInteger visibleIndex = self.positionedInitialPage && self.pagerLayoutWidth > 0 ? MIN((NSUInteger)MAX(0, llround(self.scrollView.contentOffset.x / self.pagerLayoutWidth)), self.pages.count ? self.pages.count - 1 : 0) : self.initialIndex;
  BOOL sizeChanged = fabs(self.pagerLayoutWidth - size.width) > 0.5;
  if (!self.verticalDismissTracking) self.dismissContentView.frame = self.view.bounds;
  self.mediaContainerView.frame = self.dismissContentView.bounds;
  self.scrollView.frame = self.mediaContainerView.bounds;
  self.bottomGradientLayer.frame = self.bottomGradientView.bounds;
  self.scrollView.contentSize = CGSizeMake(size.width * self.pages.count, size.height);
  for (NSUInteger index = 0; index < self.pages.count; index++) {
    self.pages[index].frame = CGRectMake(size.width * index, 0.0, size.width, size.height);
  }
  if (!self.positionedInitialPage || sizeChanged) self.scrollView.contentOffset = CGPointMake(size.width * visibleIndex, 0.0);
  self.pagerLayoutWidth = size.width;
  self.positionedInitialPage = YES;
  [self updateVideoChromeLayout];
  if (self.lastPlaybackIndex < 0 || sizeChanged) [self updateCurrentPage];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self playCurrentVideoIfNeeded];
  [self observeCurrentPlayerIfNeeded];
  [self scheduleChromeAutoHide];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  [self updateVideoControlState];
  self.wasPlayingBeforeBackground = NO;
  [self.chromeHideTimer invalidate];
  self.chromeHideTimer = nil;
  for (NFBMediaViewerPage *page in self.pages) [page pause];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  [NFBMediaPreviewView resumeInlinePlayback];
}

- (BOOL)prefersStatusBarHidden {
  return YES;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
  (void)scrollView;
  [self updateCurrentPage];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
  (void)scrollView;
  [self updateCurrentPage];
}

- (NSUInteger)currentIndex {
  CGFloat width = CGRectGetWidth(self.scrollView.bounds);
  if (width <= 0.0) return 0;
  return MIN((NSUInteger)MAX(0, llround(self.scrollView.contentOffset.x / width)), self.pages.count > 0 ? self.pages.count - 1 : 0);
}

- (NFBMediaViewerPage *)currentPage {
  NSUInteger index = [self currentIndex];
  return index < self.pages.count ? self.pages[index] : nil;
}

- (CGRect)currentMediaFrameInView {
  NFBMediaViewerPage *page = [self currentPage];
  if (!page) return CGRectZero;
  CGRect media = [page.mediaContentView convertRect:page.mediaContentView.bounds toView:self.view];
  return CGRectIntersection(self.view.bounds, media);
}

- (void)updateVideoChromeLayout {
  self.videoControlsLeadingConstraint.constant = 0.0;
  self.videoControlsTrailingConstraint.constant = 0.0;
  self.videoControlsBottomConstraint.constant = self.tweetOverlayView ? -8.0 : -12.0;
  self.muteButtonTrailingConstraint.constant = -12.0;
  self.muteButtonBottomConstraint.constant = -8.0;
}

- (void)updateCurrentPage {
  NSUInteger current = [self currentIndex];
  if (self.lastPlaybackIndex != (NSInteger)current) {
    self.lastPlaybackIndex = (NSInteger)current;
    self.userPausedCurrentVideo = NO;
    self.userForcedPlayback = NO;
    self.userChangedMute = NO;
  }
  for (NSUInteger index = 0; index < self.pages.count; index++) {
    if (labs((long)index - (long)current) <= 1) [self.pages[index] loadImageIfNeeded];
    else [self.pages[index] unloadImage];
  }
  self.scrollView.scrollEnabled = [self currentPage].zoomScrollView.zoomScale <= 1.01;
  self.pageLabel.text = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)(current + 1), (unsigned long)self.mediaItems.count];
  if (!self.verticalDismissTracking) {
    self.dismissContentView.transform = CGAffineTransformIdentity;
    self.dismissContentView.frame = self.view.bounds;
    for (NFBMediaViewerPage *page in self.pages) {
      [page resetDismissTransform];
      page.backgroundColor = UIColor.blackColor;
    }
    self.mediaContainerView.backgroundColor = UIColor.blackColor;
    self.scrollView.backgroundColor = UIColor.blackColor;
    self.view.backgroundColor = UIColor.blackColor;
    [self restoreVerticalDismissOverlayChrome];
  }
  [self playCurrentVideoIfNeeded];
  [self observeCurrentPlayerIfNeeded];
  [self updateVideoChromeLayout];
  [self updateAltTextButton];
  [self scheduleChromeAutoHide];
}

- (void)playCurrentVideoIfNeeded {
  NSUInteger current = [self currentIndex];
  for (NSUInteger index = 0; index < self.pages.count; index++) {
    NFBMediaViewerPage *page = self.pages[index];
    if (index == current) {
      AVPlayer *player = page.player;
      if (!player) continue;
      if (!self.userChangedMute) player.muted = YES;
      BOOL shouldPlay = self.userForcedPlayback || (!self.userPausedCurrentVideo && [self autoplayEnabledForCurrentVideo]);
      if (shouldPlay) {
        if (self.playbackRate > 0.0) [player playImmediatelyAtRate:self.playbackRate];
        else [page playIfNeeded];
      } else if (!self.userForcedPlayback) {
        [player pause];
      }
    } else {
      [page pause];
    }
  }
}

- (BOOL)autoplayEnabledForCurrentVideo {
  if (!self.view.window) return NO;
  if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
  if (UIAccessibilityIsVoiceOverRunning()) return NO;
  if (UIAccessibilityIsReduceMotionEnabled()) return NO;
  if (@available(iOS 9.0, *)) {
    if (NSProcessInfo.processInfo.lowPowerModeEnabled) return NO;
  }
  return YES;
}

- (void)applicationWillResignActive:(NSNotification *)notification {
  (void)notification;
  AVPlayer *player = [self currentPlayer];
  self.wasPlayingBeforeBackground = player.rate != 0.0;
  for (NFBMediaViewerPage *page in self.pages) [page pause];
  [self updateVideoControlState];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
  (void)notification;
  if (self.wasPlayingBeforeBackground || (!self.userPausedCurrentVideo && [self autoplayEnabledForCurrentVideo])) {
    self.wasPlayingBeforeBackground = NO;
    [self playCurrentVideoIfNeeded];
  }
  [self updateVideoControlState];
}

- (void)autoplayConditionsDidChange:(NSNotification *)notification {
  (void)notification;
  if (![self autoplayEnabledForCurrentVideo] && !self.userForcedPlayback) {
    [[self currentPlayer] pause];
  } else {
    [self playCurrentVideoIfNeeded];
  }
  [self updateVideoControlState];
}

- (void)closeTapped {
  for (NFBMediaViewerPage *page in self.pages) [page pause];
  [self removeObservedPlayerTimeObserver];
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)touch:(UITouch *)touch isInsideChromeView:(UIView *)view {
  return view && !view.hidden && view.alpha > 0.01 && [touch.view isDescendantOfView:view];
}

- (NSAttributedString *)overlayBodyAttributedString {
  NSMutableAttributedString *attributed = [NFBTweetBodyAttributedStringForPost(self.post, self.overlayBodyLabel.font ?: NFBFont(16.0, NFBFontWeightRegular)) mutableCopy];
  if (attributed.length == 0) return attributed ?: [[NSAttributedString alloc] initWithString:@""];
  NSRange fullRange = NSMakeRange(0, attributed.length);
  [attributed addAttribute:NSForegroundColorAttributeName value:NFBIPAOnMediaPrimaryTextColor() range:fullRange];
  [attributed enumerateAttribute:NFBTextLinkURLAttributeName inRange:fullRange options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
    (void)stop;
    if (value) [attributed addAttribute:NSForegroundColorAttributeName value:NFBColorAccent() range:range];
  }];
  [attributed enumerateAttribute:NSLinkAttributeName inRange:fullRange options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
    (void)stop;
    if (value) [attributed addAttribute:NSForegroundColorAttributeName value:NFBColorAccent() range:range];
  }];
  return [attributed copy];
}

- (void)overlayBodyTapped {
  if (self.overlayBodyLabel.attributedText.length == 0 || self.verticalDismissTracking) return;
  if (self.overlayBodyExpanded) {
    [self openTweetPageFromOverlayBody];
    return;
  }
  self.overlayBodyExpanded = YES;
  self.overlayBodyLabel.numberOfLines = self.overlayBodyExpanded ? 0 : 4;
  self.overlayBodyLabel.lineBreakMode = self.overlayBodyExpanded ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
  [UIView animateWithDuration:0.18
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    [self.view layoutIfNeeded];
    [self updateVideoChromeLayout];
  } completion:nil];
}

- (UINavigationController *)navigationControllerForTweetPageHandoffFromPresenter:(UIViewController *)presenter {
  if ([presenter isKindOfClass:UINavigationController.class]) return (UINavigationController *)presenter;
  if (presenter.navigationController) return presenter.navigationController;
  if ([presenter isKindOfClass:UITabBarController.class]) {
    UIViewController *selected = ((UITabBarController *)presenter).selectedViewController;
    if ([selected isKindOfClass:UINavigationController.class]) return (UINavigationController *)selected;
    if (selected.navigationController) return selected.navigationController;
  }
  return nil;
}

- (void)openTweetPageFromOverlayBody {
  NSDictionary *post = self.post ?: @{};
  if (post.count == 0) return;
  UIViewController *presenter = self.presentingViewController;
  UINavigationController *navigationController = [self navigationControllerForTweetPageHandoffFromPresenter:presenter];
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  if (navigationController) {
    [self dismissViewControllerAnimated:YES completion:^{
      [navigationController pushViewController:detail animated:YES];
    }];
    return;
  }

  UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:detail];
  NFBApplyNavigationAppearance(wrapper);
  [self dismissViewControllerAnimated:YES completion:^{
    [presenter presentViewController:wrapper animated:YES completion:nil];
  }];
}

- (void)chromeToggleTapped:(UITapGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateEnded || self.verticalDismissTracking) return;
  if ([self currentPlayer] && CACurrentMediaTime() - self.lastSeekGestureTime < 0.8 && [self seekVideoAtPoint:[gesture locationInView:self.view]]) return;
  [self setViewerChromeHidden:!self.viewerChromeHidden animated:YES];
}

- (BOOL)seekVideoAtPoint:(CGPoint)point {
  AVPlayer *player = [self currentPlayer];
  CGRect media = [self currentMediaFrameInView];
  if (!player || CGRectIsEmpty(media) || !CGRectContainsPoint(media, point)) return NO;
  CGFloat fraction = (point.x - CGRectGetMinX(media)) / CGRectGetWidth(media);
  if (fraction >= 0.175 && fraction <= 0.825) return NO;
  Float64 duration = CMTimeGetSeconds(player.currentItem.duration);
  Float64 current = CMTimeGetSeconds(player.currentTime);
  if (!isfinite(duration) || duration <= 0 || !isfinite(current)) return NO;
  CGFloat step = fraction > 0.825 ? 5.0 : -5.0;
  Float64 target = MAX(0.0, MIN(duration, current + step));
  [player seekToTime:CMTimeMakeWithSeconds(target, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
  self.lastSeekGestureTime = CACurrentMediaTime();
  self.progressSlider.value = target / duration;
  [self updateVideoProgressVisual];
  self.seekFeedbackLabel.text = step > 0 ? @"+5s" : @"−5s";
  self.seekFeedbackLabel.frame = CGRectMake(step > 0 ? CGRectGetMaxX(media) - 72 : CGRectGetMinX(media) + 16, CGRectGetMidY(media) - 28, 56, 56);
  [self.seekFeedbackLabel.layer removeAllAnimations];
  self.seekFeedbackLabel.alpha = 1.0;
  [UIView animateWithDuration:0.2 delay:0.6 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ self.seekFeedbackLabel.alpha = 0.0; } completion:nil];
  [self scheduleChromeAutoHide];
  return YES;
}

- (void)mediaDoubleTapped:(UITapGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateEnded) return;
  CGPoint point = [gesture locationInView:self.view];
  if ([self seekVideoAtPoint:point]) return;
  NFBMediaViewerPage *page = [self currentPage];
  [page toggleZoomAtPoint:[gesture locationInView:page]];
}

- (void)mediaLongPressed:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan) return;
  [self.chromeHideTimer invalidate];
  self.chromeHideTimer = nil;
  if ([self currentPlayer]) [self shareTapped];
  else [self presentMediaOptionsSheet];
}

- (void)scheduleChromeAutoHide {
  [self.chromeHideTimer invalidate];
  self.chromeHideTimer = nil;
  if (self.viewerChromeHidden || ![self currentPlayer] || self.userPausedCurrentVideo || self.trackingProgressSlider || UIAccessibilityIsVoiceOverRunning()) return;
  __weak typeof(self) weakSelf = self;
  self.chromeHideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:NO block:^(NSTimer *timer) {
    if (weakSelf.view.window && !weakSelf.presentedViewController && !weakSelf.verticalDismissTracking && [weakSelf currentPlayer].rate > 0) [weakSelf setViewerChromeHidden:YES animated:YES];
  }];
}

- (void)playerDidReachEnd:(NSNotification *)notification {
  AVPlayer *player = [self currentPlayer];
  if (notification.object != player.currentItem) return;
  if ([[self currentMediaItem][@"type"] isEqualToString:@"gif"]) {
    [player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (finished && self.view.window && !self.userPausedCurrentVideo) [player playImmediatelyAtRate:self.playbackRate]; });
    }];
  } else {
    self.userPausedCurrentVideo = YES;
    [NFBMediaAudioSession stopPlayer:player];
    [self setViewerChromeHidden:NO animated:YES];
    [self updateVideoControlState];
  }
}

- (void)setViewerChromeHidden:(BOOL)hidden animated:(BOOL)animated {
  self.viewerChromeHidden = hidden;
  if (hidden) { [self.chromeHideTimer invalidate]; self.chromeHideTimer = nil; }
  else [self scheduleChromeAutoHide];
  CGFloat alpha = hidden ? 0.0 : 1.0;
  NSTimeInterval duration = hidden ? 0.18 : 0.22;
  void (^changes)(void) = ^{
    [self applyViewerChromeAlpha:alpha topAlpha:alpha bottomTranslation:0.0];
  };
  if (animated) {
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:changes
                     completion:nil];
  } else {
    changes();
  }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  if (gestureRecognizer == self.chromeToggleTapGesture || gestureRecognizer == self.mediaDoubleTap || gestureRecognizer == self.mediaLongPress) return !self.verticalDismissTracking;
  if (gestureRecognizer != self.verticalDismissGesture) return YES;
  if ([self currentPage].zoomScrollView.zoomScale > 1.01 || self.trackingProgressSlider || self.scrollView.isDecelerating) return NO;
  CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
  if (fabs(velocity.y) < 18.0) return NO;
  return fabs(velocity.y) > fabs(velocity.x);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
  if (gestureRecognizer == self.verticalDismissGesture) {
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) if ([view isKindOfClass:UIControl.class]) return NO;
    return YES;
  }
  if (gestureRecognizer != self.chromeToggleTapGesture && gestureRecognizer != self.mediaDoubleTap && gestureRecognizer != self.mediaLongPress) return YES;
  if ([self touch:touch isInsideChromeView:self.closeButton]) return NO;
  if ([self touch:touch isInsideChromeView:self.pageLabel]) return NO;
  if ([self touch:touch isInsideChromeView:self.altTextButton]) return NO;
  if ([self touch:touch isInsideChromeView:self.videoControlsView]) return NO;
  if ([self touch:touch isInsideChromeView:self.muteButton]) return NO;
  if ([self touch:touch isInsideChromeView:self.overlayAvatarView]) return NO;
  if ([self touch:touch isInsideChromeView:self.overlayAuthorTextView]) return NO;
  if ([self touch:touch isInsideChromeView:self.overlayBodyLabel]) return NO;
  if ([self touch:touch isInsideChromeView:self.overlayFollowButton]) return NO;
  if ([self touch:touch isInsideChromeView:self.overlayMoreButton]) return NO;
  if ([self touch:touch isInsideChromeView:self.actionBar]) return NO;
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  (void)otherGestureRecognizer;
  if (gestureRecognizer == self.verticalDismissGesture) return NO;
  return NO;
}

- (CGFloat)verticalDismissProgressForOffset:(CGFloat)offsetY {
  CGFloat height = MAX(CGRectGetHeight(self.view.bounds), 1.0);
  return NFBViewerClamp(fabs(offsetY) / height, 0.0, 1.0);
}

- (void)removeVerticalDismissAnimations {
  [self.dismissContentView.layer removeAllAnimations];
  [self.view.layer removeAllAnimations];
  [self.bottomGradientView.layer removeAllAnimations];
  [self.tweetOverlayView.layer removeAllAnimations];
  [self.videoControlsView.layer removeAllAnimations];
  [self.muteButton.layer removeAllAnimations];
  [self.altTextButton.layer removeAllAnimations];
  [self.closeButton.layer removeAllAnimations];
  [self.pageLabel.layer removeAllAnimations];
}

- (CGFloat)verticalDismissChromeAlphaForPercentVisible:(CGFloat)percentVisible {
  return NFBViewerSmoothProgress(NFBViewerClamp((percentVisible - 0.10) / 0.90, 0.0, 1.0));
}

- (void)applyViewerChromeAlpha:(CGFloat)alpha topAlpha:(CGFloat)topAlpha bottomTranslation:(CGFloat)bottomTranslation {
  CGFloat baseAlpha = self.viewerChromeHidden ? 0.0 : 1.0;
  CGFloat clampedAlpha = NFBViewerClamp(alpha, 0.0, 1.0) * baseAlpha;
  CGFloat clampedTopAlpha = NFBViewerClamp(topAlpha, 0.0, 1.0) * baseAlpha;
  CGAffineTransform bottomTransform = CGAffineTransformMakeTranslation(0.0, bottomTranslation);

  self.bottomGradientView.alpha = clampedAlpha;
  self.bottomGradientView.transform = CGAffineTransformIdentity;
  self.tweetOverlayView.alpha = clampedAlpha;
  self.tweetOverlayView.transform = bottomTransform;
  self.videoControlsView.alpha = self.videoControlsView.hidden ? 0.0 : clampedAlpha;
  self.videoControlsView.transform = bottomTransform;
  self.muteButton.alpha = self.muteButton.hidden ? 0.0 : clampedAlpha;
  self.muteButton.transform = bottomTransform;
  self.altTextButton.alpha = self.altTextButton.hidden ? 0.0 : clampedAlpha;
  self.altTextButton.transform = bottomTransform;

  self.closeButton.alpha = clampedTopAlpha;
  self.pageLabel.alpha = self.mediaItems.count <= 1 ? 0.0 : clampedTopAlpha;
}

- (void)restoreVerticalDismissOverlayChrome {
  CGFloat alpha = self.viewerChromeHidden ? 0.0 : 1.0;
  self.actionBar.alpha = 1.0;
  self.overlayBodyLabel.alpha = 1.0;
  [self applyViewerChromeAlpha:alpha topAlpha:alpha bottomTranslation:0.0];
}

- (void)animateVerticalDismissOverlayChromeOut {
  if (self.verticalDismissChromeDropped) return;
  self.verticalDismissChromeDropped = YES;
  [UIView animateWithDuration:0.18
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    [self applyViewerChromeAlpha:0.0 topAlpha:0.0 bottomTranslation:54.0];
  } completion:nil];
}

- (void)animateVerticalDismissOverlayChromeIn {
  self.verticalDismissChromeDropped = NO;
  CGFloat alpha = self.viewerChromeHidden ? 0.0 : 1.0;
  [UIView animateWithDuration:0.22
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    [self applyViewerChromeAlpha:alpha topAlpha:alpha bottomTranslation:0.0];
  } completion:nil];
}

- (void)applyVerticalDismissChromeForPage:(NFBMediaViewerPage *)page offsetY:(CGFloat)offsetY progress:(CGFloat)progress {
  (void)page;
  (void)progress;
  CGFloat height = MAX(CGRectGetHeight(self.view.bounds), 1.0);
  CGFloat percentVisible = NFBViewerClamp((height - fabs(offsetY)) / height, 0.0, 1.0);
  self.dismissContentView.transform = CGAffineTransformIdentity;
  self.dismissContentView.frame = CGRectOffset(self.view.bounds, 0.0, offsetY);
  self.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:percentVisible];
  self.mediaContainerView.backgroundColor = UIColor.blackColor;
  self.scrollView.backgroundColor = UIColor.blackColor;
  for (NFBMediaViewerPage *viewerPage in self.pages) {
    viewerPage.backgroundColor = UIColor.blackColor;
    [viewerPage resetDismissTransform];
  }
}

- (void)restoreVerticalDismissChromeForPage:(NFBMediaViewerPage *)page {
  (void)page;
  self.dismissContentView.transform = CGAffineTransformIdentity;
  self.dismissContentView.frame = self.view.bounds;
  for (NFBMediaViewerPage *viewerPage in self.pages) {
    [viewerPage resetDismissTransform];
    viewerPage.backgroundColor = UIColor.blackColor;
  }
  self.view.backgroundColor = UIColor.blackColor;
  self.mediaContainerView.backgroundColor = UIColor.blackColor;
  self.scrollView.backgroundColor = UIColor.blackColor;
}

- (void)verticalDismissPanned:(UIPanGestureRecognizer *)gesture {
  CGPoint translation = [gesture translationInView:self.view];
  CGPoint velocity = [gesture velocityInView:self.view];
  CGFloat offsetY = translation.y;
  CGFloat progress = [self verticalDismissProgressForOffset:offsetY];
  NFBMediaViewerPage *currentPage = [self currentPage];
  if (!currentPage) return;

  switch (gesture.state) {
    case UIGestureRecognizerStateBegan:
      self.verticalDismissTracking = YES;
      self.scrollView.scrollEnabled = NO;
      [self removeVerticalDismissAnimations];
      [self animateVerticalDismissOverlayChromeOut];
      break;
    case UIGestureRecognizerStateChanged:
      if (!self.verticalDismissTracking) return;
      [self applyVerticalDismissChromeForPage:currentPage offsetY:offsetY progress:progress];
      break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed: {
      CGFloat height = MAX(CGRectGetHeight(self.view.bounds), 1.0);
      BOOL cancelled = gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed;
      CGFloat referenceY = fabs(offsetY) >= 1.0 ? offsetY : velocity.y;
      CGFloat direction = referenceY >= 0.0 ? 1.0 : -1.0;
      BOOL velocityOpposesDrag = fabs(velocity.y) >= 20.0 && (velocity.y * direction) < 0.0;
      BOOL passedVelocity = fabs(velocity.y) > 420.0 && !velocityOpposesDrag;
      BOOL passedDistance = fabs(offsetY) > height * 0.12 && !velocityOpposesDrag;
      BOOL shouldDismiss = !cancelled && (passedVelocity || passedDistance);
      if (shouldDismiss) {
        CGFloat targetY = direction * height;
        CGFloat remaining = MAX(0.0, height - fabs(offsetY));
        CGFloat duration = MIN(remaining / MAX(fabs(velocity.y), 1.0), 0.35);
        duration = MAX(duration, 0.10);
        [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
          [self applyVerticalDismissChromeForPage:currentPage offsetY:targetY progress:1.0];
          self.view.backgroundColor = UIColor.clearColor;
        } completion:^(BOOL finished) {
          (void)finished;
          self.verticalDismissTracking = NO;
          for (NFBMediaViewerPage *page in self.pages) [page pause];
          [self removeObservedPlayerTimeObserver];
          self.view.hidden = YES;
          [self dismissViewControllerAnimated:NO completion:nil];
        }];
        return;
      }
      CGFloat springVelocity = NFBViewerClamp(fabs(velocity.y) / MAX(fabs(offsetY), 120.0), 0.0, 9.0);
      [self animateVerticalDismissOverlayChromeIn];
      [UIView animateWithDuration:0.38 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:springVelocity options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self restoreVerticalDismissChromeForPage:currentPage];
      } completion:^(BOOL finished) {
        (void)finished;
        self.verticalDismissTracking = NO;
        self.scrollView.scrollEnabled = YES;
        CGFloat chromeAlpha = self.viewerChromeHidden ? 0.0 : 1.0;
        if (!self.videoControlsView.hidden) self.videoControlsView.alpha = chromeAlpha;
        if (!self.muteButton.hidden) self.muteButton.alpha = chromeAlpha;
      }];
      break;
    }
    default:
      break;
  }
}

- (BOOL)ensureSessionForTweetAction {
  if ([[NFBAtprotoSession sharedSession] hasSession]) return YES;
  NFBPresentBlueskyLoginIfNeeded();
  return NO;
}

- (void)replyTapped {
  [[self postActionCoordinator] performReplyForPost:self.post ?: @{} sourceView:self.replyIconView];
}

- (void)repostTapped {
  [[self postActionCoordinator] performRepostForPost:self.post ?: @{} sourceView:self.repostIconView];
}

- (void)likeTapped {
  [[self postActionCoordinator] performLikeForPost:self.post ?: @{} sourceView:self.likeIconView];
}

- (void)bookmarkTapped {
  [[self postActionCoordinator] performBookmarkForPost:self.post ?: @{} sourceView:self.bookmarkIconView];
}

- (void)shareTapped {
  [[self postActionCoordinator] performShareForPost:self.post ?: @{} sourceView:self.shareIconView];
}

- (void)authorTapped {
  NSDictionary *author = [self.post[@"author"] isKindOfClass:NSDictionary.class] ? self.post[@"author"] : @{};
  [[self postActionCoordinator] performGoToProfile:author];
}

- (void)followTapped {
  NSDictionary *author = [self.post[@"author"] isKindOfClass:NSDictionary.class] ? self.post[@"author"] : @{};
  [[self postActionCoordinator] performFollowForProfile:author sourceView:self.overlayFollowButton completion:nil];
}

- (void)moreTapped {
  if ([self currentPlayer]) {
    [self presentVideoOptionsSheet];
    return;
  }
  [self presentMediaOptionsSheet];
}

- (NSDictionary *)currentMediaItem {
  NSUInteger index = [self currentIndex];
  if (index >= self.mediaItems.count) return @{};
  return self.mediaItems[index];
}

- (NSString *)currentAltText {
  NSString *alt = [[self currentMediaItem][@"alt"] isKindOfClass:NSString.class] ? [self currentMediaItem][@"alt"] : @"";
  return [alt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)updateAltTextButton {
  NSDictionary *item = [self currentIndex] < self.mediaItems.count ? self.mediaItems[[self currentIndex]] : @{};
  NSString *type = item[@"type"] ?: @"photo";
  // Reference photo description affordance. Video/GIF alt remains accessible
  // through Video options; it never floats over the playback transport.
  BOOL photoDescription = [type isEqualToString:@"photo"];
  self.altTextButton.hidden = !NFBMediaShowsAltBadge(photoDescription, [self currentAltText].length > 0, NO, NO, NO, [item[@"profilePhoto"] boolValue]);
  BOOL transport = [self currentPlayer] != nil;
  if (self.altControlsTopConstraint) {
    [NSLayoutConstraint deactivateConstraints:@[self.altPhotoBottomConstraint, self.altControlsTopConstraint]];
    (transport ? self.altControlsTopConstraint : self.altPhotoBottomConstraint).active = YES;
  }
  self.altTextButton.alpha = self.altTextButton.hidden || self.viewerChromeHidden ? 0.0 : 1.0;
  self.altTextButton.transform = CGAffineTransformIdentity;
}

- (void)altTextTapped {
  NSString *alt = [self currentAltText];
  if (alt.length == 0) return;
  NSArray<NSDictionary *> *items = @[
    @{@"id": @"body", @"title": alt, @"icon": @"nfb_alt_compose"},
    @{@"id": @"cancel", @"title": @"Close", @"icon": @"nfb_close"}
  ];
  NFBVideoOptionsSheetViewController *sheet = [[NFBVideoOptionsSheetViewController alloc] initWithTitle:@"Image Description" items:items selection:nil];
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)presentMediaOptionsSheet {
  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  if ([self currentAltText].length > 0) [items addObject:@{@"id": @"alt", @"title": @"View image description", @"icon": @"nfb_alt_compose"}];
  [items addObject:@{@"id": @"profile", @"title": @"Go to profile", @"icon": @"nfb_profile"}];
  [items addObject:@{@"id": @"share", @"title": @"Share Tweet", @"icon": @"nfb_share"}];
  [items addObject:@{@"id": @"post-options", @"title": @"Tweet options", @"icon": @"nfb_more"}];
  [items addObject:@{@"id": @"cancel", @"title": @"Cancel", @"icon": @"nfb_close"}];
  __weak typeof(self) weakSelf = self;
  NFBVideoOptionsSheetViewController *sheet = [[NFBVideoOptionsSheetViewController alloc] initWithTitle:@"Photo options" items:items selection:^(NSString *identifier) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if ([identifier isEqualToString:@"alt"]) [strongSelf altTextTapped];
    else if ([identifier isEqualToString:@"profile"]) [strongSelf authorTapped];
    else if ([identifier isEqualToString:@"share"]) [strongSelf shareTapped];
    else if ([identifier isEqualToString:@"post-options"]) [[strongSelf postActionCoordinator] presentMoreMenuForPost:strongSelf.post ?: @{} sourceView:strongSelf.overlayMoreButton];
  }];
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)applyUpdatedAuthorProfile:(NSDictionary *)updatedProfile {
  if (![updatedProfile isKindOfClass:NSDictionary.class] || updatedProfile.count == 0) return;
  NSMutableDictionary *updatedPost = [self.post mutableCopy] ?: [NSMutableDictionary dictionary];
  updatedPost[@"author"] = updatedProfile;
  self.post = updatedPost;
  self.overlayNameLabel.text = [NFBAtprotoClient displayNameForProfile:updatedProfile];
  self.overlayHandleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:updatedProfile]];
  [NFBPostActionCoordinator configureFollowButton:self.overlayFollowButton profile:updatedProfile overDarkBackground:YES];
}

- (void)applyUpdatedPost:(NSDictionary *)updatedPost originalPost:(NSDictionary *)originalPost {
  if (![updatedPost isKindOfClass:NSDictionary.class] || updatedPost.count == 0) return;
  self.post = updatedPost;
  [self updateActionState];
  NSDictionary *author = [self.post[@"author"] isKindOfClass:NSDictionary.class] ? self.post[@"author"] : @{};
  [NFBPostActionCoordinator configureFollowButton:self.overlayFollowButton profile:author overDarkBackground:YES];
  if ([self.delegate respondsToSelector:@selector(mediaViewerViewController:didUpdatePost:originalPost:)]) {
    [self.delegate mediaViewerViewController:self didUpdatePost:updatedPost originalPost:originalPost ?: @{}];
  }
}

- (void)updateActionState {
  NSDictionary *viewer = [self.post[@"viewer"] isKindOfClass:NSDictionary.class] ? self.post[@"viewer"] : @{};
  BOOL liked = [viewer[@"like"] isKindOfClass:NSString.class] && [viewer[@"like"] length] > 0;
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  UIColor *inactive = NFBIPAOnMediaSecondaryTextColor();
  UIColor *repostColor = [UIColor colorWithRed:0.0 green:0.729 blue:0.486 alpha:1.0];
  UIColor *likeColor = [UIColor colorWithRed:0.976 green:0.094 blue:0.502 alpha:1.0];
  self.replyIconView.tintColor = inactive;
  self.shareIconView.tintColor = inactive;
  self.repostIconView.tintColor = reposted ? repostColor : inactive;
  self.likeIconView.image = NFBTemplateIcon(liked ? @"nfb_like_filled" : @"nfb_like");
  self.likeIconView.tintColor = liked ? likeColor : inactive;
  self.bookmarkIconView.image = NFBTemplateIcon(bookmarked ? @"nfb_bookmark_filled" : @"nfb_bookmark");
  self.bookmarkIconView.tintColor = bookmarked ? NFBColorAccent() : inactive;
  self.replyCountLabel.text = [self countTextForValue:self.post[@"replyCount"]];
  self.repostCountLabel.text = [self countTextForValue:self.post[@"repostCount"]];
  self.likeCountLabel.text = [self countTextForValue:self.post[@"likeCount"]];
}

- (NSString *)countTextForValue:(id)value {
  NSInteger count = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
  if (count <= 0) return @"";
  return NFBShortCountString(count);
}

@end
