#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBMediaPreviewView;
@class AVPlayer;

// Captured at the tap, before inline playback is paused or a table cell is reused.
@interface NFBMediaTransitionSource : NSObject
@property (nonatomic, weak, nullable) UIView *view;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, copy) BOOL (^isStillValid)(void);
@end

@protocol NFBMediaPreviewViewDelegate <NSObject>
- (void)mediaPreviewView:(NFBMediaPreviewView *)view didSelectItemAtIndex:(NSUInteger)index;
@optional
- (void)mediaPreviewView:(NFBMediaPreviewView *)view didTapRemoveItemAtIndex:(NSUInteger)index;
- (void)mediaPreviewView:(NFBMediaPreviewView *)view didTapAltForItemAtIndex:(NSUInteger)index;
- (void)mediaPreviewView:(NFBMediaPreviewView *)view moveItemAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex;
@end

@interface NFBMediaPreviewView : UIView

@property (nonatomic, weak, nullable) id<NFBMediaPreviewViewDelegate> delegate;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *mediaItems;
@property (nonatomic, assign) BOOL composerRailStyle;
@property (nonatomic, assign) BOOL quotedCardStyle;

- (void)configureWithMediaItems:(NSArray<NSDictionary *> *)mediaItems;
- (void)applyTheme;
- (nullable NFBMediaTransitionSource *)transitionSourceForItemAtIndex:(NSUInteger)index;
+ (NSDictionary *)playbackStateForVideoURL:(NSString *)url;
+ (void)recordVideoURL:(NSString *)url position:(NSTimeInterval)position duration:(NSTimeInterval)duration;
+ (void)pauseInlinePlayback;
+ (void)resumeInlinePlayback;

@end

NS_ASSUME_NONNULL_END
