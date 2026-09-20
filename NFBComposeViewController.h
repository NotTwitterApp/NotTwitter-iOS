#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBCropViewController;
@class NFBEmojiInputView;

@protocol NFBCropViewControllerDelegate <NSObject>
- (void)cropViewControllerDidCancel:(NFBCropViewController *)controller;
- (void)cropViewController:(NFBCropViewController *)controller didFinishWithImage:(UIImage *)image;
@end

@protocol NFBEmojiInputViewDelegate <NSObject>
- (void)emojiInputView:(NFBEmojiInputView *)inputView didSelectEmoji:(NSString *)emoji;
- (void)emojiInputViewDidRequestKeyboard:(NFBEmojiInputView *)inputView;
@end

@interface NFBCropViewController : UIViewController
@property (nonatomic, weak) id<NFBCropViewControllerDelegate> delegate;
- (instancetype)initWithImage:(UIImage *)image;
@end

@interface NFBEmojiInputView : UIView
@property (nonatomic, weak) id<NFBEmojiInputViewDelegate> delegate;
- (void)applyTheme;
@end

@interface NFBComposeViewController : UIViewController

@property (nonatomic, copy, nullable) void (^completionHandler)(BOOL posted);

- (instancetype)initWithReplyToPost:(NSDictionary *_Nullable)post;
- (instancetype)initWithQuotePost:(NSDictionary *_Nullable)post;

@end

NS_ASSUME_NONNULL_END
