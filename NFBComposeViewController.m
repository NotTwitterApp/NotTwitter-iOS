#import "NFBInteractiveSheet.h"
#import "NFBComposeViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <PhotosUI/PhotosUI.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBLocalPostStore.h"
#import "NFBMediaPreviewView.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBQuotedPostView.h"
#import "NFBTheme.h"
#import "NFBUndoTweetView.h"
#import "NFBGIFService.h"
#import "NFBGIFRowGeometry.h"
#import "NFBMediaAttachmentPolicy.h"
#import "NFBPostLink.h"
#import "NFBComposerMediaLayout.h"
#import "NFBComposerTextLayout.h"
#import "NFBMediaViewerViewController.h"
#import "NFBMediaLibraryViewController.h"
#import "NFBMediaAudioSession.h"

static NSString * const NFBComposeReplyGateEveryone = @"everyone";
static NSString * const NFBComposeReplyGateFollowing = @"following";
static NSString * const NFBComposeReplyGateMentioned = @"mentioned";
static NSString * const NFBComposeReplyGateNobody = @"nobody";

@class NFBCropViewController;
@class NFBVideoTrimViewController;
@class NFBGIFPickerViewController;
@class NFBReplyGatePickerViewController;
@class NFBComposeAccountPickerViewController;
@class NFBEmojiInputView;
@class NFBScheduleTweetViewController;
@class NFBDraftsViewController;
@protocol NFBVideoTrimViewControllerDelegate;
@protocol NFBGIFPickerViewControllerDelegate;

static NSArray<NSDictionary *> *NFBComposeReplyGateOptions(void) {
  return @[
    @{
      @"gate": NFBComposeReplyGateEveryone,
      @"title": @"Everyone",
      @"buttonTitle": @"Everyone can reply",
      @"subtitle": @"Anyone can reply"
    },
    @{
      @"gate": NFBComposeReplyGateFollowing,
      @"title": @"People you follow",
      @"buttonTitle": @"People you follow can reply",
      @"subtitle": @"People you follow or mention can reply"
    },
    @{
      @"gate": NFBComposeReplyGateMentioned,
      @"title": @"Only people you mention",
      @"buttonTitle": @"Only people you mention can reply",
      @"subtitle": @"Only people you mention can reply"
    },
    @{
      @"gate": NFBComposeReplyGateNobody,
      @"title": @"Only you",
      @"buttonTitle": @"Only you can reply",
      @"subtitle": @"Only you can reply"
    }
  ];
}

static NSDictionary *NFBComposeReplyGateOption(NSString *gate) {
  NSString *candidate = gate.length > 0 ? gate : NFBComposeReplyGateEveryone;
  for (NSDictionary *option in NFBComposeReplyGateOptions()) {
    if ([option[@"gate"] isEqualToString:candidate]) return option;
  }
  return NFBComposeReplyGateOptions().firstObject;
}

static UIImage *NFBComposeAnimatedImageWithData(NSData *data) {
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
    NSTimeInterval frameDuration = delay.doubleValue > 0.011 ? delay.doubleValue : 0.08;
    duration += frameDuration;
    [frames addObject:[UIImage imageWithCGImage:imageRef scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]];
    CGImageRelease(imageRef);
  }
  CFRelease(source);
  if (frames.count == 0) return [UIImage imageWithData:data];
  return [UIImage animatedImageWithImages:frames duration:MAX(duration, 0.1)];
}


// Bound decoded picker previews independently of the original upload asset.
static UIImage *NFBGIFPreviewImageWithData(NSData *data) {
  CGImageSourceRef source = data.length ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
  if (!source) return nil;
  size_t count = CGImageSourceGetCount(source);
  size_t stride = MAX((size_t)1, (count + 39) / 40);
  NSMutableArray<UIImage *> *frames = [NSMutableArray array];
  NSTimeInterval duration = 0;
  NSDictionary *options = @{
    (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
    (NSString *)kCGImageSourceThumbnailMaxPixelSize: @192,
    (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES
  };
  for (size_t index = 0; index < count; index++) {
    NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSNumber *delay = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(NSString *)kCGImagePropertyGIFDelayTime];
    duration += delay.doubleValue > 0.011 ? delay.doubleValue : 0.08;
    if (index % stride) continue;
    CGImageRef frame = CGImageSourceCreateThumbnailAtIndex(source, index, (__bridge CFDictionaryRef)options);
    if (frame) {
      [frames addObject:[UIImage imageWithCGImage:frame]];
      CGImageRelease(frame);
    }
  }
  CFRelease(source);
  return frames.count > 1 ? [UIImage animatedImageWithImages:frames duration:MAX(duration, 0.1)] : frames.firstObject;
}

static NSUInteger NFBGIFPreviewCost(UIImage *image) {
  UIImage *frame = image.images.firstObject ?: image;
  return CGImageGetBytesPerRow(frame.CGImage) * CGImageGetHeight(frame.CGImage) * MAX((NSUInteger)1, image.images.count);
}


static CIContext *NFBEditorSharedCIContext(void) {
  static CIContext *context = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
  });
  return context;
}

static UIImage *NFBEditorImageByApplyingCIFilter(UIImage *image, NSString *filterName, NSDictionary<NSString *, id> *parameters) {
  if (!image || filterName.length == 0) return image;
  CIImage *input = [[CIImage alloc] initWithImage:image];
  if (!input) return image;
  CIFilter *filter = [CIFilter filterWithName:filterName];
  if (!filter) return image;
  [filter setValue:input forKey:kCIInputImageKey];
  [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
    (void)stop;
    [filter setValue:value forKey:key];
  }];
  CIImage *output = filter.outputImage;
  if (!output) return image;
  CGImageRef ref = [NFBEditorSharedCIContext() createCGImage:output fromRect:input.extent];
  if (!ref) return image;
  UIImage *result = [UIImage imageWithCGImage:ref scale:image.scale orientation:image.imageOrientation];
  CGImageRelease(ref);
  return result ?: image;
}

static UIImage *NFBEditorBlendImage(UIImage *baseImage, UIImage *overlayImage, CGFloat alpha) {
  if (!baseImage || !overlayImage || alpha <= 0.001) return baseImage;
  alpha = MAX(0.0, MIN(1.0, alpha));
  UIGraphicsBeginImageContextWithOptions(baseImage.size, YES, baseImage.scale);
  [baseImage drawInRect:CGRectMake(0.0, 0.0, baseImage.size.width, baseImage.size.height)];
  [overlayImage drawInRect:CGRectMake(0.0, 0.0, baseImage.size.width, baseImage.size.height) blendMode:kCGBlendModeNormal alpha:alpha];
  UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return result ?: baseImage;
}

static UIImage *NFBEditorImageByTinting(UIImage *image, UIColor *color, CGFloat alpha) {
  if (!image || !color || alpha <= 0.001) return image;
  UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
  [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
  [color setFill];
  UIRectFillUsingBlendMode(CGRectMake(0.0, 0.0, image.size.width, image.size.height), kCGBlendModeSoftLight);
  UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return NFBEditorBlendImage(image, tinted, alpha);
}

static UIImage *NFBEditorFilteredImage(UIImage *image, NSString *filterID, CGFloat intensity) {
  if (!image || filterID.length == 0 || [filterID isEqualToString:@"normal"]) return image;
  intensity = MAX(0.0, MIN(1.0, intensity));
  if ([filterID isEqualToString:@"vivid"]) {
    return NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
      kCIInputSaturationKey: @(1.0 + 0.62 * intensity),
      kCIInputContrastKey: @(1.0 + 0.20 * intensity),
      kCIInputBrightnessKey: @(0.015 * intensity)
    });
  }
  if ([filterID isEqualToString:@"sitges"] || [filterID isEqualToString:@"halki"] || [filterID isEqualToString:@"loreto"]) {
    CGFloat saturation = [filterID isEqualToString:@"loreto"] ? 0.34 : ([filterID isEqualToString:@"halki"] ? 0.54 : 0.46);
    CGFloat contrast = [filterID isEqualToString:@"halki"] ? 0.18 : 0.12;
    CGFloat brightness = [filterID isEqualToString:@"loreto"] ? 0.026 : 0.012;
    return NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
      kCIInputSaturationKey: @(1.0 + saturation * intensity),
      kCIInputContrastKey: @(1.0 + contrast * intensity),
      kCIInputBrightnessKey: @(brightness * intensity)
    });
  }
  if ([filterID isEqualToString:@"warm"]) {
    UIImage *adjusted = NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
      kCIInputSaturationKey: @(1.0 + 0.28 * intensity),
      kCIInputContrastKey: @(1.0 + 0.08 * intensity)
    });
    return NFBEditorImageByTinting(adjusted, [UIColor colorWithRed:1.0 green:0.58 blue:0.20 alpha:1.0], 0.22 * intensity);
  }
  if ([filterID isEqualToString:@"gazette"] || [filterID isEqualToString:@"kilda"]) {
    UIImage *adjusted = NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
      kCIInputSaturationKey: @(1.0 + ([filterID isEqualToString:@"kilda"] ? 0.24 : 0.14) * intensity),
      kCIInputContrastKey: @(1.0 + 0.08 * intensity),
      kCIInputBrightnessKey: @(([filterID isEqualToString:@"kilda"] ? 0.012 : -0.006) * intensity)
    });
    return NFBEditorImageByTinting(adjusted, [UIColor colorWithRed:1.0 green:0.54 blue:0.16 alpha:1.0], ([filterID isEqualToString:@"kilda"] ? 0.16 : 0.28) * intensity);
  }
  if ([filterID isEqualToString:@"cool"]) {
    UIImage *adjusted = NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
      kCIInputSaturationKey: @(1.0 + 0.18 * intensity),
      kCIInputContrastKey: @(1.0 + 0.06 * intensity)
    });
    return NFBEditorImageByTinting(adjusted, [UIColor colorWithRed:0.12 green:0.42 blue:1.0 alpha:1.0], 0.18 * intensity);
  }
  if ([filterID isEqualToString:@"vail"] || [filterID isEqualToString:@"lapis"]) {
    UIImage *adjusted = NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
      kCIInputSaturationKey: @(1.0 + ([filterID isEqualToString:@"lapis"] ? 0.22 : 0.08) * intensity),
      kCIInputContrastKey: @(1.0 + 0.07 * intensity),
      kCIInputBrightnessKey: @(([filterID isEqualToString:@"lapis"] ? 0.018 : -0.006) * intensity)
    });
    return NFBEditorImageByTinting(adjusted, [UIColor colorWithRed:0.12 green:0.40 blue:1.0 alpha:1.0], ([filterID isEqualToString:@"lapis"] ? 0.22 : 0.16) * intensity);
  }
  if ([filterID isEqualToString:@"steel"]) {
    UIImage *filtered = NFBEditorImageByApplyingCIFilter(image, @"CIPhotoEffectTonal", @{});
    UIImage *tinted = NFBEditorImageByTinting(filtered, [UIColor colorWithRed:0.42 green:0.56 blue:0.72 alpha:1.0], 0.16);
    return NFBEditorBlendImage(image, tinted, intensity);
  }
  if ([filterID isEqualToString:@"mono"] || [filterID isEqualToString:@"noir"]) {
    NSString *ciFilter = [filterID isEqualToString:@"noir"] ? @"CIPhotoEffectNoir" : @"CIPhotoEffectMono";
    UIImage *filtered = NFBEditorImageByApplyingCIFilter(image, ciFilter, @{});
    return NFBEditorBlendImage(image, filtered, intensity);
  }
  return image;
}

static UIImage *NFBEditorEnhancedImage(UIImage *image) {
  if (!image) return nil;
  return NFBEditorImageByApplyingCIFilter(image, @"CIColorControls", @{
    kCIInputSaturationKey: @1.18,
    kCIInputContrastKey: @1.14,
    kCIInputBrightnessKey: @0.018
  });
}

static UIImage *NFBEditorThumbnailImage(UIImage *image, CGSize size) {
  if (!image) return nil;
  UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
  UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, size.width, size.height) cornerRadius:3.0];
  [path addClip];
  CGFloat scale = MAX(size.width / MAX(image.size.width, 1.0), size.height / MAX(image.size.height, 1.0));
  CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
  CGRect drawRect = CGRectMake((size.width - drawSize.width) * 0.5, (size.height - drawSize.height) * 0.5, drawSize.width, drawSize.height);
  [image drawInRect:drawRect];
  UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return result;
}

static UIImage *NFBEditorImageByScalingToMaxDimension(UIImage *image, CGFloat maxDimension) {
  if (!image || maxDimension <= 0.0) return image;
  CGFloat largest = MAX(image.size.width, image.size.height);
  if (largest <= maxDimension) return image;
  CGFloat scale = maxDimension / MAX(largest, 1.0);
  CGSize target = CGSizeMake(floor(image.size.width * scale), floor(image.size.height * scale));
  target.width = MAX(1.0, target.width);
  target.height = MAX(1.0, target.height);
  UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
  [image drawInRect:CGRectMake(0.0, 0.0, target.width, target.height)];
  UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return result ?: image;
}

@protocol NFBVideoTrimViewControllerDelegate <NSObject>
- (void)videoTrimViewControllerDidCancel:(NFBVideoTrimViewController *)controller;
- (void)videoTrimViewController:(NFBVideoTrimViewController *)controller didFinishWithURL:(NSURL *)url thumbnail:(UIImage *)thumbnail duration:(NSTimeInterval)duration dimensions:(CGSize)dimensions;
@end

@protocol NFBGIFPickerViewControllerDelegate <NSObject>
- (void)gifPickerDidCancel:(NFBGIFPickerViewController *)controller;
- (void)gifPickerDidRequestFilePicker:(NFBGIFPickerViewController *)controller;
- (void)gifPicker:(NFBGIFPickerViewController *)controller didSelectGIFItem:(NSDictionary *)item;
@end

typedef void (^NFBScheduleTweetCompletion)(NSDate * _Nullable scheduledDate);
typedef void (^NFBDraftsSelectionHandler)(NSDictionary * _Nullable localPost);
typedef void (^NFBMediaSourcePickerCompletion)(BOOL video);

@interface NFBCropGridView : UIView
@end

@implementation NFBCropGridView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

- (void)drawRect:(CGRect)rect {
  (void)rect;
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (!context) return;
  CGRect bounds = UIEdgeInsetsInsetRect(self.bounds, UIEdgeInsetsMake(1.0, 1.0, 1.0, 1.0));
  CGFloat scale = UIScreen.mainScreen.scale ?: 1.0;
  CGFloat hairline = 1.0 / scale;

  CGContextSaveGState(context);
  CGContextSetStrokeColorWithColor(context, [UIColor.whiteColor colorWithAlphaComponent:0.62].CGColor);
  CGContextSetLineWidth(context, hairline);
  for (NSInteger index = 1; index <= 2; index++) {
    CGFloat x = CGRectGetMinX(bounds) + floor(CGRectGetWidth(bounds) * index / 3.0);
    CGContextMoveToPoint(context, x, CGRectGetMinY(bounds));
    CGContextAddLineToPoint(context, x, CGRectGetMaxY(bounds));
    CGFloat y = CGRectGetMinY(bounds) + floor(CGRectGetHeight(bounds) * index / 3.0);
    CGContextMoveToPoint(context, CGRectGetMinX(bounds), y);
    CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), y);
  }
  CGContextStrokePath(context);

  CGContextSetStrokeColorWithColor(context, UIColor.whiteColor.CGColor);
  CGContextSetLineWidth(context, 2.0);
  CGContextStrokeRect(context, bounds);

  CGFloat cornerLength = MIN(32.0, MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * 0.18);
  CGContextSetLineWidth(context, 3.0);
  CGContextMoveToPoint(context, CGRectGetMinX(bounds), CGRectGetMinY(bounds) + cornerLength);
  CGContextAddLineToPoint(context, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
  CGContextAddLineToPoint(context, CGRectGetMinX(bounds) + cornerLength, CGRectGetMinY(bounds));
  CGContextMoveToPoint(context, CGRectGetMaxX(bounds) - cornerLength, CGRectGetMinY(bounds));
  CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMinY(bounds));
  CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMinY(bounds) + cornerLength);
  CGContextMoveToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - cornerLength);
  CGContextAddLineToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(bounds));
  CGContextAddLineToPoint(context, CGRectGetMinX(bounds) + cornerLength, CGRectGetMaxY(bounds));
  CGContextMoveToPoint(context, CGRectGetMaxX(bounds) - cornerLength, CGRectGetMaxY(bounds));
  CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds));
  CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds) - cornerLength);
  CGContextStrokePath(context);
  CGContextRestoreGState(context);
}

@end

@interface NFBCropBarButton : UIButton
@property (nonatomic, assign) CGFloat titleLineHeight;
@end

@implementation NFBCropBarButton

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = NFBFont(10.0, NFBFontWeightBold);
    self.titleLabel.numberOfLines = 1;
    self.titleLineHeight = ceil(self.titleLabel.font.lineHeight);
  }
  return self;
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect {
  UIImage *image = [self imageForState:UIControlStateNormal] ?: [self imageForState:UIControlStateSelected];
  CGSize imageSize = image.size;
  CGFloat availableHeight = ceil(CGRectGetHeight(contentRect) - self.titleLineHeight);
  CGFloat layoutHeight = imageSize.height > availableHeight ? CGRectGetHeight(contentRect) : availableHeight;
  CGFloat imageHeight = MIN(layoutHeight, imageSize.height);
  CGFloat imageWidth = MIN(CGRectGetWidth(contentRect), imageSize.width);
  CGFloat x = CGRectGetMinX(contentRect) + floor((CGRectGetWidth(contentRect) - imageWidth) * 0.5);
  CGFloat y = CGRectGetMinY(contentRect) + floor((layoutHeight - imageHeight) * 0.5);
  if ([self titleForState:UIControlStateNormal].length > 0 && imageSize.height <= availableHeight) {
    y += floor(self.titleLineHeight * 0.5);
  }
  return CGRectIntegral(CGRectMake(x, y, imageWidth, imageHeight));
}

- (CGRect)titleRectForContentRect:(CGRect)contentRect {
  UIImage *image = [self imageForState:UIControlStateNormal] ?: [self imageForState:UIControlStateSelected];
  CGFloat availableHeight = ceil(CGRectGetHeight(contentRect) - self.titleLineHeight);
  if (image.size.height > availableHeight) return CGRectZero;
  return CGRectIntegral(CGRectMake(CGRectGetMinX(contentRect),
                                   CGRectGetMaxY(contentRect) - self.titleLineHeight,
                                   CGRectGetWidth(contentRect),
                                   self.titleLineHeight));
}

@end

@interface NFBStickerCanvasView : UIView
@end

@implementation NFBStickerCanvasView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  for (UIView *subview in self.subviews.reverseObjectEnumerator) {
    if (subview.hidden || subview.alpha < 0.01 || !subview.userInteractionEnabled) continue;
    CGPoint converted = [subview convertPoint:point fromView:self];
    if ([subview pointInside:converted withEvent:event]) return YES;
  }
  return NO;
}

@end

@interface NFBPlacedStickerView : UIImageView
@property (nonatomic, strong) UIImage *stickerImage;
@end

@implementation NFBPlacedStickerView
@end

@interface NFBCropViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate, UITextViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIScrollView *imageScrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) NFBCropGridView *cropFrameView;
@property (nonatomic, strong) UIView *editorToolbarView;
@property (nonatomic, strong) UIView *shadowTopView;
@property (nonatomic, strong) UIView *shadowBottomView;
@property (nonatomic, strong) UIView *shadowLeftView;
@property (nonatomic, strong) UIView *shadowRightView;
@property (nonatomic, strong) NSArray<UIButton *> *aspectButtons;
@property (nonatomic, strong) UIButton *rotateButton;
@property (nonatomic, strong) NSArray<UIButton *> *editorToolButtons;
@property (nonatomic, strong) UIView *filtersPanelView;
@property (nonatomic, strong) UIScrollView *filtersScrollView;
@property (nonatomic, strong) UISlider *filterIntensitySlider;
@property (nonatomic, strong) UIImage *filterBaseImage;
@property (nonatomic, strong) UIImage *filterPreviewBaseImage;
@property (nonatomic, strong) UIImage *preEnhanceImage;
@property (nonatomic, copy) NSString *selectedFilterID;
@property (nonatomic, assign) BOOL filtersPanelVisible;
@property (nonatomic, assign) BOOL filterNeedsFullResolutionRender;
@property (nonatomic, assign) NSInteger filterRenderGeneration;
@property (nonatomic, assign) BOOL cropToolActive;
@property (nonatomic, strong) UIView *stickerPanelView;
@property (nonatomic, strong) UIScrollView *stickerCategoryScrollView;
@property (nonatomic, strong) UIScrollView *stickerScrollView;
@property (nonatomic, strong) NFBStickerCanvasView *stickerCanvasView;
@property (nonatomic, strong) NSMutableArray<NFBPlacedStickerView *> *stickerViews;
@property (nonatomic, copy) NSString *selectedStickerCategoryID;
@property (nonatomic, assign) BOOL stickerPanelVisible;
@property (nonatomic, weak) NFBPlacedStickerView *activeStickerView;
@property (nonatomic, assign) CGAffineTransform activeStickerStartTransform;
@property (nonatomic, assign) CGPoint activeStickerStartCenter;
@property (nonatomic, assign) BOOL enhanceEnabled;
@property (nonatomic, assign) NSInteger selectedAspectIndex;
@property (nonatomic, assign) CGRect cropRect;
@property (nonatomic, assign) BOOL hasCropRect;
@property (nonatomic, assign) CGRect gestureStartCropRect;
@property (nonatomic, assign) BOOL configuredInitialImageLayout;
@property (nonatomic, assign) CGSize configuredBoundsSize;
@property (nonatomic, copy) NSString *pendingAltText;
@end

@implementation NFBCropViewController

- (instancetype)initWithImage:(UIImage *)image {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _image = [self.class normalizedImage:image ?: [UIImage new]];
    _stickerViews = [NSMutableArray array];
    _selectedStickerCategoryID = @"featured";
    _cropToolActive = YES;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
  self.title = @"Crop";
  UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 180.0, 44.0)];
  titleLabel.text = @"Crop";
  titleLabel.textColor = NFBIPAOnMediaPrimaryTextColor();
  titleLabel.font = NFBFont(22.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;
  self.navigationItem.titleView = titleLabel;
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(applyTapped)];
  self.navigationItem.leftBarButtonItem.tintColor = UIColor.whiteColor;
  self.navigationItem.rightBarButtonItem.tintColor = UIColor.whiteColor;
  self.selectedAspectIndex = 0;

  self.imageScrollView = [[UIScrollView alloc] init];
  self.imageScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.imageScrollView.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
  self.imageScrollView.delegate = self;
  self.imageScrollView.bounces = YES;
  self.imageScrollView.bouncesZoom = YES;
  self.imageScrollView.showsHorizontalScrollIndicator = NO;
  self.imageScrollView.showsVerticalScrollIndicator = NO;
  self.imageScrollView.decelerationRate = UIScrollViewDecelerationRateFast;
  [self.view addSubview:self.imageScrollView];

  self.imageView = [[UIImageView alloc] initWithImage:self.image];
  self.imageView.frame = CGRectZero;
  self.imageView.contentMode = UIViewContentModeScaleAspectFit;
  self.imageView.userInteractionEnabled = YES;
  [self.imageScrollView addSubview:self.imageView];

  UIColor *shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.54];
  self.shadowTopView = [[UIView alloc] init];
  self.shadowBottomView = [[UIView alloc] init];
  self.shadowLeftView = [[UIView alloc] init];
  self.shadowRightView = [[UIView alloc] init];
  for (UIView *shadowView in @[self.shadowTopView, self.shadowBottomView, self.shadowLeftView, self.shadowRightView]) {
    shadowView.backgroundColor = shadowColor;
    shadowView.userInteractionEnabled = NO;
    [self.view addSubview:shadowView];
  }

  self.cropFrameView = [[NFBCropGridView alloc] init];
  self.cropFrameView.translatesAutoresizingMaskIntoConstraints = YES;
  self.cropFrameView.backgroundColor = UIColor.clearColor;
  self.cropFrameView.userInteractionEnabled = NO;
  [self.view addSubview:self.cropFrameView];
  UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageDoubleTap:)];
  doubleTap.numberOfTapsRequired = 2;
  [self.imageScrollView addGestureRecognizer:doubleTap];

  self.stickerCanvasView = [[NFBStickerCanvasView alloc] initWithFrame:CGRectZero];
  self.stickerCanvasView.backgroundColor = UIColor.clearColor;
  self.stickerCanvasView.userInteractionEnabled = YES;
  [self.view addSubview:self.stickerCanvasView];

  UIView *editorToolbar = [[UIView alloc] init];
  editorToolbar.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaBarAppearance(editorToolbar);
  [self.view addSubview:editorToolbar];
  self.editorToolbarView = editorToolbar;

  UIView *editorTopBorder = [[UIView alloc] init];
  editorTopBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaSeparatorAppearance(editorTopBorder);
  [editorToolbar addSubview:editorTopBorder];

  UIStackView *editorStack = [[UIStackView alloc] init];
  editorStack.translatesAutoresizingMaskIntoConstraints = NO;
  editorStack.axis = UILayoutConstraintAxisHorizontal;
  editorStack.distribution = UIStackViewDistributionFillEqually;
  editorStack.alignment = UIStackViewAlignmentFill;
  [editorToolbar addSubview:editorStack];

  NSArray<NSDictionary *> *tools = @[
    @{@"label": @"Enhance", @"icon": @"nfb_photo_enhance", @"action": NSStringFromSelector(@selector(enhanceTapped:))},
    @{@"label": @"Filters", @"icon": @"nfb_filter", @"action": NSStringFromSelector(@selector(filtersTapped:))},
    @{@"label": @"Crop", @"icon": @"nfb_photo_crop", @"action": NSStringFromSelector(@selector(cropToolTapped:))},
    @{@"label": @"Stickers", @"icon": @"nfb_sticker", @"action": NSStringFromSelector(@selector(stickerTapped:))},
    @{@"label": @"Alt text", @"icon": @"nfb_alt_compose", @"action": NSStringFromSelector(@selector(altTextTapped:))}
  ];
  NSMutableArray<UIButton *> *editorButtons = [NSMutableArray array];
  for (NSDictionary *tool in tools) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = tool[@"label"];
    UIImage *icon = NFBTemplateIcon(tool[@"icon"]);
    [button setImage:icon forState:UIControlStateNormal];
    [button setImage:icon forState:UIControlStateSelected];
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.adjustsImageWhenHighlighted = NO;
    [button addTarget:self action:NSSelectorFromString(tool[@"action"]) forControlEvents:UIControlEventTouchUpInside];
    [editorStack addArrangedSubview:button];
    [editorButtons addObject:button];
  }
  self.editorToolButtons = editorButtons;

  self.filtersPanelView = [[UIView alloc] init];
  self.filtersPanelView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaBarAppearance(self.filtersPanelView);
  self.filtersPanelView.hidden = YES;
  self.filtersPanelView.alpha = 0.0;
  [self.view addSubview:self.filtersPanelView];

  UIView *filtersTopBorder = [[UIView alloc] init];
  filtersTopBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaSeparatorAppearance(filtersTopBorder);
  [self.filtersPanelView addSubview:filtersTopBorder];

  self.filtersScrollView = [[UIScrollView alloc] init];
  self.filtersScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.filtersScrollView.showsHorizontalScrollIndicator = NO;
  self.filtersScrollView.alwaysBounceHorizontal = YES;
  [self.filtersPanelView addSubview:self.filtersScrollView];

  self.filterIntensitySlider = [[UISlider alloc] init];
  self.filterIntensitySlider.translatesAutoresizingMaskIntoConstraints = NO;
  self.filterIntensitySlider.minimumValue = 0.0;
  self.filterIntensitySlider.maximumValue = 1.0;
  self.filterIntensitySlider.value = 1.0;
  self.filterIntensitySlider.minimumTrackTintColor = NFBColorAccent();
  self.filterIntensitySlider.maximumTrackTintColor = [NFBIPAOnMediaSecondaryTextColor() colorWithAlphaComponent:0.32];
  [self.filterIntensitySlider addTarget:self action:@selector(filterIntensityChanged:) forControlEvents:UIControlEventValueChanged];
  [self.filterIntensitySlider addTarget:self action:@selector(filterIntensityEditingDidEnd:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
  [self.filtersPanelView addSubview:self.filterIntensitySlider];
  [self buildFilterPreviewButtons];

  self.stickerPanelView = [[UIView alloc] init];
  self.stickerPanelView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaBarAppearance(self.stickerPanelView);
  self.stickerPanelView.hidden = YES;
  self.stickerPanelView.alpha = 0.0;
  [self.view addSubview:self.stickerPanelView];

  UIView *stickerTopBorder = [[UIView alloc] init];
  stickerTopBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaSeparatorAppearance(stickerTopBorder);
  [self.stickerPanelView addSubview:stickerTopBorder];

  self.stickerCategoryScrollView = [[UIScrollView alloc] init];
  self.stickerCategoryScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.stickerCategoryScrollView.showsHorizontalScrollIndicator = NO;
  self.stickerCategoryScrollView.alwaysBounceHorizontal = YES;
  [self.stickerPanelView addSubview:self.stickerCategoryScrollView];

  self.stickerScrollView = [[UIScrollView alloc] init];
  self.stickerScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.stickerScrollView.showsVerticalScrollIndicator = NO;
  self.stickerScrollView.alwaysBounceVertical = YES;
  [self.stickerPanelView addSubview:self.stickerScrollView];
  [self buildStickerPanelButtons];

  UIView *toolbar = [[UIView alloc] init];
  toolbar.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaBarAppearance(toolbar);
  [self.view addSubview:toolbar];

  UIView *toolbarTopBorder = [[UIView alloc] init];
  toolbarTopBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaSeparatorAppearance(toolbarTopBorder);
  [toolbar addSubview:toolbarTopBorder];

  UIStackView *toolbarStack = [[UIStackView alloc] init];
  toolbarStack.translatesAutoresizingMaskIntoConstraints = NO;
  toolbarStack.axis = UILayoutConstraintAxisHorizontal;
  toolbarStack.distribution = UIStackViewDistributionFillEqually;
  toolbarStack.alignment = UIStackViewAlignmentFill;
  [toolbar addSubview:toolbarStack];

  NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
  NSArray<NSString *> *titles = @[@"Original", @"Wide", @"Square"];
  NSArray<NSString *> *icons = @[@"nfb_crop_original", @"nfb_crop_wide", @"nfb_crop_square"];
  for (NSUInteger index = 0; index < titles.count; index++) {
    NFBCropBarButton *button = [[NFBCropBarButton alloc] initWithFrame:CGRectZero];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = (NSInteger)index;
    [button setTitle:titles[index] forState:UIControlStateNormal];
    UIImage *icon = NFBTemplateIcon(icons[index]);
    [button setImage:icon forState:UIControlStateNormal];
    [button setImage:icon forState:UIControlStateSelected];
    button.adjustsImageWhenHighlighted = NO;
    [button addTarget:self action:@selector(aspectButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [toolbarStack addArrangedSubview:button];
    [buttons addObject:button];
  }
  NFBCropBarButton *rotate = [[NFBCropBarButton alloc] initWithFrame:CGRectZero];
  rotate.translatesAutoresizingMaskIntoConstraints = NO;
  rotate.accessibilityLabel = @"Rotate";
  UIImage *rotateIcon = NFBTemplateIcon(@"nfb_crop_rotate");
  [rotate setImage:rotateIcon forState:UIControlStateNormal];
  NFBIPAApplyOnMediaIconButtonAppearance(rotate, NO, 0.0);
  rotate.adjustsImageWhenHighlighted = NO;
  [rotate addTarget:self action:@selector(rotateTapped) forControlEvents:UIControlEventTouchUpInside];
  [toolbarStack addArrangedSubview:rotate];
  self.rotateButton = rotate;
  self.aspectButtons = buttons;
  [self updateAspectButtons];
  [self updateEditorToolButtons];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.imageScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.imageScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.imageScrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.imageScrollView.bottomAnchor constraintEqualToAnchor:editorToolbar.topAnchor],
    [self.filtersPanelView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.filtersPanelView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.filtersPanelView.bottomAnchor constraintEqualToAnchor:editorToolbar.topAnchor],
    [self.filtersPanelView.heightAnchor constraintEqualToConstant:138.0],
    [self.stickerPanelView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.stickerPanelView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.stickerPanelView.bottomAnchor constraintEqualToAnchor:editorToolbar.topAnchor],
    [self.stickerPanelView.heightAnchor constraintEqualToConstant:216.0],
    [filtersTopBorder.topAnchor constraintEqualToAnchor:self.filtersPanelView.topAnchor],
    [filtersTopBorder.leadingAnchor constraintEqualToAnchor:self.filtersPanelView.leadingAnchor],
    [filtersTopBorder.trailingAnchor constraintEqualToAnchor:self.filtersPanelView.trailingAnchor],
    [filtersTopBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.filtersScrollView.topAnchor constraintEqualToAnchor:self.filtersPanelView.topAnchor constant:8.0],
    [self.filtersScrollView.leadingAnchor constraintEqualToAnchor:self.filtersPanelView.leadingAnchor],
    [self.filtersScrollView.trailingAnchor constraintEqualToAnchor:self.filtersPanelView.trailingAnchor],
    [self.filtersScrollView.heightAnchor constraintEqualToConstant:84.0],
    [self.filterIntensitySlider.leadingAnchor constraintEqualToAnchor:self.filtersPanelView.leadingAnchor constant:24.0],
    [self.filterIntensitySlider.trailingAnchor constraintEqualToAnchor:self.filtersPanelView.trailingAnchor constant:-24.0],
    [self.filterIntensitySlider.topAnchor constraintEqualToAnchor:self.filtersScrollView.bottomAnchor constant:8.0],
    [stickerTopBorder.topAnchor constraintEqualToAnchor:self.stickerPanelView.topAnchor],
    [stickerTopBorder.leadingAnchor constraintEqualToAnchor:self.stickerPanelView.leadingAnchor],
    [stickerTopBorder.trailingAnchor constraintEqualToAnchor:self.stickerPanelView.trailingAnchor],
    [stickerTopBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.stickerCategoryScrollView.topAnchor constraintEqualToAnchor:self.stickerPanelView.topAnchor constant:6.0],
    [self.stickerCategoryScrollView.leadingAnchor constraintEqualToAnchor:self.stickerPanelView.leadingAnchor],
    [self.stickerCategoryScrollView.trailingAnchor constraintEqualToAnchor:self.stickerPanelView.trailingAnchor],
    [self.stickerCategoryScrollView.heightAnchor constraintEqualToConstant:44.0],
    [self.stickerScrollView.topAnchor constraintEqualToAnchor:self.stickerCategoryScrollView.bottomAnchor],
    [self.stickerScrollView.leadingAnchor constraintEqualToAnchor:self.stickerPanelView.leadingAnchor],
    [self.stickerScrollView.trailingAnchor constraintEqualToAnchor:self.stickerPanelView.trailingAnchor],
    [self.stickerScrollView.bottomAnchor constraintEqualToAnchor:self.stickerPanelView.bottomAnchor],
    [editorToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [editorToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [editorToolbar.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor],
    [editorToolbar.heightAnchor constraintEqualToConstant:50.0],
    [editorTopBorder.topAnchor constraintEqualToAnchor:editorToolbar.topAnchor],
    [editorTopBorder.leadingAnchor constraintEqualToAnchor:editorToolbar.leadingAnchor],
    [editorTopBorder.trailingAnchor constraintEqualToAnchor:editorToolbar.trailingAnchor],
    [editorTopBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [editorStack.topAnchor constraintEqualToAnchor:editorToolbar.topAnchor],
    [editorStack.leadingAnchor constraintEqualToAnchor:editorToolbar.leadingAnchor constant:24.0],
    [editorStack.trailingAnchor constraintEqualToAnchor:editorToolbar.trailingAnchor constant:-24.0],
    [editorStack.bottomAnchor constraintEqualToAnchor:editorToolbar.bottomAnchor],
    [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [toolbar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    [toolbar.heightAnchor constraintEqualToConstant:62.0],
    [toolbarTopBorder.topAnchor constraintEqualToAnchor:toolbar.topAnchor],
    [toolbarTopBorder.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor],
    [toolbarTopBorder.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor],
    [toolbarTopBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [toolbarStack.topAnchor constraintEqualToAnchor:toolbar.topAnchor constant:4.0],
    [toolbarStack.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:18.0],
    [toolbarStack.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-18.0],
    [toolbarStack.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:-7.0]
  ]];
}

- (NSArray<NSDictionary *> *)filterConfigurations {
  return @[
    @{@"id": @"normal", @"title": @"No filter"},
    @{@"id": @"steel", @"title": @"Steel"},
    @{@"id": @"vail", @"title": @"Vail"},
    @{@"id": @"lapis", @"title": @"Lapis"},
    @{@"id": @"sitges", @"title": @"Sitges"},
    @{@"id": @"halki", @"title": @"Halki"},
    @{@"id": @"loreto", @"title": @"Loreto"},
    @{@"id": @"gazette", @"title": @"Gazette"},
    @{@"id": @"kilda", @"title": @"Kilda"}
  ];
}

- (NSArray<NSDictionary *> *)stickerCategories {
  return @[
    @{@"id": @"featured", @"title": @"Featured", @"icon": @"nfb_sticker_featured"},
    @{@"id": @"recent", @"title": @"Recent", @"icon": @"nfb_sticker_recent"},
    @{@"id": @"people", @"title": @"People", @"icon": @"nfb_sticker_people"},
    @{@"id": @"symbols", @"title": @"Symbols", @"icon": @"nfb_sticker_symbols"},
    @{@"id": @"activity", @"title": @"Activity", @"icon": @"nfb_sticker_activity"}
  ];
}

- (NSArray<NSDictionary *> *)stickerItemsForCategory:(NSString *)categoryID {
  NSArray<NSDictionary *> *featured = @[
    @{@"title": @"Heart eyes", @"image": @"twitter_sticker_heart_eyes"},
    @{@"title": @"Tears of joy", @"image": @"twitter_sticker_joy"},
    @{@"title": @"Rolling eyes", @"image": @"twitter_sticker_rolling_eyes"},
    @{@"title": @"Red heart", @"image": @"twitter_sticker_red_heart"},
    @{@"title": @"Pleading face", @"image": @"twitter_sticker_pleading"},
    @{@"title": @"Crying face", @"image": @"twitter_sticker_crying"},
    @{@"title": @"Broken heart", @"image": @"twitter_sticker_broken_heart"},
    @{@"title": @"Exploding head", @"image": @"twitter_sticker_exploding"},
    @{@"title": @"Thinking face", @"image": @"twitter_sticker_thinking"},
    @{@"title": @"Pouting face", @"image": @"twitter_sticker_pouting"},
    @{@"title": @"Raised fist", @"image": @"twitter_sticker_fist"},
    @{@"title": @"Victory hand", @"image": @"twitter_sticker_victory"},
    @{@"title": @"Hundred points", @"image": @"twitter_sticker_100"},
    @{@"title": @"Folded hands", @"image": @"twitter_sticker_pray"},
    @{@"title": @"Raising hands", @"image": @"twitter_sticker_raising_hands"},
    @{@"title": @"Wave", @"image": @"twitter_sticker_wave"}
  ];
  if ([categoryID isEqualToString:@"people"]) {
    return @[featured[0], featured[1], featured[2], featured[4], featured[5], featured[7], featured[8], featured[9]];
  }
  if ([categoryID isEqualToString:@"symbols"]) {
    return @[featured[3], featured[6], featured[12]];
  }
  if ([categoryID isEqualToString:@"activity"]) {
    return @[featured[10], featured[11], featured[13], featured[14], featured[15]];
  }
  if ([categoryID isEqualToString:@"recent"]) {
    return [[featured reverseObjectEnumerator] allObjects];
  }
  return featured;
}

- (void)buildFilterPreviewButtons {
  if (!self.filtersScrollView) return;
  [self.filtersScrollView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
  NSArray<NSDictionary *> *filters = [self filterConfigurations];
  UIImage *source = self.filterPreviewBaseImage ?: NFBEditorImageByScalingToMaxDimension(self.filterBaseImage ?: self.image, 480.0);
  CGSize thumbSize = CGSizeMake(58.0, 58.0);
  CGFloat itemWidth = 76.0;
  CGFloat x = 12.0;
  NSString *selectedID = self.selectedFilterID.length > 0 ? self.selectedFilterID : @"normal";
  for (NSUInteger index = 0; index < filters.count; index++) {
    NSDictionary *config = filters[index];
    NSString *filterID = config[@"id"];
    NSString *title = config[@"title"];
    UIView *item = [[UIView alloc] initWithFrame:CGRectMake(x, 0.0, itemWidth, 82.0)];
    item.backgroundColor = UIColor.clearColor;

    UIImage *filtered = NFBEditorFilteredImage(source, filterID, 1.0);
    UIImageView *thumb = [[UIImageView alloc] initWithImage:NFBEditorThumbnailImage(filtered, thumbSize)];
    thumb.frame = CGRectMake((itemWidth - thumbSize.width) * 0.5, 0.0, thumbSize.width, thumbSize.height);
    thumb.contentMode = UIViewContentModeScaleAspectFill;
    thumb.clipsToBounds = YES;
    thumb.layer.cornerRadius = 3.0;
    thumb.layer.borderWidth = [filterID isEqualToString:selectedID] ? 2.0 : (1.0 / UIScreen.mainScreen.scale);
    thumb.layer.borderColor = ([filterID isEqualToString:selectedID] ? NFBColorAccent() : NFBIPAOnMediaSeparatorColor()).CGColor;
    [item addSubview:thumb];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 62.0, itemWidth, 17.0)];
    label.text = title;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [filterID isEqualToString:selectedID] ? NFBColorAccent() : NFBIPAOnMediaSecondaryTextColor();
    label.font = NFBFont(10.0, NFBFontWeightBold);
    [item addSubview:label];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = item.bounds;
    button.tag = (NSInteger)index;
    [button addTarget:self action:@selector(filterButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [item addSubview:button];

    [self.filtersScrollView addSubview:item];
    x += itemWidth;
  }
  self.filtersScrollView.contentSize = CGSizeMake(MAX(CGRectGetWidth(self.view.bounds), x + 12.0), 82.0);
}

- (void)buildStickerPanelButtons {
  if (!self.stickerCategoryScrollView || !self.stickerScrollView) return;
  [self.stickerCategoryScrollView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
  [self.stickerScrollView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

  NSArray<NSDictionary *> *categories = [self stickerCategories];
  CGFloat categoryX = 12.0;
  for (NSUInteger index = 0; index < categories.count; index++) {
    NSDictionary *category = categories[index];
    NSString *categoryID = category[@"id"];
    BOOL selected = [categoryID isEqualToString:self.selectedStickerCategoryID ?: @"featured"];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(categoryX, 4.0, 38.0, 38.0);
    button.tag = (NSInteger)index;
    NFBIPAApplyOnMediaIconButtonAppearance(button, selected, 19.0);
    [button setImage:NFBTemplateIcon(category[@"icon"]) forState:UIControlStateNormal];
    [button addTarget:self action:@selector(stickerCategoryTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.stickerCategoryScrollView addSubview:button];
    categoryX += 50.0;
  }
  self.stickerCategoryScrollView.contentSize = CGSizeMake(MAX(CGRectGetWidth(self.view.bounds), categoryX + 12.0), 44.0);

  NSArray<NSDictionary *> *stickers = [self stickerItemsForCategory:self.selectedStickerCategoryID ?: @"featured"];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
  CGFloat itemSize = floor((width - 36.0) / 4.0);
  itemSize = MAX(68.0, MIN(86.0, itemSize));
  CGFloat gap = floor((width - itemSize * 4.0) / 5.0);
  gap = MAX(6.0, gap);
  for (NSUInteger index = 0; index < stickers.count; index++) {
    NSDictionary *sticker = stickers[index];
    NSString *imageName = sticker[@"image"];
    UIImage *image = NFBBundledImage(@"TwitterStickers", imageName, @"png");
    NSUInteger column = index % 4;
    NSUInteger row = index / 4;
    CGRect frame = CGRectMake(gap + column * (itemSize + gap), 10.0 + row * (itemSize + 12.0), itemSize, itemSize);
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.tag = (NSInteger)index;
    button.backgroundColor = UIColor.clearColor;
    button.accessibilityLabel = sticker[@"title"];
    [button setImage:image forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.adjustsImageWhenHighlighted = NO;
    [button addTarget:self action:@selector(stickerButtonSelected:) forControlEvents:UIControlEventTouchUpInside];
    [self.stickerScrollView addSubview:button];
  }
  NSUInteger rows = (stickers.count + 3) / 4;
  self.stickerScrollView.contentSize = CGSizeMake(width, MAX(CGRectGetHeight(self.stickerScrollView.bounds) + 1.0, 10.0 + rows * (itemSize + 12.0)));
}

- (void)updateEditorToolButtons {
  [self.editorToolButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
    (void)stop;
    BOOL selected = (index == 0 && self.enhanceEnabled) ||
                    (index == 1 && self.filtersPanelVisible) ||
                    (index == 2 && self.cropToolActive && !self.filtersPanelVisible && !self.stickerPanelVisible) ||
                    (index == 3 && self.stickerPanelVisible) ||
                    (index == 4 && self.pendingAltText.length > 0);
    NFBIPAApplyOnMediaIconButtonAppearance(button, selected, 0.0);
  }];
}

- (void)setFiltersPanelVisible:(BOOL)visible animated:(BOOL)animated {
  if (_filtersPanelVisible == visible) return;
  if (visible) [self setStickerPanelVisible:NO animated:animated];
  else {
    [self applyPendingFullResolutionFilterIfNeeded];
    self.filterBaseImage = nil;
    self.filterPreviewBaseImage = nil;
  }
  _filtersPanelVisible = visible;
  if (visible) {
    self.cropToolActive = NO;
    if (!self.filterBaseImage) self.filterBaseImage = self.image;
    if (!self.filterPreviewBaseImage) self.filterPreviewBaseImage = NFBEditorImageByScalingToMaxDimension(self.filterBaseImage, 900.0);
    if (self.selectedFilterID.length == 0) self.selectedFilterID = @"normal";
    [self buildFilterPreviewButtons];
    self.filtersPanelView.hidden = NO;
  }
  void (^changes)(void) = ^{
    self.filtersPanelView.alpha = visible ? 1.0 : 0.0;
  };
  void (^completion)(BOOL) = ^(BOOL finished) {
    (void)finished;
    if (!visible) self.filtersPanelView.hidden = YES;
  };
  if (animated) [UIView animateWithDuration:0.18 animations:changes completion:completion];
  else {
    changes();
    completion(YES);
  }
  [self updateEditorToolButtons];
}

- (void)setStickerPanelVisible:(BOOL)visible animated:(BOOL)animated {
  if (_stickerPanelVisible == visible) return;
  if (visible) [self setFiltersPanelVisible:NO animated:animated];
  _stickerPanelVisible = visible;
  if (visible) {
    self.cropToolActive = NO;
    if (self.selectedStickerCategoryID.length == 0) self.selectedStickerCategoryID = @"featured";
    [self buildStickerPanelButtons];
    self.stickerPanelView.hidden = NO;
  }
  void (^changes)(void) = ^{
    self.stickerPanelView.alpha = visible ? 1.0 : 0.0;
  };
  void (^completion)(BOOL) = ^(BOOL finished) {
    (void)finished;
    if (!visible) self.stickerPanelView.hidden = YES;
  };
  if (animated) [UIView animateWithDuration:0.18 animations:changes completion:completion];
  else {
    changes();
    completion(YES);
  }
  [self updateEditorToolButtons];
}

- (void)enhanceTapped:(UIButton *)sender {
  (void)sender;
  [self applyPendingFullResolutionFilterIfNeeded];
  [self setFiltersPanelVisible:NO animated:YES];
  [self setStickerPanelVisible:NO animated:YES];
  if (self.enhanceEnabled) {
    if (self.preEnhanceImage) {
      self.image = self.preEnhanceImage;
      self.imageView.image = self.image;
    }
    self.preEnhanceImage = nil;
    self.enhanceEnabled = NO;
  } else {
    self.preEnhanceImage = self.image;
    self.image = NFBEditorEnhancedImage(self.image) ?: self.image;
    self.imageView.image = self.image;
    self.enhanceEnabled = YES;
  }
  self.filterBaseImage = nil;
  self.filterPreviewBaseImage = nil;
  [self updateEditorToolButtons];
}

- (void)filtersTapped:(UIButton *)sender {
  (void)sender;
  [self setFiltersPanelVisible:!self.filtersPanelVisible animated:YES];
}

- (void)stickerTapped:(UIButton *)sender {
  (void)sender;
  [self setStickerPanelVisible:!self.stickerPanelVisible animated:YES];
}

- (void)cropToolTapped:(UIButton *)sender {
  (void)sender;
  [self setFiltersPanelVisible:NO animated:YES];
  [self setStickerPanelVisible:NO animated:YES];
  self.cropToolActive = YES;
  [self resetSelectedSticker];
  [self updateEditorToolButtons];
}

- (void)altTextTapped:(UIButton *)sender {
  (void)sender;
  [self setFiltersPanelVisible:NO animated:YES];
  [self setStickerPanelVisible:NO animated:YES];
  [self presentAltTextEditor];
}

- (void)filterButtonTapped:(UIButton *)sender {
  NSArray<NSDictionary *> *filters = [self filterConfigurations];
  if (sender.tag < 0 || sender.tag >= (NSInteger)filters.count) return;
  NSDictionary *config = filters[(NSUInteger)sender.tag];
  self.selectedFilterID = config[@"id"];
  if (!self.filterBaseImage) self.filterBaseImage = self.image;
  if (!self.filterPreviewBaseImage) self.filterPreviewBaseImage = NFBEditorImageByScalingToMaxDimension(self.filterBaseImage, 900.0);
  self.filterIntensitySlider.enabled = ![self.selectedFilterID isEqualToString:@"normal"];
  [self updateFilteredPreviewForIntensity:self.filterIntensitySlider.value immediate:YES];
  [self buildFilterPreviewButtons];
}

- (void)filterIntensityChanged:(UISlider *)slider {
  if (!self.filterBaseImage) self.filterBaseImage = self.image;
  if (!self.filterPreviewBaseImage) self.filterPreviewBaseImage = NFBEditorImageByScalingToMaxDimension(self.filterBaseImage, 900.0);
  [self updateFilteredPreviewForIntensity:slider.value immediate:NO];
}

- (void)filterIntensityEditingDidEnd:(UISlider *)slider {
  (void)slider;
  [self applyPendingFullResolutionFilterIfNeeded];
}

- (void)updateFilteredPreviewForIntensity:(CGFloat)intensity immediate:(BOOL)immediate {
  UIImage *base = self.filterPreviewBaseImage ?: NFBEditorImageByScalingToMaxDimension(self.filterBaseImage ?: self.image, 900.0);
  NSString *filterID = self.selectedFilterID.length > 0 ? self.selectedFilterID : @"normal";
  NSInteger generation = ++self.filterRenderGeneration;
  self.filterNeedsFullResolutionRender = YES;
  void (^render)(void) = ^{
    UIImage *preview = NFBEditorFilteredImage(base, filterID, intensity);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (generation != self.filterRenderGeneration) return;
      self.imageView.image = preview ?: base;
    });
  };
  if (immediate) render();
  else dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), render);
}

- (void)applyPendingFullResolutionFilterIfNeeded {
  if (!self.filterBaseImage || !self.filterNeedsFullResolutionRender) return;
  NSString *filterID = self.selectedFilterID.length > 0 ? self.selectedFilterID : @"normal";
  UIImage *rendered = NFBEditorFilteredImage(self.filterBaseImage, filterID, self.filterIntensitySlider.value);
  self.image = rendered ?: self.filterBaseImage;
  self.imageView.image = self.image;
  self.filterNeedsFullResolutionRender = NO;
  self.filterRenderGeneration++;
}

- (void)stickerCategoryTapped:(UIButton *)sender {
  NSArray<NSDictionary *> *categories = [self stickerCategories];
  if (sender.tag < 0 || sender.tag >= (NSInteger)categories.count) return;
  self.selectedStickerCategoryID = categories[(NSUInteger)sender.tag][@"id"];
  [self buildStickerPanelButtons];
}

- (void)stickerButtonSelected:(UIButton *)sender {
  NSArray<NSDictionary *> *stickers = [self stickerItemsForCategory:self.selectedStickerCategoryID ?: @"featured"];
  if (sender.tag < 0 || sender.tag >= (NSInteger)stickers.count) return;
  NSDictionary *sticker = stickers[(NSUInteger)sender.tag];
  UIImage *image = NFBBundledImage(@"TwitterStickers", sticker[@"image"], @"png");
  if (!image) return;
  [self addStickerImage:image accessibilityLabel:sticker[@"title"]];
}

- (void)addStickerImage:(UIImage *)image accessibilityLabel:(NSString *)label {
  if (!image || self.stickerViews.count >= 12) return;
  CGFloat side = 112.0;
  NFBPlacedStickerView *sticker = [[NFBPlacedStickerView alloc] initWithImage:image];
  sticker.stickerImage = image;
  sticker.bounds = CGRectMake(0.0, 0.0, side, side);
  CGPoint centerInView = CGPointMake(CGRectGetMidX(self.cropRect), CGRectGetMidY(self.cropRect));
  sticker.center = [self.stickerCanvasView convertPoint:centerInView fromView:self.view];
  sticker.contentMode = UIViewContentModeScaleAspectFit;
  sticker.userInteractionEnabled = YES;
  sticker.accessibilityLabel = label ?: @"Sticker";
  sticker.layer.shadowColor = UIColor.blackColor.CGColor;
  sticker.layer.shadowOpacity = 0.22;
  sticker.layer.shadowRadius = 3.0;
  sticker.layer.shadowOffset = CGSizeMake(0.0, 1.0);

  UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStickerTap:)];
  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleStickerPan:)];
  UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleStickerPinch:)];
  UIRotationGestureRecognizer *rotation = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleStickerRotation:)];
  UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleStickerLongPress:)];
  for (UIGestureRecognizer *recognizer in @[tap, pan, pinch, rotation, longPress]) {
    recognizer.delegate = self;
    [sticker addGestureRecognizer:recognizer];
  }

  [self.stickerCanvasView addSubview:sticker];
  [self.stickerViews addObject:sticker];
  [self selectStickerView:sticker];
  sticker.transform = CGAffineTransformMakeScale(0.72, 0.72);
  sticker.alpha = 0.0;
  [UIView animateWithDuration:0.24 delay:0.0 usingSpringWithDamping:0.66 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    sticker.transform = CGAffineTransformIdentity;
    sticker.alpha = 1.0;
  } completion:nil];
}

