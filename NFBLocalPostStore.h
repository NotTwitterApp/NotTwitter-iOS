#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFBLocalPostStoreDidChangeNotification;

typedef void (^NFBLocalPostStoreProcessCompletion)(NSUInteger postedCount, NSUInteger failedCount);

@interface NFBLocalPostStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<NSDictionary *> *)draftPosts;
- (NSArray<NSDictionary *> *)draftPostsForAccountDID:(NSString *)did;
- (NSArray<NSDictionary *> *)scheduledPostsForAccountDID:(NSString *)did;
- (NSArray<NSDictionary *> *)scheduledPosts;
- (NSDictionary *)saveDraftText:(NSString *)text
	                      replyGate:(nullable NSString *)replyGate
	                     mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems;
- (NSDictionary *)saveDraftText:(NSString *)text
	                      replyGate:(nullable NSString *)replyGate
	                     mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems
	                    threadTexts:(nullable NSArray<NSString *> *)threadTexts;
- (NSDictionary *)saveDraftText:(NSString *)text replyGate:(nullable NSString *)replyGate mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems threadTexts:(nullable NSArray<NSString *> *)threadTexts quotePost:(nullable NSDictionary *)quotePost;
- (NSDictionary *)saveScheduledPostText:(NSString *)text
                              replyGate:(nullable NSString *)replyGate
                             mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems
                          scheduledDate:(NSDate *)scheduledDate;
- (NSDictionary *)saveDraftText:(NSString *)text replyGate:(nullable NSString *)replyGate mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems threadPosts:(NSArray<NSDictionary *> *)threadPosts quotePost:(nullable NSDictionary *)quotePost account:(NSDictionary *)account;
- (NSDictionary *)saveScheduledPostText:(NSString *)text replyGate:(nullable NSString *)replyGate mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems scheduledDate:(NSDate *)date account:(NSDictionary *)account;
- (NSArray<NSDictionary *> *)mediaItemsForLocalPost:(NSDictionary *)post;
- (void)deleteLocalPostWithID:(NSString *)postID;
- (void)processDueScheduledPostsWithCompletion:(nullable NFBLocalPostStoreProcessCompletion)completion;

@end

NS_ASSUME_NONNULL_END
