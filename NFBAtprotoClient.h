#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFBAtprotoFeedListCacheDidInvalidateNotification;
extern NSString * const NFBAtprotoProfileUpdatedNotification;

typedef void (^NFBAtprotoArrayCompletion)(NSArray<NSDictionary *> *_Nullable items, NSString *_Nullable cursor, NSError *_Nullable error);
typedef void (^NFBAtprotoDictionaryCompletion)(NSDictionary *_Nullable value, NSError *_Nullable error);

@interface NFBAtprotoClient : NSObject

+ (instancetype)sharedClient;
+ (instancetype)postingClientForAccountDID:(NSString *)accountDID;

- (void)fetchHomeTimelineWithCursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchDiscoverFeedWithCursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchFeedMetadataForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchFeedWithURI:(NSString *)feedURI cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchListFeedWithURI:(NSString *)listURI cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchBookmarksWithCursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchSubscribedHomeFeedsWithCompletion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchSavedFeedResourcesWithCompletion:(NFBAtprotoArrayCompletion)completion;
- (void)searchFeedGenerators:(NSString *)query cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)setSavedFeedWithURI:(NSString *)feedURI saved:(BOOL)saved completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)reorderSavedFeedURIs:(NSArray<NSString *> *)feedURIs completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)invalidateCachedFeedAndListResources;
- (void)fetchAuthorFeedForActor:(NSString *)actor cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchAuthorFeedForActor:(NSString *)actor filter:(nullable NSString *)filter cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchAuthorFeedWithRepliesForActor:(NSString *)actor cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchAuthorArticlesForActor:(NSString *)actor cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchActorLikesForActor:(NSString *)actor cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchPostStatsForPost:(NSDictionary *)post type:(NSString *)type cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchProfileActorsForActor:(NSString *)actor kind:(NSString *)kind cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchListsForActor:(NSString *)actor cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchCurrentUserListsForKind:(NSString *)kind completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchStarterPacksForActor:(NSString *)actor cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)searchPosts:(NSString *)query cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)searchPosts:(NSString *)query sort:(NSString *)sort followingOnly:(BOOL)following mediaTab:(NSInteger)mediaTab cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)searchPosts:(NSString *)query sort:(NSString *)sort cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)searchActors:(NSString *)query limit:(NSUInteger)limit cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)searchActors:(NSString *)query limit:(NSUInteger)limit completion:(NFBAtprotoArrayCompletion)completion;
- (void)searchMessageableActors:(NSString *)query limit:(NSUInteger)limit completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchTrendingTopicsWithCompletion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchNotificationsWithCursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchNotificationsWithCursor:(nullable NSString *)cursor reasons:(nullable NSArray<NSString *> *)reasons completion:(NFBAtprotoArrayCompletion)completion;
- (void)markNotificationsSeenWithCompletion:(nullable NFBAtprotoDictionaryCompletion)completion;
- (void)setActivitySubscriptionForSubject:(NSString *)subject post:(BOOL)post reply:(BOOL)reply completion:(nullable NFBAtprotoDictionaryCompletion)completion;
- (void)registerPushToken:(NSString *)token appID:(NSString *)appID completion:(nullable NFBAtprotoDictionaryCompletion)completion;
- (void)unregisterPushToken:(NSString *)token appID:(NSString *)appID completion:(nullable NFBAtprotoDictionaryCompletion)completion;
- (void)acceptUpdatedProfile:(NSDictionary *)profile;
- (void)fetchProfileForActor:(NSString *)actor completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchChatConversationsWithCursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchChatConversationRequestsWithCursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchChatConversationWithID:(NSString *)conversationID completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchChatConversationAvailabilityForMembers:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchChatConversationForMembers:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)createChatGroupWithMembers:(NSArray<NSString *> *)members name:(NSString *)name completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)addChatMembersToConversationID:(NSString *)conversationID members:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)removeChatMembersFromConversationID:(NSString *)conversationID members:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)editChatGroupWithConversationID:(NSString *)conversationID name:(NSString *)name completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchChatMembersForConversationID:(NSString *)conversationID cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)canMessageProfile:(NSDictionary *)profile completion:(void (^)(BOOL canMessage))completion;
- (void)fetchChatMessagesForConversationID:(NSString *)conversationID cursor:(nullable NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchChatLogMessagesForConversationID:(NSString *)conversationID completion:(NFBAtprotoArrayCompletion)completion;
- (void)sendChatMessageToConversationID:(NSString *)conversationID text:(NSString *)text completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)addChatReactionToConversationID:(NSString *)conversationID messageID:(NSString *)messageID value:(NSString *)value completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)removeChatReactionFromConversationID:(NSString *)conversationID messageID:(NSString *)messageID value:(NSString *)value completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)deleteChatMessageForSelfInConversationID:(NSString *)conversationID messageID:(NSString *)messageID completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)markChatConversationRead:(NSString *)conversationID messageID:(nullable NSString *)messageID completion:(nullable NFBAtprotoDictionaryCompletion)completion;
- (void)acceptChatConversation:(NSString *)conversationID completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)setChatConversationMuted:(NSString *)conversationID muted:(BOOL)muted completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)leaveChatConversation:(NSString *)conversationID completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)createPostWithText:(NSString *)text completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)createPostWithText:(NSString *)text replyToPost:(nullable NSDictionary *)parentPost completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)createPostWithText:(NSString *)text replyToPost:(nullable NSDictionary *)parentPost quotePost:(nullable NSDictionary *)quotePost completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)createPostWithText:(NSString *)text
               replyToPost:(nullable NSDictionary *)parentPost
                 quotePost:(nullable NSDictionary *)quotePost
                mediaItems:(nullable NSArray<NSDictionary *> *)mediaItems
                 replyGate:(nullable NSString *)replyGate
                completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchPostForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchPostThreadForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchAdditionalPostRepliesForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)invalidatePostThreadForURI:(NSString *)uri;