- (void)selectStickerView:(NFBPlacedStickerView *)sticker {
  [self resetSelectedSticker];
  self.activeStickerView = sticker;
  sticker.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  sticker.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.72].CGColor;
}

- (void)resetSelectedSticker {
  for (NFBPlacedStickerView *sticker in self.stickerViews) {
    sticker.layer.borderWidth = 0.0;
  }
  self.activeStickerView = nil;
}

- (void)handleStickerTap:(UITapGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateRecognized) return;
  if ([gesture.view isKindOfClass:NFBPlacedStickerView.class]) [self selectStickerView:(NFBPlacedStickerView *)gesture.view];
}

- (void)handleStickerPan:(UIPanGestureRecognizer *)gesture {
  NFBPlacedStickerView *sticker = [gesture.view isKindOfClass:NFBPlacedStickerView.class] ? (NFBPlacedStickerView *)gesture.view : nil;
  if (!sticker) return;
  if (gesture.state == UIGestureRecognizerStateBegan) {
    [self selectStickerView:sticker];
    self.activeStickerStartCenter = sticker.center;
  }
  CGPoint translation = [gesture translationInView:self.stickerCanvasView];
  sticker.center = CGPointMake(self.activeStickerStartCenter.x + translation.x, self.activeStickerStartCenter.y + translation.y);
}

- (void)handleStickerPinch:(UIPinchGestureRecognizer *)gesture {
  NFBPlacedStickerView *sticker = [gesture.view isKindOfClass:NFBPlacedStickerView.class] ? (NFBPlacedStickerView *)gesture.view : nil;
  if (!sticker) return;
  if (gesture.state == UIGestureRecognizerStateBegan) [self selectStickerView:sticker];
  CGFloat scale = MAX(0.78, MIN(1.28, gesture.scale));
  sticker.transform = CGAffineTransformScale(sticker.transform, scale, scale);
  gesture.scale = 1.0;
}

- (void)handleStickerRotation:(UIRotationGestureRecognizer *)gesture {
  NFBPlacedStickerView *sticker = [gesture.view isKindOfClass:NFBPlacedStickerView.class] ? (NFBPlacedStickerView *)gesture.view : nil;
  if (!sticker) return;
  if (gesture.state == UIGestureRecognizerStateBegan) [self selectStickerView:sticker];
  sticker.transform = CGAffineTransformRotate(sticker.transform, gesture.rotation);
  gesture.rotation = 0.0;
}

- (void)handleStickerLongPress:(UILongPressGestureRecognizer *)gesture {
  NFBPlacedStickerView *sticker = [gesture.view isKindOfClass:NFBPlacedStickerView.class] ? (NFBPlacedStickerView *)gesture.view : nil;
  if (!sticker || gesture.state != UIGestureRecognizerStateBegan) return;
  [UIView animateWithDuration:0.16 animations:^{
    sticker.alpha = 0.0;
    sticker.transform = CGAffineTransformScale(sticker.transform, 0.1, 0.1);
  } completion:^(BOOL finished) {
    (void)finished;
    [self.stickerViews removeObject:sticker];
    [sticker removeFromSuperview];
  }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  (void)gestureRecognizer;
  (void)otherGestureRecognizer;
  return YES;
}

- (void)presentAltTextEditor {
  UIViewController *controller = [[UIViewController alloc] initWithNibName:nil bundle:nil];
  controller.view.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
  controller.title = @"Write alt text";

  UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 180.0, 44.0)];
  titleLabel.text = @"Write alt text";
  titleLabel.textColor = NFBIPAOnMediaPrimaryTextColor();
  titleLabel.font = NFBFont(20.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;
  controller.navigationItem.titleView = titleLabel;
  controller.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(altTextCancelTapped:)];
  controller.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(altTextApplyTapped:)];
  controller.navigationItem.leftBarButtonItem.tintColor = UIColor.whiteColor;
  controller.navigationItem.rightBarButtonItem.tintColor = UIColor.whiteColor;

  UITextView *textView = [[UITextView alloc] init];
  textView.translatesAutoresizingMaskIntoConstraints = NO;
  textView.text = self.pendingAltText ?: @"";
  textView.textColor = NFBIPAOnMediaPrimaryTextColor();
  textView.tintColor = NFBColorAccent();
  textView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
  textView.font = NFBFont(17.0, NFBFontWeightRegular);
  textView.layer.cornerRadius = 12.0;
  textView.textContainerInset = UIEdgeInsetsMake(14.0, 12.0, 14.0, 12.0);
  textView.accessibilityIdentifier = @"NFBPhotoAltTextView";
  [controller.view addSubview:textView];

  UILabel *helper = [[UILabel alloc] init];
  helper.translatesAutoresizingMaskIntoConstraints = NO;
  helper.text = @"Describe this photo for people who can’t see it.";
  helper.textColor = NFBIPAOnMediaMutedTextColor();
  helper.font = NFBFont(13.0, NFBFontWeightRegular);
  helper.numberOfLines = 0;
  [controller.view addSubview:helper];

  UILayoutGuide *guide = controller.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [textView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:20.0],
    [textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
    [textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
    [textView.heightAnchor constraintEqualToConstant:184.0],
    [helper.topAnchor constraintEqualToAnchor:textView.bottomAnchor constant:12.0],
    [helper.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor],
    [helper.trailingAnchor constraintEqualToAnchor:textView.trailingAnchor]
  ]];

  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
  NFBApplyDarkNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:^{
    [textView becomeFirstResponder];
  }];
}

- (UITextView *)presentedAltTextView {
  UIViewController *controller = self.presentedViewController;
  if ([controller isKindOfClass:UINavigationController.class]) {
    controller = ((UINavigationController *)controller).topViewController;
  }
  return [self findAltTextViewInView:controller.view];
}

- (UITextView *)findAltTextViewInView:(UIView *)view {
  if ([view isKindOfClass:UITextView.class] && [view.accessibilityIdentifier isEqualToString:@"NFBPhotoAltTextView"]) return (UITextView *)view;
  for (UIView *subview in view.subviews) {
    UITextView *candidate = [self findAltTextViewInView:subview];
    if (candidate) return candidate;
  }
  return nil;
}

- (void)altTextCancelTapped:(id)sender {
  (void)sender;
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)altTextApplyTapped:(id)sender {
  (void)sender;
  NSString *text = [self presentedAltTextView].text ?: @"";
  self.pendingAltText = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  [self dismissViewControllerAnimated:YES completion:nil];
  [self updateEditorToolButtons];
}

- (CGFloat)currentCropHeightMultiplier {
  if (self.selectedAspectIndex == 1) return 9.0 / 16.0;
  if (self.selectedAspectIndex == 2) return 1.0;
  CGSize size = self.image.size;
  return size.width > 0 ? size.height / size.width : 1.0;
}

- (CGFloat)currentCropAspectRatio {
  if (self.selectedAspectIndex == 1) return 16.0 / 9.0;
  if (self.selectedAspectIndex == 2) return 1.0;
  CGSize size = self.image.size;
  return size.height > 0.0 ? size.width / size.height : 1.0;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  self.stickerCanvasView.frame = self.view.bounds;
  [self updateCropRectForCurrentLayoutAnimated:NO];
  [self layoutImageScrollViewContentIfNeeded];
  [self applyCropRectToViews];
  if (self.stickerPanelVisible) [self buildStickerPanelButtons];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
  return scrollView == self.imageScrollView ? self.imageView : nil;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
  if (scrollView != self.imageScrollView) return;
  [self centerImageInScrollView];
}

- (CGRect)editingAreaRectInView {
  if (!self.imageScrollView) return CGRectZero;
  return [self.imageScrollView convertRect:self.imageScrollView.bounds toView:self.view];
}

- (CGRect)cropRectForEditingArea:(CGRect)areaRect aspect:(CGFloat)aspect {
  if (CGRectIsEmpty(areaRect) || aspect <= 0.0) return CGRectZero;
  CGFloat width = CGRectGetWidth(areaRect);
  CGFloat maxHeight = CGRectGetHeight(areaRect);
  CGFloat height = width / aspect;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * aspect;
  }
  width = MIN(width, CGRectGetWidth(areaRect));
  height = MIN(height, CGRectGetHeight(areaRect));
  width = MAX(72.0, width);
  height = MAX(72.0, height);
  return CGRectIntegral(CGRectMake(CGRectGetMidX(areaRect) - width / 2.0,
                                   CGRectGetMidY(areaRect) - height / 2.0,
                                   width,
                                   height));
}

- (void)updateCropRectForCurrentLayoutAnimated:(BOOL)animated {
  CGRect areaRect = [self editingAreaRectInView];
  CGRect newCropRect = [self cropRectForEditingArea:areaRect aspect:[self currentCropAspectRatio]];
  if (CGRectIsEmpty(newCropRect)) return;
  BOOL sizeChanged = !CGSizeEqualToSize(self.configuredBoundsSize, self.imageScrollView.bounds.size);
  if (!self.hasCropRect || sizeChanged || !CGRectEqualToRect(self.cropRect, newCropRect)) {
    self.cropRect = newCropRect;
    self.hasCropRect = YES;
    self.configuredBoundsSize = self.imageScrollView.bounds.size;
    if (animated) {
      [UIView animateWithDuration:0.18 animations:^{
        [self applyCropRectToViews];
      }];
    }
  }
}

- (void)layoutImageScrollViewContentIfNeeded {
  CGRect bounds = self.imageScrollView.bounds;
  if (CGRectIsEmpty(bounds) || self.image.size.width <= 0.0 || self.image.size.height <= 0.0) return;
  CGRect cropRectInScroll = [self.view convertRect:self.cropRect toView:self.imageScrollView];
  if (self.configuredInitialImageLayout && !CGRectIsEmpty(self.imageView.bounds)) {
    [self updateScrollViewInsetsForCropRectInScrollView:cropRectInScroll];
    [self centerImageInScrollView];
    return;
  }

  CGFloat scale = MIN(CGRectGetWidth(bounds) / self.image.size.width, CGRectGetHeight(bounds) / self.image.size.height);
  if (!isfinite(scale) || scale <= 0.0) scale = 1.0;
  CGSize fittedSize = CGSizeMake(floor(self.image.size.width * scale), floor(self.image.size.height * scale));
  fittedSize.width = MAX(1.0, fittedSize.width);
  fittedSize.height = MAX(1.0, fittedSize.height);

  CGFloat minimumZoomScale = MAX(1.0, MAX(CGRectGetWidth(cropRectInScroll) / fittedSize.width,
                                          CGRectGetHeight(cropRectInScroll) / fittedSize.height));
  self.imageView.transform = CGAffineTransformIdentity;
  self.imageView.frame = CGRectMake(0.0, 0.0, fittedSize.width, fittedSize.height);
  self.imageScrollView.contentSize = fittedSize;
  self.imageScrollView.minimumZoomScale = minimumZoomScale;
  self.imageScrollView.maximumZoomScale = MAX(4.0, minimumZoomScale * 4.0);
  self.imageScrollView.zoomScale = minimumZoomScale;
  self.configuredInitialImageLayout = YES;
  [self updateScrollViewInsetsForCropRectInScrollView:cropRectInScroll];
  [self centerImageInScrollView];
}

- (void)updateScrollViewInsetsForCropRectInScrollView:(CGRect)cropRectInScroll {
  if (CGRectIsEmpty(cropRectInScroll) || CGRectIsEmpty(self.imageScrollView.bounds)) return;
  UIEdgeInsets insets = UIEdgeInsetsMake(CGRectGetMinY(cropRectInScroll),
                                         CGRectGetMinX(cropRectInScroll),
                                         MAX(0.0, CGRectGetHeight(self.imageScrollView.bounds) - CGRectGetMaxY(cropRectInScroll)),
                                         MAX(0.0, CGRectGetWidth(self.imageScrollView.bounds) - CGRectGetMaxX(cropRectInScroll)));
  self.imageScrollView.contentInset = insets;
  self.imageScrollView.scrollIndicatorInsets = insets;
}

- (void)centerImageInScrollView {
  CGSize boundsSize = self.imageScrollView.bounds.size;
  CGRect frame = self.imageView.frame;
  CGRect cropRectInScroll = [self.view convertRect:self.cropRect toView:self.imageScrollView];
  CGFloat targetCenterX = CGRectGetMidX(cropRectInScroll);
  CGFloat targetCenterY = CGRectGetMidY(cropRectInScroll);
  frame.origin.x = frame.size.width < CGRectGetWidth(cropRectInScroll) ? targetCenterX - frame.size.width / 2.0 : floor((boundsSize.width - frame.size.width) / 2.0);
  frame.origin.y = frame.size.height < CGRectGetHeight(cropRectInScroll) ? targetCenterY - frame.size.height / 2.0 : floor((boundsSize.height - frame.size.height) / 2.0);
  self.imageView.frame = frame;
}

- (CGRect)visibleImageRectInView {
  if (!self.imageView.image || CGRectIsEmpty(self.imageView.frame)) return CGRectZero;
  return [self.imageScrollView convertRect:self.imageView.frame toView:self.view];
}

- (CGRect)defaultCropRectForVisibleImageRect:(CGRect)visibleRect aspect:(CGFloat)aspect {
  (void)visibleRect;
  return [self cropRectForEditingArea:[self editingAreaRectInView] aspect:aspect];
}

- (void)resetCropRectIfNeeded {
  CGRect visibleRect = [self visibleImageRectInView];
  if (CGRectIsEmpty(visibleRect)) return;
  if (!self.hasCropRect || !CGRectIntersectsRect(visibleRect, self.cropRect)) {
    self.cropRect = [self defaultCropRectForVisibleImageRect:visibleRect aspect:[self currentCropAspectRatio]];
    self.hasCropRect = YES;
  } else {
    self.cropRect = [self constrainedCropRect:self.cropRect inVisibleImageRect:visibleRect];
  }
}

- (CGRect)constrainedCropRect:(CGRect)rect inVisibleImageRect:(CGRect)visibleRect {
  if (CGRectIsEmpty(visibleRect) || CGRectIsEmpty(rect)) return [self defaultCropRectForVisibleImageRect:visibleRect aspect:[self currentCropAspectRatio]];
  rect.size.width = MIN(CGRectGetWidth(rect), CGRectGetWidth(visibleRect));
  rect.size.height = MIN(CGRectGetHeight(rect), CGRectGetHeight(visibleRect));
  if (CGRectGetMinX(rect) < CGRectGetMinX(visibleRect)) rect.origin.x = CGRectGetMinX(visibleRect);
  if (CGRectGetMinY(rect) < CGRectGetMinY(visibleRect)) rect.origin.y = CGRectGetMinY(visibleRect);
  if (CGRectGetMaxX(rect) > CGRectGetMaxX(visibleRect)) rect.origin.x = CGRectGetMaxX(visibleRect) - CGRectGetWidth(rect);
  if (CGRectGetMaxY(rect) > CGRectGetMaxY(visibleRect)) rect.origin.y = CGRectGetMaxY(visibleRect) - CGRectGetHeight(rect);
  return CGRectIntegral(rect);
}

- (void)applyCropRectToViews {
  CGRect areaRect = [self editingAreaRectInView];
  CGRect cropRect = self.hasCropRect ? self.cropRect : [self cropRectForEditingArea:areaRect aspect:[self currentCropAspectRatio]];
  if (CGRectIsEmpty(areaRect) || CGRectIsEmpty(cropRect)) return;
  self.cropRect = cropRect;
  self.cropFrameView.frame = cropRect;
  [self.cropFrameView setNeedsDisplay];
  self.shadowTopView.frame = CGRectMake(CGRectGetMinX(areaRect), CGRectGetMinY(areaRect), CGRectGetWidth(areaRect), MAX(0.0, CGRectGetMinY(cropRect) - CGRectGetMinY(areaRect)));
  self.shadowBottomView.frame = CGRectMake(CGRectGetMinX(areaRect), CGRectGetMaxY(cropRect), CGRectGetWidth(areaRect), MAX(0.0, CGRectGetMaxY(areaRect) - CGRectGetMaxY(cropRect)));
  self.shadowLeftView.frame = CGRectMake(CGRectGetMinX(areaRect), CGRectGetMinY(cropRect), MAX(0.0, CGRectGetMinX(cropRect) - CGRectGetMinX(areaRect)), CGRectGetHeight(cropRect));
  self.shadowRightView.frame = CGRectMake(CGRectGetMaxX(cropRect), CGRectGetMinY(cropRect), MAX(0.0, CGRectGetMaxX(areaRect) - CGRectGetMaxX(cropRect)), CGRectGetHeight(cropRect));
}

- (void)handleCropPan:(UIPanGestureRecognizer *)gesture {
  CGRect visibleRect = [self visibleImageRectInView];
  if (CGRectIsEmpty(visibleRect)) return;
  if (gesture.state == UIGestureRecognizerStateBegan) self.gestureStartCropRect = self.cropRect;
  CGPoint translation = [gesture translationInView:self.view];
  CGRect rect = self.gestureStartCropRect;
  rect.origin.x += translation.x;
  rect.origin.y += translation.y;
  self.cropRect = [self constrainedCropRect:rect inVisibleImageRect:visibleRect];
  [self applyCropRectToViews];
}

- (void)handleCropPinch:(UIPinchGestureRecognizer *)gesture {
  CGRect visibleRect = [self visibleImageRectInView];
  if (CGRectIsEmpty(visibleRect)) return;
  if (gesture.state == UIGestureRecognizerStateBegan) self.gestureStartCropRect = self.cropRect;
  CGFloat aspect = [self currentCropAspectRatio];
  CGFloat scale = MAX(0.32, MIN(2.6, gesture.scale));
  CGFloat width = CGRectGetWidth(self.gestureStartCropRect) * scale;
  CGFloat height = width / MAX(aspect, 0.01);
  CGFloat maxWidth = CGRectGetWidth(visibleRect);
  CGFloat maxHeight = CGRectGetHeight(visibleRect);
  if (width > maxWidth) {
    width = maxWidth;
    height = width / MAX(aspect, 0.01);
  }
  if (height > maxHeight) {
    height = maxHeight;
    width = height * aspect;
  }
  width = MAX(72.0, width);
  height = MAX(72.0, height);
  CGRect rect = CGRectMake(CGRectGetMidX(self.gestureStartCropRect) - width / 2.0,
                           CGRectGetMidY(self.gestureStartCropRect) - height / 2.0,
                           width,
                           height);
  self.cropRect = [self constrainedCropRect:rect inVisibleImageRect:visibleRect];
  [self applyCropRectToViews];
}

- (void)handleImageDoubleTap:(UITapGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateRecognized) return;
  if (self.imageScrollView.zoomScale > self.imageScrollView.minimumZoomScale + 0.01) {
    [self.imageScrollView setZoomScale:self.imageScrollView.minimumZoomScale animated:YES];
    return;
  }
  CGPoint point = [gesture locationInView:self.imageView];
  CGFloat zoomScale = MIN(self.imageScrollView.maximumZoomScale, MAX(2.0, self.imageScrollView.minimumZoomScale * 2.0));
  CGSize zoomSize = CGSizeMake(CGRectGetWidth(self.imageScrollView.bounds) / zoomScale,
                               CGRectGetHeight(self.imageScrollView.bounds) / zoomScale);
  CGRect zoomRect = CGRectMake(point.x - zoomSize.width / 2.0,
                               point.y - zoomSize.height / 2.0,
                               zoomSize.width,
                               zoomSize.height);
  [self.imageScrollView zoomToRect:zoomRect animated:YES];
}

- (void)ensureImageCoversCropRectAnimated:(BOOL)animated {
  if (CGRectIsEmpty(self.cropRect) || CGRectIsEmpty(self.imageView.frame)) return;
  CGRect imageFrameInView = [self.imageScrollView convertRect:self.imageView.frame toView:self.view];
  CGFloat scaleX = CGRectGetWidth(self.cropRect) / MAX(CGRectGetWidth(imageFrameInView), 1.0);
  CGFloat scaleY = CGRectGetHeight(self.cropRect) / MAX(CGRectGetHeight(imageFrameInView), 1.0);
  CGFloat neededScale = MAX(scaleX, scaleY);
  if (neededScale > 1.0) {
    CGFloat targetZoom = MIN(self.imageScrollView.maximumZoomScale, self.imageScrollView.zoomScale * neededScale * 1.01);
    [self.imageScrollView setZoomScale:targetZoom animated:animated];
  }
  [self centerImageInScrollView];
}

- (void)aspectButtonTapped:(UIButton *)sender {
  self.selectedAspectIndex = sender.tag;
  [self aspectChanged];
}

- (void)updateAspectButtons {
  [self.aspectButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
    (void)stop;
    BOOL selected = (NSInteger)index == self.selectedAspectIndex;
    NFBIPAApplyOnMediaIconButtonAppearance(button, selected, 0.0);
  }];
  NFBIPAApplyOnMediaIconButtonAppearance(self.rotateButton, NO, 0.0);
}

- (void)aspectChanged {
  [self updateAspectButtons];
  CGRect rect = [self cropRectForEditingArea:[self editingAreaRectInView] aspect:[self currentCropAspectRatio]];
  if (CGRectIsEmpty(rect)) return;
  self.cropRect = rect;
  self.hasCropRect = YES;
  [UIView animateWithDuration:0.18 animations:^{
    [self applyCropRectToViews];
    [self updateScrollViewInsetsForCropRectInScrollView:[self.view convertRect:self.cropRect toView:self.imageScrollView]];
  }];
  [self ensureImageCoversCropRectAnimated:YES];
}

- (void)rotateTapped {
  [self applyPendingFullResolutionFilterIfNeeded];
  self.rotateButton.enabled = NO;
  CGRect frameInView = [self.imageScrollView convertRect:self.imageView.frame toView:self.view];
  UIImageView *rotatingView = [[UIImageView alloc] initWithImage:self.imageView.image ?: self.image];
  rotatingView.frame = frameInView;
  rotatingView.contentMode = UIViewContentModeScaleAspectFit;
  rotatingView.clipsToBounds = YES;
  [self.view insertSubview:rotatingView aboveSubview:self.imageScrollView];
  self.imageView.hidden = YES;
  self.cropFrameView.alpha = 0.72;
  [UIView animateWithDuration:0.28 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
    rotatingView.transform = CGAffineTransformRotate(CGAffineTransformIdentity, M_PI_2);
    rotatingView.bounds = CGRectMake(0.0, 0.0, CGRectGetHeight(frameInView), CGRectGetWidth(frameInView));
    self.cropFrameView.alpha = 0.34;
    self.shadowTopView.alpha = 0.42;
    self.shadowBottomView.alpha = 0.42;
    self.shadowLeftView.alpha = 0.42;
    self.shadowRightView.alpha = 0.42;
  } completion:^(BOOL finished) {
    (void)finished;
    CGSize size = CGSizeMake(self.image.size.height, self.image.size.width);
    UIGraphicsBeginImageContextWithOptions(size, YES, self.image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, size.width / 2.0, size.height / 2.0);
    CGContextRotateCTM(context, M_PI_2);
    [self.image drawInRect:CGRectMake(-self.image.size.width / 2.0, -self.image.size.height / 2.0, self.image.size.width, self.image.size.height)];
    UIImage *rotated = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    self.image = rotated ?: self.image;
    self.imageView.image = self.image;
    self.imageView.hidden = NO;
    [rotatingView removeFromSuperview];
    self.filterBaseImage = nil;
    self.filterPreviewBaseImage = nil;
    self.hasCropRect = NO;
    self.configuredInitialImageLayout = NO;
    self.configuredBoundsSize = CGSizeZero;
    self.imageScrollView.zoomScale = 1.0;
    self.imageScrollView.contentInset = UIEdgeInsetsZero;
    self.rotateButton.enabled = YES;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.12 animations:^{
      self.cropFrameView.alpha = 1.0;
      self.shadowTopView.alpha = 1.0;
      self.shadowBottomView.alpha = 1.0;
      self.shadowLeftView.alpha = 1.0;
      self.shadowRightView.alpha = 1.0;
    }];
  }];
}

- (void)cancelTapped {
  [self.delegate cropViewControllerDidCancel:self];
}

- (void)applyTapped {
  [self applyPendingFullResolutionFilterIfNeeded];
  [self resetSelectedSticker];
  UIImage *cropped = [self centerCroppedImage];
  [self.delegate cropViewController:self didFinishWithImage:cropped ?: self.image];
}

