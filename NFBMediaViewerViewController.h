#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBMediaViewerViewController;

@protocol NFBMediaViewerViewControllerDelegate <NSObject>
@optional
- (void)mediaViewerViewController:(NFBMediaViewerViewController *)viewer
                    didUpdatePost:(NSDictionary *)updatedPost
                     originalPost:(NSDictionary *)originalPost;
@end

@interface NFBMediaViewerViewController : UIViewController

@property (nonatomic, weak, nullable) id<NFBMediaViewerViewControllerDelegate> delegate;

- (instancetype)initWithProfileImageURL:(NSString *)url previewImage:(nullable UIImage *)image avatar:(BOOL)avatar sourceImageView:(UIImageView *)source;

- (instancetype)initWithMediaItems:(NSArray<NSDictionary *> *)mediaItems initialIndex:(NSUInteger)initialIndex;
- (instancetype)initWithMediaItems:(NSArray<NSDictionary *> *)mediaItems
                      initialIndex:(NSUInteger)initialIndex
                              post:(nullable NSDictionary *)post NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
