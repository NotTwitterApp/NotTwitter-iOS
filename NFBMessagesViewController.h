#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBMessagesViewController : UIViewController

- (void)refreshConversations;

@end

@interface NFBConversationViewController : UIViewController

- (instancetype)initWithConversation:(NSDictionary *)conversation;

@property (nonatomic, copy) void (^conversationDeletedHandler)(void);
@property (nonatomic, copy) void (^conversationChangedHandler)(NSDictionary *conversation);

@end

NS_ASSUME_NONNULL_END