- (UIImage *)centerCroppedImage {
  CGRect imageFrameInView = [self.imageScrollView convertRect:self.imageView.frame toView:self.view];
  CGRect cropRect = CGRectIntersection(self.cropRect, imageFrameInView);
  if (CGRectIsEmpty(cropRect) || CGRectIsEmpty(imageFrameInView)) return self.image;
  CGSize pixelSize = CGSizeMake(CGImageGetWidth(self.image.CGImage), CGImageGetHeight(self.image.CGImage));
  CGFloat scaleX = pixelSize.width / MAX(CGRectGetWidth(imageFrameInView), 1.0);
  CGFloat scaleY = pixelSize.height / MAX(CGRectGetHeight(imageFrameInView), 1.0);
  CGRect crop = CGRectMake((CGRectGetMinX(cropRect) - CGRectGetMinX(imageFrameInView)) * scaleX,
                           (CGRectGetMinY(cropRect) - CGRectGetMinY(imageFrameInView)) * scaleY,
                           CGRectGetWidth(cropRect) * scaleX,
                           CGRectGetHeight(cropRect) * scaleY);
  crop = CGRectIntegral(CGRectIntersection(crop, CGRectMake(0.0, 0.0, pixelSize.width, pixelSize.height)));
  CGImageRef croppedRef = CGImageCreateWithImageInRect(self.image.CGImage, crop);
  if (!croppedRef) return self.image;
  UIImage *cropped = [UIImage imageWithCGImage:croppedRef scale:self.image.scale orientation:UIImageOrientationUp];
  CGImageRelease(croppedRef);
  return [self imageByApplyingStickersToImage:cropped cropRectInView:cropRect] ?: cropped;
}

- (UIImage *)imageByApplyingStickersToImage:(UIImage *)image cropRectInView:(CGRect)cropRect {
  if (!image || self.stickerViews.count == 0 || CGRectIsEmpty(cropRect)) return image;
  CGFloat scaleX = image.size.width / MAX(CGRectGetWidth(cropRect), 1.0);
  CGFloat scaleY = image.size.height / MAX(CGRectGetHeight(cropRect), 1.0);
  UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
  [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
  CGContextRef context = UIGraphicsGetCurrentContext();
  for (NFBPlacedStickerView *sticker in self.stickerViews) {
    UIImage *stickerImage = sticker.stickerImage ?: sticker.image;
    if (!stickerImage || sticker.hidden || sticker.alpha <= 0.01) continue;
    CGPoint centerInView = [self.stickerCanvasView convertPoint:sticker.center toView:self.view];
    CGRect stickerBoundsInView = [self.stickerCanvasView convertRect:sticker.frame toView:self.view];
    if (!CGRectIntersectsRect(stickerBoundsInView, cropRect)) continue;
    CGPoint outputCenter = CGPointMake((centerInView.x - CGRectGetMinX(cropRect)) * scaleX,
                                       (centerInView.y - CGRectGetMinY(cropRect)) * scaleY);
    CGAffineTransform transform = sticker.transform;
    CGFloat stickerScale = sqrt(transform.a * transform.a + transform.c * transform.c);
    if (!isfinite(stickerScale) || stickerScale <= 0.0) stickerScale = 1.0;
    CGFloat angle = atan2(transform.b, transform.a);
    CGSize outputSize = CGSizeMake(CGRectGetWidth(sticker.bounds) * scaleX * stickerScale,
                                   CGRectGetHeight(sticker.bounds) * scaleY * stickerScale);
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, outputCenter.x, outputCenter.y);
    CGContextRotateCTM(context, angle);
    [stickerImage drawInRect:CGRectMake(-outputSize.width / 2.0,
                                        -outputSize.height / 2.0,
                                        outputSize.width,
                                        outputSize.height)
                   blendMode:kCGBlendModeNormal
                       alpha:sticker.alpha];
    CGContextRestoreGState(context);
  }
  UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return result ?: image;
}

+ (UIImage *)normalizedImage:(UIImage *)image {
  if (image.imageOrientation == UIImageOrientationUp) return image;
  UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
  [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
  UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return normalized ?: image;
}

@end

@interface NFBMediaSourcePickerViewController : UIViewController
- (instancetype)initWithCompletion:(NFBMediaSourcePickerCompletion)completion;
@end

@implementation NFBMediaSourcePickerViewController {
  NFBMediaSourcePickerCompletion _completion;
  UIButton *_backdropButton;
  UIView *_sheetView;
}

- (instancetype)initWithCompletion:(NFBMediaSourcePickerCompletion)completion {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _completion = [completion copy];
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
  NFBIPAApplyModalSheetAppearance(_sheetView);
  NFBInstallSheetDismissGesture(_sheetView, _backdropButton, self, @selector(cancelTapped));
  [self.view addSubview:_sheetView];

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);
  [_sheetView addSubview:grabber];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = @"Open media";
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(18.0, NFBFontWeightHeavy);
  [_sheetView addSubview:titleLabel];

  UIStackView *rows = [[UIStackView alloc] init];
  rows.translatesAutoresizingMaskIntoConstraints = NO;
  rows.axis = UILayoutConstraintAxisVertical;
  rows.spacing = 0.0;
  [_sheetView addSubview:rows];

  [rows addArrangedSubview:[self mediaRowWithTitle:@"Photo Library" subtitle:@"Choose photos from your library" icon:@"nfb_media" video:NO]];
  [rows addArrangedSubview:[self mediaRowWithTitle:@"Video" subtitle:@"Choose and trim a video" icon:@"nfb_video" video:YES]];
  [rows addArrangedSubview:[self mediaRowWithTitle:@"Cancel" subtitle:@"" icon:@"nfb_close" video:NO cancel:YES]];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [grabber.topAnchor constraintEqualToAnchor:_sheetView.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:_sheetView.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],
    [titleLabel.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor constant:24.0],
    [titleLabel.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor constant:-24.0],
    [titleLabel.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:18.0],
    [rows.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor],
    [rows.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor],
    [rows.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
    [rows.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-8.0]
  ]];
}

- (UIButton *)mediaRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon video:(BOOL)video {
  return [self mediaRowWithTitle:title subtitle:subtitle icon:icon video:video cancel:NO];
}

- (UIButton *)mediaRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon video:(BOOL)video cancel:(BOOL)cancel {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  button.accessibilityIdentifier = cancel ? @"cancel" : (video ? @"video" : @"photo");
  [button addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
  [button.heightAnchor constraintEqualToConstant:64.0].active = YES;

  UIImageView *iconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(icon)];
  iconView.translatesAutoresizingMaskIntoConstraints = NO;
  iconView.tintColor = NFBColorText();
  iconView.contentMode = UIViewContentModeScaleAspectFit;
  [button addSubview:iconView];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = title;
  titleLabel.textColor = cancel ? NFBColorAccent() : NFBColorText();
  titleLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
  [button addSubview:titleLabel];

  UILabel *subtitleLabel = [[UILabel alloc] init];
  subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  subtitleLabel.text = subtitle;
  subtitleLabel.textColor = NFBColorSecondaryText();
  subtitleLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  subtitleLabel.hidden = subtitle.length == 0;
  [button addSubview:subtitleLabel];

  CGFloat titleCenterOffset = subtitle.length == 0 ? 0.0 : -8.0;
  [NSLayoutConstraint activateConstraints:@[
    [iconView.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:24.0],
    [iconView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    [iconView.widthAnchor constraintEqualToConstant:24.0],
    [iconView.heightAnchor constraintEqualToConstant:24.0],
    [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:18.0],
    [titleLabel.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-24.0],
    [titleLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor constant:titleCenterOffset],
    [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
    [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0]
  ]];
  return button;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  _backdropButton.frame = self.view.bounds;
  CGFloat rowsHeight = 64.0 * 3.0;
  CGFloat sheetHeight = 61.0 + rowsHeight + self.view.safeAreaInsets.bottom + 8.0;
  _sheetView.frame = CGRectMake(0.0, CGRectGetHeight(self.view.bounds) - sheetHeight, CGRectGetWidth(self.view.bounds), sheetHeight);
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  _sheetView.transform = CGAffineTransformMakeTranslation(0.0, CGRectGetHeight(_sheetView.bounds));
  [UIView animateWithDuration:0.26 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.25 options:UIViewAnimationOptionCurveEaseOut animations:^{
    self->_sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)rowTapped:(UIButton *)sender {
  NSString *identifier = sender.accessibilityIdentifier ?: @"";
  if ([identifier isEqualToString:@"cancel"]) {
    [self cancelTapped];
    return;
  }
  BOOL video = [identifier isEqualToString:@"video"];
  NFBMediaSourcePickerCompletion completion = [_completion copy];
  [self dismissViewControllerAnimated:YES completion:^{
    if (completion) completion(video);
  }];
}

- (void)cancelTapped {
  [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface NFBVideoRangeSliderView : UIControl
@property (nonatomic, readonly) NSInteger trackingBound;
@property (nonatomic, assign) CGFloat minimumValue;
@property (nonatomic, assign) CGFloat maximumValue;
@property (nonatomic, assign) CGFloat lowerBound;
@property (nonatomic, assign) CGFloat upperBound;
@property (nonatomic, assign) CGFloat value;
@property (nonatomic, assign) CGFloat minimumBoundsRange;
@property (nonatomic, assign) CGFloat maximumBoundsRange;
@property (nonatomic, copy) NSArray<UIImage *> *thumbnailImages;
@end

@implementation NFBVideoRangeSliderView {
  NSInteger _trackingMode;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    _minimumValue = 0.0;
    _maximumValue = 1.0;
    _lowerBound = 0.0;
    _upperBound = 1.0;
    _minimumBoundsRange = 1.0;
    _maximumBoundsRange = CGFLOAT_MAX;
    _value = 0.0;
    self.multipleTouchEnabled = NO;
    self.accessibilityLabel = @"Trim video";
  }
  return self;
}

- (void)setThumbnailImages:(NSArray<UIImage *> *)thumbnailImages {
  _thumbnailImages = [thumbnailImages copy] ?: @[];
  [self setNeedsDisplay];
}

- (void)setLowerBound:(CGFloat)lowerBound {
  _lowerBound = [self constrainedLowerBound:lowerBound upper:_upperBound];
  [self setNeedsDisplay];
}

- (void)setUpperBound:(CGFloat)upperBound {
  _upperBound = [self constrainedUpperBound:upperBound lower:_lowerBound];
  [self setNeedsDisplay];
}

- (void)setValue:(CGFloat)value {
  _value = MIN(MAX(value, self.minimumValue), self.maximumValue);
  [self setNeedsDisplay];
}

- (NSInteger)trackingBound { return _trackingMode; }

- (CGRect)trackRect {
  return CGRectInset(self.bounds, 18.0, 18.0);
}

- (CGFloat)xForValue:(CGFloat)value {
  CGRect track = [self trackRect];
  CGFloat progress = (value - self.minimumValue) / MAX(self.maximumValue - self.minimumValue, 0.001);
  return CGRectGetMinX(track) + CGRectGetWidth(track) * MIN(MAX(progress, 0.0), 1.0);
}

- (CGFloat)valueForX:(CGFloat)x {
  CGRect track = [self trackRect];
  CGFloat progress = (x - CGRectGetMinX(track)) / MAX(CGRectGetWidth(track), 1.0);
  return self.minimumValue + (self.maximumValue - self.minimumValue) * MIN(MAX(progress, 0.0), 1.0);
}

- (CGFloat)constrainedLowerBound:(CGFloat)candidate upper:(CGFloat)upper {
  CGFloat lower = MAX(self.minimumValue, MIN(candidate, upper - self.minimumBoundsRange));
  if (upper - lower > self.maximumBoundsRange) lower = upper - self.maximumBoundsRange;
  return MAX(self.minimumValue, lower);
}

- (CGFloat)constrainedUpperBound:(CGFloat)candidate lower:(CGFloat)lower {
  CGFloat upper = MIN(self.maximumValue, MAX(candidate, lower + self.minimumBoundsRange));
  if (upper - lower > self.maximumBoundsRange) upper = lower + self.maximumBoundsRange;
  return MIN(self.maximumValue, upper);
}

- (void)drawRect:(CGRect)rect {
  (void)rect;
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (!context) return;
  CGRect track = [self trackRect];
  UIBezierPath *clipPath = [UIBezierPath bezierPathWithRoundedRect:track cornerRadius:4.0];
  CGContextSaveGState(context);
  [clipPath addClip];
  [[UIColor colorWithWhite:0.08 alpha:1.0] setFill];
  UIRectFill(track);
  NSUInteger count = self.thumbnailImages.count;
  if (count > 0) {
    CGFloat tileWidth = CGRectGetWidth(track) / count;
    [self.thumbnailImages enumerateObjectsUsingBlock:^(UIImage *image, NSUInteger index, BOOL *stop) {
      (void)stop;
      CGRect tile = CGRectMake(CGRectGetMinX(track) + tileWidth * index, CGRectGetMinY(track), ceil(tileWidth), CGRectGetHeight(track));
      CGFloat scale = MAX(CGRectGetWidth(tile) / MAX(image.size.width, 1.0), CGRectGetHeight(tile) / MAX(image.size.height, 1.0));
      CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
      CGRect drawRect = CGRectMake(CGRectGetMidX(tile) - drawSize.width / 2.0,
                                   CGRectGetMidY(tile) - drawSize.height / 2.0,
                                   drawSize.width,
                                   drawSize.height);
      [image drawInRect:drawRect];
    }];
  }
  CGFloat lowerX = [self xForValue:self.lowerBound];
  CGFloat upperX = [self xForValue:self.upperBound];
  [[UIColor.blackColor colorWithAlphaComponent:0.58] setFill];
  UIRectFill(CGRectMake(CGRectGetMinX(track), CGRectGetMinY(track), lowerX - CGRectGetMinX(track), CGRectGetHeight(track)));
  UIRectFill(CGRectMake(upperX, CGRectGetMinY(track), CGRectGetMaxX(track) - upperX, CGRectGetHeight(track)));
  CGContextRestoreGState(context);

  CGRect selected = CGRectMake(lowerX, CGRectGetMinY(track), MAX(1.0, upperX - lowerX), CGRectGetHeight(track));
  UIBezierPath *selection = [UIBezierPath bezierPathWithRoundedRect:selected cornerRadius:4.0];
  [UIColor.whiteColor setStroke];
  selection.lineWidth = 3.0;
  [selection stroke];

  CGFloat valueX = [self xForValue:self.value];
  if (valueX >= lowerX && valueX <= upperX) {
    [[UIColor.whiteColor colorWithAlphaComponent:0.92] setFill];
    UIRectFill(CGRectMake(valueX - 1.0, CGRectGetMinY(track) + 4.0, 2.0, CGRectGetHeight(track) - 8.0));
  }

  [self drawThumbAtX:lowerX inTrack:track];
  [self drawThumbAtX:upperX inTrack:track];
}

- (void)drawThumbAtX:(CGFloat)x inTrack:(CGRect)track {
  CGRect thumb = CGRectMake(x - 6.0, CGRectGetMinY(track) - 2.0, 12.0, CGRectGetHeight(track) + 4.0);
  UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:thumb cornerRadius:5.0];
  [UIColor.whiteColor setFill];
  [path fill];
  [[UIColor.blackColor colorWithAlphaComponent:0.35] setFill];
  UIRectFill(CGRectMake(CGRectGetMidX(thumb) - 1.0, CGRectGetMidY(thumb) - 10.0, 2.0, 20.0));
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
  (void)event;
  CGPoint point = [touch locationInView:self];
  CGFloat lowerX = [self xForValue:self.lowerBound];
  CGFloat upperX = [self xForValue:self.upperBound];
  CGFloat lowerDistance = fabs(point.x - lowerX);
  CGFloat upperDistance = fabs(point.x - upperX);
  _trackingMode = lowerDistance <= upperDistance ? 1 : 2;
  if (MIN(lowerDistance, upperDistance) > 34.0 && point.x > lowerX && point.x < upperX) {
    _trackingMode = 3;
  }
  [self continueTrackingWithTouch:touch withEvent:event];
  return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
  (void)event;
  CGFloat value = [self valueForX:[touch locationInView:self].x];
  if (_trackingMode == 1) self.lowerBound = value;
  else if (_trackingMode == 2) self.upperBound = value;
  self.value = _trackingMode == 3 ? MIN(self.upperBound, MAX(self.lowerBound, value)) : (_trackingMode == 2 ? self.upperBound : self.lowerBound);
  [self sendActionsForControlEvents:UIControlEventValueChanged];
  return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
  (void)touch;
  (void)event;
  _trackingMode = 0;
  [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
  (void)event;
  _trackingMode = 0;
  [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
}

@end

@interface NFBMediaContentSettingsController : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *labels;
@property (nonatomic, copy) void (^completionHandler)(NSArray<NSString *> *);
@end
@implementation NFBMediaContentSettingsController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Content settings";
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.tableView.rowHeight = 52;
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 3; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return @"Put a content warning on this Tweet"; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return @"Select a category, and we’ll put a content warning on this Tweet. This helps people avoid content they don’t want to see."; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  NFBIPAApplyTableCellAppearance(cell, UITableViewCellSelectionStyleDefault);
  cell.textLabel.text = @[@"Nudity", @"Violence", @"Sensitive"][path.row];
  cell.textLabel.font = NFBFont(17, NFBFontWeightRegular);
  cell.textLabel.textColor = NFBColorText(); cell.tintColor = NFBColorAccent();
  BOOL selected = [self.labels containsObject:@[@"nudity", @"gore", @"!warn"][path.row]];
  cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  cell.accessibilityTraits |= selected ? UIAccessibilityTraitSelected : 0;
  return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
  NSMutableArray *labels = [self.labels mutableCopy] ?: [NSMutableArray array];
  NSString *label = @[@"nudity", @"gore", @"!warn"][path.row];
  if ([labels containsObject:label]) [labels removeObject:label]; else [labels addObject:label];
  self.labels = labels; [table reloadData];
}
- (void)cancel { [self.navigationController popViewControllerAnimated:YES]; }
- (void)done { if (self.completionHandler) self.completionHandler(self.labels ?: @[]); [self cancel]; }
@end

@interface NFBVideoTrimViewController : UIViewController
@property (nonatomic, copy) NSArray<NSString *> *contentWarnings;
@property (nonatomic, weak) id<NFBVideoTrimViewControllerDelegate> delegate;
- (instancetype)initWithURL:(NSURL *)url;
@end

@interface NFBVideoTrimViewController ()
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) UIView *playerView;
@property (nonatomic, strong) NFBVideoRangeSliderView *rangeSlider;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIButton *trimPlayPauseButton;
@property (nonatomic, strong) UIButton *trimMuteButton;
@property (nonatomic, strong) UIButton *trimToolbarButton;
@property (nonatomic, strong) UIView *trimControlsView;
@property (nonatomic, strong) UIImageView *activity;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, assign) BOOL mutedForExport;
@property (nonatomic, assign) BOOL generatedTrimThumbnails;
@property (nonatomic, strong) AVAssetExportSession *exporter;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL exporting;
@end

@implementation NFBVideoTrimViewController

- (instancetype)initWithURL:(NSURL *)url {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _url = url;
    _asset = [AVURLAsset URLAssetWithURL:url options:nil];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
  self.title = @"Edit video";
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(trimTapped)];
  self.navigationItem.leftBarButtonItem.tintColor = UIColor.whiteColor;
  self.navigationItem.rightBarButtonItem.tintColor = UIColor.whiteColor;

  self.playerView = [[UIView alloc] init];
  self.playerView.translatesAutoresizingMaskIntoConstraints = NO;
  self.playerView.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
  [self.view addSubview:self.playerView];
  self.player = [AVPlayer playerWithURL:self.url];
  [NFBMediaAudioSession setMuted:YES forPlayer:self.player];
  [self.playerView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(trimPlayPauseTapped)]];
  AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:self.player];
  layer.videoGravity = AVLayerVideoGravityResizeAspect;
  layer.frame = self.view.bounds;
  [self.playerView.layer addSublayer:layer];

  self.durationLabel = [[UILabel alloc] init];
  self.durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.durationLabel.font = NFBFont(13.0, NFBFontWeightHeavy);
  self.durationLabel.textAlignment = NSTextAlignmentCenter;
  NFBIPAApplyOnMediaLabelPillAppearance(self.durationLabel, 14.0);

  self.trimPlayPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.trimPlayPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaFloatingButtonAppearance(self.trimPlayPauseButton, 32.0);
  [self.trimPlayPauseButton setImage:NFBTemplateIcon(@"nfb_play") forState:UIControlStateNormal];
  [self.trimPlayPauseButton addTarget:self action:@selector(trimPlayPauseTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.playerView addSubview:self.trimPlayPauseButton];

  self.trimMuteButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.trimMuteButton.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaFloatingButtonAppearance(self.trimMuteButton, 18.0);
  [self.trimMuteButton setImage:NFBTemplateIcon(@"nfb_speaker_off") forState:UIControlStateNormal];
  [self.trimMuteButton addTarget:self action:@selector(trimMuteTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.playerView addSubview:self.trimMuteButton];

  NSTimeInterval assetDuration = CMTimeGetSeconds(self.asset.duration);
  if (!isfinite(assetDuration) || assetDuration <= 0.0) assetDuration = 1.0;
  self.rangeSlider = [[NFBVideoRangeSliderView alloc] init];
  self.rangeSlider.translatesAutoresizingMaskIntoConstraints = NO;
  self.rangeSlider.minimumValue = 0.0;
  self.rangeSlider.maximumValue = assetDuration;
  self.rangeSlider.lowerBound = 0.0;
  self.rangeSlider.upperBound = MIN(assetDuration, NFBMaxVideoDuration);
  self.rangeSlider.value = self.rangeSlider.lowerBound;
  self.rangeSlider.minimumBoundsRange = MIN(0.1, assetDuration);
  self.rangeSlider.maximumBoundsRange = NFBMaxVideoDuration;
  [self.rangeSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
  [self.rangeSlider addTarget:self action:@selector(sliderEditingEnded) forControlEvents:UIControlEventEditingDidEnd];

  self.activity = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  self.activity.translatesAutoresizingMaskIntoConstraints = NO;
  self.activity.tintColor = NFBIPAOnMediaPrimaryTextColor();
  self.activity.contentMode = UIViewContentModeScaleAspectFit;
  self.activity.hidden = YES;

  self.trimControlsView = [[UIView alloc] init];
  self.trimControlsView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaBarAppearance(self.trimControlsView);
  [self.view addSubview:self.trimControlsView];

  UIView *controlsBorder = [[UIView alloc] init];
  controlsBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyOnMediaSeparatorAppearance(controlsBorder);
  [self.trimControlsView addSubview:controlsBorder];
  [self.trimControlsView addSubview:self.durationLabel];
  [self.trimControlsView addSubview:self.rangeSlider];

  self.trimToolbarButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.trimToolbarButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.trimToolbarButton.accessibilityLabel = @"Trim video";
  [self.trimToolbarButton addTarget:self action:@selector(showTrimControls) forControlEvents:UIControlEventTouchUpInside];
  NFBIPAApplyOnMediaIconButtonAppearance(self.trimToolbarButton, YES, 24.0);
  self.trimToolbarButton.titleLabel.font = NFBFont(13.0, NFBFontWeightHeavy);
  [self.trimToolbarButton setImage:NFBTemplateIcon(@"nfb_paintbrush_stroke") forState:UIControlStateNormal];
  self.trimToolbarButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, -4.0, 0.0, 4.0);
  self.trimToolbarButton.adjustsImageWhenHighlighted = NO;
  [self.trimControlsView addSubview:self.trimToolbarButton];
  UIButton *settings = [UIButton buttonWithType:UIButtonTypeCustom];
  settings.translatesAutoresizingMaskIntoConstraints = NO;
  settings.accessibilityLabel = @"Video settings";
  NFBIPAApplyOnMediaIconButtonAppearance(settings, NO, 24);
  [settings setImage:NFBTemplateIcon(@"nfb_settings_stroke") forState:UIControlStateNormal];
  [settings addTarget:self action:@selector(showVideoSettings) forControlEvents:UIControlEventTouchUpInside];
  [self.trimControlsView addSubview:settings];
  [self.view addSubview:self.activity];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.playerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.playerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.playerView.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.playerView.bottomAnchor constraintEqualToAnchor:self.trimControlsView.topAnchor],
    [self.trimPlayPauseButton.centerXAnchor constraintEqualToAnchor:self.playerView.centerXAnchor],
    [self.trimPlayPauseButton.centerYAnchor constraintEqualToAnchor:self.playerView.centerYAnchor],
    [self.trimPlayPauseButton.widthAnchor constraintEqualToConstant:64.0],
    [self.trimPlayPauseButton.heightAnchor constraintEqualToConstant:64.0],
    [self.trimMuteButton.trailingAnchor constraintEqualToAnchor:self.playerView.trailingAnchor constant:-18.0],
    [self.trimMuteButton.bottomAnchor constraintEqualToAnchor:self.playerView.bottomAnchor constant:-18.0],
    [self.trimMuteButton.widthAnchor constraintEqualToConstant:36.0],
    [self.trimMuteButton.heightAnchor constraintEqualToConstant:36.0],
    [self.trimControlsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.trimControlsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.trimControlsView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    [self.trimControlsView.heightAnchor constraintEqualToConstant:134.0],
    [controlsBorder.topAnchor constraintEqualToAnchor:self.trimControlsView.topAnchor],
    [controlsBorder.leadingAnchor constraintEqualToAnchor:self.trimControlsView.leadingAnchor],
    [controlsBorder.trailingAnchor constraintEqualToAnchor:self.trimControlsView.trailingAnchor],
    [controlsBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.durationLabel.bottomAnchor constraintEqualToAnchor:self.trimControlsView.topAnchor constant:-4.0],
    [self.durationLabel.centerXAnchor constraintEqualToAnchor:self.trimControlsView.centerXAnchor],
    [self.durationLabel.widthAnchor constraintGreaterThanOrEqualToConstant:96.0],
    [self.durationLabel.heightAnchor constraintEqualToConstant:28.0],
    [self.rangeSlider.topAnchor constraintEqualToAnchor:self.trimControlsView.topAnchor],
    [self.rangeSlider.leadingAnchor constraintEqualToAnchor:self.trimControlsView.leadingAnchor],
    [self.rangeSlider.trailingAnchor constraintEqualToAnchor:self.trimControlsView.trailingAnchor],
    [self.rangeSlider.heightAnchor constraintEqualToConstant:90.0],
    [self.trimToolbarButton.topAnchor constraintEqualToAnchor:self.rangeSlider.bottomAnchor constant:0.0],
    [NSLayoutConstraint constraintWithItem:self.trimToolbarButton attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.trimControlsView attribute:NSLayoutAttributeTrailing multiplier:1.0/3.0 constant:0],
    [self.trimToolbarButton.heightAnchor constraintEqualToConstant:44.0],
    [self.trimToolbarButton.widthAnchor constraintEqualToConstant:44.0],
    [settings.centerYAnchor constraintEqualToAnchor:self.trimToolbarButton.centerYAnchor],
    [NSLayoutConstraint constraintWithItem:settings attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.trimControlsView attribute:NSLayoutAttributeTrailing multiplier:2.0/3.0 constant:0],
    [settings.widthAnchor constraintEqualToConstant:44], [settings.heightAnchor constraintEqualToConstant:44],
    [self.activity.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.activity.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [self.activity.widthAnchor constraintEqualToConstant:28.0],
    [self.activity.heightAnchor constraintEqualToConstant:28.0]
  ]];

  self.durationLabel.hidden = YES;
  [self generateTrimThumbnailsIfNeeded];
  [self attachTimeObserver];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  ((AVPlayerLayer *)self.playerView.layer.sublayers.firstObject).frame = self.playerView.bounds;
  [self generateTrimThumbnailsIfNeeded];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (!self.cancelled && !self.exporting) [self startTrimPlayback];
}
- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated]; [NFBMediaAudioSession stopPlayer:self.player];
}
- (void)startTrimPlayback {
  [self.player play]; self.trimPlayPauseButton.hidden = YES;
}
- (void)sliderChanged {
  [self.player pause];
  self.durationLabel.hidden = NO;
  self.durationLabel.text = [NSString stringWithFormat:@"%.1fs selected", self.rangeSlider.upperBound - self.rangeSlider.lowerBound];
  NSTimeInterval position = self.rangeSlider.trackingBound == 2 ? self.rangeSlider.upperBound : self.rangeSlider.trackingBound == 3 ? self.rangeSlider.value : self.rangeSlider.lowerBound;
  [self.player seekToTime:CMTimeMakeWithSeconds(position, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
  self.trimPlayPauseButton.hidden = YES;
}
- (void)sliderEditingEnded {
  self.durationLabel.hidden = YES;
  self.rangeSlider.value = self.rangeSlider.lowerBound;
  [self.player seekToTime:CMTimeMakeWithSeconds(self.rangeSlider.lowerBound, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    dispatch_async(dispatch_get_main_queue(), ^{ if (finished && !self.cancelled && !self.exporting) [self startTrimPlayback]; });
  }];
}
- (void)trimPlayPauseTapped {
  if (self.exporting) return;
  if (self.player.rate == 0) [self sliderEditingEnded];
  else { [self.player pause]; self.trimPlayPauseButton.hidden = NO; self.trimPlayPauseButton.accessibilityLabel = @"Play"; }
}
- (void)trimMuteTapped {
  BOOL muted = !self.player.muted;
  [NFBMediaAudioSession setMuted:muted forPlayer:self.player];
  [self.trimMuteButton setImage:NFBTemplateIcon(self.player.muted ? @"nfb_speaker_off" : @"nfb_speaker") forState:UIControlStateNormal];
  self.trimMuteButton.accessibilityLabel = self.player.muted ? @"Unmute preview" : @"Mute preview";
}
- (void)showTrimControls { UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.rangeSlider); }
- (void)showVideoSettings {
  [self.player pause]; self.trimPlayPauseButton.hidden = NO;
  NFBMediaContentSettingsController *settings = [[NFBMediaContentSettingsController alloc] initWithStyle:UITableViewStylePlain];
  settings.labels = self.contentWarnings;
  __weak typeof(self) weakSelf = self;
  settings.completionHandler = ^(NSArray<NSString *> *labels) { weakSelf.contentWarnings = labels; };
  [self.navigationController pushViewController:settings animated:YES];
}

- (void)cancelTapped {
  self.cancelled = YES;
  [self.exporter cancelExport];
  [NFBMediaAudioSession stopPlayer:self.player];
  [self detachTimeObserver];
  [self.delegate videoTrimViewControllerDidCancel:self];
}

- (void)trimTapped {
  if (self.exporting) return;
  self.exporting = YES;
  [NFBMediaAudioSession stopPlayer:self.player];
  self.trimControlsView.userInteractionEnabled = NO;
  self.playerView.userInteractionEnabled = NO;
  NFBStartLoadingAnimation(self.activity);
  self.navigationItem.rightBarButtonItem.enabled = NO;
  [self exportSelectionWithPreset:AVAssetExportPresetHighestQuality];
}
- (void)exportSelectionWithPreset:(NSString *)preset {
  NSTimeInterval start = self.rangeSlider.lowerBound;
  NSTimeInterval duration = MIN(self.rangeSlider.upperBound - start, NFBMaxVideoDuration);
  NSURL *output = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"nfb-trim-%@.mp4", NSUUID.UUID.UUIDString]]];
  AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:self.asset presetName:preset];
  if (!exporter) { [self finishExportWithError:@"This video format could not be exported."]; return; }
  self.exporter = exporter; exporter.outputURL = output; exporter.outputFileType = AVFileTypeMPEG4;
  exporter.shouldOptimizeForNetworkUse = YES;
  exporter.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600), CMTimeMakeWithSeconds(duration, 600));
  if (self.mutedForExport) exporter.audioMix = [self silentAudioMix];
  [exporter exportAsynchronouslyWithCompletionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self.cancelled) { [NSFileManager.defaultManager removeItemAtURL:output error:nil]; return; }
      if (exporter.status != AVAssetExportSessionStatusCompleted) {
        [NSFileManager.defaultManager removeItemAtURL:output error:nil];
        [self finishExportWithError:exporter.error.localizedDescription ?: @"Video trimming failed."]; return;
      }
      NSNumber *bytes; [output getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
      AVAsset *result = [AVURLAsset URLAssetWithURL:output options:nil];
      NSTimeInterval actualDuration = CMTimeGetSeconds(result.duration);
      if (bytes.unsignedLongLongValue > NFBMaxVideoUploadBytes && [preset isEqual:AVAssetExportPresetHighestQuality]) {
        [NSFileManager.defaultManager removeItemAtURL:output error:nil];
        [self exportSelectionWithPreset:AVAssetExportPresetMediumQuality]; return;
      }
      if (!NFBVideoUploadIsValid(bytes.unsignedLongLongValue, actualDuration)) {
        [NSFileManager.defaultManager removeItemAtURL:output error:nil];
        [self finishExportWithError:@"Select a shorter clip. Videos must be up to 10 minutes and 300 MB."]; return;
      }
      AVAssetTrack *track = [result tracksWithMediaType:AVMediaTypeVideo].firstObject;
      CGSize size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
      [self finishExportWithError:nil];
      [self.delegate videoTrimViewController:self didFinishWithURL:output thumbnail:[self thumbnailAtTime:start] duration:actualDuration dimensions:CGSizeMake(fabs(size.width), fabs(size.height))];
    });
  }];
}
- (void)finishExportWithError:(NSString *)error {
  self.exporting = NO; self.exporter = nil;
  self.trimControlsView.userInteractionEnabled = YES; self.playerView.userInteractionEnabled = YES;
  NFBStopLoadingAnimation(self.activity); self.activity.hidden = YES;
  self.navigationItem.rightBarButtonItem.enabled = YES;
  if (error) [self showTrimError:error];
}

- (void)generateTrimThumbnailsIfNeeded {
  if (self.generatedTrimThumbnails || CGRectGetWidth(self.rangeSlider.bounds) <= 0.0) return;
  self.generatedTrimThumbnails = YES;
  NSUInteger count = MAX(8, (NSUInteger)ceil(CGRectGetWidth(self.rangeSlider.bounds) / 44.0));
  NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:count];
  NSTimeInterval duration = CMTimeGetSeconds(self.asset.duration);
  if (!isfinite(duration) || duration <= 0.0) duration = 1.0;

  AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.asset];
  generator.appliesPreferredTrackTransform = YES;
  generator.maximumSize = CGSizeMake(160.0, 160.0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
  for (NSUInteger index = 0; index < count; index++) {
    NSTimeInterval position = duration * ((CGFloat)index / MAX((CGFloat)count - 1.0, 1.0));
    CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(position, 600) actualTime:NULL error:nil];
    if (!imageRef) continue;
    [images addObject:[UIImage imageWithCGImage:imageRef]];
    CGImageRelease(imageRef);
  }
  dispatch_async(dispatch_get_main_queue(), ^{ if (!self.cancelled) self.rangeSlider.thumbnailImages = images; });
  });
}

- (void)attachTimeObserver {
  if (self.timeObserver) return;
  __weak typeof(self) weakSelf = self;
  self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 20)
                                                                queue:dispatch_get_main_queue()
                                                           usingBlock:^(CMTime time) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    NSTimeInterval seconds = CMTimeGetSeconds(time);
    if (!isfinite(seconds)) return;
    if (strongSelf.rangeSlider.tracking) return;
    strongSelf.rangeSlider.value = seconds;
    if (seconds >= strongSelf.rangeSlider.upperBound) {
      [strongSelf.player pause];
      [strongSelf.player seekToTime:CMTimeMakeWithSeconds(strongSelf.rangeSlider.lowerBound, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
      strongSelf.rangeSlider.value = strongSelf.rangeSlider.lowerBound;
      strongSelf.trimPlayPauseButton.hidden = NO;
      [strongSelf.trimPlayPauseButton setImage:NFBTemplateIcon(@"nfb_play") forState:UIControlStateNormal];
      strongSelf.trimPlayPauseButton.accessibilityLabel = @"Play";
    }
  }];
}

- (void)detachTimeObserver {
  if (!self.timeObserver) return;
  [self.player removeTimeObserver:self.timeObserver];
  self.timeObserver = nil;
}

- (AVAudioMix *)silentAudioMix {
  NSArray<AVAssetTrack *> *tracks = [self.asset tracksWithMediaType:AVMediaTypeAudio];
  if (tracks.count == 0) return nil;
  NSMutableArray<AVAudioMixInputParameters *> *parameters = [NSMutableArray arrayWithCapacity:tracks.count];
  for (AVAssetTrack *track in tracks) {
    AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
    [input setVolume:0.0 atTime:kCMTimeZero];
    [parameters addObject:input];
  }
  AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
  mix.inputParameters = parameters;
  return mix;
}

- (UIImage *)thumbnailAtTime:(NSTimeInterval)time {
  AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.asset];
  generator.appliesPreferredTrackTransform = YES;
  CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(time, 600) actualTime:NULL error:nil];
  if (!imageRef) return [UIImage new];
  UIImage *image = [UIImage imageWithCGImage:imageRef];
  CGImageRelease(imageRef);
  return image;
}