- (void)deletePost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchStandardSiteArticleForCard:(NSDictionary *)card completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)toggleLikeForPost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)toggleRepostForPost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)toggleBookmarkForPost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)followProfileIfNeeded:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)toggleFollowForProfile:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)blockProfileIfNeeded:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)toggleBlockForProfile:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion;

+ (NSDictionary *)postFromFeedItem:(NSDictionary *)item;
+ (NSString *)postURIFromFeedItem:(NSDictionary *)item;
+ (NSDictionary *)replyParentPostFromFeedItem:(NSDictionary *)item;
+ (NSString *)replyParentURIForPost:(NSDictionary *)post;
+ (NSString *)webURLStringForPost:(NSDictionary *)post;
+ (NSString *)stableIDForPost:(NSDictionary *)post;
+ (NSString *)displayNameForProfile:(NSDictionary *)profile;
+ (NSString *)canonicalHandleForProfile:(NSDictionary *)profile;
+ (NSString *)handleForProfile:(NSDictionary *)profile;
+ (NSString *)displayHandleForProfile:(NSDictionary *)profile;
+ (NSString *)avatarURLForProfile:(NSDictionary *)profile;
+ (NSString *)textForPost:(NSDictionary *)post;
+ (NSString *)mediaURLForPost:(NSDictionary *)post;
+ (NSArray<NSDictionary *> *)mediaItemsForPost:(NSDictionary *)post;
+ (nullable NSDictionary *)externalCardForPost:(NSDictionary *)post;
+ (BOOL)externalCardIsStandardSiteArticle:(NSDictionary *)card;
+ (NSString *)standardSiteArticleExcerptFromText:(NSString *)text maxLength:(NSUInteger)maxLength;
+ (nullable NSDictionary *)quotedPostForPost:(NSDictionary *)post;
+ (NSString *)relativeTimeForPost:(NSDictionary *)post;
+ (NSString *)reasonTextForFeedItem:(NSDictionary *)item;
+ (BOOL)isProfileVerified:(NSDictionary *)profile;
+ (NSDictionary *)post:(NSDictionary *)post applyingToggleForViewerKey:(NSString *)viewerKey countKey:(nullable NSString *)countKey response:(nullable NSDictionary *)response;
+ (NSDictionary *)postByApplyingBookmarkToggleForPost:(NSDictionary *)post response:(nullable NSDictionary *)response;
+ (NSDictionary *)profile:(NSDictionary *)profile applyingFollowToggleWithResponse:(nullable NSDictionary *)response;
+ (NSDictionary *)profile:(NSDictionary *)profile applyingBlockToggleWithResponse:(nullable NSDictionary *)response;

@end

NS_ASSUME_NONNULL_END