- (CGSize)videoDimensions {
  AVAssetTrack *track = [[self.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  if (!track) return CGSizeMake(1.0, 1.0);
  CGSize size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
  return CGSizeMake(fabs(size.width), fabs(size.height));
}

- (void)showTrimError:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Video failed" message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
  [self.exporter cancelExport];
  [NFBMediaAudioSession stopPlayer:self.player];
  [self detachTimeObserver];
}

@end

@interface NFBGIFCategoryCell : UICollectionViewCell
- (void)configureWithTitle:(NSString *)title colors:(NSArray<UIColor *> *)colors previewURL:(NSString *)previewURL;
@end

@interface NFBGIFCategoryCell ()
@property (nonatomic, strong) UIView *gradientView;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSURLSessionDataTask *previewTask;
@property (nonatomic, copy) NSString *previewURLString;
@end

@implementation NFBGIFCategoryCell

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.contentView.layer.cornerRadius = 0.0;
    self.contentView.backgroundColor = NFBIPAColor(NFBIPAColorRoleFaintBackground);
    self.contentView.layer.masksToBounds = YES;

    _previewImageView = [[UIImageView alloc] init];
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    _previewImageView.clipsToBounds = YES;

    _gradientView = [[UIView alloc] init];
    _gradientView.translatesAutoresizingMaskIntoConstraints = NO;
    _gradientView.userInteractionEnabled = NO;

    _gradientLayer = [CAGradientLayer layer];
    _gradientLayer.startPoint = CGPointMake(0.5, 0.0);
    _gradientLayer.endPoint = CGPointMake(0.5, 1.0);
    _gradientLayer.colors = @[
      (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
      (id)[UIColor colorWithWhite:0.0 alpha:0.8].CGColor
    ];
    [_gradientView.layer addSublayer:_gradientLayer];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = NFBFont(20.0, NFBFontWeightRegular);
    _titleLabel.textAlignment = NSTextAlignmentNatural;
    _titleLabel.numberOfLines = 2;
    _titleLabel.adjustsFontSizeToFitWidth = NO;
    _titleLabel.backgroundColor = UIColor.clearColor;

    [self.contentView addSubview:_previewImageView];
    [self.contentView addSubview:_gradientView];
    [self.contentView addSubview:_titleLabel];
    [NSLayoutConstraint activateConstraints:@[
      [_previewImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
      [_previewImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
      [_previewImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [_previewImageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
      [_gradientView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
      [_gradientView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
      [_gradientView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [_gradientView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
      [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
      [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
      [_titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0]
    ]];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  [self.previewTask cancel];
  self.previewTask = nil;
  self.previewURLString = nil;
  self.previewImageView.image = nil;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  self.gradientLayer.frame = self.gradientView.bounds;
}

- (void)configureWithTitle:(NSString *)title colors:(NSArray<UIColor *> *)colors previewURL:(NSString *)previewURL {
  self.titleLabel.text = title;
  (void)colors;
  self.previewImageView.image = nil;
  self.accessibilityLabel = title;
  [self loadPreviewURL:previewURL];
}

- (void)loadPreviewURL:(NSString *)previewURL {
  [self.previewTask cancel];
  self.previewTask = nil;
  self.previewURLString = previewURL ?: @"";
  if (self.previewURLString.length == 0) return;

  UIImage *cached = [[self.class previewCache] objectForKey:self.previewURLString];
  if (cached) {
    self.previewImageView.image = cached;
    return;
  }

  NSURL *url = [NSURL URLWithString:self.previewURLString];
  if (!url) return;
  __weak typeof(self) weakSelf = self;
  self.previewTask = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = NFBGIFPreviewImageWithData(data);
    if (!image) return;
    [[weakSelf.class previewCache] setObject:image forKey:previewURL cost:NFBGIFPreviewCost(image)];
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf.previewURLString isEqualToString:previewURL]) return;
      strongSelf.previewImageView.image = image;
    });
  }];
  [self.previewTask resume];
}

+ (NSCache *)previewCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 40;
    cache.totalCostLimit = 16 * 1024 * 1024;
  });
  return cache;
}

@end

@interface NFBGIFResultCell : UICollectionViewCell
@property (nonatomic, assign) BOOL autoplayEnabled;
- (void)configureWithItem:(NSDictionary *)item;
@end

@interface NFBGIFResultCell ()
@property (nonatomic, strong) UIImage *animatedPreview;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) NSURLSessionDataTask *previewTask;
@property (nonatomic, copy) NSString *previewURLString;
@end

@implementation NFBGIFResultCell

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.contentView.backgroundColor = NFBColorElevatedBackground();
    self.contentView.clipsToBounds = YES;

    _imageView = [[UIImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.clipsToBounds = YES;
    [self.contentView addSubview:_imageView];

    [NSLayoutConstraint activateConstraints:@[
      [_imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
      [_imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
      [_imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [_imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]
    ]];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  [self.previewTask cancel];
  self.previewTask = nil;
  self.previewURLString = nil;
  self.imageView.image = nil;
  self.animatedPreview = nil;
}

- (void)configureWithItem:(NSDictionary *)item {
  NSString *title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"GIF";
  self.imageView.image = nil;
  self.animatedPreview = nil;
  self.accessibilityLabel = title;
  NSString *previewURL = [item[@"previewURL"] isKindOfClass:NSString.class] ? item[@"previewURL"] : @"";
  [self loadPreviewURL:previewURL];
}

- (void)loadPreviewURL:(NSString *)previewURL {
  [self.previewTask cancel];
  self.previewTask = nil;
  self.previewURLString = previewURL ?: @"";
  if (self.previewURLString.length == 0) return;

  UIImage *cached = [[self.class previewCache] objectForKey:self.previewURLString];
  if (cached) {
    [self displayPreview:cached];
    return;
  }

  NSURL *url = [NSURL URLWithString:self.previewURLString];
  if (!url) return;
  __weak typeof(self) weakSelf = self;
  self.previewTask = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = NFBGIFPreviewImageWithData(data);
    if (!image) return;
    [[weakSelf.class previewCache] setObject:image forKey:previewURL cost:NFBGIFPreviewCost(image)];
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf.previewURLString isEqualToString:previewURL]) return;
      [strongSelf displayPreview:image];
    });
  }];
  [self.previewTask resume];
}

+ (NSCache *)previewCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 80;
    cache.totalCostLimit = 32 * 1024 * 1024;
  });
  return cache;
}

- (void)displayPreview:(UIImage *)image {
  self.animatedPreview = image;
  self.imageView.image = self.autoplayEnabled ? image : (image.images.firstObject ?: image);
}

- (void)setAutoplayEnabled:(BOOL)enabled {
  _autoplayEnabled = enabled;
  if (self.animatedPreview) [self displayPreview:self.animatedPreview];
}

@end

@class NFBGIFResultsLayout;

@protocol NFBGIFResultsLayoutDelegate <NSObject>
- (CGFloat)gifResultsLayout:(NFBGIFResultsLayout *)layout aspectRatioForItemAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface NFBGIFResultsLayout : UICollectionViewLayout
@property (nonatomic, weak) id<NFBGIFResultsLayoutDelegate> delegate;
@end

@interface NFBGIFResultsLayout ()
@property (nonatomic, copy) NSArray<UICollectionViewLayoutAttributes *> *cachedAttributes;
@property (nonatomic, assign) CGSize cachedContentSize;
@end

@implementation NFBGIFResultsLayout

- (instancetype)init {
  self = [super init];
  if (self) {
    _cachedAttributes = @[];
    _cachedContentSize = CGSizeZero;
  }
  return self;
}

- (void)prepareLayout {
  [super prepareLayout];
  NSUInteger count = [self.collectionView numberOfItemsInSection:0];
  CGFloat width = CGRectGetWidth(self.collectionView.bounds);
  if (!count || width <= 0) {
    self.cachedAttributes = @[];
    self.cachedContentSize = CGSizeMake(MAX(0, width), 0);
    return;
  }
  double *ratios = calloc(count, sizeof(double));
  if (!ratios) return;
  for (NSUInteger index = 0; index < count; index++) {
    ratios[index] = NFBGIFAspectRatio([self.delegate gifResultsLayout:self aspectRatioForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]]);
  }
  NSMutableArray *attributes = [NSMutableArray arrayWithCapacity:count];
  CGFloat y = 0;
  NSUInteger start = 0;
  BOOL rtl = self.collectionView.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  while (start < count) {
    NFBGIFRow row = NFBGIFNextRow(ratios, count, start, width);
    CGFloat x = 0;
    for (NSUInteger index = start; index < row.end; index++) {
      CGFloat itemWidth = MIN(width - x, ratios[index] * row.height);
      UICollectionViewLayoutAttributes *item = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
      item.frame = CGRectMake(rtl ? width - x - itemWidth : x, y, itemWidth, row.height);
      [attributes addObject:item];
      x += itemWidth + 1.0;
    }
    start = row.end;
    y += row.height + 1.0;
  }
  free(ratios);
  self.cachedAttributes = attributes;
  self.cachedContentSize = CGSizeMake(width, ceil(MAX(0, y - 1.0)));
}

- (CGSize)collectionViewContentSize {
  return self.cachedContentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
  NSMutableArray *visible = [NSMutableArray array];
  for (UICollectionViewLayoutAttributes *attribute in self.cachedAttributes) {
    if (CGRectIntersectsRect(attribute.frame, rect)) [visible addObject:attribute];
  }
  return visible;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.item >= self.cachedAttributes.count) return nil;
  return self.cachedAttributes[indexPath.item];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
  return fabs(CGRectGetWidth(newBounds) - CGRectGetWidth(self.collectionView.bounds)) > 0.5;
}

@end

@interface NFBGIFPickerViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate>
@property (nonatomic, weak) id<NFBGIFPickerViewControllerDelegate> delegate;
@end

@interface NFBGIFPickerViewController () <NFBGIFResultsLayoutDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *categories;
@property (nonatomic, copy) NSArray<NSDictionary *> *gifItems;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleGIFItems;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIButton *searchClearButton;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) NSURLSessionDataTask *searchTask;
@property (nonatomic, assign) BOOL showingGIFItems;
@property (nonatomic, assign) BOOL loadingGIFItems;
@property (nonatomic, copy) NSString *initialQuery;
@property (nonatomic, strong) UIView *autoplayBar;
@property (nonatomic, strong) UISwitch *autoplaySwitch;
@property (nonatomic, strong) NSLayoutConstraint *autoplayHeightConstraint;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) NSMutableArray<NSURLSessionDataTask *> *categoryTasks;
@property (nonatomic, copy) NSString *nextCursor;
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic, assign) NSUInteger searchGeneration;

@end

@implementation NFBGIFPickerViewController

- (instancetype)init {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _categories = [self.class gifCategories];
    _gifItems = @[];
    _visibleGIFItems = @[];
  }
  return self;
}

- (instancetype)initWithQuery:(NSString *)query title:(NSString *)title {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _showingGIFItems = YES;
    _initialQuery = [query copy] ?: @"";
    self.title = [title copy] ?: @"Choose GIF";
    _categories = [self.class gifCategories];
    _gifItems = @[];
    _visibleGIFItems = @[];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.categoryTasks = [NSMutableArray array];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  self.title = self.title.length > 0 ? self.title : @"GIFs";
  self.view.backgroundColor = NFBColorBackground();
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
  self.navigationItem.titleView = NFBTitleView(self.title, nil);

  UIView *searchContainer = [[UIView alloc] init];
  searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
  searchContainer.backgroundColor = NFBColorBackground();
  [self.view addSubview:searchContainer];

  self.searchField = [[UITextField alloc] init];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.delegate = self;
  NFBIPAApplySearchTextFieldAppearance(self.searchField, @"Search for GIFs");
  self.searchField.backgroundColor = NFBIPASearchFieldBackgroundColor();
  self.searchField.text = self.initialQuery ?: @"";
  self.searchField.returnKeyType = UIReturnKeySearch;
  self.searchField.autocorrectionType = UITextAutocorrectionTypeNo;
  self.searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.searchField.layer.cornerRadius = 18.0;
  self.searchField.clipsToBounds = YES;
  [self.searchField addTarget:self action:@selector(searchFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

  UIImageView *searchIcon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_search")];
  searchIcon.tintColor = NFBColorSecondaryText();
  searchIcon.contentMode = UIViewContentModeScaleAspectFit;
  UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 38.0, 36.0)];
  searchIcon.frame = CGRectMake(12.0, 9.0, 18.0, 18.0);
  [leftView addSubview:searchIcon];
  self.searchField.leftView = leftView;
  self.searchField.leftViewMode = UITextFieldViewModeAlways;

  self.searchClearButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.searchClearButton.frame = CGRectMake(0.0, 0.0, 36.0, 36.0);
  self.searchClearButton.tintColor = NFBColorSecondaryText();
  [self.searchClearButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  self.searchClearButton.imageEdgeInsets = UIEdgeInsetsMake(9.0, 9.0, 9.0, 9.0);
  [self.searchClearButton addTarget:self action:@selector(clearSearchTapped) forControlEvents:UIControlEventTouchUpInside];
  self.searchField.rightView = self.searchClearButton;
  self.searchField.rightViewMode = self.searchField.text.length > 0 ? UITextFieldViewModeAlways : UITextFieldViewModeNever;
  [searchContainer addSubview:self.searchField];

  UIView *bottomBorder = [[UIView alloc] init];
  bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(bottomBorder);
  [searchContainer addSubview:bottomBorder];

  UICollectionViewLayout *collectionLayout = nil;
  if (self.showingGIFItems) {
    NFBGIFResultsLayout *resultsLayout = [[NFBGIFResultsLayout alloc] init];
    resultsLayout.delegate = self;
    collectionLayout = resultsLayout;
  } else {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 1.0;
    layout.minimumInteritemSpacing = 1.0;
    layout.sectionInset = UIEdgeInsetsZero;
    collectionLayout = layout;
  }

  self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:collectionLayout];
  self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
  self.collectionView.backgroundColor = NFBColorBackground();
  self.collectionView.alwaysBounceVertical = YES;
  self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  self.collectionView.dataSource = self;
  self.collectionView.delegate = self;
  [self.collectionView registerClass:NFBGIFCategoryCell.class forCellWithReuseIdentifier:@"gifCategory"];
  [self.collectionView registerClass:NFBGIFResultCell.class forCellWithReuseIdentifier:@"gifResult"];
  [self.view addSubview:self.collectionView];

  self.stateLabel = [[UILabel alloc] init];
  self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.stateLabel.textAlignment = NSTextAlignmentCenter;
  self.stateLabel.textColor = NFBColorSecondaryText();
  self.stateLabel.font = NFBFont(16.0, NFBFontWeightRegular);
  self.stateLabel.hidden = YES;
  [self.view addSubview:self.stateLabel];

  self.autoplayBar = [[UIView alloc] init];
  self.autoplayBar.translatesAutoresizingMaskIntoConstraints = NO;
  self.autoplayBar.clipsToBounds = YES;
  [self.view addSubview:self.autoplayBar];
  UILabel *autoplayLabel = [[UILabel alloc] init];
  autoplayLabel.translatesAutoresizingMaskIntoConstraints = NO;
  autoplayLabel.text = @"Autoplay GIFs";
  autoplayLabel.font = NFBFont(15.0, NFBFontWeightBold);
  autoplayLabel.textColor = NFBColorText();
  [self.autoplayBar addSubview:autoplayLabel];
  self.autoplaySwitch = [[UISwitch alloc] init];
  self.autoplaySwitch.translatesAutoresizingMaskIntoConstraints = NO;
  self.autoplaySwitch.on = ![NSUserDefaults.standardUserDefaults boolForKey:@"nfb_gif_autoplay_disabled"];
  self.autoplaySwitch.onTintColor = NFBColorAccent();
  self.autoplaySwitch.accessibilityLabel = @"Autoplay GIFs";
  [self.autoplaySwitch addTarget:self action:@selector(autoplayChanged) forControlEvents:UIControlEventValueChanged];
  [self.autoplayBar addSubview:self.autoplaySwitch];
  self.autoplayHeightConstraint = [self.autoplayBar.heightAnchor constraintEqualToConstant:self.showingGIFItems ? 48.0 : 0.0];
  self.autoplayBar.hidden = !self.showingGIFItems;
  self.retryButton = [NFBPillButton buttonWithType:UIButtonTypeSystem];
  self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.retryButton setTitle:@"Try again" forState:UIControlStateNormal];
  [self.retryButton addTarget:self action:@selector(loadResultsForPendingSearch) forControlEvents:UIControlEventTouchUpInside];
  NFBIPAApplyButtonAppearance(self.retryButton, NFBIPAButtonStylePrimary, NFBIPAButtonSizeSmall);
  self.retryButton.hidden = YES;
  [self.view addSubview:self.retryButton];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [searchContainer.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [searchContainer.heightAnchor constraintEqualToConstant:52.0],
    [self.searchField.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor constant:12.0],
    [self.searchField.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor constant:-12.0],
    [self.searchField.centerYAnchor constraintEqualToAnchor:searchContainer.centerYAnchor],
    [self.searchField.heightAnchor constraintEqualToConstant:36.0],
    [bottomBorder.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor],
    [bottomBorder.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor],
    [bottomBorder.bottomAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
    [bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.autoplayBar.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
    [self.autoplayBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.autoplayBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    self.autoplayHeightConstraint,
    [autoplayLabel.leadingAnchor constraintEqualToAnchor:self.autoplayBar.leadingAnchor constant:12.0],
    [autoplayLabel.centerYAnchor constraintEqualToAnchor:self.autoplayBar.centerYAnchor],
    [autoplayLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.autoplaySwitch.leadingAnchor constant:-12.0],
    [self.autoplaySwitch.trailingAnchor constraintEqualToAnchor:self.autoplayBar.trailingAnchor constant:-12.0],
    [self.autoplaySwitch.centerYAnchor constraintEqualToAnchor:self.autoplayBar.centerYAnchor],
    [self.collectionView.topAnchor constraintEqualToAnchor:self.autoplayBar.bottomAnchor],
    [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.stateLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28.0],
    [self.stateLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28.0],
    [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.collectionView.centerYAnchor],
    [self.retryButton.topAnchor constraintEqualToAnchor:self.stateLabel.bottomAnchor constant:16.0],
    [self.retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
  ]];

  if (self.showingGIFItems) [self loadResultsForQuery:self.initialQuery];
  else [self refreshCategoryPreviews];
}

- (void)cancelTapped {
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  self.searchGeneration++;
  [self.searchTask cancel];
  for (NSURLSessionDataTask *task in self.categoryTasks) [task cancel];
  [self.delegate gifPickerDidCancel:self];
}

- (void)dealloc {
  [self.searchTask cancel];
  for (NSURLSessionDataTask *task in self.categoryTasks) [task cancel];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
  (void)collectionView; (void)section;
  return self.showingGIFItems ? self.visibleGIFItems.count : self.categories.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
  if (self.showingGIFItems) {
    NFBGIFResultCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"gifResult" forIndexPath:indexPath];
    cell.autoplayEnabled = self.autoplaySwitch.on;
    if (indexPath.item < self.visibleGIFItems.count) [cell configureWithItem:self.visibleGIFItems[indexPath.item]];
    return cell;
  }

  NFBGIFCategoryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"gifCategory" forIndexPath:indexPath];
  NSDictionary *category = self.categories[indexPath.item];
  NSArray<UIColor *> *colors = [category[@"colors"] isKindOfClass:NSArray.class] ? category[@"colors"] : @[];
  NSString *previewURL = [category[@"previewURL"] isKindOfClass:NSString.class] ? category[@"previewURL"] : @"";
  [cell configureWithTitle:category[@"title"] colors:colors previewURL:previewURL];
  return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
  (void)collectionViewLayout; (void)indexPath;
  if (self.showingGIFItems) {
    CGFloat width = floor((CGRectGetWidth(collectionView.bounds) - 18.0) / 3.0);
    return CGSizeMake(MAX(0.0, width), MAX(0.0, width));
  }
  CGFloat width = floor((CGRectGetWidth(collectionView.bounds) - 1.0) / 2.0);
  return CGSizeMake(MAX(0.0, width), MAX(0.0, width));
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  (void)collectionView;
  if (self.showingGIFItems) {
    if (indexPath.item >= self.visibleGIFItems.count) return;
    [self.delegate gifPicker:self didSelectGIFItem:self.visibleGIFItems[indexPath.item]];
    return;
  }

  if (indexPath.item >= self.categories.count) return;
  NSDictionary *category = self.categories[indexPath.item];
  NSString *query = [category[@"searchTerm"] isKindOfClass:NSString.class] ? category[@"searchTerm"] : category[@"title"];
  [self.searchField resignFirstResponder];
  [self setShowingResults:YES];
  [self loadResultsForQuery:query];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  [textField resignFirstResponder];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadResultsForPendingSearch) object:nil];
  [self loadResultsForPendingSearch];
  return YES;
}

- (void)searchFieldDidChange:(UITextField *)textField {
  NSString *query = [textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  self.searchField.rightViewMode = query.length ? UITextFieldViewModeAlways : UITextFieldViewModeNever;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadResultsForPendingSearch) object:nil];
  [self.searchTask cancel];
  self.searchGeneration++;
  self.initialQuery = query;
  self.nextCursor = @"";
  self.loadError = @"";
  self.gifItems = @[];
  self.visibleGIFItems = @[];
  self.loadingGIFItems = query.length > 0;
  [self setShowingResults:query.length > 0];
  [self updateStateLabel];
  [self.collectionView reloadData];
  if (query.length) [self performSelector:@selector(loadResultsForPendingSearch) withObject:nil afterDelay:0.28];
}

- (void)setShowingResults:(BOOL)showing {
  if (self.showingGIFItems != showing) {
    self.showingGIFItems = showing;
    if (showing) {
      NFBGIFResultsLayout *layout = [[NFBGIFResultsLayout alloc] init];
      layout.delegate = self;
      [self.collectionView setCollectionViewLayout:layout animated:NO];
    } else {
      UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
      layout.minimumInteritemSpacing = 1.0;
      layout.minimumLineSpacing = 1.0;
      [self.collectionView setCollectionViewLayout:layout animated:NO];
    }
  }
  self.autoplayBar.hidden = !showing;
  self.autoplayHeightConstraint.constant = showing ? 48.0 : 0.0;
  [self.collectionView reloadData];
}

- (void)backTapped {
  if (self.showingGIFItems) {
    self.searchField.text = @"";
    [self searchFieldDidChange:self.searchField];
    [self.searchField resignFirstResponder];
  } else [self cancelTapped];
}

- (void)autoplayChanged {
  [NSUserDefaults.standardUserDefaults setBool:!self.autoplaySwitch.on forKey:@"nfb_gif_autoplay_disabled"];
  for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
    if ([cell isKindOfClass:NFBGIFResultCell.class]) ((NFBGIFResultCell *)cell).autoplayEnabled = self.autoplaySwitch.on;
  }
}

- (void)themeChanged:(NSNotification *)notification {
  self.searchField.backgroundColor = NFBIPASearchFieldBackgroundColor();
  [self.collectionView reloadData];
}

- (void)clearSearchTapped {
  self.searchField.text = @"";
  [self searchFieldDidChange:self.searchField];
  [self.searchField becomeFirstResponder];
}

- (void)loadResultsForPendingSearch {
  [self loadResultsForQuery:self.initialQuery ?: @""];
}

- (void)loadResultsForQuery:(NSString *)query {
  NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  if (!trimmed.length) return;
  self.initialQuery = trimmed;
  self.searchField.text = trimmed;
  self.searchField.rightViewMode = UITextFieldViewModeAlways;
  [self setShowingResults:YES];
  [self.searchTask cancel];
  self.searchGeneration++;
  self.gifItems = @[];
  self.visibleGIFItems = @[];
  self.nextCursor = @"";
  [self.collectionView reloadData];
  [self fetchResultsWithCursor:nil];
}

- (void)fetchResultsWithCursor:(NSString *)cursor {
  self.loadingGIFItems = YES;
  self.loadError = @"";
  [self updateStateLabel];
  NSUInteger generation = self.searchGeneration;
  __weak typeof(self) weakSelf = self;
  self.searchTask = [NFBGIFService searchQuery:self.initialQuery limit:45 cursor:cursor completion:^(NSArray<NSDictionary *> *items, NSString *next, NSError *error) {
    __strong typeof(weakSelf) self = weakSelf;
    if (!self || generation != self.searchGeneration) return;
    self.loadingGIFItems = NO;
    self.loadError = error ? @"GIFs couldn't load. Try again." : @"";
    self.nextCursor = [next isEqualToString:cursor] ? @"" : next;
    NSMutableArray *combined = [self.gifItems mutableCopy] ?: [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *item in combined) [ids addObject:item[@"assetURL"]];
    for (NSDictionary *item in items) {
      if (![ids containsObject:item[@"assetURL"]]) { [combined addObject:item]; [ids addObject:item[@"assetURL"]]; }
    }
    self.gifItems = combined;
    self.visibleGIFItems = combined;
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    [self updateStateLabel];
  }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (self.showingGIFItems && !self.loadingGIFItems && !self.loadError.length && self.nextCursor.length &&
      scrollView.contentOffset.y + CGRectGetHeight(scrollView.bounds) > scrollView.contentSize.height - 300.0) {
    [self fetchResultsWithCursor:self.nextCursor];
  }
}

- (void)refreshCategoryPreviews {
  for (NSUInteger index = 0; index < self.categories.count; index++) {
    NSDictionary *category = self.categories[index];
    NSString *query = [category[@"searchTerm"] isKindOfClass:NSString.class] ? category[@"searchTerm"] : @"";
    if (query.length == 0) continue;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NFBGIFService searchQuery:query limit:1 cursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *next, NSError *error) {
      NSDictionary *item = items.firstObject;
      NSString *previewURL = [item[@"previewURL"] isKindOfClass:NSString.class] ? item[@"previewURL"] : @"";
      if (previewURL.length == 0) return;
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || index >= strongSelf.categories.count) return;
        NSMutableArray *next = [strongSelf.categories mutableCopy];
        NSMutableDictionary *updated = [next[index] mutableCopy];
        updated[@"previewURL"] = previewURL;
        next[index] = updated;
        strongSelf.categories = next;
        if (!strongSelf.showingGIFItems) [strongSelf.collectionView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
      });
    }];
    [self.categoryTasks addObject:task];
  }
}

- (void)updateStateLabel {
  self.retryButton.hidden = !self.loadError.length;
  if (!self.showingGIFItems) {
    self.stateLabel.hidden = YES;
    return;
  }
  if (self.loadError.length && self.visibleGIFItems.count == 0) {
    self.stateLabel.text = self.loadError;
    self.stateLabel.hidden = NO;
  } else if (self.loadingGIFItems && self.visibleGIFItems.count == 0) {
    self.stateLabel.text = @"Loading GIFs";
    self.stateLabel.hidden = NO;
  } else if (self.visibleGIFItems.count == 0) {
    self.stateLabel.text = @"No GIFs found";
    self.stateLabel.hidden = NO;
  } else {
    self.stateLabel.hidden = YES;
  }
}

- (CGFloat)gifResultsLayout:(NFBGIFResultsLayout *)layout aspectRatioForItemAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.item >= self.visibleGIFItems.count) return 1.0;
  NSDictionary *item = self.visibleGIFItems[indexPath.item];
  return [item[@"width"] doubleValue] / MAX(1.0, [item[@"height"] doubleValue]);
}

+ (NSArray<NSDictionary *> *)gifCategories {
  NSArray<NSDictionary *> *base = @[
    @{@"title": @"Agree", @"searchTerm": @"agree"},
    @{@"title": @"Applause", @"searchTerm": @"applause"},
    @{@"title": @"Aww", @"searchTerm": @"aww"},
    @{@"title": @"Dance", @"searchTerm": @"dance"},
    @{@"title": @"Deal with it", @"searchTerm": @"deal with it"},
    @{@"title": @"Do not want", @"searchTerm": @"do not want"},
    @{@"title": @"Eww", @"searchTerm": @"eww"},
    @{@"title": @"Can't believe it", @"searchTerm": @"can't believe it"},
    @{@"title": @"Shocked", @"searchTerm": @"shocked"},
    @{@"title": @"Fist bump", @"searchTerm": @"fist bump"},
    @{@"title": @"You got this", @"searchTerm": @"you got this"},
    @{@"title": @"Happy dance", @"searchTerm": @"happy dance"},
    @{@"title": @"Love", @"searchTerm": @"love"},
    @{@"title": @"High five", @"searchTerm": @"high five"},
    @{@"title": @"Hug", @"searchTerm": @"hug"},
    @{@"title": @"I don't know", @"searchTerm": @"i don't know"},
    @{@"title": @"Kiss", @"searchTerm": @"kiss"},
    @{@"title": @"Mic drop", @"searchTerm": @"mic drop"},
    @{@"title": @"No", @"searchTerm": @"no"},
    @{@"title": @"Oh no", @"searchTerm": @"oh no"},
    @{@"title": @"Okay", @"searchTerm": @"okay"},
    @{@"title": @"Oops", @"searchTerm": @"oops"},
    @{@"title": @"Please", @"searchTerm": @"please"},
    @{@"title": @"Popcorn", @"searchTerm": @"popcorn"},
    @{@"title": @"Seriously?", @"searchTerm": @"seriously"},
    @{@"title": @"Scared", @"searchTerm": @"scared"},
    @{@"title": @"Surprised", @"searchTerm": @"surprised"},
    @{@"title": @"Sigh", @"searchTerm": @"sigh"},
    @{@"title": @"Slow clap", @"searchTerm": @"slow clap"},
    @{@"title": @"Sorry", @"searchTerm": @"sorry"},
    @{@"title": @"Thank you", @"searchTerm": @"thank you"},
    @{@"title": @"Thumbs down", @"searchTerm": @"thumbs down"},
    @{@"title": @"Thumbs up", @"searchTerm": @"thumbs up"},
    @{@"title": @"Want", @"searchTerm": @"want"},
    @{@"title": @"Win", @"searchTerm": @"win"},
    @{@"title": @"Wink", @"searchTerm": @"wink"},
    @{@"title": @"YOLO", @"searchTerm": @"yolo"},
    @{@"title": @"Yawn", @"searchTerm": @"yawn"},
    @{@"title": @"Yes", @"searchTerm": @"yes"},
    @{@"title": @"Way to go", @"searchTerm": @"way to go"}
  ];

  NSArray<NSArray<UIColor *> *> *colors = @[
    @[[UIColor colorWithRed:0.12 green:0.55 blue:0.95 alpha:1.0], [UIColor colorWithRed:0.00 green:0.74 blue:0.61 alpha:1.0]],
    @[[UIColor colorWithRed:0.95 green:0.36 blue:0.21 alpha:1.0], [UIColor colorWithRed:0.97 green:0.74 blue:0.18 alpha:1.0]],
    @[[UIColor colorWithRed:0.96 green:0.21 blue:0.54 alpha:1.0], [UIColor colorWithRed:0.54 green:0.34 blue:1.0 alpha:1.0]],
    @[[UIColor colorWithRed:0.38 green:0.28 blue:0.98 alpha:1.0], [UIColor colorWithRed:0.10 green:0.76 blue:0.98 alpha:1.0]],
    @[[UIColor colorWithRed:0.16 green:0.19 blue:0.25 alpha:1.0], [UIColor colorWithRed:0.51 green:0.59 blue:0.67 alpha:1.0]]
  ];

  NSMutableArray *categories = [NSMutableArray arrayWithCapacity:base.count];
  [base enumerateObjectsUsingBlock:^(NSDictionary *category, NSUInteger index, BOOL *stop) {
    (void)stop;
    NSMutableDictionary *next = [category mutableCopy];
    next[@"colors"] = colors[index % colors.count];
    [categories addObject:next];
  }];
  return categories;
}


@end

@interface NFBEmojiInputView () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<NSString *> *emojis;
@property (nonatomic, strong) UIView *categoryBar;
@property (nonatomic, strong) UIView *topBorder;
@end

@implementation NFBEmojiInputView

- (instancetype)initWithFrame:(CGRect)frame {
  CGRect initialFrame = CGRectEqualToRect(frame, CGRectZero) ? CGRectMake(0.0, 0.0, UIScreen.mainScreen.bounds.size.width, 292.0) : frame;
  self = [super initWithFrame:initialFrame];
  if (self) {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emojis = @[@"😀", @"😃", @"😄", @"😁", @"😆", @"😅", @"😂", @"🤣", @"😊", @"😇", @"🙂", @"🙃", @"😉", @"😍", @"😘", @"😗", @"😙", @"😚", @"😋", @"😛", @"😜", @"🤪", @"😎", @"🥳", @"😏", @"😒", @"😞", @"😔", @"😟", @"😕", @"🙁", @"☹️", @"😣", @"😖", @"😫", @"😩", @"🥺", @"😢", @"😭", @"😤", @"😠", @"😡", @"🤯", @"😳", @"🥶", @"😱", @"😨", @"😰", @"😥", @"😓", @"🤗", @"🤔", @"🫡", @"🤫", @"🤭", @"🙄", @"😬", @"😮‍💨", @"😴", @"🤤", @"😵", @"🤐", @"🤢", @"🤮", @"🤧", @"😷", @"🤒", @"🤕", @"🤑", @"🤠", @"😈", @"👿", @"👋", @"🤚", @"✋", @"🖖", @"👌", @"🤌", @"🤏", @"✌️", @"🤞", @"🤟", @"🤘", @"🤙", @"👈", @"👉", @"👆", @"👇", @"☝️", @"👍", @"👎", @"✊", @"👊", @"🤛", @"🤜", @"👏", @"🙌", @"🫶", @"🙏", @"💪", @"🔥", @"✨", @"💯", @"❤️", @"💙", @"💚", @"💛", @"💜", @"🖤", @"🤍", @"💔", @"💕", @"💞", @"💫", @"⭐️", @"🌟", @"⚡️", @"☀️", @"🌙", @"🌈", @"🎉", @"🎊", @"🎈", @"🏆", @"🥇", @"🍿", @"☕️", @"🍕", @"🌭", @"🍔", @"🍟", @"🍩", @"🍪"];

    _topBorder = [[UIView alloc] init];
    _topBorder.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_topBorder];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 6.0;
    layout.minimumInteritemSpacing = 0.0;
    layout.sectionInset = UIEdgeInsetsMake(10.0, 8.0, 10.0, 8.0);

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.alwaysBounceVertical = YES;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"emoji"];
    [self addSubview:_collectionView];

    _categoryBar = [[UIView alloc] init];
    _categoryBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_categoryBar];

    NSArray<NSString *> *categoryTitles = @[@"😀", @"🐻", @"🍔", @"⚽️", @"💡", @"❤️", @"ABC"];
    UIStackView *categoryStack = [[UIStackView alloc] init];
    categoryStack.translatesAutoresizingMaskIntoConstraints = NO;
    categoryStack.axis = UILayoutConstraintAxisHorizontal;
    categoryStack.distribution = UIStackViewDistributionFillEqually;
    categoryStack.alignment = UIStackViewAlignmentFill;
    for (NSString *title in categoryTitles) {
      UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
      [button setTitle:title forState:UIControlStateNormal];
      [button setTitleColor:NFBColorSecondaryText() forState:UIControlStateNormal];
      button.titleLabel.font = [title isEqualToString:@"ABC"] ? NFBFont(13.0, NFBFontWeightHeavy) : [UIFont systemFontOfSize:23.0];
      if ([title isEqualToString:@"ABC"]) [button addTarget:self action:@selector(keyboardTapped) forControlEvents:UIControlEventTouchUpInside];
      [categoryStack addArrangedSubview:button];
    }
    [_categoryBar addSubview:categoryStack];

    [NSLayoutConstraint activateConstraints:@[
      [_topBorder.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_topBorder.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_topBorder.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_topBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
      [_collectionView.topAnchor constraintEqualToAnchor:_topBorder.bottomAnchor],
      [_collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_collectionView.bottomAnchor constraintEqualToAnchor:_categoryBar.topAnchor],
      [_categoryBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_categoryBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_categoryBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [_categoryBar.heightAnchor constraintEqualToConstant:45.0],
      [categoryStack.topAnchor constraintEqualToAnchor:_categoryBar.topAnchor],
      [categoryStack.leadingAnchor constraintEqualToAnchor:_categoryBar.leadingAnchor constant:4.0],
      [categoryStack.trailingAnchor constraintEqualToAnchor:_categoryBar.trailingAnchor constant:-4.0],
      [categoryStack.bottomAnchor constraintEqualToAnchor:_categoryBar.bottomAnchor]
    ]];
    [self applyTheme];
  }
  return self;
}

- (CGSize)intrinsicContentSize {
  return CGSizeMake(UIViewNoIntrinsicMetric, 292.0);
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)applyTheme {
  self.backgroundColor = NFBColorBackground();
  self.collectionView.backgroundColor = NFBColorBackground();
  self.categoryBar.backgroundColor = NFBColorElevatedBackground();
  self.topBorder.backgroundColor = NFBColorBorder();
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
  (void)collectionView; (void)section;
  return self.emojis.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
  UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"emoji" forIndexPath:indexPath];
  UILabel *label = [cell.contentView viewWithTag:39191];
  UIImageView *imageView = [cell.contentView viewWithTag:39192];
  if (!label) {
    label = [[UILabel alloc] init];
    label.tag = 39191;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:31.0];
    [cell.contentView addSubview:label];
    imageView = [[UIImageView alloc] init];
    imageView.tag = 39192;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [cell.contentView addSubview:imageView];
    [NSLayoutConstraint activateConstraints:@[
      [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
      [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
      [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
      [label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
      [imageView.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
      [imageView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
      [imageView.widthAnchor constraintEqualToConstant:31.0],
      [imageView.heightAnchor constraintEqualToConstant:31.0]
    ]];
  }
  NSString *emoji = self.emojis[indexPath.item];
  UIImage *twemoji = NFBTwemojiImageForEmoji(emoji);
  label.text = twemoji ? @"" : emoji;
  label.hidden = twemoji != nil;
  imageView.image = twemoji;
  imageView.hidden = twemoji == nil;
  cell.backgroundColor = UIColor.clearColor;
  cell.contentView.backgroundColor = UIColor.clearColor;
  return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
  (void)collectionViewLayout; (void)indexPath;
  CGFloat columns = 8.0;
  CGFloat width = floor((CGRectGetWidth(collectionView.bounds) - 16.0) / columns);
  return CGSizeMake(MAX(36.0, width), 38.0);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  (void)collectionView;
  if (indexPath.item >= self.emojis.count) return;
  [self.delegate emojiInputView:self didSelectEmoji:self.emojis[indexPath.item]];
}

- (void)keyboardTapped {
  [self.delegate emojiInputViewDidRequestKeyboard:self];
}

@end

@interface NFBScheduleTweetViewController : UIViewController
@property (nonatomic, copy) NFBScheduleTweetCompletion completionHandler;
@end

@interface NFBScheduleTweetViewController ()
@property (nonatomic, strong) UIButton *backdropButton;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, assign) BOOL dismissing;
@end

@implementation NFBScheduleTweetViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.clearColor;

  self.backdropButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.backdropButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.backdropButton.backgroundColor = NFBIPAModalSheetScrimColor();
  self.backdropButton.alpha = 0.0;
  [self.backdropButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backdropButton];

  self.sheetView = [[UIView alloc] init];
  self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetAppearance(self.sheetView);
  NFBInstallSheetDismissGesture(self.sheetView, self.backdropButton, self, @selector(cancelTapped));
  [self.view addSubview:self.sheetView];

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = @"Schedule Tweet";
  title.textColor = NFBColorText();
  title.font = NFBFont(20.0, NFBFontWeightHeavy);
  title.textAlignment = NSTextAlignmentCenter;

  UILabel *subtitle = [[UILabel alloc] init];
  subtitle.translatesAutoresizingMaskIntoConstraints = NO;
  subtitle.text = @"Saved locally and sent the next time Not Twitter is running after this time.";
  subtitle.textColor = NFBColorSecondaryText();
  subtitle.font = NFBFont(14.0, NFBFontWeightRegular);
  subtitle.textAlignment = NSTextAlignmentCenter;
  subtitle.numberOfLines = 0;

  self.datePicker = [[UIDatePicker alloc] init];
  self.datePicker.translatesAutoresizingMaskIntoConstraints = NO;
  self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
  self.datePicker.minimumDate = [NSDate dateWithTimeIntervalSinceNow:60.0];
  self.datePicker.date = [NSDate dateWithTimeIntervalSinceNow:3600.0];
  self.datePicker.tintColor = NFBColorAccent();
  if (@available(iOS 13.4, *)) self.datePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;

  UIButton *cancelButton = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
  [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
  NFBIPAApplyButtonAppearance(cancelButton, NFBIPAButtonStyleNeutralOutline, NFBIPAButtonSizeMedium);
  [cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];

  UIButton *scheduleButton = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  scheduleButton.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyButtonAppearance(scheduleButton, NFBIPAButtonStylePrimary, NFBIPAButtonSizeMedium);
  [scheduleButton setTitle:@"Schedule" forState:UIControlStateNormal];
  [scheduleButton addTarget:self action:@selector(scheduleTapped) forControlEvents:UIControlEventTouchUpInside];

  UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[cancelButton, scheduleButton]];
  buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
  buttonStack.axis = UILayoutConstraintAxisHorizontal;
  buttonStack.spacing = 12.0;
  buttonStack.distribution = UIStackViewDistributionFillEqually;

  [self.sheetView addSubview:grabber];
  [self.sheetView addSubview:title];
  [self.sheetView addSubview:subtitle];
  [self.sheetView addSubview:self.datePicker];
  [self.sheetView addSubview:buttonStack];

  [NSLayoutConstraint activateConstraints:@[
    [self.backdropButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.backdropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.backdropButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.backdropButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [grabber.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:self.sheetView.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],
    [title.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:16.0],
    [title.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor constant:24.0],
    [title.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor constant:-24.0],
    [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
    [subtitle.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor constant:30.0],
    [subtitle.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor constant:-30.0],
    [self.datePicker.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:8.0],
    [self.datePicker.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [self.datePicker.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [buttonStack.topAnchor constraintEqualToAnchor:self.datePicker.bottomAnchor constant:12.0],
    [buttonStack.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor constant:20.0],
    [buttonStack.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor constant:-20.0],
    [cancelButton.heightAnchor constraintEqualToConstant:44.0],
    [scheduleButton.heightAnchor constraintEqualToConstant:44.0],
    [buttonStack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16.0]
  ]];

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, MAX(440.0, CGRectGetHeight(self.sheetView.bounds) + 40.0));
  [UIView animateWithDuration:0.34 delay:0.0 usingSpringWithDamping:0.88 initialSpringVelocity:0.54 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^{
    self.backdropButton.alpha = 1.0;
    self.sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)cancelTapped {
  [self dismissWithDate:nil];
}

- (void)scheduleTapped {
  [self dismissWithDate:self.datePicker.date ?: [NSDate dateWithTimeIntervalSinceNow:3600.0]];
}

- (void)dismissWithDate:(NSDate *)date {
  if (self.dismissing) return;
  self.dismissing = YES;
  NFBScheduleTweetCompletion completion = self.completionHandler;
  [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction animations:^{
    self.backdropButton.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, MAX(440.0, CGRectGetHeight(self.sheetView.bounds) + 40.0));
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:^{
      if (completion) completion(date);
    }];
  }];
}

@end

@interface NFBDraftsViewController : UITableViewController
@property (nonatomic, copy) NSString *accountDID;
@property (nonatomic, copy) NFBDraftsSelectionHandler selectionHandler;
@end

@interface NFBDraftsViewController ()
@property (nonatomic, strong) UIView *tabBar;
@property (nonatomic, strong) UIButton *draftsTabButton;
@property (nonatomic, strong) UIButton *scheduledTabButton;
@property (nonatomic, strong) UIView *tabIndicator;
@property (nonatomic, strong) NSLayoutConstraint *tabIndicatorLeadingConstraint;
@property (nonatomic, assign) NSInteger selectedTabIndex;
@property (nonatomic, copy) NSArray<NSDictionary *> *items;
@end

@implementation NFBDraftsViewController

- (instancetype)init {
  self = [super initWithStyle:UITableViewStylePlain];
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Drafts";
  self.view.backgroundColor = NFBColorBackground();
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.tableView.rowHeight = 72.0;
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"New Tweet" style:UIBarButtonItemStylePlain target:self action:@selector(newTweetTapped)];

  self.navigationItem.titleView = NFBTitleView(@"Drafts", nil);
  self.selectedTabIndex = 0;
  self.tabBar = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, UIScreen.mainScreen.bounds.size.width, 52.0)];
  self.tabBar.backgroundColor = NFBColorBackground();
  self.draftsTabButton = [self tabButtonWithTitle:@"Drafts" selected:YES action:@selector(draftsTabTapped)];
  self.scheduledTabButton = [self tabButtonWithTitle:@"Scheduled" selected:NO action:@selector(scheduledTabTapped)];
  self.tabIndicator = [[UIView alloc] init];
  self.tabIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabIndicator.backgroundColor = NFBColorAccent();
  self.tabIndicator.layer.cornerRadius = 2.0;
  UIView *bottomBorder = [[UIView alloc] init];
  bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(bottomBorder);
  [self.tabBar addSubview:self.draftsTabButton];
  [self.tabBar addSubview:self.scheduledTabButton];
  [self.tabBar addSubview:bottomBorder];
  [self.tabBar addSubview:self.tabIndicator];
  self.tabIndicatorLeadingConstraint = [self.tabIndicator.leadingAnchor constraintEqualToAnchor:self.tabBar.leadingAnchor constant:0.0];
  [NSLayoutConstraint activateConstraints:@[
    [self.draftsTabButton.topAnchor constraintEqualToAnchor:self.tabBar.topAnchor],
    [self.draftsTabButton.leadingAnchor constraintEqualToAnchor:self.tabBar.leadingAnchor],
    [self.draftsTabButton.bottomAnchor constraintEqualToAnchor:self.tabBar.bottomAnchor],
    [self.draftsTabButton.widthAnchor constraintEqualToAnchor:self.tabBar.widthAnchor multiplier:0.5],
    [self.scheduledTabButton.topAnchor constraintEqualToAnchor:self.tabBar.topAnchor],
    [self.scheduledTabButton.leadingAnchor constraintEqualToAnchor:self.draftsTabButton.trailingAnchor],
    [self.scheduledTabButton.trailingAnchor constraintEqualToAnchor:self.tabBar.trailingAnchor],
    [self.scheduledTabButton.bottomAnchor constraintEqualToAnchor:self.tabBar.bottomAnchor],
    [bottomBorder.leadingAnchor constraintEqualToAnchor:self.tabBar.leadingAnchor],
    [bottomBorder.trailingAnchor constraintEqualToAnchor:self.tabBar.trailingAnchor],
    [bottomBorder.bottomAnchor constraintEqualToAnchor:self.tabBar.bottomAnchor],
    [bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    self.tabIndicatorLeadingConstraint,
    [self.tabIndicator.bottomAnchor constraintEqualToAnchor:self.tabBar.bottomAnchor],
    [self.tabIndicator.widthAnchor constraintEqualToAnchor:self.tabBar.widthAnchor multiplier:0.5],
    [self.tabIndicator.heightAnchor constraintEqualToConstant:4.0]
  ]];
  self.tableView.tableHeaderView = self.tabBar;
  [self reloadItems];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGRect headerFrame = self.tabBar.frame;
  CGFloat width = CGRectGetWidth(self.tableView.bounds);
  if (fabs(CGRectGetWidth(headerFrame) - width) > 0.5 || fabs(CGRectGetHeight(headerFrame) - 52.0) > 0.5) {
    headerFrame.size = CGSizeMake(width, 52.0);
    self.tabBar.frame = headerFrame;
    self.tableView.tableHeaderView = self.tabBar;
  }
  [self updateTabChromeAnimated:NO];
}

- (UIButton *)tabButtonWithTitle:(NSString *)title selected:(BOOL)selected action:(SEL)action {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
  button.titleLabel.font = NFBFont(16.0, selected ? NFBFontWeightHeavy : NFBFontWeightBold);
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (void)closeTapped {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)newTweetTapped {
  NFBDraftsSelectionHandler handler = self.selectionHandler;
  [self dismissViewControllerAnimated:YES completion:^{
    if (handler) handler(nil);
  }];
}

- (void)draftsTabTapped {
  [self setSelectedTabIndex:0 animated:YES];
}

- (void)scheduledTabTapped {
  [self setSelectedTabIndex:1 animated:YES];
}

- (void)setSelectedTabIndex:(NSInteger)selectedTabIndex animated:(BOOL)animated {
  if (_selectedTabIndex == selectedTabIndex && self.items) return;
  _selectedTabIndex = selectedTabIndex;
  [self updateTabChromeAnimated:animated];
  [self reloadItems];
}

- (void)updateTabChromeAnimated:(BOOL)animated {
  BOOL scheduled = self.selectedTabIndex == 1;
  [self.draftsTabButton setTitleColor:scheduled ? NFBColorSecondaryText() : NFBColorText() forState:UIControlStateNormal];
  [self.scheduledTabButton setTitleColor:scheduled ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
  self.draftsTabButton.titleLabel.font = NFBFont(16.0, scheduled ? NFBFontWeightBold : NFBFontWeightHeavy);
  self.scheduledTabButton.titleLabel.font = NFBFont(16.0, scheduled ? NFBFontWeightHeavy : NFBFontWeightBold);
  self.tabIndicator.backgroundColor = NFBColorAccent();
  self.tabIndicatorLeadingConstraint.constant = scheduled ? floor(CGRectGetWidth(self.tabBar.bounds) * 0.5) : 0.0;
  void (^changes)(void) = ^{
    [self.tabBar layoutIfNeeded];
  };
  if (animated) [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
  else changes();
}

- (void)reloadItems {
  self.items = self.selectedTabIndex == 1 ? [[NFBLocalPostStore sharedStore] scheduledPostsForAccountDID:self.accountDID] : [[NFBLocalPostStore sharedStore] draftPostsForAccountDID:self.accountDID];
  [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView; (void)section;
  return MAX((NSInteger)self.items.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"draft"];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"draft"];
  NFBIPAApplyTableCellAppearance(cell, UITableViewCellSelectionStyleDefault);
  cell.textLabel.textColor = NFBColorText();
  cell.detailTextLabel.textColor = NFBColorSecondaryText();
  cell.textLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
  cell.detailTextLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

  if (self.items.count == 0) {
    cell.textLabel.text = self.selectedTabIndex == 1 ? @"No scheduled Tweets" : @"No drafts";
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    NFBIPAApplyTableCellAppearance(cell, UITableViewCellSelectionStyleNone);
    return cell;
  }

  NSDictionary *item = self.items[indexPath.row];
  cell.textLabel.text = [self titleForLocalPost:item];
  cell.detailTextLabel.text = [self detailForLocalPost:item];
  NFBIPAApplyTableCellAppearance(cell, UITableViewCellSelectionStyleDefault);
  return cell;
}

- (NSString *)titleForLocalPost:(NSDictionary *)post {
  NSString *text = [post[@"text"] isKindOfClass:NSString.class] ? post[@"text"] : @"";
  text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length > 0) return text;
  NSArray *media = [post[@"mediaItems"] isKindOfClass:NSArray.class] ? post[@"mediaItems"] : @[];
  NSDictionary *first = [media.firstObject isKindOfClass:NSDictionary.class] ? media.firstObject : @{};
  NSString *type = [first[@"type"] isKindOfClass:NSString.class] ? first[@"type"] : @"";
  if ([type isEqualToString:@"gif"]) return @"Animated GIF";
  if ([type isEqualToString:@"video"]) return @"Video";
  if (media.count > 0) return @"Photo";
  return @"No text";
}

- (NSString *)detailForLocalPost:(NSDictionary *)post {
  NSString *error = [post[@"lastError"] isKindOfClass:NSString.class] ? post[@"lastError"] : @"";
  if (error.length > 0) return [@"Failed to send - " stringByAppendingString:error];
  NSNumber *timestamp = nil;
  NSString *prefix = @"Saved";
  if (self.selectedTabIndex == 1) {
    timestamp = [post[@"scheduledAt"] isKindOfClass:NSNumber.class] ? post[@"scheduledAt"] : nil;
    prefix = @"Scheduled";
  } else {
    timestamp = [post[@"createdAt"] isKindOfClass:NSNumber.class] ? post[@"createdAt"] : nil;
  }
  if (!timestamp) return prefix;
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.doesRelativeDateFormatting = YES;
  formatter.dateStyle = NSDateFormatterMediumStyle;
  formatter.timeStyle = NSDateFormatterShortStyle;
  return [NSString stringWithFormat:@"%@ %@", prefix, [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue]]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (self.items.count == 0 || indexPath.row >= self.items.count) return;
  NSDictionary *item = self.items[indexPath.row];
  NFBDraftsSelectionHandler handler = self.selectionHandler;
  [self dismissViewControllerAnimated:YES completion:^{
    if (handler) handler(item);
  }];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  return self.items.count > 0 && indexPath.row < self.items.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= self.items.count) return;
  NSDictionary *item = self.items[indexPath.row];
  NSString *postID = [item[@"id"] isKindOfClass:NSString.class] ? item[@"id"] : @"";
  [[NFBLocalPostStore sharedStore] deleteLocalPostWithID:postID];
  [self reloadItems];
}

@end

typedef void (^NFBReplyGatePickerCompletion)(NSString *gate);

@interface NFBReplyGatePickerViewController : UIViewController
@property (nonatomic, copy) NSString *selectedGate;
@property (nonatomic, copy) NFBReplyGatePickerCompletion completionHandler;
@end

@interface NFBReplyGatePickerViewController ()
@property (nonatomic, strong) UIButton *backdropButton;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, assign) BOOL dismissing;
@end

@implementation NFBReplyGatePickerViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.clearColor;

  self.backdropButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.backdropButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.backdropButton.backgroundColor = NFBIPAModalSheetScrimColor();
  self.backdropButton.alpha = 0.0;
  [self.backdropButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backdropButton];

  self.sheetView = [[UIView alloc] init];
  self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetAppearance(self.sheetView);
  NFBInstallSheetDismissGesture(self.sheetView, self.backdropButton, self, @selector(cancelTapped));
  [self.view addSubview:self.sheetView];

  UIView *grabberRow = [[UIView alloc] init];
  grabberRow.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);
  [grabberRow addSubview:grabber];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = @"Who can reply?";
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(20.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;

  UILabel *descriptionLabel = [[UILabel alloc] init];
  descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
  descriptionLabel.text = @"Pick who can reply to this Tweet. Keep in mind that anyone mentioned can always reply.";
  descriptionLabel.textColor = NFBColorSecondaryText();
  descriptionLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  descriptionLabel.numberOfLines = 0;

  UIView *headerContainer = [[UIView alloc] init];
  headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [headerContainer addSubview:titleLabel];
  [headerContainer addSubview:descriptionLabel];

  NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObjects:grabberRow, headerContainer, nil];
  for (NSDictionary *option in NFBComposeReplyGateOptions()) {
    [rows addObject:[self optionRowWithOption:option]];
  }

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;
  [self.sheetView addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [self.backdropButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.backdropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.backdropButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.backdropButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],

    [stack.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-14.0],

    [grabberRow.heightAnchor constraintEqualToConstant:18.0],
    [grabber.topAnchor constraintEqualToAnchor:grabberRow.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:grabberRow.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],

    [headerContainer.heightAnchor constraintGreaterThanOrEqualToConstant:98.0],
    [titleLabel.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:10.0],
    [titleLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:24.0],
    [titleLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-24.0],
    [descriptionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10.0],
    [descriptionLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:24.0],
    [descriptionLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-24.0],
    [descriptionLabel.bottomAnchor constraintLessThanOrEqualToAnchor:headerContainer.bottomAnchor constant:-16.0]
  ]];

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, MAX(420.0, CGRectGetHeight(self.sheetView.bounds) + 40.0));
  [UIView animateWithDuration:0.34
                        delay:0.0
       usingSpringWithDamping:0.88
        initialSpringVelocity:0.54
                      options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                   animations:^{
    self.backdropButton.alpha = 1.0;
    self.sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (UIControl *)optionRowWithOption:(NSDictionary *)option {
  NSString *gate = [option[@"gate"] isKindOfClass:NSString.class] ? option[@"gate"] : NFBComposeReplyGateEveryone;
  BOOL selected = [gate isEqualToString:self.selectedGate ?: NFBComposeReplyGateEveryone];

  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.accessibilityIdentifier = gate;
  row.accessibilityLabel = option[@"title"];
  row.accessibilityHint = @"Sets who can reply to your Tweet";
  row.accessibilityTraits = UIAccessibilityTraitButton;
  [row addTarget:self action:@selector(optionTouchDown:) forControlEvents:UIControlEventTouchDown];
  [row addTarget:self action:@selector(optionTouchCancelled:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [row addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIView *highlight = [[UIView alloc] init];
  highlight.translatesAutoresizingMaskIntoConstraints = NO;
  highlight.tag = 51827;
  highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:0.0];
  highlight.userInteractionEnabled = NO;
  [row addSubview:highlight];

  UIView *iconCircle = [[UIView alloc] init];
  iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
  iconCircle.backgroundColor = NFBColorAccent();
  iconCircle.layer.cornerRadius = 18.0;
  iconCircle.userInteractionEnabled = NO;

  NSString *iconName = @"nfb_globe";
  if ([gate isEqualToString:NFBComposeReplyGateFollowing]) iconName = @"nfb_people";
  else if ([gate isEqualToString:NFBComposeReplyGateMentioned]) iconName = @"nfb_reply";
  else if ([gate isEqualToString:NFBComposeReplyGateNobody]) iconName = @"nfb_profile";

  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.tintColor = UIColor.whiteColor;
  icon.contentMode = UIViewContentModeScaleAspectFit;
  [iconCircle addSubview:icon];

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = option[@"title"];
  title.textColor = NFBColorText();
  title.font = NFBFont(17.0, NFBFontWeightHeavy);
  title.lineBreakMode = NSLineBreakByTruncatingTail;
  title.userInteractionEnabled = NO;

  UILabel *subtitle = [[UILabel alloc] init];
  subtitle.translatesAutoresizingMaskIntoConstraints = NO;
  subtitle.text = option[@"subtitle"];
  subtitle.textColor = NFBColorSecondaryText();
  subtitle.font = NFBFont(14.0, NFBFontWeightRegular);
  subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
  subtitle.userInteractionEnabled = NO;

  UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
  textStack.translatesAutoresizingMaskIntoConstraints = NO;
  textStack.axis = UILayoutConstraintAxisVertical;
  textStack.alignment = UIStackViewAlignmentFill;
  textStack.spacing = 2.0;
  textStack.userInteractionEnabled = NO;

  UIImageView *check = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_check")];
  check.translatesAutoresizingMaskIntoConstraints = NO;
  check.tintColor = NFBColorAccent();
  check.contentMode = UIViewContentModeScaleAspectFit;
  check.hidden = !selected;
  check.userInteractionEnabled = NO;

  [row addSubview:iconCircle];
  [row addSubview:textStack];
  [row addSubview:check];

  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:66.0],
    [highlight.topAnchor constraintEqualToAnchor:row.topAnchor],
    [highlight.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [highlight.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [highlight.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    [iconCircle.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:24.0],
    [iconCircle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [iconCircle.widthAnchor constraintEqualToConstant:36.0],
    [iconCircle.heightAnchor constraintEqualToConstant:36.0],
    [icon.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
    [icon.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
    [icon.widthAnchor constraintEqualToConstant:20.0],
    [icon.heightAnchor constraintEqualToConstant:20.0],
    [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-24.0],
    [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [check.widthAnchor constraintEqualToConstant:22.0],
    [check.heightAnchor constraintEqualToConstant:22.0],
    [textStack.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:16.0],
    [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor constant:-16.0],
    [textStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
  ]];

  return row;
}

- (void)optionTouchDown:(UIControl *)row {
  UIView *highlight = [row viewWithTag:51827];
  highlight.backgroundColor = NFBIPAModalSheetRowHighlightColor();
}

- (void)optionTouchCancelled:(UIControl *)row {
  UIView *highlight = [row viewWithTag:51827];
  [UIView animateWithDuration:0.12 animations:^{
    highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:0.0];
  }];
}

- (void)optionTapped:(UIControl *)row {
  [self optionTouchCancelled:row];
  NSString *gate = row.accessibilityIdentifier ?: NFBComposeReplyGateEveryone;
  [self dismissWithGate:gate];
}

- (void)cancelTapped {
  [self dismissWithGate:nil];
}

- (void)dismissWithGate:(NSString *)gate {
  if (self.dismissing) return;
  self.dismissing = YES;
  NFBReplyGatePickerCompletion completion = self.completionHandler;
  [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseIn animations:^{
    self.backdropButton.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, MAX(420.0, CGRectGetHeight(self.sheetView.bounds) + 40.0));
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:^{
      if (completion) completion(gate);
    }];
  }];
}

@end

typedef void (^NFBComposeAccountPickerCompletion)(NSDictionary *account);

@interface NFBComposeAccountPickerViewController : UIViewController
@property (nonatomic, copy) NSArray<NSDictionary *> *accounts;
@property (nonatomic, copy) NSString *selectedDID;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NFBComposeAccountPickerCompletion completionHandler;
@end

@interface NFBComposeAccountPickerViewController ()
@property (nonatomic, strong) UIButton *backdropButton;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *avatarCache;
@property (nonatomic, assign) BOOL dismissing;
@end

@implementation NFBComposeAccountPickerViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  if (!self.accounts) self.accounts = [[NFBAtprotoSession sharedSession] savedAccountDictionaries];
  self.avatarCache = [[NSCache alloc] init];
  self.view.backgroundColor = UIColor.clearColor;

  self.backdropButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.backdropButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.backdropButton.backgroundColor = NFBIPAModalSheetScrimColor();
  self.backdropButton.alpha = 0.0;
  [self.backdropButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backdropButton];

  self.sheetView = [[UIView alloc] init];
  self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetAppearance(self.sheetView);
  NFBInstallSheetDismissGesture(self.sheetView, self.backdropButton, self, @selector(cancelTapped));
  [self.view addSubview:self.sheetView];

  UIView *grabberRow = [[UIView alloc] init];
  grabberRow.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);
  [grabberRow addSubview:grabber];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = self.titleText.length > 0 ? self.titleText : @"Tweet from";
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(18.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;

  UIView *titleRow = [[UIView alloc] init];
  titleRow.translatesAutoresizingMaskIntoConstraints = NO;
  [titleRow addSubview:titleLabel];

  NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObjects:grabberRow, titleRow, nil];
  for (NSUInteger index = 0; index < self.accounts.count; index++) {
    [rows addObject:[self accountRowForAccount:self.accounts[index] index:index]];
  }

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;
  [stack setCustomSpacing:0.0 afterView:grabberRow];
  [stack setCustomSpacing:2.0 afterView:titleRow];
  [self.sheetView addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [self.backdropButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.backdropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.backdropButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.backdropButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],

    [stack.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-14.0],

    [grabberRow.heightAnchor constraintEqualToConstant:18.0],
    [grabber.topAnchor constraintEqualToAnchor:grabberRow.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:grabberRow.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],

    [titleRow.heightAnchor constraintEqualToConstant:44.0],
    [titleLabel.leadingAnchor constraintEqualToAnchor:titleRow.leadingAnchor constant:24.0],
    [titleLabel.trailingAnchor constraintEqualToAnchor:titleRow.trailingAnchor constant:-24.0],
    [titleLabel.centerYAnchor constraintEqualToAnchor:titleRow.centerYAnchor]
  ]];

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, MAX(420.0, CGRectGetHeight(self.sheetView.bounds) + 40.0));
  [UIView animateWithDuration:0.34
                        delay:0.0
       usingSpringWithDamping:0.88
        initialSpringVelocity:0.54
                      options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                   animations:^{
    self.backdropButton.alpha = 1.0;
    self.sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (UIControl *)accountRowForAccount:(NSDictionary *)account index:(NSUInteger)index {
  NSString *did = [account[@"did"] isKindOfClass:NSString.class] ? account[@"did"] : @"";
  BOOL selected = did.length > 0 && [did isEqualToString:self.selectedDID ?: @""];
  if (self.selectedDID.length == 0 && [account[@"active"] boolValue]) selected = YES;

  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.tag = (NSInteger)index;
  row.exclusiveTouch = YES;
  row.accessibilityTraits = UIAccessibilityTraitButton;
  row.accessibilityLabel = [NSString stringWithFormat:@"%@ @%@", self.titleText ?: @"Tweet from", [NFBAtprotoClient handleForProfile:account]];
  if (selected) row.accessibilityTraits |= UIAccessibilityTraitSelected;
  [row addTarget:self action:@selector(accountTouchDown:) forControlEvents:UIControlEventTouchDown];
  [row addTarget:self action:@selector(accountTouchCancelled:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [row addTarget:self action:@selector(accountTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIView *highlight = [[UIView alloc] init];
  highlight.translatesAutoresizingMaskIntoConstraints = NO;
  highlight.tag = 96201;
  highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:0.0];
  highlight.userInteractionEnabled = NO;
  [row addSubview:highlight];

  UIImageView *avatar = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
  avatar.translatesAutoresizingMaskIntoConstraints = NO;
  avatar.contentMode = UIViewContentModeScaleAspectFill;
  avatar.clipsToBounds = YES;
  avatar.layer.cornerRadius = 18.0;
  avatar.userInteractionEnabled = NO;

  UILabel *nameLabel = [[UILabel alloc] init];
  nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
  nameLabel.textColor = NFBColorText();
  nameLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
  nameLabel.text = [NFBAtprotoClient displayNameForProfile:account];
  nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  nameLabel.userInteractionEnabled = NO;

  UILabel *handleLabel = [[UILabel alloc] init];
  handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  handleLabel.textColor = NFBColorSecondaryText();
  handleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:account]];
  handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  handleLabel.userInteractionEnabled = NO;

  UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, handleLabel]];
  textStack.translatesAutoresizingMaskIntoConstraints = NO;
  textStack.axis = UILayoutConstraintAxisVertical;
  textStack.alignment = UIStackViewAlignmentFill;
  textStack.spacing = 1.0;
  textStack.userInteractionEnabled = NO;

  UIImageView *check = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_check")];
  check.translatesAutoresizingMaskIntoConstraints = NO;
  check.tintColor = NFBColorAccent();
  check.contentMode = UIViewContentModeScaleAspectFit;
  check.hidden = !selected;
  check.userInteractionEnabled = NO;

  [row addSubview:avatar];
  [row addSubview:textStack];
  [row addSubview:check];

  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:58.0],
    [highlight.topAnchor constraintEqualToAnchor:row.topAnchor],
    [highlight.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [highlight.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [highlight.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    [avatar.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
    [avatar.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [avatar.widthAnchor constraintEqualToConstant:36.0],
    [avatar.heightAnchor constraintEqualToConstant:36.0],
    [textStack.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:12.0],
    [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor constant:-12.0],
    [textStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20.0],
    [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [check.widthAnchor constraintEqualToConstant:22.0],
    [check.heightAnchor constraintEqualToConstant:22.0]
  ]];

  [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:account] intoImageView:avatar];
  return row;
}

- (void)loadAvatarURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  UIImage *cached = [self.avatarCache objectForKey:url.absoluteString];
  if (cached) {
    imageView.image = cached;
    return;
  }
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [self.avatarCache setObject:image forKey:url.absoluteString];
    dispatch_async(dispatch_get_main_queue(), ^{
      imageView.image = image;
    });
  }] resume];
}

- (void)accountTouchDown:(UIControl *)row {
  UIView *highlight = [row viewWithTag:96201];
  highlight.backgroundColor = NFBIPAModalSheetRowHighlightColor();
}

- (void)accountTouchCancelled:(UIControl *)row {
  UIView *highlight = [row viewWithTag:96201];
  [UIView animateWithDuration:0.12 animations:^{
    highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:0.0];
  }];
}

- (void)accountTapped:(UIControl *)row {
  [self accountTouchCancelled:row];
  if (row.tag < 0 || (NSUInteger)row.tag >= self.accounts.count) return;
  [self dismissWithAccount:self.accounts[(NSUInteger)row.tag]];
}

- (void)cancelTapped {
  [self dismissWithAccount:nil];
}

- (void)dismissWithAccount:(NSDictionary *)account {
  if (self.dismissing) return;
  self.dismissing = YES;
  NFBComposeAccountPickerCompletion completion = self.completionHandler;
  [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseIn animations:^{
    self.backdropButton.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, MAX(420.0, CGRectGetHeight(self.sheetView.bounds) + 40.0));
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:^{
      if (completion) completion(account);
    }];
  }];
}

@end

static NSString * const NFBComposeSuggestionCellIdentifier = @"NFBComposeSuggestionCell";

@interface NFBComposeSuggestionCell : UITableViewCell
- (void)configureWithSuggestion:(NSDictionary *)suggestion;
@end

@implementation NFBComposeSuggestionCell {
  UIImageView *_iconView;
  UILabel *_titleLabel;
  UILabel *_subtitleLabel;
  NSString *_avatarURLString;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

    _iconView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.clipsToBounds = YES;
    _iconView.layer.cornerRadius = 18.0;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 1.0;

    [self.contentView addSubview:_iconView];
    [self.contentView addSubview:textStack];
    [NSLayoutConstraint activateConstraints:@[
      [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
      [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
      [_iconView.widthAnchor constraintEqualToConstant:36.0],
      [_iconView.heightAnchor constraintEqualToConstant:36.0],
      [textStack.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10.0],
      [textStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
      [textStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
      [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:54.0]
    ]];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  _avatarURLString = nil;
  _iconView.image = NFBDefaultAvatarImage();
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  _titleLabel.textColor = NFBColorText();
  _subtitleLabel.textColor = NFBColorSecondaryText();
}

- (void)configureWithSuggestion:(NSDictionary *)suggestion {
  [self applyTheme];
  NSString *type = [suggestion[@"type"] isKindOfClass:NSString.class] ? suggestion[@"type"] : @"";
  if ([type isEqualToString:@"actor"]) {
    NSDictionary *profile = [suggestion[@"profile"] isKindOfClass:NSDictionary.class] ? suggestion[@"profile"] : @{};
    _titleLabel.text = [NFBAtprotoClient displayNameForProfile:profile];
    _subtitleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:profile]];
    _iconView.layer.cornerRadius = 18.0;
    _iconView.tintColor = nil;
    [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:profile]];
  } else {
    NSString *tag = [suggestion[@"tag"] isKindOfClass:NSString.class] ? suggestion[@"tag"] : @"";
    _titleLabel.text = tag.length > 0 ? tag : @"#";
    _subtitleLabel.text = @"Hashtag";
    _iconView.layer.cornerRadius = 0.0;
    _iconView.image = NFBTemplateIcon(@"nfb_search");
    _iconView.tintColor = NFBColorAccent();
  }
}

- (void)loadAvatarURL:(NSString *)urlString {
  _avatarURLString = urlString ?: @"";
  _iconView.image = NFBDefaultAvatarImage();
  NSURL *url = [NSURL URLWithString:_avatarURLString];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self->_avatarURLString isEqualToString:urlString ?: @""]) self->_iconView.image = image;
    });
  }] resume];
}

@end



@interface NFBComposeTextView : UITextView
@property (nonatomic, copy) void (^pasteImagesHandler)(UITextView *, NSArray<UIImage *> *);
@end
@implementation NFBComposeTextView
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
  if (action == @selector(paste:) && self.editable && UIPasteboard.generalPasteboard.hasImages) return YES;
  return [super canPerformAction:action withSender:sender];
}
- (void)paste:(id)sender {
  if (self.editable && self.pasteImagesHandler && UIPasteboard.generalPasteboard.hasImages) {
    NSArray *images = UIPasteboard.generalPasteboard.images;
    if (images.count) { self.pasteImagesHandler(self, images); return; }
  }
  [super paste:sender];
}
@end

// Keep media with the draft row that owns it, independent of keyboard focus.
@interface NFBComposeThreadRow : UIView
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mediaItems;
@property (nonatomic, strong) NFBMediaPreviewView *mediaPreview;
@property (nonatomic, strong) NSLayoutConstraint *mediaHeight;
@property (nonatomic, strong) NSLayoutConstraint *mediaTop;
@end
@implementation NFBComposeThreadRow
@end

@interface NFBComposeViewController () <UITextViewDelegate, UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate, NFBMediaPreviewViewDelegate, NFBCropViewControllerDelegate, NFBVideoTrimViewControllerDelegate, NFBGIFPickerViewControllerDelegate, NFBEmojiInputViewDelegate>

@property (nonatomic, strong, nullable) NSDictionary *replyToPost;
@property (nonatomic, strong, nullable) NSDictionary *quotePost;
@property (nonatomic, strong) UIScrollView *contentScrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *threadRootConnectorView;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong, nullable) UIButton *audienceButton;
@property (nonatomic, strong, nullable) UIButton *accountButton;
@property (nonatomic, strong, nullable) UILabel *replyContextLabel;
@property (nonatomic, strong, nullable) NFBQuotedPostView *quotedPostView;
@property (nonatomic, strong) UIButton *removeQuoteButton;
@property (nonatomic, strong) UIStackView *threadStackView;
@property (nonatomic, strong) NSMutableArray<UITextView *> *threadTextViews;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *threadAvatarViews;
@property (nonatomic, strong) NFBMediaPreviewView *mediaPreviewView;
@property (nonatomic, strong) UITableView *suggestionsTableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mediaItems;
@property (nonatomic, assign) BOOL importingPhotos;
@property (nonatomic, assign) NSUInteger photoImportGeneration;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIView *countCircle;
@property (nonatomic, strong) CAShapeLayer *countTrackLayer;
@property (nonatomic, strong) CAShapeLayer *countProgressLayer;
@property (nonatomic, strong) UIControl *threadAddButton;
@property (nonatomic, strong) UIImageView *spinner;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *draftsButton;
@property (nonatomic, strong) UIButton *tweetButton;
@property (nonatomic, strong) UIBarButtonItem *draftsNavigationItem;
@property (nonatomic, strong) UIBarButtonItem *tweetNavigationItem;
@property (nonatomic, strong) UIView *inputAccessoryBar;
@property (nonatomic, strong) NFBUndoTweetView *undoTweetBar;
@property (nonatomic, strong) NSLayoutConstraint *undoTweetHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputAccessoryHeightConstraint;
@property (nonatomic, strong) NSTimer *undoTweetTimer;
@property (nonatomic, strong) NSDate *undoTweetFireDate;
@property (nonatomic, assign) NSTimeInterval undoTweetTotalInterval;
@property (nonatomic, assign) BOOL undoTweetPending;
@property (nonatomic, strong) UIControl *conversationControl;
@property (nonatomic, strong) UIImageView *conversationIconView;
@property (nonatomic, strong) UILabel *conversationLabel;
@property (nonatomic, copy) NSString *replyGate;
@property (nonatomic, copy) NSDictionary *selectedComposerAccount;
@property (nonatomic, strong) NFBAtprotoClient *postingClient;
@property (nonatomic, weak) UITextView *mediaTargetTextView;
@property (nonatomic, assign) BOOL posting;
@property (nonatomic, assign) BOOL pickingGIF;
@property (nonatomic, assign) BOOL usingEmojiPicker;
@property (nonatomic, strong) NFBEmojiInputView *emojiInputView;
@property (nonatomic, copy) NSString *loadedLocalPostID;
@property (nonatomic, strong) NSLayoutConstraint *textViewHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mediaPreviewHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *suggestionsHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputAccessoryBottomConstraint;
@property (nonatomic, assign) BOOL editingMediaItem;
@property (nonatomic, assign) NSUInteger editingMediaIndex;
@property (nonatomic, strong, nullable) UIImage *pendingOriginalImage;
@property (nonatomic, copy) NSArray<NSDictionary *> *composerSuggestions;
@property (nonatomic, copy) NSString *activeSuggestionKind;
@property (nonatomic, copy) NSString *activeSuggestionQuery;
@property (nonatomic, assign) NSRange activeSuggestionRange;
@property (nonatomic, assign) NSUInteger suggestionGeneration;
@property (nonatomic, assign) BOOL applyingComposerTextAttributes;
@property (nonatomic, strong) NSLayoutConstraint *threadTopWithoutQuote;
@property (nonatomic, strong) NSLayoutConstraint *mediaTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *threadConnectorBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *threadConnectorCollapsedConstraint;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *quoteConstraints;
@property (nonatomic, assign) NSUInteger quoteLookupGeneration;
@property (nonatomic, assign) BOOL resolvingQuote;
@property (nonatomic, assign) BOOL shouldResolvePostLink;
@property (nonatomic, strong) UITextView *attachmentAltTextView;
@property (nonatomic, assign) NSUInteger attachmentAltIndex;
@property (nonatomic, copy) NSString *resolvingQuoteURL;

@end

@implementation NFBComposeViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
	  if (self) {
	    _mediaItems = [NSMutableArray array];
	    _threadTextViews = [NSMutableArray array];
	    _threadAvatarViews = [NSMutableArray array];
	    _replyGate = NFBComposeReplyGateEveryone;
	  }
  return self;
}

- (instancetype)initWithReplyToPost:(NSDictionary *)post {
  self = [super initWithNibName:nil bundle:nil];
	  if (self) {
	    _replyToPost = [post copy];
	    _mediaItems = [NSMutableArray array];
	    _threadTextViews = [NSMutableArray array];
	    _threadAvatarViews = [NSMutableArray array];
	    _replyGate = NFBComposeReplyGateEveryone;
	  }
  return self;
}

- (instancetype)initWithQuotePost:(NSDictionary *)post {
  self = [super initWithNibName:nil bundle:nil];
	  if (self) {
	    _quotePost = [post copy];
	    _mediaItems = [NSMutableArray array];
	    _threadTextViews = [NSMutableArray array];
	    _threadAvatarViews = [NSMutableArray array];
	    _replyGate = NFBComposeReplyGateEveryone;
	  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  NFBInstallComposerDismissGesture(self.view, self, @selector(cancelTapped));
  self.view.backgroundColor = NFBColorBackground();
  self.title = nil;
  self.navigationItem.titleView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1.0, 1.0)];

  self.navigationItem.leftBarButtonItem = [self closeBarButtonItem];
  self.tweetButton = [self composerSendButton];
  self.tweetNavigationItem = [[UIBarButtonItem alloc] initWithCustomView:self.tweetButton];
  self.draftsNavigationItem = [self draftsBarButtonItem];
  self.navigationItem.rightBarButtonItems = @[self.tweetNavigationItem];
  [self updateDraftsButtonState];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChange:) name:NFBThemeDidChangeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localPostStoreDidChange:) name:NFBLocalPostStoreDidChangeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameDidChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameDidChange:) name:UIKeyboardWillHideNotification object:nil];

  BOOL isReply = self.replyToPost != nil;
  
  self.selectedComposerAccount = [self currentSavedComposerAccount];

  self.avatarView = [[UIImageView alloc] initWithImage:NFBBrandIconImage() ?: NFBDefaultAvatarImage()];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
	  self.avatarView.layer.cornerRadius = 20.0;
	  NSString *avatarURL = [NFBAtprotoClient avatarURLForProfile:self.selectedComposerAccount ?: @{}];
	  if (avatarURL.length > 0) [self loadAvatarURL:avatarURL intoImageView:self.avatarView];

	  self.threadRootConnectorView = [[UIView alloc] init];
	  self.threadRootConnectorView.translatesAutoresizingMaskIntoConstraints = NO;
	  self.threadRootConnectorView.backgroundColor = NFBColorBorder();
	  self.threadRootConnectorView.hidden = YES;

  self.audienceButton = nil;
  self.accountButton = ([self savedComposerAccounts].count > 1) ? [self makeReplyAccountButton] : nil;
  if (self.accountButton) {
    self.avatarView.userInteractionEnabled = YES;
    UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replyAccountTapped)];
    [self.avatarView addGestureRecognizer:avatarTap];
  }

  self.replyContextLabel = nil;
  NSDictionary *contextPost = self.replyToPost;
  if (contextPost) {
    NSDictionary *author = [contextPost[@"author"] isKindOfClass:NSDictionary.class] ? contextPost[@"author"] : @{};
    NSString *prefix = @"Replying to ";
    NSString *handle = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:author]];
    NSString *text = [prefix stringByAppendingString:handle];
    NSMutableAttributedString *contextText = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
      NSForegroundColorAttributeName: NFBColorSecondaryText(),
      NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)
    }];
    [contextText addAttribute:NSForegroundColorAttributeName value:NFBColorAccent() range:NSMakeRange(prefix.length, handle.length)];

    self.replyContextLabel = [[UILabel alloc] init];
    self.replyContextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyContextLabel.attributedText = contextText;
    self.replyContextLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    self.replyContextLabel.numberOfLines = 1;
    self.replyContextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  }

  self.textView = [self newComposerTextView];
  self.textView.translatesAutoresizingMaskIntoConstraints = NO;
  self.textView.delegate = self;
  self.textView.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular);
  self.textView.textColor = NFBColorText();
  self.textView.tintColor = NFBColorAccent();
	  self.textView.backgroundColor = NFBColorBackground();
	  self.textView.scrollEnabled = NO;
	  self.textView.textContainerInset = UIEdgeInsetsMake(0.0, 0.0, 18.0, 0.0);
  self.textView.textContainer.lineFragmentPadding = 0.0;
  self.textView.alwaysBounceVertical = YES;
  self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

  self.composerSuggestions = @[];
  self.activeSuggestionRange = NSMakeRange(NSNotFound, 0);
  self.suggestionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.suggestionsTableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(self.suggestionsTableView);
  self.suggestionsTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.suggestionsTableView.rowHeight = UITableViewAutomaticDimension;
  self.suggestionsTableView.estimatedRowHeight = 54.0;
  self.suggestionsTableView.scrollEnabled = NO;
  self.suggestionsTableView.hidden = YES;
  self.suggestionsTableView.alpha = 0.0;
  self.suggestionsTableView.layer.cornerRadius = 14.0;
  self.suggestionsTableView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  self.suggestionsTableView.layer.borderColor = NFBColorBorder().CGColor;
  self.suggestionsTableView.clipsToBounds = YES;
  self.suggestionsTableView.dataSource = self;
  self.suggestionsTableView.delegate = self;
  [self.suggestionsTableView registerClass:NFBComposeSuggestionCell.class forCellReuseIdentifier:NFBComposeSuggestionCellIdentifier];

  self.placeholderLabel = [[UILabel alloc] init];
  self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.placeholderLabel.text = isReply ? @"Tweet your reply" : @"What's happening?";
  self.placeholderLabel.textColor = NFBColorSecondaryText();
  self.placeholderLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular);

  self.threadStackView = [[UIStackView alloc] init];
  self.threadStackView.translatesAutoresizingMaskIntoConstraints = NO;
  self.threadStackView.axis = UILayoutConstraintAxisVertical;
  self.threadStackView.alignment = UIStackViewAlignmentFill;
	  self.threadStackView.spacing = 0.0;
  self.threadStackView.backgroundColor = NFBColorBackground();

  self.countLabel = [[UILabel alloc] init];
  self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.countLabel.font = NFBFont(11.0, NFBFontWeightRegular);
  self.countLabel.textColor = NFBColorSecondaryText();
  self.countLabel.textAlignment = NSTextAlignmentCenter;

  self.spinner = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
  self.spinner.tintColor = NFBColorSecondaryText();
  self.spinner.contentMode = UIViewContentModeScaleAspectFit;
  self.spinner.hidden = YES;

  self.inputAccessoryBar = [self composeInputAccessoryBar];
  self.inputAccessoryBar.translatesAutoresizingMaskIntoConstraints = NO;
  self.undoTweetBar = [self composeUndoTweetBar];
  self.undoTweetBar.translatesAutoresizingMaskIntoConstraints = NO;


  self.mediaPreviewView = [[NFBMediaPreviewView alloc] initWithFrame:CGRectZero];
  self.mediaPreviewView.translatesAutoresizingMaskIntoConstraints = NO;
  self.mediaPreviewView.delegate = self;
	  self.mediaPreviewView.composerRailStyle = YES;
	  [self.mediaPreviewView configureWithMediaItems:self.mediaItems];

  self.contentScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
  self.contentScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentScrollView.backgroundColor = NFBColorBackground();
  self.contentScrollView.alwaysBounceVertical = YES;
  self.contentScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  if (@available(iOS 11.0, *)) self.contentScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

  self.contentView = [[UIView alloc] init];
  self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentView.backgroundColor = NFBColorBackground();

  [self.view addSubview:self.contentScrollView];
  [self.contentScrollView addSubview:self.contentView];
  [self.contentView addSubview:self.avatarView];
  [self.contentView addSubview:self.threadRootConnectorView];
  if (self.audienceButton) [self.contentView addSubview:self.audienceButton];
  if (self.accountButton) [self.contentView addSubview:self.accountButton];
  if (self.replyContextLabel) [self.contentView addSubview:self.replyContextLabel];
  [self.contentView addSubview:self.textView];
  [self.contentView addSubview:self.placeholderLabel];
  [self.contentView addSubview:self.threadStackView];
  [self.contentView addSubview:self.mediaPreviewView];
  if (self.quotedPostView) [self.contentView addSubview:self.quotedPostView];
  [self.contentView addSubview:self.suggestionsTableView];
	  [self.contentView addSubview:self.undoTweetBar];
	  [self.view addSubview:self.inputAccessoryBar];

	  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
	  NSLayoutYAxisAnchor *textTopAnchor = self.replyContextLabel ? self.replyContextLabel.bottomAnchor : (self.accountButton ? self.accountButton.bottomAnchor : (self.audienceButton ? self.audienceButton.bottomAnchor : self.contentView.topAnchor));
	  CGFloat textTopOffset = self.replyContextLabel ? 10.0 : ((self.accountButton || self.audienceButton) ? 10.0 : 18.0);
	  self.textViewHeightConstraint = [self.textView.heightAnchor constraintEqualToConstant:self.textView.font.lineHeight];
  self.mediaPreviewHeightConstraint = [self.mediaPreviewView.heightAnchor constraintEqualToConstant:0.0];
  self.suggestionsHeightConstraint = [self.suggestionsTableView.heightAnchor constraintEqualToConstant:0.0];
  self.inputAccessoryBottomConstraint = [self.inputAccessoryBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
  self.inputAccessoryHeightConstraint = [self.inputAccessoryBar.heightAnchor constraintEqualToConstant:100.0];
  self.undoTweetHeightConstraint = [self.undoTweetBar.heightAnchor constraintEqualToConstant:0.0];
  self.mediaTopConstraint = [self.mediaPreviewView.topAnchor constraintEqualToAnchor:self.textView.bottomAnchor];
  self.threadConnectorBottomConstraint = [self.threadRootConnectorView.bottomAnchor constraintEqualToAnchor:self.threadStackView.topAnchor constant:-4];
  self.threadConnectorCollapsedConstraint = [self.threadRootConnectorView.heightAnchor constraintEqualToConstant:0];
  NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
    [self.contentScrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.contentScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.contentScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.contentScrollView.bottomAnchor constraintEqualToAnchor:self.inputAccessoryBar.topAnchor],
    [self.contentView.topAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.topAnchor],
    [self.contentView.leadingAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.leadingAnchor],
    [self.contentView.trailingAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.trailingAnchor],
    [self.contentView.bottomAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.bottomAnchor],
    [self.contentView.widthAnchor constraintEqualToAnchor:self.contentScrollView.frameLayoutGuide.widthAnchor],
		    [self.avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
		    [self.avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
		    [self.avatarView.widthAnchor constraintEqualToConstant:40.0],
		    [self.avatarView.heightAnchor constraintEqualToConstant:40.0],
	    [self.threadRootConnectorView.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
	    [self.threadRootConnectorView.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:6.0],
      self.threadConnectorCollapsedConstraint,
	    [self.threadRootConnectorView.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
	    [self.textView.topAnchor constraintEqualToAnchor:textTopAnchor constant:textTopOffset],
    [self.textView.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:12.0],
	    [self.textView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
	    self.textViewHeightConstraint,
    [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
    [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.textView.topAnchor],
	    [self.threadStackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
	    [self.threadStackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
      self.mediaTopConstraint,
	    [self.mediaPreviewView.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
	    [self.mediaPreviewView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
	    self.mediaPreviewHeightConstraint,
	    [self.suggestionsTableView.topAnchor constraintEqualToAnchor:self.textView.bottomAnchor constant:4.0],
	    [self.suggestionsTableView.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
	    [self.suggestionsTableView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    self.suggestionsHeightConstraint,
    [self.undoTweetBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
    [self.undoTweetBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [self.undoTweetBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-20.0],
    [self.undoTweetBar.topAnchor constraintEqualToAnchor:self.threadStackView.bottomAnchor],
    self.undoTweetHeightConstraint,
    [self.inputAccessoryBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.inputAccessoryBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    self.inputAccessoryBottomConstraint,
    self.inputAccessoryHeightConstraint
  ]];
  if (self.audienceButton) {
    [constraints addObjectsFromArray:@[
	      [self.audienceButton.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:12.0],
	      [self.audienceButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
	      [self.audienceButton.heightAnchor constraintEqualToConstant:30.0]
	    ]];
  }
  if (self.accountButton) {
    [constraints addObjectsFromArray:@[
	      [self.accountButton.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:12.0],
	      [self.accountButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
	      [self.accountButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
	      [self.accountButton.heightAnchor constraintEqualToConstant:30.0],
	      [self.accountButton.widthAnchor constraintGreaterThanOrEqualToConstant:118.0]
	    ]];
  }
  if (self.replyContextLabel) {
    NSLayoutYAxisAnchor *replyContextTopAnchor = self.accountButton ? self.accountButton.bottomAnchor : self.contentView.topAnchor;
    CGFloat replyContextTopOffset = self.accountButton ? 6.0 : 19.0;
    [constraints addObjectsFromArray:@[
	      [self.replyContextLabel.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
	      [self.replyContextLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
	      [self.replyContextLabel.topAnchor constraintEqualToAnchor:replyContextTopAnchor constant:replyContextTopOffset]
	    ]];
	  }
  self.threadTopWithoutQuote = [self.threadStackView.topAnchor constraintEqualToAnchor:self.mediaPreviewView.bottomAnchor];
  [constraints addObject:self.threadTopWithoutQuote];
  [NSLayoutConstraint activateConstraints:constraints];
  if (self.quotePost) [self showQuotePreview:self.quotePost];

  [self applyComposerChrome];
  [self updateComposerLayoutForThread];
  [self updateCount];
  [self.textView becomeFirstResponder];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self applyComposerChrome];
}

- (UITextView *)activeComposerTextView {
  if (self.textView.isFirstResponder) return self.textView;
  for (UITextView *threadTextView in self.threadTextViews) {
    if (threadTextView.isFirstResponder) return threadTextView;
  }
  return nil;
}

- (void)scrollComposerTextViewIntoVisibleArea:(UITextView *)textView animated:(BOOL)animated {
  if (!self.contentScrollView || !self.contentView || !textView) return;
  CGRect targetRect = textView.bounds;
  UITextRange *selection = textView.selectedTextRange;
  if (selection) {
    CGRect caretRect = [textView caretRectForPosition:selection.end];
    if (!CGRectIsEmpty(caretRect)) targetRect = CGRectUnion(caretRect, CGRectInset(caretRect, -2.0, -28.0));
  }
  CGRect contentRect = [textView convertRect:targetRect toView:self.contentView];
  contentRect = CGRectInset(contentRect, 0.0, -72.0);
  [self.contentScrollView scrollRectToVisible:contentRect animated:animated];
}

- (void)keyboardFrameDidChange:(NSNotification *)notification {
  if (!self.inputAccessoryBottomConstraint) return;
  CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect localFrame = [self.view convertRect:endFrame fromView:nil];
  CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(localFrame));
  CGFloat inset = MAX(0.0, overlap - self.view.safeAreaInsets.bottom);
  self.inputAccessoryBottomConstraint.constant = -inset;

  NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
  NSNumber *curveNumber = notification.userInfo[UIKeyboardAnimationCurveUserInfoKey];
  UIViewAnimationOptions options = curveNumber ? (UIViewAnimationOptions)(curveNumber.integerValue << 16) : UIViewAnimationOptionCurveEaseInOut;
  [UIView animateWithDuration:duration > 0.0 ? duration : 0.25
                        delay:0.0
                      options:options | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
	                   animations:^{
	    [self.view layoutIfNeeded];
	  } completion:^(BOOL finished) {
    (void)finished;
    [self scrollComposerTextViewIntoVisibleArea:[self activeComposerTextView] animated:YES];
  }];
}

- (void)dealloc {
  [self.undoTweetTimer invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIBarButtonItem *)closeBarButtonItem {
  self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.closeButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
  self.closeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  self.closeButton.contentEdgeInsets = UIEdgeInsetsMake(10.0, 0.0, 10.0, 18.0);
  [self.closeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  self.closeButton.accessibilityLabel = @"Close";
  [self.closeButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  return [[UIBarButtonItem alloc] initWithCustomView:self.closeButton];
}

- (UIBarButtonItem *)draftsBarButtonItem {
  self.draftsButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.draftsButton.frame = CGRectMake(0.0, 0.0, 60.0, 44.0);
  self.draftsButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
  self.draftsButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 6.0);
  [self.draftsButton setTitle:@"Drafts" forState:UIControlStateNormal];
  [self.draftsButton setTitleColor:NFBColorAccent() forState:UIControlStateNormal];
  self.draftsButton.titleLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
  self.draftsButton.accessibilityLabel = @"Drafts";
  [self.draftsButton addTarget:self action:@selector(draftsTapped) forControlEvents:UIControlEventTouchUpInside];
  [self updateDraftsButtonState];
  return [[UIBarButtonItem alloc] initWithCustomView:self.draftsButton];
}

- (UIButton *)composerSendButton {
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  button.frame = CGRectMake(0.0, 0.0, 66.0, 32.0);
  NFBIPAApplyButtonAppearance(button, NFBIPAButtonStylePrimary, NFBIPAButtonSizeSmall);
  [button setTitle:self.replyToPost ? @"Reply" : @"Tweet" forState:UIControlStateNormal];
  [button addTarget:self action:@selector(postTapped) forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (void)setTweetButtonWidth:(CGFloat)width {
  if (!self.tweetButton) return;
  CGRect frame = self.tweetButton.frame;
  if (fabs(frame.size.width - width) < 0.5) return;
  frame.size.width = width;
  self.tweetButton.frame = frame;
  [self.tweetButton invalidateIntrinsicContentSize];
  [self.navigationController.navigationBar setNeedsLayout];
}

- (void)themeDidChange:(NSNotification *)notification {
  (void)notification;
  [self applyComposerChrome];
}

- (void)applyComposerChrome {
  self.view.backgroundColor = NFBColorBackground();
  self.contentScrollView.backgroundColor = NFBColorBackground();
  self.contentView.backgroundColor = NFBColorBackground();
  self.textView.backgroundColor = NFBColorBackground();
  self.textView.textColor = NFBColorText();
  self.textView.tintColor = NFBColorAccent();
  [self applyComposerTextAttributesPreservingSelection];
	  self.placeholderLabel.textColor = NFBColorSecondaryText();
	  self.threadStackView.backgroundColor = NFBColorBackground();
	  self.threadRootConnectorView.backgroundColor = NFBColorBorder();
	  for (UITextView *threadTextView in self.threadTextViews) {
	    threadTextView.backgroundColor = NFBColorBackground();
	    threadTextView.textColor = NFBColorText();
	    threadTextView.tintColor = NFBColorAccent();
	    UIView *row = threadTextView.superview;
    [((NFBComposeThreadRow *)row).mediaPreview applyTheme];
	    row.backgroundColor = NFBColorBackground();
	    UIView *rail = [row viewWithTag:9103];
	    rail.backgroundColor = NFBColorBorder();
	    UILabel *placeholder = (UILabel *)[row viewWithTag:9101];
	    if ([placeholder isKindOfClass:UILabel.class]) {
	      placeholder.textColor = NFBColorSecondaryText();
      placeholder.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular);
    }
  }
  self.closeButton.tintColor = NFBColorText();
  [self.draftsButton setTitleColor:NFBColorAccent() forState:UIControlStateNormal];
  NFBIPAApplyButtonAppearance(self.tweetButton, NFBIPAButtonStylePrimary, NFBIPAButtonSizeSmall);
  self.countLabel.textColor = NFBColorSecondaryText();
  self.countCircle.layer.borderColor = NFBColorBorder().CGColor;
  self.inputAccessoryBar.backgroundColor = NFBColorBackground();
  [self updateReplyAccountButtonChrome];
  [self.undoTweetBar applyTheme];
  [self updateUndoTweetLayout];
  NFBIPAApplyTableViewAppearance(self.suggestionsTableView);
  self.suggestionsTableView.layer.borderColor = NFBColorBorder().CGColor;
  [self.suggestionsTableView reloadData];
  self.conversationControl.backgroundColor = NFBColorBackground();
  self.conversationIconView.tintColor = NFBColorAccent();
  self.conversationLabel.textColor = NFBColorAccent();
  [self updateReplyGateChrome];
  [self.emojiInputView applyTheme];
  [self.mediaPreviewView applyTheme];
  [self.quotedPostView applyTheme];
  self.removeQuoteButton.backgroundColor = NFBColorBackground();
  self.removeQuoteButton.tintColor = NFBColorText();
  [self updateCount];

  UINavigationBar *bar = self.navigationController.navigationBar;
  if (!bar) return;
  bar.prefersLargeTitles = NO;
  bar.tintColor = NFBColorText();
  bar.translucent = NO;
  bar.shadowImage = [UIImage new];
  [bar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];

  if (NSClassFromString(@"UINavigationBarAppearance")) {
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = NFBColorBackground();
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{
      NSForegroundColorAttributeName: NFBColorText(),
      NSFontAttributeName: NFBFont(19.0, NFBFontWeightHeavy)
    };
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
  } else {
    bar.barTintColor = NFBColorBackground();
    bar.titleTextAttributes = @{
      NSForegroundColorAttributeName: NFBColorText(),
      NSFontAttributeName: NFBFont(19.0, NFBFontWeightHeavy)
    };
  }
}

- (NSArray<NSDictionary *> *)savedComposerAccounts {
  NSArray<NSDictionary *> *accounts = [[NFBAtprotoSession sharedSession] savedAccountDictionaries];
  NSMutableArray<NSDictionary *> *validAccounts = [NSMutableArray array];
  for (NSDictionary *account in accounts) {
    if (![account isKindOfClass:NSDictionary.class]) continue;
    NSString *did = [account[@"did"] isKindOfClass:NSString.class] ? account[@"did"] : @"";
    if (did.length > 0) [validAccounts addObject:account];
  }
  return validAccounts;
}

- (NSDictionary *)currentSavedComposerAccount {
  NSDictionary *current = [[NFBAtprotoSession sharedSession] currentAccountDictionary] ?: @{};
  NSString *currentDID = [current[@"did"] isKindOfClass:NSString.class] ? current[@"did"] : @"";
  for (NSDictionary *account in [self savedComposerAccounts]) {
    NSString *did = [account[@"did"] isKindOfClass:NSString.class] ? account[@"did"] : @"";
    if (did.length > 0 && [did isEqualToString:currentDID]) return account;
  }
  return current;
}

- (UIButton *)makeReplyAccountButton {
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyButtonAppearance(button, NFBIPAButtonStyleOutline, NFBIPAButtonSizeCompact);
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 28.0);
  button.titleLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
  button.titleLabel.adjustsFontSizeToFitWidth = YES;
  button.titleLabel.minimumScaleFactor = 0.78;
  button.tintColor = NFBColorAccent();
  button.accessibilityTraits = UIAccessibilityTraitButton;
  [button addTarget:self action:@selector(replyAccountTapped) forControlEvents:UIControlEventTouchUpInside];

  UIImageView *chevron = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_chevron_down")];
  chevron.translatesAutoresizingMaskIntoConstraints = NO;
  chevron.tag = 96202;
  chevron.tintColor = NFBColorAccent();
  chevron.contentMode = UIViewContentModeScaleAspectFit;
  chevron.userInteractionEnabled = NO;
  [button addSubview:chevron];

  [NSLayoutConstraint activateConstraints:@[
    [chevron.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-10.0],
    [chevron.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    [chevron.widthAnchor constraintEqualToConstant:11.0],
    [chevron.heightAnchor constraintEqualToConstant:11.0]
  ]];

  return button;
}

- (void)updateReplyAccountButtonChrome {
  if (!self.accountButton) return;
  NFBIPAApplyButtonAppearance(self.accountButton, NFBIPAButtonStyleOutline, NFBIPAButtonSizeCompact);
  self.accountButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
  self.accountButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 28.0);
  self.accountButton.titleLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
  self.accountButton.tintColor = NFBColorAccent();

  NSDictionary *account = self.selectedComposerAccount ?: [self currentSavedComposerAccount];
  NSString *handle = [NFBAtprotoClient handleForProfile:account];
  NSString *title = handle.length > 0 ? [NSString stringWithFormat:@"From @%@", handle] : @"Choose account";
  [self.accountButton setTitle:title forState:UIControlStateNormal];
  [self.accountButton setTitleColor:NFBColorAccent() forState:UIControlStateNormal];
  self.accountButton.accessibilityLabel = title;

  UIImageView *chevron = (UIImageView *)[self.accountButton viewWithTag:96202];
  if ([chevron isKindOfClass:UIImageView.class]) chevron.tintColor = NFBColorAccent();
}

- (void)updateSelectedComposerAccount:(NSDictionary *)account {
  if (![account isKindOfClass:NSDictionary.class]) return;
  self.selectedComposerAccount = [account copy];
  [self updateReplyAccountButtonChrome];
  UIImage *fallback = NFBBrandIconImage() ?: NFBDefaultAvatarImage();
  self.avatarView.image = fallback;
  NSString *avatarURL = [NFBAtprotoClient avatarURLForProfile:self.selectedComposerAccount ?: @{}];
  if (avatarURL.length > 0) [self loadAvatarURL:avatarURL intoImageView:self.avatarView];
  [self updateThreadAvatarImages];
  [self updateDraftsButtonState];
}

- (UIButton *)makeAudienceButton {
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyButtonAppearance(button, NFBIPAButtonStyleOutline, NFBIPAButtonSizeCompact);
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 28.0);
  button.tintColor = NFBColorAccent();
  [button setImage:NFBTemplateIcon(@"nfb_globe") forState:UIControlStateNormal];
  [button setTitle:@"Everyone" forState:UIControlStateNormal];
  button.imageEdgeInsets = UIEdgeInsetsMake(0.0, -1.0, 0.0, 6.0);
  button.titleEdgeInsets = UIEdgeInsetsMake(0.0, 4.0, 0.0, 0.0);

  UIImageView *chevron = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_chevron_down")];
  chevron.translatesAutoresizingMaskIntoConstraints = NO;
  chevron.tintColor = NFBColorAccent();
  chevron.contentMode = UIViewContentModeScaleAspectFit;
  [button addSubview:chevron];
  [NSLayoutConstraint activateConstraints:@[
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],
    [chevron.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-10.0],
    [chevron.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    [chevron.widthAnchor constraintEqualToConstant:11.0],
    [chevron.heightAnchor constraintEqualToConstant:11.0]
  ]];

  return button;
}

- (UIView *)composeInputAccessoryBar {
  UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, UIScreen.mainScreen.bounds.size.width, 100.0)];
  accessory.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  accessory.backgroundColor = NFBColorBackground();

  self.conversationControl = [[UIControl alloc] init];
  self.conversationControl.translatesAutoresizingMaskIntoConstraints = NO;
  self.conversationControl.backgroundColor = NFBColorBackground();
  [self.conversationControl addTarget:self action:@selector(replyGateTapped) forControlEvents:UIControlEventTouchUpInside];

  self.conversationIconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_globe")];
  self.conversationIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.conversationIconView.tintColor = NFBColorAccent();
  self.conversationIconView.contentMode = UIViewContentModeScaleAspectFit;

  self.conversationLabel = [[UILabel alloc] init];
  self.conversationLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.conversationLabel.textColor = NFBColorAccent();
  self.conversationLabel.font = NFBFont(14.0, NFBFontWeightHeavy);

  UIView *conversationBottomBorder = [[UIView alloc] init];
  conversationBottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  conversationBottomBorder.backgroundColor = NFBColorBorder();

  UIView *buttonBar = [[UIView alloc] init];
  buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
  buttonBar.backgroundColor = NFBColorBackground();

  UIStackView *toolIcons = [[UIStackView alloc] initWithArrangedSubviews:@[
    [self toolbarButtonWithIcon:@"nfb_media" selector:@selector(mediaButtonTapped)],
    [self toolbarButtonWithIcon:@"nfb_gif" selector:@selector(gifButtonTapped)],
    [self toolbarButtonWithIcon:@"nfb_emoji" selector:@selector(emojiButtonTapped)],
    [self toolbarButtonWithIcon:@"nfb_calendar" selector:@selector(scheduleButtonTapped)]
  ]];
  toolIcons.translatesAutoresizingMaskIntoConstraints = NO;
  toolIcons.axis = UILayoutConstraintAxisHorizontal;
  toolIcons.spacing = 17.0;
  toolIcons.alignment = UIStackViewAlignmentCenter;

  self.countCircle = [[UIView alloc] init];
  self.countCircle.translatesAutoresizingMaskIntoConstraints = NO;
  self.countCircle.layer.cornerRadius = 11.0;
  self.countCircle.layer.borderWidth = 0.0;

  self.countTrackLayer = [CAShapeLayer layer];
  self.countTrackLayer.fillColor = UIColor.clearColor.CGColor;
  self.countTrackLayer.strokeColor = NFBColorBorder().CGColor;
  self.countTrackLayer.lineWidth = 2.0;
  [self.countCircle.layer addSublayer:self.countTrackLayer];

  self.countProgressLayer = [CAShapeLayer layer];
  self.countProgressLayer.fillColor = UIColor.clearColor.CGColor;
  self.countProgressLayer.strokeColor = NFBColorAccent().CGColor;
  self.countProgressLayer.lineWidth = 2.0;
  self.countProgressLayer.lineCap = kCALineCapRound;
  self.countProgressLayer.strokeEnd = 0.0;
  [self.countCircle.layer addSublayer:self.countProgressLayer];

  [self.countCircle addSubview:self.countLabel];

  UIView *divider = [[UIView alloc] init];
  divider.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(divider);

  self.threadAddButton = [self toolbarButtonWithIcon:@"nfb_plus" selector:@selector(addThreadPostTapped)];

  [accessory addSubview:self.conversationControl];
  [accessory addSubview:buttonBar];
  [self.conversationControl addSubview:self.conversationIconView];
  [self.conversationControl addSubview:self.conversationLabel];
  [self.conversationControl addSubview:conversationBottomBorder];
  [buttonBar addSubview:toolIcons];
  [buttonBar addSubview:self.countCircle];
  [buttonBar addSubview:divider];
  [buttonBar addSubview:self.threadAddButton];
  [buttonBar addSubview:self.spinner];

  [NSLayoutConstraint activateConstraints:@[
    [self.conversationControl.topAnchor constraintEqualToAnchor:accessory.topAnchor],
    [self.conversationControl.leadingAnchor constraintEqualToAnchor:accessory.leadingAnchor],
    [self.conversationControl.trailingAnchor constraintEqualToAnchor:accessory.trailingAnchor],
    [self.conversationControl.heightAnchor constraintEqualToConstant:44.0],
    [self.conversationIconView.leadingAnchor constraintEqualToAnchor:self.conversationControl.leadingAnchor constant:68.0],
    [self.conversationIconView.centerYAnchor constraintEqualToAnchor:self.conversationControl.centerYAnchor],
    [self.conversationIconView.widthAnchor constraintEqualToConstant:18.0],
    [self.conversationIconView.heightAnchor constraintEqualToConstant:18.0],
    [self.conversationLabel.leadingAnchor constraintEqualToAnchor:self.conversationIconView.trailingAnchor constant:8.0],
    [self.conversationLabel.centerYAnchor constraintEqualToAnchor:self.conversationControl.centerYAnchor],
    [self.conversationLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.conversationControl.trailingAnchor constant:-16.0],
    [conversationBottomBorder.leadingAnchor constraintEqualToAnchor:self.conversationControl.leadingAnchor constant:68.0],
    [conversationBottomBorder.trailingAnchor constraintEqualToAnchor:self.conversationControl.trailingAnchor],
    [conversationBottomBorder.bottomAnchor constraintEqualToAnchor:self.conversationControl.bottomAnchor],
    [conversationBottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [buttonBar.topAnchor constraintEqualToAnchor:self.conversationControl.bottomAnchor],
    [buttonBar.leadingAnchor constraintEqualToAnchor:accessory.leadingAnchor],
    [buttonBar.trailingAnchor constraintEqualToAnchor:accessory.trailingAnchor],
    [buttonBar.bottomAnchor constraintEqualToAnchor:accessory.bottomAnchor],
    [toolIcons.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor constant:17.0],
    [toolIcons.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    [toolIcons.trailingAnchor constraintLessThanOrEqualToAnchor:self.countCircle.leadingAnchor constant:-14.0],
    [self.countCircle.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor constant:-12.0],
    [self.countCircle.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    [self.countCircle.widthAnchor constraintEqualToConstant:22.0],
    [self.countCircle.heightAnchor constraintEqualToConstant:22.0],
    [self.countLabel.centerXAnchor constraintEqualToAnchor:self.countCircle.centerXAnchor],
    [self.countLabel.centerYAnchor constraintEqualToAnchor:self.countCircle.centerYAnchor],
    [self.countLabel.widthAnchor constraintEqualToAnchor:self.countCircle.widthAnchor],
    [self.countLabel.heightAnchor constraintEqualToAnchor:self.countCircle.heightAnchor],
    [divider.trailingAnchor constraintEqualToAnchor:self.threadAddButton.leadingAnchor constant:-12.0],
    [divider.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    [divider.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [divider.heightAnchor constraintEqualToConstant:28.0],
    [self.threadAddButton.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor constant:-10.0],
    [self.threadAddButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    [self.spinner.centerYAnchor constraintEqualToAnchor:self.countCircle.centerYAnchor],
    [self.spinner.trailingAnchor constraintEqualToAnchor:self.countCircle.leadingAnchor constant:-10.0],
    [self.spinner.widthAnchor constraintEqualToConstant:22.0],
    [self.spinner.heightAnchor constraintEqualToConstant:22.0]
  ]];

  return accessory;
}

- (NFBUndoTweetView *)composeUndoTweetBar {
  NFBUndoTweetView *bar = [[NFBUndoTweetView alloc] initWithFrame:CGRectZero];
  bar.hidden = YES;
  bar.alpha = 0.0;
  [bar.undoButton addTarget:self action:@selector(cancelUndoTweetCountdown) forControlEvents:UIControlEventTouchUpInside];
  [bar.sendNowButton addTarget:self action:@selector(sendUndoTweetNow) forControlEvents:UIControlEventTouchUpInside];
  return bar;
}

- (void)updateUndoTweetLayout {
  CGFloat width = MAX(1.0, CGRectGetWidth(self.view.bounds) - 32.0);
  CGFloat height = self.undoTweetPending ? [self.undoTweetBar sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height : 0.0;
  if (fabs(self.undoTweetHeightConstraint.constant - height) > 0.5) self.undoTweetHeightConstraint.constant = height;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self updateUndoTweetLayout];
  [self updateMediaPreviewHeight];
  [self updateComposerTextHeight];
}

- (UIImageView *)toolbarIcon:(NSString *)iconName {
  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.tintColor = NFBColorAccent();
  icon.contentMode = UIViewContentModeScaleAspectFit;
  [NSLayoutConstraint activateConstraints:@[
    [icon.widthAnchor constraintEqualToConstant:22.0],
    [icon.heightAnchor constraintEqualToConstant:22.0]
  ]];
  return icon;
}

- (UIControl *)toolbarButtonWithIcon:(NSString *)iconName selector:(SEL)selector {
  UIControl *button = [[UIControl alloc] init];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  UIImageView *icon = [self toolbarIcon:iconName];
  [button addSubview:icon];
  [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
  [NSLayoutConstraint activateConstraints:@[
    [button.widthAnchor constraintEqualToConstant:36.0],
    [button.heightAnchor constraintEqualToConstant:40.0],
    [icon.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
    [icon.centerYAnchor constraintEqualToAnchor:button.centerYAnchor]
  ]];
  return button;
}

- (NFBComposeTextView *)newComposerTextView {
  NFBComposeTextView *textView = [[NFBComposeTextView alloc] init];
  __weak typeof(self) weakSelf = self;
  textView.pasteImagesHandler = ^(UITextView *target, NSArray<UIImage *> *images) {
    __strong typeof(weakSelf) self = weakSelf;
    if (!self || self.posting || self.undoTweetPending || self.importingPhotos) return;
    self.mediaTargetTextView = target;
    if ([self containsVideoLikeMedia] || images.count > NFBMaxPhotosPerPost - self.editingMediaItems.count) {
      [self showError:@"Attach up to 10 photos, or one video/GIF, to each Tweet."]; return;
    }
    [self resetMediaEditingState];
    for (UIImage *image in images) [self addImageAttachment:image type:@"photo" mimeType:@"image/jpeg" altText:nil];
    [self scrollComposerTextViewIntoVisibleArea:target animated:YES];
  };
  return textView;
}

- (NSMutableArray<NSDictionary *> *)editingMediaItems {
  if ([self.mediaTargetTextView.superview isKindOfClass:NFBComposeThreadRow.class]) return ((NFBComposeThreadRow *)self.mediaTargetTextView.superview).mediaItems;
  return self.mediaItems;
}

- (void)targetMediaPreview:(NFBMediaPreviewView *)preview {
  self.mediaTargetTextView = preview == self.mediaPreviewView ? self.textView : ((NFBComposeThreadRow *)preview.superview).textView;
}

- (NSArray<NSDictionary *> *)threadPostsForDraft {
  NSMutableArray *posts = [NSMutableArray array];
  for (UITextView *textView in self.threadTextViews) {
    NFBComposeThreadRow *row = (NFBComposeThreadRow *)textView.superview;
    [posts addObject:@{@"text":textView.text ?: @"", @"mediaItems":[row.mediaItems copy]}];
  }
  return posts;
}

- (UIView *)threadComposerRowForTextView:(UITextView *)textView {
	  NFBComposeThreadRow *row = [[NFBComposeThreadRow alloc] init];
  row.textView = textView;
  row.mediaItems = [NSMutableArray array];
	  row.translatesAutoresizingMaskIntoConstraints = NO;
	  row.backgroundColor = NFBColorBackground();
	  row.clipsToBounds = YES;

	  UIView *rail = [[UIView alloc] init];
	  rail.translatesAutoresizingMaskIntoConstraints = NO;
	  rail.backgroundColor = NFBColorBorder();
	  rail.tag = 9103;

	  UIImageView *avatar = [[UIImageView alloc] initWithImage:self.avatarView.image ?: NFBDefaultAvatarImage()];
	  avatar.translatesAutoresizingMaskIntoConstraints = NO;
	  avatar.contentMode = UIViewContentModeScaleAspectFill;
	  avatar.clipsToBounds = YES;
	  avatar.layer.cornerRadius = 20.0;
	  avatar.tag = 9102;
  avatar.userInteractionEnabled = [self savedComposerAccounts].count > 1;
  [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replyAccountTapped)]];
	  [self.threadAvatarViews addObject:avatar];

	  textView.translatesAutoresizingMaskIntoConstraints = NO;
	  textView.delegate = self;
	  textView.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular);
	  textView.textColor = NFBColorText();
	  textView.tintColor = NFBColorAccent();
	  textView.backgroundColor = NFBColorBackground();
	  textView.scrollEnabled = NO;
	  textView.textContainerInset = UIEdgeInsetsMake(0.0, 0.0, 10.0, 0.0);
	  textView.textContainer.lineFragmentPadding = 0.0;
	  textView.alwaysBounceVertical = NO;
	  [textView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
	  [textView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

  UILabel *placeholder = [[UILabel alloc] init];
  placeholder.translatesAutoresizingMaskIntoConstraints = NO;
  placeholder.text = @"Add another Tweet";
  placeholder.textColor = NFBColorSecondaryText();
  placeholder.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular);
  placeholder.tag = 9101;

  UIButton *removeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  removeButton.translatesAutoresizingMaskIntoConstraints = NO;
  removeButton.tintColor = NFBColorSecondaryText();
  removeButton.accessibilityLabel = @"Remove Tweet from thread";
  [removeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  [removeButton addTarget:self action:@selector(removeThreadPostTapped:) forControlEvents:UIControlEventTouchUpInside];

  row.mediaPreview = [[NFBMediaPreviewView alloc] init];
  row.mediaPreview.translatesAutoresizingMaskIntoConstraints = NO;
  row.mediaPreview.delegate = self;
  row.mediaPreview.composerRailStyle = YES;
  [row addSubview:row.mediaPreview];
  row.mediaHeight = [row.mediaPreview.heightAnchor constraintEqualToConstant:0];
  row.mediaTop = [row.mediaPreview.topAnchor constraintEqualToAnchor:textView.bottomAnchor];
  [row addSubview:rail];
  [row addSubview:avatar];
  [row addSubview:textView];
  [row addSubview:placeholder];
  [row addSubview:removeButton];

	  [NSLayoutConstraint activateConstraints:@[
	    [row.heightAnchor constraintGreaterThanOrEqualToConstant:76.0],
	    [rail.centerXAnchor constraintEqualToAnchor:avatar.centerXAnchor],
	    [rail.topAnchor constraintEqualToAnchor:row.topAnchor],
	    [rail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
	    [rail.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
	    [avatar.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
	    [avatar.topAnchor constraintEqualToAnchor:row.topAnchor constant:10.0],
	    [avatar.widthAnchor constraintEqualToConstant:40.0],
	    [avatar.heightAnchor constraintEqualToConstant:40.0],
	    [textView.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:12.0],
	    [textView.topAnchor constraintEqualToAnchor:row.topAnchor constant:12.0],
	    [textView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-38.0],
	    row.mediaTop, row.mediaHeight,
      [row.mediaPreview.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor],
      [row.mediaPreview.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
      [row.mediaPreview.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],
	    [placeholder.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor],
	    [placeholder.topAnchor constraintEqualToAnchor:textView.topAnchor],
	    [placeholder.trailingAnchor constraintLessThanOrEqualToAnchor:textView.trailingAnchor],
    [removeButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [removeButton.topAnchor constraintEqualToAnchor:row.topAnchor constant:2.0],
    [removeButton.widthAnchor constraintEqualToConstant:34.0],
    [removeButton.heightAnchor constraintEqualToConstant:34.0]
  ]];

  return row;
}

- (void)animateThreadAddButtonTap {
  if (!self.threadAddButton) return;
  self.threadAddButton.userInteractionEnabled = NO;
  [UIView animateWithDuration:0.10
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    self.threadAddButton.alpha = 0.58;
  } completion:^(BOOL finished) {
    (void)finished;
    [UIView animateWithDuration:0.16
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
      self.threadAddButton.alpha = self.threadAddButton.enabled ? 1.0 : 0.45;
    } completion:^(BOOL finished2) {
      (void)finished2;
      self.threadAddButton.userInteractionEnabled = YES;
      self.threadAddButton.transform = CGAffineTransformIdentity;
      self.threadAddButton.alpha = self.threadAddButton.enabled ? 1.0 : 0.45;
    }];
  }];
}

- (void)animateThreadComposerRowInsertion:(UIView *)row textView:(UITextView *)textView {
  if (!row) return;
  row.alpha = 0.0;
  [self.view layoutIfNeeded];
  [UIView animateWithDuration:0.28
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
	                   animations:^{
    row.alpha = 1.0;
    [self.view layoutIfNeeded];
  } completion:^(BOOL finished) {
    (void)finished;
    row.alpha = 1.0;
    row.transform = CGAffineTransformIdentity;
  }];

	  if (textView) {
	    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
	      [textView becomeFirstResponder];
	      [self scrollComposerTextViewIntoVisibleArea:textView animated:YES];
	    });
	  }
}
	
- (void)addThreadPostTapped {
  if (![self canAddThreadPost]) return;
  [self animateThreadAddButtonTap];
  UITextView *threadTextView = [self newComposerTextView];
  UIView *row = [self threadComposerRowForTextView:threadTextView];
  [self.view layoutIfNeeded];
  [self.threadTextViews addObject:threadTextView];
  [self.threadStackView addArrangedSubview:row];
  [self updateComposerLayoutForThread];
  [self updateCount];
  [self animateThreadComposerRowInsertion:row textView:threadTextView];
}

- (void)removeThreadPostTapped:(UIButton *)sender {
  UIView *row = sender.superview;
  if (!row) return;
  UITextView *targetTextView = nil;
  for (UIView *subview in row.subviews) {
    if ([subview isKindOfClass:UITextView.class]) {
      targetTextView = (UITextView *)subview;
      break;
    }
	  }
  UIImageView *avatar = (UIImageView *)[row viewWithTag:9102];
  if ([avatar isKindOfClass:UIImageView.class]) [self.threadAvatarViews removeObject:avatar];
  if (self.mediaTargetTextView == targetTextView) self.mediaTargetTextView = self.textView;
  if (targetTextView) [self.threadTextViews removeObject:targetTextView];
  [UIView animateWithDuration:0.22
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    row.alpha = 0.0;
    [self.threadStackView removeArrangedSubview:row];
    [row removeFromSuperview];
    [self updateComposerLayoutForThread];
    [self.view layoutIfNeeded];
  } completion:^(BOOL finished) {
    (void)finished;
    [self updateCount];
  }];
}

- (void)updateThreadAvatarImages {
  UIImage *image = self.avatarView.image ?: NFBDefaultAvatarImage();
  for (UIImageView *avatar in self.threadAvatarViews) {
    avatar.image = image;
    avatar.layer.cornerRadius = 20.0;
  }
}

- (void)clearThreadComposerRows {
  self.mediaTargetTextView = self.textView;
  NSArray<UIView *> *rows = [self.threadStackView.arrangedSubviews copy];
  for (UIView *row in rows) {
    [self.threadStackView removeArrangedSubview:row];
    [row removeFromSuperview];
  }
  [self.threadTextViews removeAllObjects];
  [self.threadAvatarViews removeAllObjects];
}

- (void)restoreThreadComposerRowsWithTexts:(NSArray *)threadTexts {
  [self clearThreadComposerRows];
  for (id value in threadTexts ?: @[]) {
    if (![value isKindOfClass:NSString.class]) continue;
    UITextView *threadTextView = [self newComposerTextView];
    threadTextView.text = (NSString *)value;
    UIView *row = [self threadComposerRowForTextView:threadTextView];
    [self.threadTextViews addObject:threadTextView];
    [self.threadStackView addArrangedSubview:row];
  }
  [self updateThreadPlaceholders];
}

- (BOOL)threadTextViewsAreValid {
  for (UITextView *threadTextView in self.threadTextViews) {
    NSString *text = threadTextView.text ?: @"";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ((trimmed.length == 0 && ((NFBComposeThreadRow *)threadTextView.superview).mediaItems.count == 0) || text.length > 300) return NO;
  }
  return YES;
}

- (BOOL)canAddThreadPost {
  if (self.posting || self.undoTweetPending) return NO;
  if (self.threadTextViews.count == 0) return [self hasComposerContent] && self.textView.text.length <= 300;
  UITextView *lastTextView = self.threadTextViews.lastObject;
  NSString *lastText = lastTextView.text ?: @"";
  NSString *trimmed = [lastText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return (trimmed.length > 0 || ((NFBComposeThreadRow *)lastTextView.superview).mediaItems.count > 0) && lastText.length <= 300;
}

- (void)updateThreadPlaceholders {
  for (UITextView *threadTextView in self.threadTextViews) {
    UILabel *placeholder = (UILabel *)[threadTextView.superview viewWithTag:9101];
    if ([placeholder isKindOfClass:UILabel.class]) placeholder.hidden = threadTextView.text.length > 0;
  }
}

- (CGFloat)composerTextColumnWidth {
  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
  return MAX(180.0, width - 16.0 - 40.0 - 12.0 - 16.0);
}

- (BOOL)textView:(UITextView *)textView needsInternalScrollingForHeight:(CGFloat)height {
  if (!textView) return NO;
  CGSize targetSize = CGSizeMake([self composerTextColumnWidth], CGFLOAT_MAX);
  CGFloat measured = ceil([textView sizeThatFits:targetSize].height);
  return measured > height + 1.0;
}

- (void)updatePrimaryTextViewScrollingForHeight:(CGFloat)height {
  BOOL scrollable = [self textView:self.textView needsInternalScrollingForHeight:height];
  if (self.textView.scrollEnabled != scrollable) self.textView.scrollEnabled = scrollable;
  self.textView.alwaysBounceVertical = scrollable;
  if (scrollable && self.textView.isFirstResponder) [self.textView scrollRangeToVisible:self.textView.selectedRange];
  else if (!scrollable && self.textView.contentOffset.y != 0.0) self.textView.contentOffset = CGPointZero;
}

- (void)updateComposerTextHeight {
  UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, NFBComposerTextBottomInset(self.mediaItems.count > 0 || self.quotePost != nil), 0);
  if (!UIEdgeInsetsEqualToEdgeInsets(self.textView.textContainerInset, insets)) self.textView.textContainerInset = insets;
  CGFloat measured = [self.textView sizeThatFits:CGSizeMake([self composerTextColumnWidth], CGFLOAT_MAX)].height;
  CGFloat textHeight = NFBComposerTextHeight(measured, self.textView.font.lineHeight, self.mediaItems.count > 0, self.quotePost != nil, self.threadTextViews.count > 0, self.undoTweetPending);
  if (fabs(self.textViewHeightConstraint.constant - textHeight) > .5) self.textViewHeightConstraint.constant = textHeight;
  [self updatePrimaryTextViewScrollingForHeight:textHeight];
}

- (void)updateComposerLayoutForThread {
  BOOL hasThreadRows = self.threadTextViews.count > 0;
  self.threadRootConnectorView.hidden = !hasThreadRows;
  if (hasThreadRows) {
    self.threadConnectorCollapsedConstraint.active = NO;
    self.threadConnectorBottomConstraint.active = YES;
  } else {
    self.threadConnectorBottomConstraint.active = NO;
    self.threadConnectorCollapsedConstraint.active = YES;
  }
  self.mediaTopConstraint.constant = self.mediaItems.count > 0 ? 8 : 0;
  [self updateComposerTextHeight];
  for (UITextView *threadTextView in self.threadTextViews) {
    [threadTextView invalidateIntrinsicContentSize];
    [threadTextView setNeedsLayout];
  }
  [self.view setNeedsLayout];
  [UIView animateWithDuration:0.18 animations:^{
    [self.view layoutIfNeeded];
  }];
}

- (void)cancelTapped {
  if (self.importingPhotos) {
    self.photoImportGeneration++;
    self.importingPhotos = NO;
    [self setPosting:NO];
  }
  if (self.undoTweetPending) {
    [self cancelUndoTweetCountdown];
    return;
  }
  if (![self hasComposerContent]) {
    [self dismissViewControllerAnimated:YES completion:nil];
    return;
  }
  NSMutableArray<NSDictionary<NSString *, id> *> *actions = [NSMutableArray array];
  __weak typeof(self) weakSelf = self;
  if (!self.replyToPost) {
    [actions addObject:@{
      @"id": @"save",
      @"title": @"Save draft",
      @"icon": @"nfb_lists",
      @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf saveCurrentDraftAndDismiss];
      } copy]
    }];
  }
  [actions addObject:@{
    @"id": @"delete",
    @"title": @"Delete",
    @"icon": @"nfb_trash",
    @"destructive": @YES,
    @"handler": [^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      [strongSelf dismissViewControllerAnimated:YES completion:nil];
    } copy]
  }];
  NFBPresentNeoFreeBirdActionSheet(self, actions, @"Cancel");
}

- (void)postTapped {
  if (self.posting || self.importingPhotos || self.resolvingQuote) return;
  if (self.undoTweetPending) {
    [self sendUndoTweetNow];
    return;
  }
  if (NFBUndoTweetEnabled() && NFBUndoTweetKindEnabled([self undoTweetKind])) {
    [self beginUndoTweetCountdown];
    return;
  }
  [self submitPostNow];
}

- (NSString *)undoTweetKind {
  if (self.threadTextViews.count > 0) return @"thread";
  if (self.replyToPost) return @"reply";
  if (self.quotePost) return @"quote";
  return @"tweet";
}

- (void)submitPostNow {
  NSString *text = self.textView.text ?: @"";
  NSArray<NSDictionary *> *threadPosts = [self threadPostsForDraft];
  NSString *accountDID = self.selectedComposerAccount[@"did"];
  if (!accountDID.length) {
    [self showError:@"Choose a logged-in account before posting."];
    return;
  }
  self.postingClient = [NFBAtprotoClient postingClientForAccountDID:accountDID];
  [self setPosting:YES];
  [self.postingClient createPostWithText:text
                                          replyToPost:self.replyToPost
                                            quotePost:self.quotePost
                                           mediaItems:self.mediaItems
                                            replyGate:self.replyGate
                                           completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {

        [self setPosting:NO];
        [self restoreTweetButtonTitle];
        [self showError:error.localizedDescription ?: @"Could not post."];
        return;
      }
      if (threadPosts.count > 0) {
        [self submitThreadPosts:threadPosts parentPost:value completion:^(NSError *threadError) {
          dispatch_async(dispatch_get_main_queue(), ^{

            [self setPosting:NO];
            if (threadError) {
              [self restoreTweetButtonTitle];
              [self showError:threadError.localizedDescription ?: @"Could not post thread."];
              return;
            }
            if (self.loadedLocalPostID.length > 0) [[NFBLocalPostStore sharedStore] deleteLocalPostWithID:self.loadedLocalPostID];
            if (self.completionHandler) self.completionHandler(YES);
            [self dismissViewControllerAnimated:YES completion:nil];
          });
        }];
        return;
      }

      [self setPosting:NO];
      if (self.loadedLocalPostID.length > 0) [[NFBLocalPostStore sharedStore] deleteLocalPostWithID:self.loadedLocalPostID];
      if (self.completionHandler) self.completionHandler(YES);
      [self dismissViewControllerAnimated:YES completion:nil];
    });
  }];
}

- (void)submitThreadPosts:(NSArray<NSDictionary *> *)posts parentPost:(NSDictionary *)parentPost completion:(void (^)(NSError *error))completion {
  if (!posts.count) { if (completion) completion(nil); return; }
  NSDictionary *post = posts.firstObject;
  NSArray *remaining = [posts subarrayWithRange:NSMakeRange(1, posts.count - 1)];
  [self.postingClient createPostWithText:post[@"text"] replyToPost:parentPost quotePost:nil mediaItems:post[@"mediaItems"] replyGate:nil completion:^(NSDictionary *value, NSError *error) {
    if (error) { if (completion) completion(error); return; }
    [self submitThreadPosts:remaining parentPost:value completion:completion];
  }];
}

- (void)beginUndoTweetCountdown {
  if (self.undoTweetPending || ![self hasComposerContent]) return;
  self.undoTweetPending = YES;
  self.undoTweetTotalInterval = MAX(1.0, (NSTimeInterval)NFBUndoTweetIntervalSeconds());
  self.undoTweetFireDate = [NSDate dateWithTimeIntervalSinceNow:self.undoTweetTotalInterval];
  self.textView.editable = NO;
  for (UITextView *threadTextView in self.threadTextViews) threadTextView.editable = NO;
  [self hideComposerSuggestions];
  [self.view endEditing:YES];
  [self.undoTweetBar resetProgress];
  [self setUndoTweetBarVisible:YES];
  [self updateUndoTweetCountdown];

  [self.undoTweetTimer invalidate];
  self.undoTweetTimer = [NSTimer timerWithTimeInterval:0.25
                                                target:self
                                              selector:@selector(undoTweetTimerTick:)
                                              userInfo:nil
                                               repeats:YES];
  [NSRunLoop.mainRunLoop addTimer:self.undoTweetTimer forMode:NSRunLoopCommonModes];
}

- (void)undoTweetTimerTick:(NSTimer *)timer {
  (void)timer;
  if (!self.undoTweetPending) return;
  if ([self.undoTweetFireDate timeIntervalSinceNow] <= 0.0) {
    [self finishUndoTweetCountdownAndSend];
    return;
  }
  [self updateUndoTweetCountdown];
}

- (void)updateUndoTweetCountdown {
  NSTimeInterval remaining = MAX(0.0, [self.undoTweetFireDate timeIntervalSinceNow]);
  [self.undoTweetBar updateWithRemainingTime:remaining totalInterval:self.undoTweetTotalInterval];
}

- (void)setUndoTweetBarVisible:(BOOL)visible {
  self.undoTweetBar.hidden = !visible;
  self.inputAccessoryBar.hidden = visible;
  self.inputAccessoryHeightConstraint.constant = visible ? 0.0 : 100.0;
  self.mediaPreviewView.userInteractionEnabled = !visible;
  self.threadStackView.userInteractionEnabled = !visible;
  self.accountButton.enabled = !visible;
  self.avatarView.userInteractionEnabled = !visible && self.accountButton != nil;
  [self updateDraftsButtonState];
  [self updateUndoTweetLayout];
  [self updateComposerLayoutForThread];
  [UIView animateWithDuration:0.22
                        delay:0.0
                      options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                   animations:^{
    self.undoTweetBar.alpha = visible ? 1.0 : 0.0;
    [self.view layoutIfNeeded];
  } completion:nil];
  if (visible) {
    CGRect controls = [self.undoTweetBar convertRect:self.undoTweetBar.bounds toView:self.contentView];
    [self.contentScrollView scrollRectToVisible:CGRectInset(controls, 0.0, -12.0) animated:YES];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.undoTweetBar.undoButton);
  } else {
    [self.undoTweetBar resetProgress];
  }
}

- (void)restoreTweetButtonTitle {
  [self setTweetButtonWidth:66.0];
  [self.tweetButton setTitle:(self.replyToPost ? @"Reply" : @"Tweet") forState:UIControlStateNormal];
}

- (void)cancelUndoTweetCountdown {
  if (!self.undoTweetPending) return;
  [self.undoTweetTimer invalidate];
  self.undoTweetTimer = nil;
  self.undoTweetFireDate = nil;
  self.undoTweetPending = NO;
  self.textView.editable = YES;
  for (UITextView *threadTextView in self.threadTextViews) threadTextView.editable = YES;
  [self restoreTweetButtonTitle];
  [self setUndoTweetBarVisible:NO];
  [self updateCount];
  [self.textView becomeFirstResponder];
}

- (void)sendUndoTweetNow {
  [self finishUndoTweetCountdownAndSend];
}

- (void)finishUndoTweetCountdownAndSend {
  if (!self.undoTweetPending) return;
  [self.undoTweetTimer invalidate];
  self.undoTweetTimer = nil;
  self.undoTweetFireDate = nil;
  self.undoTweetPending = NO;
  self.textView.editable = YES;
  for (UITextView *threadTextView in self.threadTextViews) threadTextView.editable = YES;
  [self restoreTweetButtonTitle];
  [self setUndoTweetBarVisible:NO];
  [self submitPostNow];
}

- (BOOL)hasComposerContent {
  NSString *text = [self.textView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  return text.length > 0 || self.mediaItems.count > 0 || self.quotePost != nil || self.threadTextViews.count > 0;
}

- (void)saveCurrentDraftAndDismiss {
  if (![self hasComposerContent]) {
    [self dismissViewControllerAnimated:YES completion:nil];
    return;
  }
  if (self.loadedLocalPostID.length > 0) [[NFBLocalPostStore sharedStore] deleteLocalPostWithID:self.loadedLocalPostID];
  [[NFBLocalPostStore sharedStore] saveDraftText:self.textView.text ?: @""
	                                      replyGate:self.replyGate
	                                     mediaItems:self.mediaItems
	                                    threadPosts:[self threadPostsForDraft] quotePost:self.quotePost account:self.selectedComposerAccount];
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)localPostStoreDidChange:(NSNotification *)notification {
  (void)notification;
  [self updateDraftsButtonState];
}

- (void)updateDraftsButtonState {
  if (self.undoTweetPending) {
    self.navigationItem.rightBarButtonItems = @[];
    return;
  }
  NSString *did = self.selectedComposerAccount[@"did"];
  NSUInteger count = [[NFBLocalPostStore sharedStore] draftPostsForAccountDID:did].count + [[NFBLocalPostStore sharedStore] scheduledPostsForAccountDID:did].count;
  self.draftsButton.enabled = count > 0;
  self.draftsButton.alpha = count > 0 ? 1.0 : 0.0;
  if (!self.tweetNavigationItem || !self.draftsNavigationItem) return;
  NSArray<UIBarButtonItem *> *items = count > 0 ? @[self.tweetNavigationItem, self.draftsNavigationItem] : @[self.tweetNavigationItem];
  if (![self.navigationItem.rightBarButtonItems isEqualToArray:items]) {
    self.navigationItem.rightBarButtonItems = items;
  }
}

- (void)setPosting:(BOOL)posting {
  _posting = posting;
  self.accountButton.enabled = !posting && !self.undoTweetPending;
  self.avatarView.userInteractionEnabled = !posting && !self.undoTweetPending && self.accountButton != nil;
  self.inputAccessoryBar.userInteractionEnabled = !posting;
  self.navigationItem.leftBarButtonItem.enabled = !posting || self.importingPhotos;
  self.mediaPreviewView.userInteractionEnabled = !posting;
  self.threadStackView.userInteractionEnabled = !posting;
  self.textView.editable = !posting;
  for (UITextView *threadTextView in self.threadTextViews) threadTextView.editable = !posting;
  if (posting) {
    self.tweetButton.enabled = NO;
    self.tweetButton.alpha = 0.62;
    NFBStartLoadingAnimation(self.spinner);
  } else {
    NFBStopLoadingAnimation(self.spinner);
    self.spinner.hidden = YES;
    [self updateCount];
  }
}

- (void)showError:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Post failed" message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateCount {
  UITextView *activeText = [self activeComposerTextView] ?: self.mediaTargetTextView ?: self.textView;
  NSUInteger rootCount = self.textView.text.length;
  NSUInteger count = activeText.text.length;
  NSInteger remaining = 300 - (NSInteger)count;
  BOOL hasAttachment = self.mediaItems.count > 0 || self.quotePost != nil;
  BOOL hasContent = count > 0 || hasAttachment;
  BOOL validThread = [self threadTextViewsAreValid];
  self.tweetButton.enabled = !self.posting && !self.importingPhotos && !self.resolvingQuote && (rootCount > 0 || hasAttachment) && rootCount <= 300 && validThread;
  self.tweetButton.alpha = self.tweetButton.enabled ? 1.0 : 0.45;
  self.threadAddButton.enabled = [self canAddThreadPost];
  self.threadAddButton.alpha = self.threadAddButton.enabled ? 1.0 : 0.45;
  self.placeholderLabel.hidden = rootCount > 0;
  [self updateThreadPlaceholders];

  CGRect ringBounds = self.countCircle.bounds;
  if (CGRectIsEmpty(ringBounds)) ringBounds = CGRectMake(0.0, 0.0, 22.0, 22.0);
  UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(ringBounds, 2.0, 2.0)];
  self.countTrackLayer.frame = ringBounds;
  self.countTrackLayer.path = path.CGPath;
  self.countProgressLayer.frame = ringBounds;
  self.countProgressLayer.path = path.CGPath;
  self.countProgressLayer.transform = CATransform3DMakeRotation(-M_PI_2, 0.0, 0.0, 1.0);

  CGFloat progress = MIN(1.0, (CGFloat)count / 300.0);
  self.countCircle.alpha = hasContent ? 1.0 : 0.0;
  self.countTrackLayer.strokeColor = NFBColorBorder().CGColor;
  self.countProgressLayer.strokeEnd = hasContent ? progress : 0.0;

  BOOL warning = remaining <= 20 && remaining >= 0;
  BOOL overLimit = remaining < 0;
  UIColor *countColor = overLimit ? UIColor.systemRedColor : (warning ? [UIColor colorWithRed:1.0 green:0.72 blue:0.18 alpha:1.0] : NFBColorAccent());
  self.countProgressLayer.strokeColor = countColor.CGColor;
  self.countLabel.text = (warning || overLimit) ? [NSString stringWithFormat:@"%ld", (long)remaining] : @"";
  self.countLabel.font = NFBFont(overLimit ? 10.0 : 11.0, NFBFontWeightRegular);
  self.countLabel.textColor = overLimit ? UIColor.systemRedColor : NFBColorSecondaryText();
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
  // Resolve a pasted link, or a completed typed link followed by whitespace;
  // don't issue lookups for every partial record key while someone is typing.
  if (textView == self.textView) self.shouldResolvePostLink = text.length > 1 || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound;
  return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
  if (self.applyingComposerTextAttributes) return;
  [self normalizePostLinksInTextView:textView];
  if (textView == self.textView) {
    [self applyComposerTextAttributesPreservingSelection];
    if (self.shouldResolvePostLink || self.resolvingQuote) [self resolvePastedQuoteIfNeeded];
    self.shouldResolvePostLink = NO;
  }
  [self updateComposerLayoutForThread];
  [self updateCount];
  if (textView == self.textView) [self updateComposerSuggestionsForCurrentSelection];
  [self scrollComposerTextViewIntoVisibleArea:textView animated:NO];
}

- (void)showQuotePreview:(NSDictionary *)post {
  if (self.quoteConstraints) [NSLayoutConstraint deactivateConstraints:self.quoteConstraints];
  [self.quotedPostView removeFromSuperview];
  self.quotedPostView = nil;
  self.removeQuoteButton = nil;
  self.quoteConstraints = nil;
  self.quotePost = post;
  self.threadTopWithoutQuote.active = post == nil;
  if (post) {
    NFBQuotedPostView *preview = [[NFBQuotedPostView alloc] init];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [preview configureWithPost:post];
    self.quotedPostView = preview;
    [self.contentView addSubview:preview];
    self.quoteConstraints = @[
      [preview.topAnchor constraintEqualToAnchor:self.mediaPreviewView.bottomAnchor constant:8],
      [preview.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
      [preview.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
      [self.threadStackView.topAnchor constraintEqualToAnchor:preview.bottomAnchor]];
    [NSLayoutConstraint activateConstraints:self.quoteConstraints];
    UIButton *remove = [UIButton buttonWithType:UIButtonTypeCustom];
    self.removeQuoteButton = remove;
    remove.translatesAutoresizingMaskIntoConstraints = NO;
    remove.backgroundColor = NFBColorBackground();
    remove.layer.cornerRadius = 14;
    remove.tintColor = NFBColorText();
    remove.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    [remove setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
    remove.accessibilityLabel = @"Remove quoted Tweet";
    [remove addTarget:self action:@selector(removePastedQuote) forControlEvents:UIControlEventTouchUpInside];
    [preview addSubview:remove];
    [NSLayoutConstraint activateConstraints:@[[remove.topAnchor constraintEqualToAnchor:preview.topAnchor constant:4], [remove.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:-4], [remove.widthAnchor constraintEqualToConstant:28], [remove.heightAnchor constraintEqualToConstant:28]]];
  }
  [self updateComposerLayoutForThread];
  [self updateCount];
}
- (void)removePastedQuote {
  self.quoteLookupGeneration++;
  self.resolvingQuote = NO;
  self.resolvingQuoteURL = nil;
  [self showQuotePreview:nil];
}
- (NSArray<NSTextCheckingResult *> *)linksInText:(NSString *)text {
  NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
  return [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)];
}
- (void)normalizePostLinksInTextView:(UITextView *)textView {
  if (textView.markedTextRange) return;
  NSMutableString *text = [textView.text mutableCopy] ?: [NSMutableString string];
  NSRange selection = textView.selectedRange;
  BOOL changed = NO;
  for (NSTextCheckingResult *match in [[self linksInText:text] reverseObjectEnumerator]) {
    NSDictionary *route = NFBPostLink(match.URL.absoluteString);
    NSString *replacement = route[@"url"];
    if (!replacement || [[text substringWithRange:match.range] isEqual:replacement]) continue;
    [text replaceCharactersInRange:match.range withString:replacement];
    if (selection.location >= NSMaxRange(match.range)) selection.location = selection.location - match.range.length + replacement.length;
    else if (selection.location > match.range.location) selection.location = match.range.location + replacement.length;
    changed = YES;
  }
  if (changed) {
    textView.text = text;
    selection.location = MIN(selection.location, text.length);
    selection.length = MIN(selection.length, text.length - selection.location);
    textView.selectedRange = selection;
  }
}
- (void)resolvePastedQuoteIfNeeded {
  if (self.quotePost || self.textView.markedTextRange) return;
  NSDictionary *route = nil;
  for (NSTextCheckingResult *match in [self linksInText:self.textView.text ?: @""]) {
    route = NFBPostLink(match.URL.absoluteString);
    if (route) break;
  }
  NSString *url = route[@"url"];
  if (self.resolvingQuote && [self.resolvingQuoteURL isEqual:url]) return;
  NSUInteger generation = ++self.quoteLookupGeneration;
  self.resolvingQuote = route != nil;
  self.resolvingQuoteURL = url;
  if (!route) return;
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) self = weakSelf;
    if (!self || generation != self.quoteLookupGeneration) return;
    void (^finish)(NSDictionary *, NSError *) = ^(NSDictionary *post, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.quoteLookupGeneration) return;
        self.resolvingQuote = NO;
        NSRange range = [self.textView.text rangeOfString:url];
        if (range.location == NSNotFound || self.quotePost) { [self updateCount]; return; }
        if (error || ![post[@"cid"] length] || ![post[@"uri"] length]) {
          [self updateCount];
          [self showError:@"That quoted Tweet could not be loaded. The Bluesky link has been kept in your text."];
          return;
        }
        NSString *text = [self.textView.text stringByReplacingCharactersInRange:range withString:@""];
        self.textView.text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        self.textView.selectedRange = NSMakeRange(MIN(range.location, self.textView.text.length), 0);
        [self applyComposerTextAttributesPreservingSelection];
        [self showQuotePreview:post];
      });
    };
    void (^fetch)(NSString *) = ^(NSString *did) {
      NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, route[@"rkey"]];
      [[NFBAtprotoClient sharedClient] fetchPostForURI:uri completion:finish];
    };
    NSString *actor = route[@"actor"];
    if ([actor hasPrefix:@"did:"]) fetch(actor);
    else [[NFBAtprotoClient sharedClient] fetchProfileForActor:actor completion:^(NSDictionary *profile, NSError *error) {
      if (!error && [profile[@"did"] length]) fetch(profile[@"did"]);
      else finish(nil, error);
    }];
  });
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
  if (textView == self.textView || [self.threadTextViews containsObject:textView]) { self.mediaTargetTextView = textView; [self updateCount]; }
  [self scrollComposerTextViewIntoVisibleArea:textView animated:YES];
}

- (void)textViewDidChangeSelection:(UITextView *)textView {
  if (self.applyingComposerTextAttributes) return;
  if (textView == self.textView) [self updateComposerSuggestionsForCurrentSelection];
  if (textView.isFirstResponder) [self scrollComposerTextViewIntoVisibleArea:textView animated:NO];
}

- (void)applyComposerTextAttributesPreservingSelection {
  if (!self.textView || self.applyingComposerTextAttributes) return;
  if (self.textView.markedTextRange) return;
  NSString *text = self.textView.text ?: @"";
  NSRange selection = self.textView.selectedRange;
  CGPoint contentOffset = self.textView.contentOffset;
  self.applyingComposerTextAttributes = YES;
  NSAttributedString *attributed = NFBComposerTextAttributedString(text, self.textView.font ?: NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular));
  self.textView.attributedText = attributed;
  NSUInteger safeLocation = MIN(selection.location, self.textView.text.length);
  NSUInteger safeLength = MIN(selection.length, self.textView.text.length - safeLocation);
  self.textView.selectedRange = NSMakeRange(safeLocation, safeLength);
  self.textView.typingAttributes = @{
    NSFontAttributeName: self.textView.font ?: NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular),
    NSForegroundColorAttributeName: NFBColorText()
  };
  self.textView.contentOffset = contentOffset;
  self.applyingComposerTextAttributes = NO;
}

- (NSDictionary *)composerSuggestionContext {
  if (!self.textView || self.textView.markedTextRange) return nil;
  NSRange selection = self.textView.selectedRange;
  NSString *text = self.textView.text ?: @"";
  if (selection.length != 0 || selection.location > text.length || text.length == 0) return nil;
  NSUInteger cursor = selection.location;
  NSUInteger start = cursor;
  NSCharacterSet *breakCharacters = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (start > 0) {
    unichar character = [text characterAtIndex:start - 1];
    if ([breakCharacters characterIsMember:character]) break;
    if (character == '(' || character == '[' || character == '{' || character == '"' || character == '\'') break;
    start--;
  }
  if (start >= cursor) return nil;
  NSRange range = NSMakeRange(start, cursor - start);
  NSString *token = [text substringWithRange:range];
  if (token.length == 0) return nil;
  unichar first = [token characterAtIndex:0];
  if (first != '@' && first != '#') return nil;
  if ([token rangeOfString:@"/"].location != NSNotFound) return nil;
  NSString *query = token.length > 1 ? [token substringFromIndex:1] : @"";
  NSString *kind = first == '@' ? @"actor" : @"hashtag";
  return @{@"kind": kind, @"query": query, @"range": [NSValue valueWithRange:range]};
}

- (void)updateComposerSuggestionsForCurrentSelection {
  NSDictionary *context = [self composerSuggestionContext];
  if (!context) {
    [self hideComposerSuggestions];
    return;
  }
  self.activeSuggestionKind = context[@"kind"];
  self.activeSuggestionQuery = context[@"query"] ?: @"";
  self.activeSuggestionRange = [context[@"range"] rangeValue];
  self.suggestionGeneration++;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchComposerSuggestions) object:nil];
  [self performSelector:@selector(fetchComposerSuggestions) withObject:nil afterDelay:0.18];
}

- (void)fetchComposerSuggestions {
  NSString *kind = [self.activeSuggestionKind copy] ?: @"";
  NSString *query = [self.activeSuggestionQuery copy] ?: @"";
  NSUInteger generation = self.suggestionGeneration;
  if ([kind isEqualToString:@"actor"]) {
    if (query.length == 0) {
      [self hideComposerSuggestions];
      return;
    }
    [[NFBAtprotoClient sharedClient] searchActors:query limit:8 completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
      (void)cursor;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.suggestionGeneration || ![self.activeSuggestionKind isEqualToString:@"actor"] || ![self.activeSuggestionQuery isEqualToString:query]) return;
        NSMutableArray<NSDictionary *> *suggestions = [NSMutableArray array];
        if (!error) {
          for (NSDictionary *profile in items ?: @[]) {
            if ([profile isKindOfClass:NSDictionary.class]) [suggestions addObject:@{@"type": @"actor", @"profile": profile}];
            if (suggestions.count >= 8) break;
          }
        }
        [self showComposerSuggestions:suggestions];
      });
    }];
    return;
  }
  if ([kind isEqualToString:@"hashtag"]) {
    [self fetchHashtagSuggestionsForQuery:query generation:generation];
  }
}

- (NSString *)normalizedHashtagFromText:(NSString *)text {
  NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  if ([trimmed hasPrefix:@"#"]) trimmed = [trimmed substringFromIndex:1];
  NSMutableString *tag = [NSMutableString string];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  for (NSUInteger index = 0; index < trimmed.length; index++) {
    unichar character = [trimmed characterAtIndex:index];
    if ([allowed characterIsMember:character]) [tag appendFormat:@"%C", character];
  }
  if (tag.length == 0) return @"";
  return [@"#" stringByAppendingString:tag];
}

- (NSArray<NSDictionary *> *)hashtagSuggestionsFromTags:(NSArray<NSString *> *)tags query:(NSString *)query {
  NSString *lowerQuery = (query ?: @"").lowercaseString;
  NSMutableArray<NSDictionary *> *suggestions = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (NSString *rawTag in tags ?: @[]) {
    NSString *tag = [self normalizedHashtagFromText:rawTag];
    if (tag.length <= 1) continue;
    NSString *body = [[tag substringFromIndex:1] lowercaseString];
    if (lowerQuery.length > 0 && ![body hasPrefix:lowerQuery]) continue;
    if ([seen containsObject:body]) continue;
    [seen addObject:body];
    [suggestions addObject:@{@"type": @"hashtag", @"tag": tag}];
    if (suggestions.count >= 8) break;
  }
  return suggestions;
}

- (NSArray<NSString *> *)hashtagsFromSearchItems:(NSArray<NSDictionary *> *)items {
  NSMutableArray<NSString *> *tags = [NSMutableArray array];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"#[\\p{L}\\p{M}\\p{N}_]+" options:0 error:nil];
  for (NSDictionary *item in items ?: @[]) {
    NSDictionary *post = [item[@"post"] isKindOfClass:NSDictionary.class] ? item[@"post"] : @{};
    NSString *text = [NFBAtprotoClient textForPost:post];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches) {
      if (match.range.location != NSNotFound && NSMaxRange(match.range) <= text.length) {
        [tags addObject:[text substringWithRange:match.range]];
      }
    }
  }
  return tags;
}

- (void)fetchHashtagSuggestionsForQuery:(NSString *)query generation:(NSUInteger)generation {
  [[NFBAtprotoClient sharedClient] fetchTrendingTopicsWithCompletion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    NSMutableArray<NSString *> *trendTags = [NSMutableArray array];
    if (!error) {
      for (NSDictionary *item in items ?: @[]) {
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        NSString *displayName = [item[@"displayName"] isKindOfClass:NSString.class] ? item[@"displayName"] : @"";
        NSString *queryText = [item[@"query"] isKindOfClass:NSString.class] ? item[@"query"] : @"";
        if (name.length > 0) [trendTags addObject:name];
        if (displayName.length > 0) [trendTags addObject:displayName];
        if (queryText.length > 0) [trendTags addObject:queryText];
      }
    }
    NSArray<NSDictionary *> *trendSuggestions = [self hashtagSuggestionsFromTags:trendTags query:query];
    if (trendSuggestions.count >= 5 || query.length == 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == self.suggestionGeneration && [self.activeSuggestionKind isEqualToString:@"hashtag"] && [self.activeSuggestionQuery isEqualToString:query]) [self showComposerSuggestions:trendSuggestions];
      });
      return;
    }
    NSString *searchQuery = [@"#" stringByAppendingString:query ?: @""];
    [[NFBAtprotoClient sharedClient] searchPosts:searchQuery cursor:nil completion:^(NSArray<NSDictionary *> *postItems, NSString *postCursor, NSError *postError) {
      (void)postCursor;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.suggestionGeneration || ![self.activeSuggestionKind isEqualToString:@"hashtag"] || ![self.activeSuggestionQuery isEqualToString:query]) return;
        NSMutableArray<NSDictionary *> *combined = [trendSuggestions mutableCopy];
        NSMutableArray<NSString *> *seenTags = [NSMutableArray array];
        for (NSDictionary *suggestion in combined) [seenTags addObject:[suggestion[@"tag"] lowercaseString] ?: @""];
        if (!postError) {
          NSArray<NSDictionary *> *postSuggestions = [self hashtagSuggestionsFromTags:[self hashtagsFromSearchItems:postItems] query:query];
          for (NSDictionary *suggestion in postSuggestions) {
            NSString *tag = [suggestion[@"tag"] lowercaseString] ?: @"";
            if ([seenTags containsObject:tag]) continue;
            [seenTags addObject:tag];
            [combined addObject:suggestion];
            if (combined.count >= 8) break;
          }
        }
        [self showComposerSuggestions:combined];
      });
    }];
  }];
}

- (void)showComposerSuggestions:(NSArray<NSDictionary *> *)suggestions {
  self.composerSuggestions = suggestions ?: @[];
  [self.suggestionsTableView reloadData];
  CGFloat height = self.composerSuggestions.count > 0 ? MIN(216.0, self.composerSuggestions.count * 54.0) : 0.0;
  self.suggestionsHeightConstraint.constant = height;
  BOOL visible = height > 0.0;
  if (visible) self.suggestionsTableView.hidden = NO;
  [UIView animateWithDuration:0.16 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
    self.suggestionsTableView.alpha = visible ? 1.0 : 0.0;
    [self.view layoutIfNeeded];
  } completion:^(BOOL finished) {
    (void)finished;
    if (!visible) self.suggestionsTableView.hidden = YES;
  }];
}

- (void)hideComposerSuggestions {
  self.suggestionGeneration++;
  self.activeSuggestionKind = nil;
  self.activeSuggestionQuery = nil;
  self.activeSuggestionRange = NSMakeRange(NSNotFound, 0);
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchComposerSuggestions) object:nil];
  [self showComposerSuggestions:@[]];
}

- (void)insertComposerSuggestion:(NSDictionary *)suggestion {
  if (self.activeSuggestionRange.location == NSNotFound) return;
  NSString *type = [suggestion[@"type"] isKindOfClass:NSString.class] ? suggestion[@"type"] : @"";
  NSString *replacement = @"";
  if ([type isEqualToString:@"actor"]) {
    NSDictionary *profile = [suggestion[@"profile"] isKindOfClass:NSDictionary.class] ? suggestion[@"profile"] : @{};
    NSString *handle = [NFBAtprotoClient handleForProfile:profile];
    replacement = handle.length > 0 ? [NSString stringWithFormat:@"@%@ ", handle] : @"";
  } else {
    NSString *tag = [suggestion[@"tag"] isKindOfClass:NSString.class] ? suggestion[@"tag"] : @"";
    replacement = tag.length > 0 ? [tag stringByAppendingString:@" "] : @"";
  }
  if (replacement.length == 0) return;
  NSString *text = self.textView.text ?: @"";
  if (NSMaxRange(self.activeSuggestionRange) > text.length) return;
  NSMutableString *updated = [text mutableCopy];
  [updated replaceCharactersInRange:self.activeSuggestionRange withString:replacement];
  NSUInteger cursor = self.activeSuggestionRange.location + replacement.length;
  self.textView.text = updated;
  self.textView.selectedRange = NSMakeRange(MIN(cursor, self.textView.text.length), 0);
  [self applyComposerTextAttributesPreservingSelection];
  [self updateComposerLayoutForThread];
  [self updateCount];
  [self hideComposerSuggestions];
}

#pragma mark - Composer suggestions table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)section;
  if (tableView == self.suggestionsTableView) return (NSInteger)self.composerSuggestions.count;
  return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if (tableView == self.suggestionsTableView) {
    NFBComposeSuggestionCell *cell = [tableView dequeueReusableCellWithIdentifier:NFBComposeSuggestionCellIdentifier forIndexPath:indexPath];
    [cell configureWithSuggestion:self.composerSuggestions[(NSUInteger)indexPath.row]];
    return cell;
  }
  return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (tableView != self.suggestionsTableView) return;
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if ((NSUInteger)indexPath.row >= self.composerSuggestions.count) return;
  [self insertComposerSuggestion:self.composerSuggestions[(NSUInteger)indexPath.row]];
}

- (void)updateReplyGateChrome {
  if (!self.conversationLabel) return;
  self.conversationLabel.text = NFBComposeReplyGateOption(self.replyGate)[@"buttonTitle"];
}

- (void)replyAccountTapped {
  if (self.posting || self.undoTweetPending) return;
  NSArray<NSDictionary *> *accounts = [self savedComposerAccounts];
  if (accounts.count <= 1) return;
  UITextView *activeTextView = [self activeComposerTextView];
  BOOL shouldResumeEditing = activeTextView != nil;
  [activeTextView resignFirstResponder];

  NFBComposeAccountPickerViewController *sheet = [[NFBComposeAccountPickerViewController alloc] init];
  sheet.accounts = accounts;
  sheet.selectedDID = [self.selectedComposerAccount[@"did"] isKindOfClass:NSString.class] ? self.selectedComposerAccount[@"did"] : @"";
  sheet.titleText = self.replyToPost ? @"Reply from" : @"Tweet from";
  sheet.modalPresentationStyle = UIModalPresentationOverFullScreen;
  sheet.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

  __weak typeof(self) weakSelf = self;
  sheet.completionHandler = ^(NSDictionary *account) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if ([account isKindOfClass:NSDictionary.class]) {
      [strongSelf updateSelectedComposerAccount:account];
      if (@available(iOS 10.0, *)) {
        UISelectionFeedbackGenerator *feedback = [[UISelectionFeedbackGenerator alloc] init];
        [feedback selectionChanged];
      }
    }
    if (shouldResumeEditing) [activeTextView becomeFirstResponder];
  };
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)replyGateTapped {
  if (self.replyToPost) return;
  BOOL shouldResumeEditing = self.textView.isFirstResponder;
  [self.textView resignFirstResponder];

  NFBReplyGatePickerViewController *sheet = [[NFBReplyGatePickerViewController alloc] init];
  sheet.selectedGate = self.replyGate ?: NFBComposeReplyGateEveryone;
  sheet.modalPresentationStyle = UIModalPresentationOverFullScreen;
  sheet.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

  __weak typeof(self) weakSelf = self;
  sheet.completionHandler = ^(NSString *gate) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if (gate.length > 0) {
      strongSelf.replyGate = gate;
      [strongSelf updateReplyGateChrome];
    }
    if (shouldResumeEditing) [strongSelf.textView becomeFirstResponder];
  };
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)mediaButtonTapped {
  if (self.posting || self.importingPhotos || self.undoTweetPending) return;
  self.mediaTargetTextView = [self activeComposerTextView] ?: self.mediaTargetTextView ?: self.textView;
  if (self.editingMediaItems.count >= NFBMaxPhotosPerPost || [self containsVideoLikeMedia]) {
    [self showError:@"Attach up to 10 photos, or one video/GIF, to each Tweet."]; return;
  }
  [self.view endEditing:YES];
  NFBMediaLibraryViewController *library = [NFBMediaLibraryViewController new];
  library.photoLimit = NFBMaxPhotosPerPost - self.editingMediaItems.count;
  library.allowsVideo = self.editingMediaItems.count == 0;
  __weak typeof(self) weakSelf = self;
  library.selectionHandler = ^(NSArray<PHAsset *> *assets) {
    __strong typeof(weakSelf) self = weakSelf;
    if (!self || !assets.count) return;
    self.importingPhotos = YES; self.photoImportGeneration++;
    [self resetMediaEditingState]; [self setPosting:YES];
    [self importLibraryAssets:assets index:0 generation:self.photoImportGeneration];
  };
  library.cameraHandler = ^(BOOL video) {
    __strong typeof(weakSelf) self = weakSelf;
    if (!self) return;
    UIImagePickerController *camera = [UIImagePickerController new];
    camera.sourceType = UIImagePickerControllerSourceTypeCamera; camera.delegate = self;
    camera.mediaTypes = video ? @[@"public.movie"] : @[@"public.image"];
    camera.videoMaximumDuration = NFBMaxVideoDuration;
    camera.videoQuality = UIImagePickerControllerQualityTypeHigh;
    [self presentViewController:camera animated:YES completion:nil];
  };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:library];
  NFBApplyNavigationAppearance(nav); nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)importLibraryAssets:(NSArray<PHAsset *> *)assets index:(NSUInteger)index generation:(NSUInteger)generation {
  if (!self.importingPhotos || generation != self.photoImportGeneration) return;
  if (index >= assets.count) { self.importingPhotos = NO; [self setPosting:NO]; return; }
  PHAsset *asset = assets[index];
  if (asset.mediaType == PHAssetMediaTypeVideo) {
    PHVideoRequestOptions *options = [PHVideoRequestOptions new]; options.networkAccessAllowed = YES;
    options.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat;
    [PHImageManager.defaultManager requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *video, AVAudioMix *mix, NSDictionary *info) {
      void (^ready)(NSURL *, NSError *) = ^(NSURL *url, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (!self.importingPhotos || generation != self.photoImportGeneration) return;
          self.importingPhotos = NO; [self setPosting:NO];
          if (url) [self presentVideoTrimControllerForURL:url];
          else [self showError:error.localizedDescription ?: @"That video could not be downloaded from your library."];
        });
      };
      if ([video isKindOfClass:AVURLAsset.class]) ready(((AVURLAsset *)video).URL, nil);
      else if (video) {
        AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:video presetName:AVAssetExportPresetHighestQuality];
        exporter.outputFileType = AVFileTypeMPEG4;
        exporter.outputURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"nfb-library-%@.mp4", NSUUID.UUID.UUIDString]]];
        [exporter exportAsynchronouslyWithCompletionHandler:^{ ready(exporter.status == AVAssetExportSessionStatusCompleted ? exporter.outputURL : nil, exporter.error); }];
      } else ready(nil, info[PHImageErrorKey]);
    }];
    return;
  }
  PHImageRequestOptions *options = [PHImageRequestOptions new]; options.networkAccessAllowed = YES; options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
  [PHImageManager.defaultManager requestImageDataAndOrientationForAsset:asset options:options resultHandler:^(NSData *data, NSString *uti, CGImagePropertyOrientation orientation, NSDictionary *info) {
    if ([info[PHImageResultIsDegradedKey] boolValue]) return;
    UIImage *image = [UIImage imageWithData:data];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self.importingPhotos || generation != self.photoImportGeneration) return;
      if (!image) { self.importingPhotos = NO; [self setPosting:NO]; [self showError:@"That photo could not be downloaded. Photos already added are still in your draft."]; return; }
      NSUInteger count = self.editingMediaItems.count;
      [self addImageAttachment:image type:@"photo" mimeType:@"image/jpeg" altText:nil];
      if (count == self.editingMediaItems.count) { self.importingPhotos = NO; [self setPosting:NO]; return; }
      [self importLibraryAssets:assets index:index + 1 generation:generation];
    });
  }];
}

- (void)gifButtonTapped {
  if (self.importingPhotos) return;
  [self restoreSystemKeyboardIfNeededAndReload:NO];
  NFBGIFPickerViewController *picker = [[NFBGIFPickerViewController alloc] init];
  picker.delegate = self;
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)draftsTapped {
  if (self.importingPhotos) return;
  [self restoreSystemKeyboardIfNeededAndReload:NO];
  NFBDraftsViewController *drafts = [[NFBDraftsViewController alloc] init];
  drafts.accountDID = self.selectedComposerAccount[@"did"];
  __weak typeof(self) weakSelf = self;
  drafts.selectionHandler = ^(NSDictionary *localPost) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if (!localPost) {
      [strongSelf clearComposerContent];
      [strongSelf.textView becomeFirstResponder];
      return;
    }
    [strongSelf loadLocalPostForEditing:localPost];
  };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:drafts];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)scheduleButtonTapped {
  if (self.importingPhotos) return;
  [self restoreSystemKeyboardIfNeededAndReload:NO];
  if (self.replyToPost || self.quotePost || self.threadTextViews.count) {
    [self showError:@"Scheduling is available for single new Tweets only. You can save this thread as a draft."];
    return;
  }
  NFBScheduleTweetViewController *sheet = [[NFBScheduleTweetViewController alloc] init];
  sheet.modalPresentationStyle = UIModalPresentationOverFullScreen;
  sheet.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  __weak typeof(self) weakSelf = self;
  sheet.completionHandler = ^(NSDate *scheduledDate) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || !scheduledDate) {
      [strongSelf.textView becomeFirstResponder];
      return;
    }
    if (![strongSelf hasComposerContent]) {
      [strongSelf showError:@"Add text, a photo, a GIF, or a video before scheduling."];
      [strongSelf.textView becomeFirstResponder];
      return;
    }
    if (strongSelf.loadedLocalPostID.length > 0) [[NFBLocalPostStore sharedStore] deleteLocalPostWithID:strongSelf.loadedLocalPostID];
    [[NFBLocalPostStore sharedStore] saveScheduledPostText:strongSelf.textView.text ?: @""
                                                replyGate:strongSelf.replyGate
                                               mediaItems:strongSelf.mediaItems
                                            scheduledDate:scheduledDate account:strongSelf.selectedComposerAccount];
    if (strongSelf.completionHandler) strongSelf.completionHandler(NO);
    [strongSelf dismissViewControllerAnimated:YES completion:nil];
  };
  [self presentViewController:sheet animated:NO completion:nil];
}

- (void)loadLocalPostForEditing:(NSDictionary *)localPost {
  for (NSDictionary *account in [self savedComposerAccounts]) {
    if ([account[@"did"] isEqual:localPost[@"accountDID"]]) { [self updateSelectedComposerAccount:account]; break; }
  }
  self.mediaTargetTextView = self.textView;
  [self removePastedQuote];
  if ([localPost[@"quotePost"] isKindOfClass:NSDictionary.class]) [self showQuotePreview:localPost[@"quotePost"]];
  NSString *postID = [localPost[@"id"] isKindOfClass:NSString.class] ? localPost[@"id"] : @"";
  self.loadedLocalPostID = postID;
  self.textView.text = [localPost[@"text"] isKindOfClass:NSString.class] ? localPost[@"text"] : @"";
  self.replyGate = [localPost[@"replyGate"] isKindOfClass:NSString.class] ? localPost[@"replyGate"] : NFBComposeReplyGateEveryone;
  [self.mediaItems removeAllObjects];
  [self.mediaItems addObjectsFromArray:[[NFBLocalPostStore sharedStore] mediaItemsForLocalPost:localPost]];
  NSArray *threadTexts = [localPost[@"threadTexts"] isKindOfClass:NSArray.class] ? localPost[@"threadTexts"] : @[];
  [self restoreThreadComposerRowsWithTexts:threadTexts];
  if (postID.length > 0) [[NFBLocalPostStore sharedStore] deleteLocalPostWithID:postID];
  NSArray *threadPosts = localPost[@"threadPosts"];
  if ([threadPosts isKindOfClass:NSArray.class]) {
    [self clearThreadComposerRows];
    for (NSDictionary *post in threadPosts) {
      UITextView *text = [self newComposerTextView];
      text.text = post[@"text"] ?: @"";
      NFBComposeThreadRow *row = (NFBComposeThreadRow *)[self threadComposerRowForTextView:text];
      [self.threadTextViews addObject:text];
      [self.threadStackView addArrangedSubview:row];
      [row.mediaItems addObjectsFromArray:[[NFBLocalPostStore sharedStore] mediaItemsForLocalPost:post]];
      self.mediaTargetTextView = text;
      [self updateMediaPreview];
    }
    self.mediaTargetTextView = self.textView;
  }
  [self updateReplyGateChrome];
  [self updateMediaPreview];
  [self updateComposerLayoutForThread];
  [self updateCount];
  [self.textView becomeFirstResponder];
}

- (void)clearComposerContent {
  [self removePastedQuote];
  self.loadedLocalPostID = nil;
  self.textView.text = @"";
  self.replyGate = NFBComposeReplyGateEveryone;
  [self.mediaItems removeAllObjects];
  [self clearThreadComposerRows];
  [self updateReplyGateChrome];
  [self updateMediaPreview];
  [self updateComposerLayoutForThread];
  [self updateCount];
}

- (void)emojiButtonTapped {
  if (self.usingEmojiPicker) {
    [self restoreSystemKeyboardIfNeededAndReload:YES];
    return;
  }
  if (!self.emojiInputView) {
    self.emojiInputView = [[NFBEmojiInputView alloc] initWithFrame:CGRectZero];
    self.emojiInputView.delegate = self;
  }
  self.usingEmojiPicker = YES;
  self.textView.inputView = self.emojiInputView;
  [self.emojiInputView applyTheme];
  if (!self.textView.isFirstResponder) [self.textView becomeFirstResponder];
  [self.textView reloadInputViews];
}

- (void)restoreSystemKeyboardIfNeededAndReload:(BOOL)reload {
  if (!self.usingEmojiPicker && self.textView.inputView == nil) return;
  self.usingEmojiPicker = NO;
  self.textView.inputView = nil;
  if (reload) {
    if (!self.textView.isFirstResponder) [self.textView becomeFirstResponder];
    [self.textView reloadInputViews];
  }
}

- (void)emojiInputView:(NFBEmojiInputView *)inputView didSelectEmoji:(NSString *)emoji {
  (void)inputView;
  if (emoji.length == 0) return;
  NSRange range = self.textView.selectedRange;
  NSString *text = self.textView.text ?: @"";
  if (range.location == NSNotFound || NSMaxRange(range) > text.length) range = NSMakeRange(text.length, 0);
  NSString *updated = [text stringByReplacingCharactersInRange:range withString:emoji];
  self.textView.text = updated;
  self.textView.selectedRange = NSMakeRange(range.location + emoji.length, 0);
  [self textViewDidChange:self.textView];
}

- (void)emojiInputViewDidRequestKeyboard:(NFBEmojiInputView *)inputView {
  (void)inputView;
  [self restoreSystemKeyboardIfNeededAndReload:YES];
}

- (void)disabledComposerToolTapped {
  [self showError:@"That composer tool is not available yet."];
}

- (void)presentImagePickerForVideo:(BOOL)video {
  if (!video) {
    if (self.editingMediaItems.count >= NFBMaxPhotosPerPost || [self containsVideoLikeMedia]) {
      [self showError:@"Attach up to 10 photos, or one video/GIF."];
      return;
    }
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = NFBMaxPhotosPerPost - self.editingMediaItems.count;
    // The Linux toolchain lacks compiler-rt's @available runtime helper.
    // A selector check also supports iOS 14, where ordered selection is absent.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    if ([configuration respondsToSelector:@selector(setSelection:)]) configuration.selection = PHPickerConfigurationSelectionOrdered;
#pragma clang diagnostic pop
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
    return;
  }
  if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
    [self showError:@"Photo Library is not available."];
    return;
  }
  UIImagePickerController *picker = [[UIImagePickerController alloc] init];
  picker.delegate = self;
  picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
  picker.mediaTypes = video ? @[@"public.movie"] : @[@"public.image"];
  picker.videoMaximumDuration = NFBMaxVideoDuration;
  picker.allowsEditing = NO;
  picker.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  [picker dismissViewControllerAnimated:YES completion:^{
    if (results.count == 0) return;
    self.photoImportGeneration++;
    self.importingPhotos = YES;
    [self resetMediaEditingState];
    [self setPosting:YES];
    [self importPhotoResults:results index:0];
  }];
}

- (void)importPhotoResults:(NSArray<PHPickerResult *> *)results index:(NSUInteger)index {
  if (index >= results.count || self.editingMediaItems.count >= NFBMaxPhotosPerPost) {
    self.importingPhotos = NO;
    [self setPosting:NO];
    return;
  }
  NSUInteger generation = self.photoImportGeneration;
  // Decode serially and downsample before retaining ten camera-sized images.
  [results[index].itemProvider loadFileRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSURL *url, NSError *error) {
    UIImage *image = nil;
    if (url && !error) {
      CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
      if (source) {
        NSDictionary *options = @{
          (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
          (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
          (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(NFBMaxImageDimension)
        };
        CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        if (thumbnail) { image = [UIImage imageWithCGImage:thumbnail]; CGImageRelease(thumbnail); }
        CFRelease(source);
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self.importingPhotos || generation != self.photoImportGeneration) return;
      if (!image) {
        self.importingPhotos = NO;
        [self setPosting:NO];
        [self showError:error.localizedDescription ?: @"That photo could not be opened. Photos already added are still in your draft."];
        return;
      }
      NSUInteger previousCount = self.editingMediaItems.count;
      [self addImageAttachment:image type:@"photo" mimeType:@"image/jpeg" altText:@""];
      if (self.editingMediaItems.count == previousCount) {
        self.importingPhotos = NO;
        [self setPosting:NO];
        return;
      }
      [self importPhotoResults:results index:index + 1];
    });
  }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
  [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
  NSString *mediaType = [info[UIImagePickerControllerMediaType] isKindOfClass:NSString.class] ? info[UIImagePickerControllerMediaType] : @"";
  if ([mediaType isEqualToString:@"public.movie"]) {
    NSURL *url = [info[UIImagePickerControllerMediaURL] isKindOfClass:NSURL.class] ? info[UIImagePickerControllerMediaURL] : nil;
    [picker dismissViewControllerAnimated:YES completion:^{
      if (!url) {
        [self showError:@"That video could not be opened."];
        return;
      }
      [self resetMediaEditingState];
      [self presentVideoTrimControllerForURL:url];
    }];
    return;
  }

  UIImage *image = [info[UIImagePickerControllerOriginalImage] isKindOfClass:UIImage.class] ? info[UIImagePickerControllerOriginalImage] : nil;
  [picker dismissViewControllerAnimated:YES completion:^{
    if (!image) {
      [self showError:@"That photo could not be opened."];
      return;
    }
    [self resetMediaEditingState];
    self.pendingOriginalImage = image;
    NFBCropViewController *crop = [[NFBCropViewController alloc] initWithImage:image];
    crop.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:crop];
    NFBApplyDarkNavigationAppearance(nav);
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
  }];
}

- (void)presentVideoTrimControllerForURL:(NSURL *)url {
  NFBVideoTrimViewController *trim = [[NFBVideoTrimViewController alloc] initWithURL:url];
  trim.delegate = self;
  if (self.editingMediaItem && self.editingMediaIndex < self.editingMediaItems.count) trim.contentWarnings = self.editingMediaItems[self.editingMediaIndex][@"contentWarnings"];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:trim];
  NFBApplyDarkNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)cropViewControllerDidCancel:(NFBCropViewController *)controller {
  [self resetMediaEditingState];
  [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)cropViewController:(NFBCropViewController *)controller didFinishWithImage:(UIImage *)image {
  NSString *altText = controller.pendingAltText ?: @"";
  [controller dismissViewControllerAnimated:YES completion:^{
    [self addImageAttachment:image type:@"photo" mimeType:@"image/jpeg" altText:altText];
  }];
}

- (void)videoTrimViewControllerDidCancel:(NFBVideoTrimViewController *)controller {
  [self resetMediaEditingState];
  [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)videoTrimViewController:(NFBVideoTrimViewController *)controller didFinishWithURL:(NSURL *)url thumbnail:(UIImage *)thumbnail duration:(NSTimeInterval)duration dimensions:(CGSize)dimensions {
  [controller dismissViewControllerAnimated:YES completion:^{
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
      [self showError:@"That video could not be read."];
      return;
    }
    if (data.length > NFBMaxVideoUploadBytes) {
      [self showError:@"Bluesky videos must be 300 MB or smaller."];
      return;
    }
    NSMutableDictionary *item = [@{
      @"type": @"video",
      @"mimeType": @"video/mp4",
      @"data": data,
      @"url": url,
      @"image": thumbnail ?: [UIImage new],
      @"width": @((NSInteger)MAX(1.0, dimensions.width)),
      @"height": @((NSInteger)MAX(1.0, dimensions.height)),
      @"duration": @(duration)
    } mutableCopy];
    item[@"contentWarnings"] = controller.contentWarnings ?: @[];
    if (self.editingMediaItem && self.editingMediaIndex < self.editingMediaItems.count) {
      self.editingMediaItems[self.editingMediaIndex] = item;
    } else {
      [self.editingMediaItems removeAllObjects];
      [self.editingMediaItems addObject:item];
    }
    [self resetMediaEditingState];
    [self updateMediaPreview];
  }];
}

- (void)gifPickerDidCancel:(NFBGIFPickerViewController *)controller {
  [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)gifPickerDidRequestFilePicker:(NFBGIFPickerViewController *)controller {
  [controller dismissViewControllerAnimated:YES completion:^{
    self.pickingGIF = YES;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.compuserve.gif", @"public.mpeg-4", @"public.movie"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
  }];
}

- (void)gifPicker:(NFBGIFPickerViewController *)controller didSelectGIFItem:(NSDictionary *)item {
  [controller dismissViewControllerAnimated:YES completion:^{
    [self attachGIFItem:item];
  }];
}

- (void)attachGIFItem:(NSDictionary *)item {
  NSString *assetURLString = [item[@"assetURL"] isKindOfClass:NSString.class] ? item[@"assetURL"] : @"";
  NSString *mimeType = [item[@"mimeType"] isKindOfClass:NSString.class] ? item[@"mimeType"] : @"image/gif";
  if (assetURLString.length == 0) {
    [self showError:@"That GIF could not be opened."];
    return;
  }

  NSURL *assetURL = [NSURL URLWithString:assetURLString];
  if (!assetURL) {
    [self showError:@"That GIF could not be opened."];
    return;
  }

  self.importingPhotos = YES;
  NSUInteger generation = ++self.photoImportGeneration;
  [self setPosting:YES];
  __weak typeof(self) weakSelf = self;
  [[NSURLSession.sharedSession dataTaskWithURL:assetURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || !strongSelf.importingPhotos || strongSelf.photoImportGeneration != generation) return;
      strongSelf.importingPhotos = NO;
      [strongSelf setPosting:NO];
      if (error || data.length == 0) {
        [strongSelf showError:@"That GIF could not be downloaded."];
        return;
      }

      NSString *title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"GIF";
      NSNumber *fallbackWidth = [item[@"width"] isKindOfClass:NSNumber.class] ? item[@"width"] : @(320);
      NSNumber *fallbackHeight = [item[@"height"] isKindOfClass:NSNumber.class] ? item[@"height"] : @(240);
      NSString *previewURL = [item[@"previewURL"] isKindOfClass:NSString.class] ? item[@"previewURL"] : @"";

      if ([mimeType isEqualToString:@"video/mp4"]) {
        if (data.length > NFBMaxVideoUploadBytes) {
          [strongSelf showError:@"Bluesky videos must be 300 MB or smaller."];
          return;
        }
        NSDictionary *metadata = [strongSelf videoMetadataForData:data previewURL:previewURL fallbackWidth:fallbackWidth fallbackHeight:fallbackHeight];
        UIImage *thumbnail = [metadata[@"image"] isKindOfClass:UIImage.class] ? metadata[@"image"] : [UIImage new];
        NSNumber *width = [metadata[@"width"] isKindOfClass:NSNumber.class] ? metadata[@"width"] : fallbackWidth;
        NSNumber *height = [metadata[@"height"] isKindOfClass:NSNumber.class] ? metadata[@"height"] : fallbackHeight;
        NSNumber *duration = [metadata[@"duration"] isKindOfClass:NSNumber.class] ? metadata[@"duration"] : item[@"duration"];
        [strongSelf.editingMediaItems removeAllObjects];
        [strongSelf.editingMediaItems addObject:@{
          @"type": @"gif",
          @"mimeType": @"video/mp4",
          @"data": data,
          @"image": thumbnail,
          @"width": @((NSInteger)MAX(1.0, width.doubleValue)),
          @"height": @((NSInteger)MAX(1.0, height.doubleValue)),
          @"duration": @((duration && [duration respondsToSelector:@selector(doubleValue)]) ? duration.doubleValue : 0.0),
          @"alt": title.length > 0 ? title : @"GIF"
        }];
        [strongSelf updateMediaPreview];
        return;
      }

      if (data.length > NFBMaxImageUploadBytes) {
        [strongSelf showError:@"Bluesky GIF image uploads must be 2 MB or smaller."];
        return;
      }
      UIImage *image = NFBComposeAnimatedImageWithData(data) ?: [UIImage imageWithData:data] ?: [UIImage new];
      CGSize dimensions = [strongSelf dimensionsForImageData:data fallback:image];
      [strongSelf.editingMediaItems removeAllObjects];
      [strongSelf.editingMediaItems addObject:@{
        @"type": @"gif",
        @"mimeType": @"image/gif",
        @"data": data,
        @"image": image,
        @"width": @((NSInteger)MAX(1.0, dimensions.width)),
        @"height": @((NSInteger)MAX(1.0, dimensions.height)),
        @"alt": title.length > 0 ? title : @"GIF"
      }];
      [strongSelf updateMediaPreview];
    });
  }] resume];
}

- (NSDictionary *)videoMetadataForData:(NSData *)data previewURL:(NSString *)previewURL fallbackWidth:(NSNumber *)fallbackWidth fallbackHeight:(NSNumber *)fallbackHeight {
  NSMutableDictionary *metadata = [@{
    @"width": fallbackWidth ?: @(320),
    @"height": fallbackHeight ?: @(240),
    @"duration": @(0.0)
  } mutableCopy];
  NSString *fileName = [NSString stringWithFormat:@"nfb-gif-%@.mp4", NSUUID.UUID.UUIDString];
  NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
  if (![data writeToURL:url atomically:YES]) return metadata;

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
  AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  if (track) {
    CGSize natural = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    CGFloat width = fabs(natural.width);
    CGFloat height = fabs(natural.height);
    if (width > 0.0 && height > 0.0) {
      metadata[@"width"] = @((NSInteger)width);
      metadata[@"height"] = @((NSInteger)height);
    }
  }
  NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
  if (isfinite(duration) && duration > 0.0) metadata[@"duration"] = @(duration);

  AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
  generator.appliesPreferredTrackTransform = YES;
  generator.maximumSize = CGSizeMake(640.0, 640.0);
  CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(0.05, 600) actualTime:NULL error:nil];
  if (!imageRef) imageRef = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
  if (imageRef) {
    metadata[@"image"] = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
  } else if (previewURL.length > 0) {
    NSURL *previewAssetURL = [NSURL URLWithString:previewURL];
    if (previewAssetURL) {
      NSData *previewData = [NSData dataWithContentsOfURL:previewAssetURL];
      UIImage *preview = NFBGIFPreviewImageWithData(previewData) ?: [UIImage imageWithData:previewData];
      if (preview) metadata[@"image"] = preview;
    }
  }
  [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
  return metadata;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
  (void)controller;
  self.pickingGIF = NO;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  (void)controller;
  NSURL *url = urls.firstObject;
  if (!url) {
    self.pickingGIF = NO;
    return;
  }
  NSString *extension = url.pathExtension.lowercaseString ?: @"";
  if ([extension isEqualToString:@"mp4"] || [extension isEqualToString:@"mov"] || [extension isEqualToString:@"m4v"]) {
    self.pickingGIF = NO;
    [self resetMediaEditingState];
    [self presentVideoTrimControllerForURL:url];
    return;
  }
  NSData *data = [NSData dataWithContentsOfURL:url];
  self.pickingGIF = NO;
  if (data.length == 0) {
    [self showError:@"That GIF could not be read."];
    return;
  }
  if (data.length > NFBMaxImageUploadBytes) {
    [self showError:@"Bluesky GIF image uploads must be 2 MB or smaller. Pick an MP4 GIF to use the video/GIF path."];
    return;
  }
  UIImage *image = [UIImage imageWithData:data] ?: [UIImage new];
  CGSize dimensions = [self dimensionsForImageData:data fallback:image];
  [self.editingMediaItems removeAllObjects];
  [self.editingMediaItems addObject:@{
    @"type": @"gif",
    @"mimeType": @"image/gif",
    @"data": data,
    @"image": image,
    @"width": @((NSInteger)MAX(1.0, dimensions.width)),
    @"height": @((NSInteger)MAX(1.0, dimensions.height))
  }];
  [self updateMediaPreview];
}

- (void)addImageAttachment:(UIImage *)image type:(NSString *)type mimeType:(NSString *)mimeType altText:(NSString *)altText {
  BOOL replacing = self.editingMediaItem && self.editingMediaIndex < self.editingMediaItems.count;
  NSDictionary *replacedItem = replacing ? self.editingMediaItems[self.editingMediaIndex] : nil;
  if (!replacing && self.editingMediaItems.count >= NFBMaxPhotosPerPost) {
    [self showError:@"Bluesky allows up to 10 photos in one post."];
    [self resetMediaEditingState];
    return;
  }
  if (!replacing && [self containsVideoLikeMedia]) {
    [self showError:@"Bluesky allows either one video/GIF or up to 10 photos, not mixed media."];
    [self resetMediaEditingState];
    return;
  }
  NSData *data = [self jpegDataForImage:image maxBytes:NFBMaxImageUploadBytes];
  if (data.length == 0 || data.length > NFBMaxImageUploadBytes) {
    [self showError:@"That image is too large for Bluesky's 2 MB image limit."];
    [self resetMediaEditingState];
    return;
  }
  UIImage *encodedImage = [UIImage imageWithData:data];
  CGSize dimensions = CGSizeMake(CGImageGetWidth(encodedImage.CGImage), CGImageGetHeight(encodedImage.CGImage));
  NSMutableDictionary *item = [@{
    @"type": type ?: @"photo",
    @"mimeType": mimeType ?: @"image/jpeg",
    @"data": data,
    @"image": image,
    @"width": @((NSInteger)MAX(1.0, dimensions.width)),
    @"height": @((NSInteger)MAX(1.0, dimensions.height))
  } mutableCopy];
  UIImage *originalImage = self.pendingOriginalImage;
  if (!originalImage && [replacedItem[@"originalImage"] isKindOfClass:UIImage.class]) originalImage = replacedItem[@"originalImage"];
  if (!originalImage) originalImage = image;
  if (originalImage) item[@"originalImage"] = originalImage;
  NSData *originalData = [replacedItem[@"originalData"] isKindOfClass:NSData.class] ? replacedItem[@"originalData"] : nil;
  if (originalData.length > 0) item[@"originalData"] = originalData;
  NSString *existingAlt = [replacedItem[@"alt"] isKindOfClass:NSString.class] ? replacedItem[@"alt"] : @"";
  NSString *finalAlt = altText.length > 0 ? altText : existingAlt;
  if (finalAlt.length > 0) item[@"alt"] = finalAlt;
  if (replacing) self.editingMediaItems[self.editingMediaIndex] = item;
  else [self.editingMediaItems addObject:item];
  [self resetMediaEditingState];
  [self updateMediaPreview];
}

- (BOOL)containsVideoLikeMedia {
  for (NSDictionary *item in self.editingMediaItems) {
    NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"";
    NSString *mimeType = [item[@"mimeType"] isKindOfClass:NSString.class] ? item[@"mimeType"] : @"";
    if ([type isEqualToString:@"video"] || ([type isEqualToString:@"gif"] && [mimeType isEqualToString:@"video/mp4"])) return YES;
  }
  return NO;
}

- (void)updateMediaPreview {
  // Drafts retain upload bytes; make a playback URL only for the presentation.
  NSMutableArray *previews = [NSMutableArray arrayWithCapacity:self.editingMediaItems.count];
  for (NSUInteger index = 0; index < self.editingMediaItems.count; index++) {
    NSDictionary *item = self.editingMediaItems[index];
    NSMutableDictionary *preview = [item mutableCopy];
    if ([item[@"mimeType"] isEqual:@"video/mp4"]) {
      NSURL *url = [self editableVideoURLForMediaItem:item];
      if (url) {
        if (!item[@"url"]) {
          NSMutableDictionary *stored = [item mutableCopy];
          stored[@"url"] = url;
          self.editingMediaItems[index] = stored;
        }
        preview[@"videoURL"] = url.absoluteString;
      }
    }
    [previews addObject:preview];
  }
  NFBMediaPreviewView *preview = [self.mediaTargetTextView.superview isKindOfClass:NFBComposeThreadRow.class] ? ((NFBComposeThreadRow *)self.mediaTargetTextView.superview).mediaPreview : self.mediaPreviewView;
  [preview configureWithMediaItems:previews];
  [self updateMediaPreviewHeight];
  [self updateComposerLayoutForThread];
  [self updateCount];
}

- (void)updateMediaPreviewHeight {
  NSDictionary *first = self.mediaItems.firstObject;
  double width = [first[@"width"] doubleValue], height = [first[@"height"] doubleValue];
  CGFloat availableWidth = [self composerTextColumnWidth];
  self.mediaPreviewHeightConstraint.constant = NFBComposerMediaHeight(availableWidth, height > 0 ? width / height : 1, self.mediaItems.count);
  for (UITextView *textView in self.threadTextViews) {
    NFBComposeThreadRow *row = (NFBComposeThreadRow *)textView.superview;
    NSDictionary *media = row.mediaItems.firstObject;
    double w = [media[@"width"] doubleValue], h = [media[@"height"] doubleValue];
    row.mediaHeight.constant = NFBComposerMediaHeight(availableWidth, h > 0 ? w / h : 1, row.mediaItems.count);
    row.mediaTop.constant = row.mediaItems.count ? 8 : 0;
    UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, row.mediaItems.count ? 0 : 10, 0);
    if (!UIEdgeInsetsEqualToEdgeInsets(textView.textContainerInset, inset)) textView.textContainerInset = inset;
  }
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view didTapAltForItemAtIndex:(NSUInteger)index {
  [self targetMediaPreview:view];
  if (index >= self.editingMediaItems.count) return;
  self.attachmentAltIndex = index;
  UIViewController *editor = [UIViewController new];
  editor.title = @"Write alt text";
  editor.view.backgroundColor = NFBColorBackground();
  self.attachmentAltTextView = [UITextView new];
  UITextView *text = self.attachmentAltTextView;
  text.translatesAutoresizingMaskIntoConstraints = NO;
  text.font = NFBFont(17, NFBFontWeightRegular);
  text.textColor = NFBColorText();
  text.backgroundColor = NFBColorBackground();
  text.tintColor = NFBColorAccent();
  text.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12);
  text.text = self.editingMediaItems[index][@"alt"] ?: @"";
  text.accessibilityLabel = @"Image description";
  [editor.view addSubview:text];
  NSLayoutYAxisAnchor *bottom = editor.view.safeAreaLayoutGuide.bottomAnchor;
  if ([editor.view respondsToSelector:@selector(keyboardLayoutGuide)]) {
    UILayoutGuide *keyboard = [editor.view valueForKey:@"keyboardLayoutGuide"];
    bottom = keyboard.topAnchor;
  }
  [NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.topAnchor], [text.leadingAnchor constraintEqualToAnchor:editor.view.leadingAnchor], [text.trailingAnchor constraintEqualToAnchor:editor.view.trailingAnchor], [text.bottomAnchor constraintEqualToAnchor:bottom]]];
  editor.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAttachmentAltText)];
  editor.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(applyAttachmentAltText)];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:^{ [text becomeFirstResponder]; }];
}
- (void)cancelAttachmentAltText { [self dismissViewControllerAnimated:YES completion:nil]; self.attachmentAltTextView = nil; }
- (void)applyAttachmentAltText {
  if (self.attachmentAltIndex < self.editingMediaItems.count) {
    NSMutableDictionary *item = [self.editingMediaItems[self.attachmentAltIndex] mutableCopy];
    item[@"alt"] = self.attachmentAltTextView.text ?: @"";
    self.editingMediaItems[self.attachmentAltIndex] = item;
    [self updateMediaPreview];
  }
  [self cancelAttachmentAltText];
}

- (void)resetMediaEditingState {
  self.editingMediaItem = NO;
  self.editingMediaIndex = 0;
  self.pendingOriginalImage = nil;
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view didSelectItemAtIndex:(NSUInteger)index {
  [self targetMediaPreview:view];
  if (index >= self.editingMediaItems.count) return;
  NSDictionary *item = self.editingMediaItems[index];
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"photo";
  NSString *mimeType = [item[@"mimeType"] isKindOfClass:NSString.class] ? item[@"mimeType"] : @"";

  if ([type isEqualToString:@"gif"]) {
    NSMutableDictionary *preview = [item mutableCopy];
    preview[@"previewImage"] = item[@"image"] ?: [UIImage new];
    if ([mimeType isEqualToString:@"video/mp4"]) {
      NSURL *url = [self editableVideoURLForMediaItem:item];
      if (!url) { [self showError:@"That GIF could not be reopened."]; return; }
      preview[@"videoURL"] = url.absoluteString;
    }
    NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithMediaItems:@[preview] initialIndex:0];
    [self presentViewController:viewer animated:YES completion:nil];
    return;
  }

  if ([type isEqualToString:@"video"]) {
    NSURL *url = [self editableVideoURLForMediaItem:item];
    if (!url) {
      [self showError:@"That video could not be reopened."];
      return;
    }
    self.editingMediaItem = YES;
    self.editingMediaIndex = index;
    [self presentVideoTrimControllerForURL:url];
    return;
  }

  UIImage *image = [item[@"originalImage"] isKindOfClass:UIImage.class] ? item[@"originalImage"] : nil;
  NSData *data = [item[@"originalData"] isKindOfClass:NSData.class] ? item[@"originalData"] : nil;
  if (!image && data.length > 0) image = [UIImage imageWithData:data];
  if (!image) image = [item[@"image"] isKindOfClass:UIImage.class] ? item[@"image"] : nil;
  if (!data) data = [item[@"data"] isKindOfClass:NSData.class] ? item[@"data"] : nil;
  if (!image && data.length > 0) image = [UIImage imageWithData:data];
  if (!image) {
    [self showError:@"That photo could not be reopened."];
    return;
  }

  self.editingMediaItem = YES;
  self.editingMediaIndex = index;
  self.pendingOriginalImage = image;
  NFBCropViewController *crop = [[NFBCropViewController alloc] initWithImage:image];
  crop.delegate = self;
  crop.pendingAltText = [item[@"alt"] isKindOfClass:NSString.class] ? item[@"alt"] : @"";
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:crop];
  NFBApplyDarkNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view didTapRemoveItemAtIndex:(NSUInteger)index {
  [self targetMediaPreview:view];
  if (index >= self.editingMediaItems.count) return;
  [self.editingMediaItems removeObjectAtIndex:index];
  [self resetMediaEditingState];
  [self updateMediaPreview];
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view moveItemAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex {
  [self targetMediaPreview:view];
  if (fromIndex >= self.editingMediaItems.count || toIndex >= self.editingMediaItems.count || fromIndex == toIndex) return;
  NSDictionary *item = self.editingMediaItems[fromIndex];
  [self.editingMediaItems removeObjectAtIndex:fromIndex];
  [self.editingMediaItems insertObject:item atIndex:toIndex];
  [self updateMediaPreview];
}

- (NSURL *)editableVideoURLForMediaItem:(NSDictionary *)item {
  id storedURL = item[@"url"];
  if ([storedURL isKindOfClass:NSURL.class]) return storedURL;
  if ([storedURL isKindOfClass:NSString.class] && [(NSString *)storedURL length] > 0) return [NSURL fileURLWithPath:(NSString *)storedURL];
  NSData *data = [item[@"data"] isKindOfClass:NSData.class] ? item[@"data"] : nil;
  if (data.length == 0) return nil;
  NSString *fileName = [NSString stringWithFormat:@"nfb-edit-video-%@.mp4", NSUUID.UUID.UUIDString];
  NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
  return [data writeToURL:url atomically:YES] ? url : nil;
}

- (NSData *)jpegDataForImage:(UIImage *)image maxBytes:(NSUInteger)maxBytes {
  UIImage *working = image;
  CGSize pixels = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
  if (MAX(pixels.width, pixels.height) > NFBMaxImageDimension) {
    CGFloat scale = NFBMaxImageDimension / MAX(pixels.width, pixels.height);
    CGSize target = CGSizeMake(floor(image.size.width * image.scale * scale), floor(image.size.height * image.scale * scale));
    UIGraphicsBeginImageContextWithOptions(target, YES, 1);
    [image drawInRect:(CGRect){CGPointZero, target}];
    working = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
  }
  CGFloat quality = 0.9;
  NSData *data = UIImageJPEGRepresentation(working, quality);
  CGFloat maxDimension = NFBMaxImageDimension;
  while (data.length > maxBytes && maxDimension >= 640.0) {
    CGSize size = working.size;
    CGFloat largest = MAX(size.width, size.height);
    CGFloat scale = MIN(1.0, maxDimension / MAX(largest, 1.0));
    CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [working drawInRect:CGRectMake(0.0, 0.0, target.width, target.height)];
    working = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    quality = 0.86;
    data = UIImageJPEGRepresentation(working, quality);
    maxDimension *= 0.82;
  }
  while (data.length > maxBytes && quality > 0.45) {
    quality -= 0.08;
    data = UIImageJPEGRepresentation(working, quality);
  }
  return data;
}

- (CGSize)dimensionsForImageData:(NSData *)data fallback:(UIImage *)fallback {
  CGSize size = fallback ? CGSizeMake(CGImageGetWidth(fallback.CGImage), CGImageGetHeight(fallback.CGImage)) : CGSizeZero;
  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
  if (!source) return size;
  NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
  CFRelease(source);
  NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
  NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];
  if (width.doubleValue > 0 && height.doubleValue > 0) return CGSizeMake(width.doubleValue, height.doubleValue);
  return size;
}

- (void)loadAvatarURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
	    UIImage *image = [UIImage imageWithData:data];
	    if (!image) return;
	    dispatch_async(dispatch_get_main_queue(), ^{
	      if (imageView == self.avatarView && ![[NFBAtprotoClient avatarURLForProfile:self.selectedComposerAccount] isEqualToString:urlString]) return;
      imageView.image = image;
	      if (imageView == self.avatarView) [self updateThreadAvatarImages];
	    });
	  }] resume];
}

@end
