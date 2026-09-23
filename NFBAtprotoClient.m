#import "NFBProfileRecord.h"
#import "NFBRichText.h"
#import "NFBPostLinkResolver.h"
#import "NFBPostLink.h"
#import "NFBSearchQuery.h"
#import "NFBAtprotoClient.h"
#import "NFBProfilePresentation.h"
#import "NFBRepostContext.h"
#import "NFBChatPermission.h"
#import "NFBMediaAttachmentPolicy.h"

#import "NFBAtprotoSession.h"

NSString * const NFBAtprotoProfileUpdatedNotification = @"NFBAtprotoProfileUpdatedNotification";

NSString * const NFBAtprotoFeedListCacheDidInvalidateNotification = @"NFBAtprotoFeedListCacheDidInvalidateNotification";

static NSString * const NFBAtprotoAppViewURL = @"https://api.bsky.app";
static NSString * const NFBAtprotoPublicAppViewURL = @"https://public.api.bsky.app";
static NSString * const NFBAtprotoDiscoverFeedActor = @"bsky.app";
static NSString * const NFBAtprotoDiscoverFeedRkey = @"whats-hot";
static NSString * const NFBAtprotoNotificationServiceDID = @"did:web:api.bsky.app";
static NSString * const NFBAtprotoPushPlatformIOS = @"ios";
static NSString * const NFBMessageableActorFollowsViewerKey = @"__nfbFollowsViewer";
static NSString * const NFBComposeReplyGateEveryone = @"everyone";
static NSString * const NFBComposeReplyGateFollowing = @"following";
static NSString * const NFBComposeReplyGateMentioned = @"mentioned";
static NSString * const NFBComposeReplyGateNobody = @"nobody";
static NSTimeInterval const NFBAtprotoProfileCacheTTL = 45.0;
static NSTimeInterval const NFBAtprotoThreadCacheTTL = 12.0;

static NSString *NFBAtprotoDiscoverFeedURI = nil;

typedef void (^NFBAtprotoCachedArrayLoader)(NFBAtprotoArrayCompletion completion);

static NSString *NFBClientStringValue(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray<NSString *> *NFBClientUniqueNonEmptyStrings(NSArray<NSString *> *values) {
  NSMutableArray<NSString *> *unique = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (NSString *value in values ?: @[]) {
    if (![value isKindOfClass:NSString.class] || value.length == 0 || [seen containsObject:value]) continue;
    [seen addObject:value];
    [unique addObject:value];
  }
  return unique;
}

static NSString *NFBClientStringByLimitingComposedCharacters(NSString *value, NSUInteger maxCharacters, NSUInteger maxLength) {
  if (value.length == 0) return @"";
  NSString *limited = value;
  if (maxLength > 0 && limited.length > maxLength) {
    NSRange range = [limited rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, maxLength)];
    limited = [limited substringWithRange:range];
  }
  if (maxCharacters == 0) return limited;
  __block NSUInteger count = 0;
  __block NSUInteger end = limited.length;
  [limited enumerateSubstringsInRange:NSMakeRange(0, limited.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
    (void)substring;
    (void)enclosingRange;
    count++;
    if (count > maxCharacters) {
      end = substringRange.location;
      *stop = YES;
    }
  }];
  return end < limited.length ? [limited substringToIndex:end] : limited;
}

@interface NFBAtprotoClient ()
@property (nonatomic, copy) NSString *postingAccountDID;
@property (atomic) NSUInteger profileEditRevision;
@property (nonatomic, strong) NSMutableDictionary *recentProfileEdits;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *standardSiteArticleRequests;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *resourceArrayCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *resourceArrayFingerprintCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *profileCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *profileCacheDates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *profilePendingCompletions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *threadPayloadCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *threadPayloadCacheDates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *threadPendingCompletions;

- (void)fetchAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)requiresAuth completion:(NFBAtprotoValueCompletion)completion;
- (void)fetchRawAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)requiresAuth completion:(NFBAtprotoValueCompletion)completion;
- (void)fetchFeedGeneratorViewsForURIs:(NSArray<NSString *> *)uris completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *generatorsByURI))completion;
- (void)fetchFeedGeneratorViewsForURIs:(NSArray<NSString *> *)uris offset:(NSUInteger)offset generatorsByURI:(NSMutableDictionary<NSString *, NSDictionary *> *)generatorsByURI completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *generatorsByURI))completion;
- (void)fetchSavedFeedItemsWithCompletion:(void (^)(NSArray<NSDictionary *> *items, NSArray *preferences, NSError *error))completion;
- (void)putSavedFeedItems:(NSArray<NSDictionary *> *)items preferences:(NSArray *)preferences completion:(NFBAtprotoDictionaryCompletion)completion;
- (NSArray<NSDictionary *> *)savedFeedItemsFromPreferences:(NSArray *)preferences;
- (void)fetchPostViewsForURIs:(NSArray<NSString *> *)uris completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *postsByURI, NSError *error))completion;
- (void)fetchPostViewsForURIs:(NSArray<NSString *> *)uris offset:(NSUInteger)offset postsByURI:(NSMutableDictionary<NSString *, NSDictionary *> *)postsByURI firstError:(NSError *)firstError completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *postsByURI, NSError *error))completion;
- (void)fetchProfileRecordForDID:(NSString *)did completion:(void (^)(NSDictionary *record, NSString *endpoint))completion;
- (void)filterMessageableActors:(NSArray<NSDictionary *> *)actors limit:(NSUInteger)limit completion:(NFBAtprotoArrayCompletion)completion;
- (void)messagePermissionForProfile:(NSDictionary *)profile completion:(void (^)(BOOL canMessage, BOOL followsViewer))completion;
- (void)fetchChatLogMessagesForConversationID:(NSString *)conversationID cursor:(NSString *)cursor remainingPages:(NSUInteger)remainingPages messagesByID:(NSMutableDictionary<NSString *, NSDictionary *> *)messagesByID nextCursor:(NSString *)nextCursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)updateChatReactionWithMethod:(NSString *)method conversationID:(NSString *)conversationID messageID:(NSString *)messageID value:(NSString *)value completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)finishResourceResponse:(id)value key:(NSString *)key type:(NSString *)type error:(NSError *)error completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchResourceArrayWithCacheKey:(NSString *)cacheKey loader:(NFBAtprotoCachedArrayLoader)loader completion:(NFBAtprotoArrayCompletion)completion;
- (NSString *)resourceCacheKeyWithName:(NSString *)name qualifier:(NSString *)qualifier;
- (NSString *)resourceCachePrefixForCurrentAccount;
- (void)finishAuthorFeedWithRepliesItems:(NSArray<NSDictionary *> *)items cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)completePendingDictionaryRequests:(NSArray *)requests value:(NSDictionary *)value error:(NSError *)error;
- (void)invalidateThreadPayloadCache;
+ (NSString *)resourceArrayFingerprint:(NSArray<NSDictionary *> *)items;
- (void)fetchAuthorArticlesForActor:(NSString *)actor cursor:(NSString *)cursor accumulatedItems:(NSMutableArray<NSDictionary *> *)accumulatedItems remainingPages:(NSUInteger)remainingPages completion:(NFBAtprotoArrayCompletion)completion;
- (void)uploadMediaItems:(NSArray<NSDictionary *> *)mediaItems completion:(void (^)(NSArray<NSDictionary *> *uploadedItems, NSError *error))completion;
- (void)uploadMediaItems:(NSArray<NSDictionary *> *)mediaItems index:(NSUInteger)index uploadedItems:(NSMutableArray<NSDictionary *> *)uploadedItems completion:(void (^)(NSArray<NSDictionary *> *uploadedItems, NSError *error))completion;
- (void)uploadBlobData:(NSData *)data mimeType:(NSString *)mimeType completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)createThreadgateForPostURI:(NSString *)postURI replyGate:(NSString *)replyGate completion:(NFBAtprotoDictionaryCompletion)completion;
- (NSString *)targetPostURIForNotification:(NSDictionary *)notification;
- (BOOL)notificationReasonRoutesToProfile:(NSString *)reason;
- (NSDictionary *)syntheticPostForNotification:(NSDictionary *)notification targetURI:(NSString *)targetURI;
+ (NSString *)replyParentURIForPost:(NSDictionary *)post;
+ (NSString *)replyParentURIForRecord:(NSDictionary *)record;
+ (NSString *)replyRootURIForPost:(NSDictionary *)post;
+ (NSString *)replyRootURIForRecord:(NSDictionary *)record;
+ (NSString *)replyTargetTextForFeedItem:(NSDictionary *)item;
+ (NSArray<NSString *> *)standardSiteAssociatedURIsForCard:(NSDictionary *)card;
+ (NSString *)standardSiteArticleCacheKeyForCard:(NSDictionary *)card;
+ (NSDictionary *)standardSiteDocumentRecordFromAssociatedRecords:(NSArray *)records;
+ (NSString *)standardSiteDocumentTextFromRecord:(NSDictionary *)record;
+ (NSString *)standardSiteTextByRemovingReaderPreamble:(NSString *)text;
+ (NSArray<NSString *> *)standardSiteTagsFromRecord:(NSDictionary *)record;
+ (void)appendTextFromUnknownContent:(id)value depth:(NSUInteger)depth toArray:(NSMutableArray<NSString *> *)texts;
+ (NSString *)recordString:(NSDictionary *)record key:(NSString *)key;
+ (NSString *)stringByReplacingRegex:(NSString *)pattern inString:(NSString *)string withString:(NSString *)replacement;
+ (BOOL)string:(NSString *)string matchesRegex:(NSString *)pattern;
+ (BOOL)hasVerificationRecordCheckmark:(id)record;
+ (BOOL)isPositiveVerificationFlag:(id)value;
+ (BOOL)isAbsentVerificationStatus:(id)value;
+ (NSString *)categoryForTrendTopic:(NSDictionary *)topic;
+ (NSString *)providedCategoryForTrendTopic:(NSDictionary *)topic;
+ (NSString *)normalizedCategoryText:(NSString *)value;
+ (BOOL)categoryText:(NSString *)value containsKeyword:(NSString *)keyword;
+ (NSDictionary *)trendItemForTopic:(NSDictionary *)topic kind:(NSString *)kind rank:(NSInteger)rank;
+ (NSString *)rkeyFromAtURI:(NSString *)uri;
+ (NSDictionary *)postRefForPost:(NSDictionary *)post;
+ (NSDictionary *)embedForUploadedMediaItems:(NSArray<NSDictionary *> *)uploadedItems quoteRef:(NSDictionary *)quoteRef;
+ (NSArray<NSDictionary *> *)threadgateAllowRulesForReplyGate:(NSString *)replyGate;
+ (NSError *)composeErrorWithMessage:(NSString *)message code:(NSInteger)code;
+ (NSDictionary *)postOrTombstoneFromThreadNode:(NSDictionary *)threadNode;
+ (NSDictionary *)postOrTombstoneFromThreadNode:(NSDictionary *)threadNode hiddenAuthorReasons:(NSDictionary *)hiddenAuthorReasons;
+ (NSDictionary *)tombstonePostFromSource:(NSDictionary *)source fallbackType:(NSString *)fallbackType;
+ (NSDictionary *)tombstonePostFromPost:(NSDictionary *)post reason:(NSString *)reason;
+ (BOOL)typeStringIndicatesBlueskyTombstone:(NSString *)type;
+ (NSDictionary *)replyParentPostFromFeedItem:(NSDictionary *)item;
+ (NSArray<NSDictionary *> *)feedItemsSortedNewestFirst:(NSArray<NSDictionary *> *)items;
+ (void)collectHiddenAuthorReasonsFromThreadNode:(id)threadNode intoDictionary:(NSMutableDictionary *)reasons;
+ (NSString *)hiddenReasonForPostAuthor:(NSDictionary *)author;
+ (void)appendParentPostsFromThread:(id)threadNode toArray:(NSMutableArray *)posts hiddenAuthorReasons:(NSDictionary *)hiddenAuthorReasons;

@end

@implementation NFBAtprotoClient

+ (instancetype)sharedClient {
  static NFBAtprotoClient *client = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    client = [[NFBAtprotoClient alloc] init];
  });
  return client;
}


// A send operation owns its identity for the entire upload/post/thread chain.
+ (instancetype)postingClientForAccountDID:(NSString *)accountDID {
  NFBAtprotoClient *client = [[self alloc] init];
  client.postingAccountDID = accountDID ?: @"";
  return client;
}

- (NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *)resourceArrayCache {
  if (!_resourceArrayCache) _resourceArrayCache = [NSMutableDictionary dictionary];
  return _resourceArrayCache;
}

- (NSMutableDictionary<NSString *, NSString *> *)resourceArrayFingerprintCache {
  if (!_resourceArrayFingerprintCache) _resourceArrayFingerprintCache = [NSMutableDictionary dictionary];
  return _resourceArrayFingerprintCache;
}

- (NSMutableDictionary<NSString *, NSDictionary *> *)profileCache {
  if (!_profileCache) _profileCache = [NSMutableDictionary dictionary];
  return _profileCache;
}

- (NSMutableDictionary<NSString *, NSDate *> *)profileCacheDates {
  if (!_profileCacheDates) _profileCacheDates = [NSMutableDictionary dictionary];
  return _profileCacheDates;
}

- (NSMutableDictionary<NSString *, NSMutableArray *> *)profilePendingCompletions {
  if (!_profilePendingCompletions) _profilePendingCompletions = [NSMutableDictionary dictionary];
  return _profilePendingCompletions;
}

- (NSMutableDictionary<NSString *, NSDictionary *> *)threadPayloadCache {
  if (!_threadPayloadCache) _threadPayloadCache = [NSMutableDictionary dictionary];
  return _threadPayloadCache;
}

- (NSMutableDictionary<NSString *, NSDate *> *)threadPayloadCacheDates {
  if (!_threadPayloadCacheDates) _threadPayloadCacheDates = [NSMutableDictionary dictionary];
  return _threadPayloadCacheDates;
}

- (NSMutableDictionary<NSString *, NSMutableArray *> *)threadPendingCompletions {
  if (!_threadPendingCompletions) _threadPendingCompletions = [NSMutableDictionary dictionary];
  return _threadPendingCompletions;
}

- (void)completePendingDictionaryRequests:(NSArray *)requests value:(NSDictionary *)value error:(NSError *)error {
  for (id request in requests ?: @[]) {
    NFBAtprotoDictionaryCompletion completion = (NFBAtprotoDictionaryCompletion)request;
    if (completion) completion(value, error);
  }
}

- (void)invalidateThreadPayloadCache {
  @synchronized (self) {
    [self.threadPayloadCache removeAllObjects];
    [self.threadPayloadCacheDates removeAllObjects];
  }
}

- (NSString *)resourceCachePrefixForCurrentAccount {
  NSString *account = [NFBAtprotoSession sharedSession].did ?: [NFBAtprotoSession sharedSession].handle ?: @"";
  if (account.length == 0) account = @"anonymous";
  return [@"account:" stringByAppendingString:account];
}

- (NSString *)resourceCacheKeyWithName:(NSString *)name qualifier:(NSString *)qualifier {
  NSString *safeName = name.length > 0 ? name : @"resource";
  NSString *safeQualifier = qualifier.length > 0 ? qualifier : @"default";
  return [NSString stringWithFormat:@"%@|%@|%@", [self resourceCachePrefixForCurrentAccount], safeName, safeQualifier];
}

+ (NSString *)resourceArrayFingerprint:(NSArray<NSDictionary *> *)items {
  NSArray *safeItems = [items isKindOfClass:NSArray.class] ? items : @[];
  NSData *data = [NSJSONSerialization dataWithJSONObject:safeItems options:0 error:nil];
  if (data.length > 0) {
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length > 0) return json;
  }
  return [safeItems description] ?: @"";
}

- (void)fetchResourceArrayWithCacheKey:(NSString *)cacheKey loader:(NFBAtprotoCachedArrayLoader)loader completion:(NFBAtprotoArrayCompletion)completion {
  if (cacheKey.length == 0 || !loader) {
    if (loader) loader(completion);
    return;
  }

  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  __block NSArray<NSDictionary *> *cachedItems = nil;
  __block NSString *cachedFingerprint = nil;
  @synchronized (self) {
    cachedItems = self.resourceArrayCache[cacheKey];
    cachedFingerprint = self.resourceArrayFingerprintCache[cacheKey];
  }

  BOOL hasCachedItems = cachedItems != nil;
  if (hasCachedItems && completion) completion(cachedItems, nil, nil);

  loader(^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
      if (!hasCachedItems && completion) completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      return;
    }
    if (error) {
      if (!hasCachedItems && completion) completion(nil, cursor, error);
      return;
    }

    NSArray<NSDictionary *> *nextItems = [items isKindOfClass:NSArray.class] ? items : @[];
    NSString *nextFingerprint = [self.class resourceArrayFingerprint:nextItems];
    BOOL changed = !hasCachedItems || ![nextFingerprint isEqualToString:cachedFingerprint ?: @""];
    if (!changed) return;

    @synchronized (self) {
      self.resourceArrayCache[cacheKey] = nextItems;
      self.resourceArrayFingerprintCache[cacheKey] = nextFingerprint ?: @"";
    }
    if (completion) completion(nextItems, cursor, nil);
  });
}

- (void)invalidateCachedFeedAndListResources {
  NSString *prefix = [self resourceCachePrefixForCurrentAccount];
  @synchronized (self) {
    NSArray<NSString *> *keys = [self.resourceArrayCache.allKeys copy];
    for (NSString *key in keys) {
      if (![key hasPrefix:prefix]) continue;
      [self.resourceArrayCache removeObjectForKey:key];
      [self.resourceArrayFingerprintCache removeObjectForKey:key];
    }
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:NFBAtprotoFeedListCacheDidInvalidateNotification object:self];
  });
}

- (void)fetchHomeTimelineWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSMutableDictionary *params = [@{@"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.feed.getTimeline"
                 params:params
           requiresAuth:YES
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishFeedResponse:value key:@"feed" error:error completion:completion];
  }];
}

- (void)fetchDiscoverFeedWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (NFBAtprotoDiscoverFeedURI.length > 0) {
    [self fetchFeedWithURI:NFBAtprotoDiscoverFeedURI cursor:cursor completion:completion];
    return;
  }

  [self fetchProfileForActor:NFBAtprotoDiscoverFeedActor completion:^(NSDictionary *value, NSError *error) {
    if (error || ![value[@"did"] isKindOfClass:NSString.class]) {
      if (completion) completion(nil, nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:20 userInfo:@{NSLocalizedDescriptionKey: @"Could not load the For you feed."}]);
      return;
    }
    NFBAtprotoDiscoverFeedURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.generator/%@", value[@"did"], NFBAtprotoDiscoverFeedRkey];
    [self fetchFeedWithURI:NFBAtprotoDiscoverFeedURI cursor:cursor completion:completion];
  }];
}

- (void)fetchFeedWithURI:(NSString *)feedURI cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (feedURI.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"feed": feedURI, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.feed.getFeed"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishFeedResponse:value key:@"feed" error:error completion:completion];
  }];
}

- (void)fetchFeedMetadataForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion {
  [self fetchAppViewGET:@"app.bsky.feed.getFeedGenerator" params:@{@"feed": uri ?: @""} requiresAuth:NO completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    NSDictionary *view = [value isKindOfClass:NSDictionary.class] && [value[@"view"] isKindOfClass:NSDictionary.class] ? value[@"view"] : nil;
    if (completion) completion(view, error);
  }];
}

- (void)fetchListFeedWithURI:(NSString *)listURI cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (listURI.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"list": listURI, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.feed.getListFeed"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishFeedResponse:value key:@"feed" error:error completion:completion];
  }];
}

- (void)fetchBookmarksWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSMutableDictionary *params = [@{@"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.bookmark.getBookmarks"
                 params:params
           requiresAuth:YES
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *bookmarks = [value isKindOfClass:NSDictionary.class] && [value[@"bookmarks"] isKindOfClass:NSArray.class] ? value[@"bookmarks"] : @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:bookmarks.count];
    for (NSDictionary *bookmark in bookmarks) {
      if (![bookmark isKindOfClass:NSDictionary.class]) continue;
      NSDictionary *post = [bookmark[@"item"] isKindOfClass:NSDictionary.class] ? bookmark[@"item"] : nil;
      if (!post) continue;
      NSMutableDictionary *updatedPost = [post mutableCopy];
      NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
      NSMutableDictionary *updatedViewer = [viewer mutableCopy] ?: [NSMutableDictionary dictionary];
      updatedViewer[@"bookmarked"] = @YES;
      updatedPost[@"viewer"] = updatedViewer;
      [items addObject:@{@"post": updatedPost, @"bookmarkCreatedAt": NFBClientStringValue(bookmark[@"createdAt"])}];
    }
    NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)fetchSubscribedHomeFeedsWithCompletion:(NFBAtprotoArrayCompletion)completion {
  NSString *cacheKey = [self resourceCacheKeyWithName:@"home-feed-tabs" qualifier:nil];
  [self fetchResourceArrayWithCacheKey:cacheKey loader:^(NFBAtprotoArrayCompletion cachedCompletion) {
    [[NFBAtprotoSession sharedSession] xrpcGET:@"app.bsky.actor.getPreferences"
                                       service:nil
                                        params:nil
                                 authenticated:YES
                                    completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)response;
      if (error) {
        if (cachedCompletion) cachedCompletion(nil, nil, error);
        return;
      }

      NSArray *preferences = [value isKindOfClass:NSDictionary.class] && [value[@"preferences"] isKindOfClass:NSArray.class] ? value[@"preferences"] : @[];
      NSArray<NSDictionary *> *savedFeeds = [self savedHomeFeedsFromPreferences:preferences];
      if (savedFeeds.count == 0) {
        if (cachedCompletion) cachedCompletion(@[], nil, nil);
        return;
      }

      NSMutableArray<NSString *> *feedURIs = [NSMutableArray array];
      NSMutableSet<NSString *> *seen = [NSMutableSet set];
      for (NSDictionary *feed in savedFeeds) {
        NSString *uri = [feed[@"value"] isKindOfClass:NSString.class] ? feed[@"value"] : @"";
        if (uri.length == 0 || [seen containsObject:uri]) continue;
        [seen addObject:uri];
        [feedURIs addObject:uri];
      }

      [self fetchFeedGeneratorViewsForURIs:feedURIs completion:^(NSDictionary<NSString *,NSDictionary *> *generators) {
        NSMutableArray<NSDictionary *> *tabs = [NSMutableArray array];
        NSMutableSet<NSString *> *addedURIs = [NSMutableSet set];
        for (NSDictionary *feed in savedFeeds) {
          NSString *uri = [feed[@"value"] isKindOfClass:NSString.class] ? feed[@"value"] : @"";
          if (uri.length == 0 || [addedURIs containsObject:uri]) continue;
          [addedURIs addObject:uri];
          NSDictionary *generator = generators[uri];
          NSString *displayName = [generator[@"displayName"] isKindOfClass:NSString.class] ? generator[@"displayName"] : [self.class fallbackFeedNameForURI:uri];
          NSString *description = [generator[@"description"] isKindOfClass:NSString.class] ? generator[@"description"] : @"";
          NSDictionary *creator = [generator[@"creator"] isKindOfClass:NSDictionary.class] ? generator[@"creator"] : @{};
          [tabs addObject:@{
            @"type": @"feed",
            @"label": displayName ?: @"Feed",
            @"uri": uri,
            @"description": description ?: @"",
            @"avatar": [generator[@"avatar"] isKindOfClass:NSString.class] ? generator[@"avatar"] : @"",
            @"creator": [creator[@"handle"] isKindOfClass:NSString.class] ? creator[@"handle"] : @""
          }];
        }
        if (cachedCompletion) cachedCompletion(tabs, nil, nil);
      }];
    }];
  } completion:completion];
}

- (void)fetchSavedFeedResourcesWithCompletion:(NFBAtprotoArrayCompletion)completion {
  NSString *cacheKey = [self resourceCacheKeyWithName:@"saved-feed-resources" qualifier:nil];
  [self fetchResourceArrayWithCacheKey:cacheKey loader:^(NFBAtprotoArrayCompletion cachedCompletion) {
    [self fetchSavedFeedItemsWithCompletion:^(NSArray<NSDictionary *> *items, NSArray *preferences, NSError *error) {
      (void)preferences;
      if (error) {
        if (cachedCompletion) cachedCompletion(nil, nil, error);
        return;
      }
      NSMutableArray<NSString *> *uris = [NSMutableArray array];
      NSMutableSet<NSString *> *seen = [NSMutableSet set];
      for (NSDictionary *feed in items) {
        if (![feed[@"type"] isEqualToString:@"feed"]) continue;
        NSString *uri = NFBClientStringValue(feed[@"value"]);
        if (uri.length == 0 || [seen containsObject:uri]) continue;
        [seen addObject:uri];
        [uris addObject:uri];
      }
      [self fetchFeedGeneratorViewsForURIs:uris completion:^(NSDictionary<NSString *,NSDictionary *> *generatorsByURI) {
        NSMutableArray *resources = [NSMutableArray array];
        for (NSDictionary *feed in items) {
          if (![feed[@"type"] isEqualToString:@"feed"]) continue;
          NSString *uri = NFBClientStringValue(feed[@"value"]);
          if (uri.length == 0) continue;
          NSDictionary *generator = generatorsByURI[uri] ?: @{};
          NSMutableDictionary *resource = [generator mutableCopy];
          resource[@"uri"] = uri;
          resource[@"_nfbSavedFeedID"] = NFBClientStringValue(feed[@"id"]).length > 0 ? feed[@"id"] : uri;
          resource[@"_nfbSavedFeedSaved"] = @YES;
          [resources addObject:@{@"type": @"feed", @"resource": resource}];
        }
        if (cachedCompletion) cachedCompletion(resources, nil, nil);
      }];
    }];
  } completion:completion];
}

- (void)searchFeedGenerators:(NSString *)query cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSMutableDictionary *params = [@{@"limit": @"30"} mutableCopy];
  NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  if (trimmed.length > 0) params[@"query"] = trimmed;
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchSavedFeedItemsWithCompletion:^(NSArray<NSDictionary *> *savedItems, NSArray *preferences, NSError *savedError) {
    (void)preferences;
    NSMutableDictionary<NSString *, NSDictionary *> *savedByURI = [NSMutableDictionary dictionary];
    for (NSDictionary *item in savedItems ?: @[]) {
      if (![item[@"type"] isEqualToString:@"feed"]) continue;
      NSString *uri = NFBClientStringValue(item[@"value"]);
      if (uri.length > 0) savedByURI[uri] = item;
    }

    [self fetchAppViewGET:@"app.bsky.unspecced.getPopularFeedGenerators"
                   params:params
             requiresAuth:NO
               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)response;
      if (error) {
        if (completion) completion(nil, nil, error);
        return;
      }
      NSArray *feeds = [value isKindOfClass:NSDictionary.class] && [value[@"feeds"] isKindOfClass:NSArray.class] ? value[@"feeds"] : @[];
      NSMutableArray *items = [NSMutableArray arrayWithCapacity:feeds.count];
      for (NSDictionary *feed in feeds) {
        if (![feed isKindOfClass:NSDictionary.class]) continue;
        NSString *uri = NFBClientStringValue(feed[@"uri"]);
        NSMutableDictionary *resource = [feed mutableCopy];
        NSDictionary *saved = savedByURI[uri];
        if (saved) {
          resource[@"_nfbSavedFeedID"] = NFBClientStringValue(saved[@"id"]).length > 0 ? saved[@"id"] : uri;
          resource[@"_nfbSavedFeedSaved"] = @YES;
        } else {
          resource[@"_nfbSavedFeedSaved"] = @NO;
        }
        [items addObject:@{@"type": @"feed", @"resource": resource}];
      }
      NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
      (void)savedError;
      if (completion) completion(items, nextCursor, nil);
    }];
  }];
}

- (void)setSavedFeedWithURI:(NSString *)feedURI saved:(BOOL)saved completion:(NFBAtprotoDictionaryCompletion)completion {
  if (feedURI.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:91 userInfo:@{NSLocalizedDescriptionKey: @"Feed was not available."}]);
    return;
  }
  [self fetchSavedFeedItemsWithCompletion:^(NSArray<NSDictionary *> *items, NSArray *preferences, NSError *error) {
    if (error) {
      if (completion) completion(nil, error);
      return;
    }
    NSMutableArray<NSDictionary *> *next = [NSMutableArray array];
    BOOL alreadySaved = NO;
    for (NSDictionary *item in items) {
      if (![item isKindOfClass:NSDictionary.class]) continue;
      NSString *value = NFBClientStringValue(item[@"value"]);
      if ([item[@"type"] isEqualToString:@"feed"] && [value isEqualToString:feedURI]) {
        alreadySaved = YES;
        if (!saved) continue;
      }
      [next addObject:item];
    }
    if (saved && !alreadySaved) {
      [next addObject:@{
        @"id": [[NSUUID UUID] UUIDString],
        @"type": @"feed",
        @"value": feedURI,
        @"pinned": @YES
      }];
    }
    [self putSavedFeedItems:next preferences:preferences completion:completion];
  }];
}

- (void)reorderSavedFeedURIs:(NSArray<NSString *> *)feedURIs completion:(NFBAtprotoDictionaryCompletion)completion {
  NSMutableArray<NSString *> *orderedURIs = [NSMutableArray array];
  NSMutableSet<NSString *> *seenURIs = [NSMutableSet set];
  for (NSString *uri in feedURIs ?: @[]) {
    if (![uri isKindOfClass:NSString.class] || uri.length == 0 || [seenURIs containsObject:uri]) continue;
    [seenURIs addObject:uri];
    [orderedURIs addObject:uri];
  }
  if (orderedURIs.count == 0) {
    if (completion) completion(@{}, nil);
    return;
  }

  [self fetchSavedFeedItemsWithCompletion:^(NSArray<NSDictionary *> *items, NSArray *preferences, NSError *error) {
    if (error) {
      if (completion) completion(nil, error);
      return;
    }

    NSMutableDictionary<NSString *, NSDictionary *> *feedItemsByURI = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *remainingFeedItems = [NSMutableArray array];
    NSMutableSet<NSString *> *orderedSet = [NSMutableSet setWithArray:orderedURIs];
    for (NSDictionary *item in items ?: @[]) {
      if (![item isKindOfClass:NSDictionary.class] || ![item[@"type"] isEqualToString:@"feed"]) continue;
      NSString *uri = NFBClientStringValue(item[@"value"]);
      if (uri.length == 0) continue;
      if ([orderedSet containsObject:uri]) feedItemsByURI[uri] = item;
      else [remainingFeedItems addObject:item];
    }

    NSMutableArray<NSDictionary *> *orderedFeedItems = [NSMutableArray array];
    for (NSString *uri in orderedURIs) {
      NSDictionary *item = feedItemsByURI[uri];
      if (item.count > 0) [orderedFeedItems addObject:item];
    }
    [orderedFeedItems addObjectsFromArray:remainingFeedItems];

    NSMutableArray<NSDictionary *> *next = [NSMutableArray array];
    NSUInteger feedIndex = 0;
    for (NSDictionary *item in items ?: @[]) {
      if (![item isKindOfClass:NSDictionary.class]) continue;
      if ([item[@"type"] isEqualToString:@"feed"]) {
        if (feedIndex < orderedFeedItems.count) [next addObject:orderedFeedItems[feedIndex++]];
      } else {
        [next addObject:item];
      }
    }
    while (feedIndex < orderedFeedItems.count) {
      [next addObject:orderedFeedItems[feedIndex++]];
    }

    [self putSavedFeedItems:next preferences:preferences completion:completion];
  }];
}

- (void)fetchAuthorFeedForActor:(NSString *)actor cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  [self fetchAuthorFeedForActor:actor filter:nil cursor:cursor completion:completion];
}

- (void)fetchAuthorFeedForActor:(NSString *)actor filter:(NSString *)filter cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"actor": actor, @"limit": @"50"} mutableCopy];
  if (filter.length > 0) params[@"filter"] = filter;
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.feed.getAuthorFeed"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishFeedResponse:value key:@"feed" error:error completion:completion];
  }];
}

- (void)fetchAuthorFeedWithRepliesForActor:(NSString *)actor cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  [self fetchAuthorFeedForActor:actor filter:@"posts_with_replies" cursor:cursor completion:^(NSArray<NSDictionary *> *items, NSString *nextCursor, NSError *error) {
    if (error) {
      if (completion) completion(items, nextCursor, error);
      return;
    }
    [self finishAuthorFeedWithRepliesItems:items cursor:nextCursor completion:completion];
  }];
}

- (void)finishAuthorFeedWithRepliesItems:(NSArray<NSDictionary *> *)items cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSArray<NSDictionary *> *safeItems = [items isKindOfClass:NSArray.class] ? items : @[];
  NSMutableOrderedSet<NSString *> *parentURIs = [NSMutableOrderedSet orderedSet];
  for (NSDictionary *item in safeItems) {
    if (![item isKindOfClass:NSDictionary.class]) continue;
    if ([self.class replyParentPostFromFeedItem:item].count > 0) continue;
    NSDictionary *post = [self.class postFromFeedItem:item];
    NSString *parentURI = [self.class replyParentURIForPost:post];
    if (parentURI.length > 0) [parentURIs addObject:parentURI];
  }

  void (^finish)(NSDictionary<NSString *, NSDictionary *> *) = ^(NSDictionary<NSString *, NSDictionary *> *postsByURI) {
    NSMutableArray<NSDictionary *> *hydrated = [NSMutableArray arrayWithCapacity:safeItems.count];
    for (NSDictionary *item in safeItems) {
      if (![item isKindOfClass:NSDictionary.class]) continue;
      NSMutableDictionary *nextItem = [item mutableCopy];
      NSDictionary *post = [self.class postFromFeedItem:item];
      NSString *parentURI = [self.class replyParentURIForPost:post];
      if (parentURI.length > 0) {
        nextItem[@"_nfbShowReplyContext"] = @YES;
        nextItem[@"replyParentURI"] = parentURI;
        NSDictionary *parentPost = [self.class replyParentPostFromFeedItem:item];
        if (parentPost.count == 0) parentPost = [postsByURI[parentURI] isKindOfClass:NSDictionary.class] ? postsByURI[parentURI] : nil;
        if (parentPost.count > 0) nextItem[@"replyParentPost"] = parentPost;
      }
      [hydrated addObject:[nextItem copy]];
    }
    if (completion) completion([self.class feedItemsSortedNewestFirst:hydrated], cursor, nil);
  };

  if (parentURIs.count == 0) {
    finish(@{});
    return;
  }

  [self fetchPostViewsForURIs:parentURIs.array completion:^(NSDictionary<NSString *,NSDictionary *> *postsByURI, NSError *error) {
    (void)error;
    finish([postsByURI isKindOfClass:NSDictionary.class] ? postsByURI : @{});
  }];
}

- (void)fetchAuthorArticlesForActor:(NSString *)actor cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }
  [self fetchAuthorArticlesForActor:actor
                              cursor:cursor
                    accumulatedItems:[NSMutableArray array]
                      remainingPages:5
                          completion:completion];
}

- (void)fetchAuthorArticlesForActor:(NSString *)actor
                             cursor:(NSString *)cursor
                   accumulatedItems:(NSMutableArray<NSDictionary *> *)accumulatedItems
                     remainingPages:(NSUInteger)remainingPages
                         completion:(NFBAtprotoArrayCompletion)completion {
  [self fetchAuthorFeedForActor:actor filter:@"posts_no_replies" cursor:cursor completion:^(NSArray<NSDictionary *> *items, NSString *nextCursor, NSError *error) {
    if (error) {
      if (completion) completion(accumulatedItems.copy ?: @[], nextCursor, error);
      return;
    }

    for (NSDictionary *item in items ?: @[]) {
      NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
      NSDictionary *card = [NFBAtprotoClient externalCardForPost:post ?: @{}];
      if ([NFBAtprotoClient externalCardIsStandardSiteArticle:card]) [accumulatedItems addObject:item];
    }

    if (accumulatedItems.count >= 20 || nextCursor.length == 0 || remainingPages <= 1) {
      if (completion) completion(accumulatedItems.copy ?: @[], nextCursor, nil);
      return;
    }

    [self fetchAuthorArticlesForActor:actor
                                cursor:nextCursor
                      accumulatedItems:accumulatedItems
                        remainingPages:remainingPages - 1
                            completion:completion];
  }];
}

- (void)fetchActorLikesForActor:(NSString *)actor cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"actor": actor, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.feed.getActorLikes"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishFeedResponse:value key:@"feed" error:error completion:completion];
  }];
}

- (void)fetchPostStatsForPost:(NSDictionary *)post type:(NSString *)type cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSString *uri = NFBClientStringValue(post[@"uri"]);
  if (uri.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"uri": uri, @"limit": @"50"} mutableCopy];
  NSString *cid = NFBClientStringValue(post[@"cid"]);
  if (cid.length > 0) params[@"cid"] = cid;
  if (cursor.length > 0) params[@"cursor"] = cursor;

  NSString *normalizedType = type.length > 0 ? type : @"likes";
  NSString *method = @"app.bsky.feed.getLikes";
  if ([normalizedType isEqualToString:@"reposts"]) method = @"app.bsky.feed.getRepostedBy";
  else if ([normalizedType isEqualToString:@"quotes"]) method = @"app.bsky.feed.getQuotes";

  [self fetchAppViewGET:method
                 params:params
           requiresAuth:YES
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSDictionary *dictionary = [value isKindOfClass:NSDictionary.class] ? value : @{};
    NSString *nextCursor = NFBClientStringValue(dictionary[@"cursor"]);
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    if ([normalizedType isEqualToString:@"quotes"]) {
      NSArray *posts = [dictionary[@"posts"] isKindOfClass:NSArray.class] ? dictionary[@"posts"] : @[];
      for (NSDictionary *quotedPost in posts) {
        if ([quotedPost isKindOfClass:NSDictionary.class]) [items addObject:@{@"post": quotedPost}];
      }
    } else if ([normalizedType isEqualToString:@"reposts"]) {
      NSArray *actors = [dictionary[@"repostedBy"] isKindOfClass:NSArray.class] ? dictionary[@"repostedBy"] : @[];
      for (NSDictionary *actor in actors) {
        if ([actor isKindOfClass:NSDictionary.class]) [items addObject:actor];
      }
    } else {
      NSArray *likes = [dictionary[@"likes"] isKindOfClass:NSArray.class] ? dictionary[@"likes"] : @[];
      for (NSDictionary *like in likes) {
        NSDictionary *actor = [like[@"actor"] isKindOfClass:NSDictionary.class] ? like[@"actor"] : nil;
        if (actor) [items addObject:actor];
      }
    }
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)fetchProfileActorsForActor:(NSString *)actor kind:(NSString *)kind cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSString *normalizedKind = kind.length > 0 ? kind : @"followers";
  NSString *method = @"app.bsky.graph.getFollowers";
  NSString *key = @"followers";
  if ([normalizedKind isEqualToString:@"following"]) {
    method = @"app.bsky.graph.getFollows";
    key = @"follows";
  } else if ([normalizedKind isEqualToString:@"known"]) {
    method = @"app.bsky.graph.getKnownFollowers";
    key = @"followers";
  }

  NSMutableDictionary *params = [@{@"actor": actor, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;
  [self fetchAppViewGET:method
                 params:params
           requiresAuth:[normalizedKind isEqualToString:@"known"]
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSDictionary *dictionary = [value isKindOfClass:NSDictionary.class] ? value : @{};
    NSArray *actors = [dictionary[key] isKindOfClass:NSArray.class] ? dictionary[key] : @[];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *actorItem in actors) {
      if ([actorItem isKindOfClass:NSDictionary.class]) [items addObject:actorItem];
    }
    if (completion) completion(items, NFBClientStringValue(dictionary[@"cursor"]), nil);
  }];
}

- (void)fetchListsForActor:(NSString *)actor cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"actor": actor, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.graph.getLists"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishResourceResponse:value key:@"lists" type:@"list" error:error completion:completion];
  }];
}

- (void)fetchCurrentUserListsForKind:(NSString *)kind completion:(NFBAtprotoArrayCompletion)completion {
  NSString *actor = [NFBAtprotoSession sharedSession].did ?: [NFBAtprotoSession sharedSession].handle ?: @"";
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSString *cacheKey = [self resourceCacheKeyWithName:@"current-user-lists" qualifier:[kind isEqualToString:@"block"] ? @"block" : @"follow"];
  [self fetchResourceArrayWithCacheKey:cacheKey loader:^(NFBAtprotoArrayCompletion cachedCompletion) {
  [self fetchListsForActor:actor cursor:nil completion:^(NSArray<NSDictionary *> *ownedItems, NSString *cursor, NSError *error) {
    (void)cursor;
    if (error) {
      if (cachedCompletion) cachedCompletion(nil, nil, error);
      return;
    }

    BOOL blockLists = [kind isEqualToString:@"block"];
    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
    NSMutableSet<NSString *> *seenURIs = [NSMutableSet set];
    void (^addListItem)(NSDictionary *, BOOL, BOOL) = ^(NSDictionary *item, BOOL muted, BOOL blocked) {
      NSDictionary *resource = [item[@"resource"] isKindOfClass:NSDictionary.class] ? item[@"resource"] : @{};
      NSString *uri = NFBClientStringValue(resource[@"uri"]);
      if (uri.length == 0 || [seenURIs containsObject:uri]) return;
      NSString *purpose = NFBClientStringValue(resource[@"purpose"]);
      BOOL moderation = [purpose hasSuffix:@"#modlist"] || [purpose isEqualToString:@"moderation"];
      BOOL follow = !moderation;
      if ((!blockLists && !follow) || (blockLists && !moderation && !muted && !blocked)) return;
      [seenURIs addObject:uri];
      NSMutableDictionary *mutableResource = [resource mutableCopy];
      if (muted) mutableResource[@"_nfbViewerMuted"] = @YES;
      if (blocked) mutableResource[@"_nfbViewerBlocked"] = @YES;
      [filtered addObject:@{@"type": @"list", @"resource": mutableResource}];
    };

    for (NSDictionary *item in ownedItems ?: @[]) addListItem(item, NO, NO);
    if (!blockLists) {
      if (cachedCompletion) cachedCompletion(filtered, nil, nil);
      return;
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSArray<NSDictionary *> *mutedItems = @[];
    __block NSArray<NSDictionary *> *blockedItems = @[];

    dispatch_group_enter(group);
    [self fetchAppViewGET:@"app.bsky.graph.getListMutes" params:@{@"limit": @"100"} requiresAuth:YES completion:^(id value, NSHTTPURLResponse *response, NSError *muteError) {
      (void)response;
      if (!muteError) {
        NSMutableArray *items = [NSMutableArray array];
        NSArray *lists = [value isKindOfClass:NSDictionary.class] && [value[@"lists"] isKindOfClass:NSArray.class] ? value[@"lists"] : @[];
        for (NSDictionary *list in lists) if ([list isKindOfClass:NSDictionary.class]) [items addObject:@{@"type": @"list", @"resource": list}];
        mutedItems = items;
      }
      dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self fetchAppViewGET:@"app.bsky.graph.getListBlocks" params:@{@"limit": @"100"} requiresAuth:YES completion:^(id value, NSHTTPURLResponse *response, NSError *blockError) {
      (void)response;
      if (!blockError) {
        NSMutableArray *items = [NSMutableArray array];
        NSArray *lists = [value isKindOfClass:NSDictionary.class] && [value[@"lists"] isKindOfClass:NSArray.class] ? value[@"lists"] : @[];
        for (NSDictionary *list in lists) if ([list isKindOfClass:NSDictionary.class]) [items addObject:@{@"type": @"list", @"resource": list}];
        blockedItems = items;
      }
      dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
      for (NSDictionary *item in mutedItems) addListItem(item, YES, NO);
      for (NSDictionary *item in blockedItems) addListItem(item, NO, YES);
      if (cachedCompletion) cachedCompletion(filtered, nil, nil);
    });
  }];
  } completion:completion];
}

- (void)fetchStarterPacksForActor:(NSString *)actor cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"actor": actor, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.graph.getActorStarterPacks"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    [self finishResourceResponse:value key:@"starterPacks" type:@"starterPack" error:error completion:completion];
  }];
}

- (void)searchPosts:(NSString *)query cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  [self searchPosts:query sort:@"latest" cursor:cursor completion:completion];
}

- (void)searchPosts:(NSString *)query sort:(NSString *)sort cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  [self searchPosts:query sort:sort followingOnly:NO mediaTab:0 cursor:cursor completion:completion];
}
- (void)searchPosts:(NSString *)query sort:(NSString *)sort followingOnly:(BOOL)following mediaTab:(NSInteger)mediaTab cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [NFBSearchRequestParameters(trimmed, sort, following, mediaTab, [NFBAtprotoSession sharedSession].did) mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [self fetchAppViewGET:@"app.bsky.feed.searchPostsV2"
                 params:params
           requiresAuth:[[NFBAtprotoSession sharedSession] hasSession]
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *posts = [value isKindOfClass:[NSDictionary class]] && [value[@"posts"] isKindOfClass:[NSArray class]] ? value[@"posts"] : @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:posts.count];
    for (NSDictionary *post in posts) {
      if ([post isKindOfClass:[NSDictionary class]]) [items addObject:@{@"post": post}];
    }
    NSString *nextCursor = [value isKindOfClass:[NSDictionary class]] && [value[@"cursor"] isKindOfClass:[NSString class]] ? value[@"cursor"] : nil;
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)searchActors:(NSString *)query limit:(NSUInteger)limit completion:(NFBAtprotoArrayCompletion)completion {
  [self searchActors:query limit:limit cursor:nil completion:completion];
}

- (void)searchActors:(NSString *)query limit:(NSUInteger)limit cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSUInteger clampedLimit = MIN(MAX(limit, (NSUInteger)1), (NSUInteger)25);
  NSMutableDictionary *params = [@{@"q": trimmed, @"limit": @(clampedLimit)} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;
  [self fetchAppViewGET:@"app.bsky.actor.searchActors"
                 params:params
           requiresAuth:[[NFBAtprotoSession sharedSession] hasSession]
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *actors = [value isKindOfClass:NSDictionary.class] && [value[@"actors"] isKindOfClass:NSArray.class] ? value[@"actors"] : @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:actors.count];
    for (NSDictionary *actor in actors) {
      if ([actor isKindOfClass:NSDictionary.class]) [items addObject:actor];
    }
    NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)fetchTrendingTopicsWithCompletion:(NFBAtprotoArrayCompletion)completion {
  [[NFBAtprotoSession sharedSession] xrpcGET:@"app.bsky.unspecced.getTrends"
                                     service:NFBAtprotoPublicAppViewURL
                                      params:@{@"limit": @"25"}
                               authenticated:NO
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }

    NSArray *topics = [value isKindOfClass:NSDictionary.class] && [value[@"trends"] isKindOfClass:NSArray.class] ? value[@"trends"] : @[];
    NSArray *suggested = [value isKindOfClass:NSDictionary.class] && [value[@"suggested"] isKindOfClass:NSArray.class] ? value[@"suggested"] : @[];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSInteger rank = 1;

    for (NSDictionary *topic in topics) {
      if (![topic isKindOfClass:NSDictionary.class]) continue;
      [items addObject:[self.class trendItemForTopic:topic kind:@"topic" rank:rank++]];
      if (items.count >= 25) break;
    }

    if (items.count < 25) {
      for (NSDictionary *topic in suggested) {
        if (![topic isKindOfClass:NSDictionary.class]) continue;
        [items addObject:[self.class trendItemForTopic:topic kind:@"suggested" rank:rank++]];
        if (items.count >= 25) break;
      }
    }

    if (completion) completion(items, nil, nil);
  }];
}

- (void)fetchNotificationsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  [self fetchNotificationsWithCursor:cursor reasons:nil completion:completion];
}

- (void)fetchNotificationsWithCursor:(NSString *)cursor reasons:(NSArray<NSString *> *)reasons completion:(NFBAtprotoArrayCompletion)completion {
  NSMutableDictionary *params = [@{@"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;
  if (reasons.count > 0) params[@"reasons"] = reasons;

  [[NFBAtprotoSession sharedSession] xrpcGETViaAppViewProxy:@"app.bsky.notification.listNotifications"
                                                     params:params
                                                 completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }

    NSArray *notifications = [value isKindOfClass:[NSDictionary class]] && [value[@"notifications"] isKindOfClass:[NSArray class]] ? value[@"notifications"] : @[];
    NSMutableArray *draftItems = [NSMutableArray arrayWithCapacity:notifications.count];
    NSMutableOrderedSet<NSString *> *targetURIs = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *notification in notifications) {
      if (![notification isKindOfClass:[NSDictionary class]]) continue;
      NSString *reason = [notification[@"reason"] isKindOfClass:[NSString class]] ? notification[@"reason"] : @"notification";
      NSString *targetURI = [self targetPostURIForNotification:notification];
      if (targetURI.length > 0) [targetURIs addObject:targetURI];
      BOOL profileRoute = [self notificationReasonRoutesToProfile:reason];
      NSDictionary *post = profileRoute ? @{} : [self syntheticPostForNotification:notification targetURI:targetURI];
      NSString *replyParentURI = [self.class replyParentURIForPost:post];
      if (replyParentURI.length > 0) [targetURIs addObject:replyParentURI];
      [draftItems addObject:@{
        @"post": post,
        @"reason": reason,
        @"targetURI": targetURI ?: @"",
        @"notification": notification,
        @"route": profileRoute ? @"profile" : @"post"
      }];
    }
    NSString *nextCursor = [value isKindOfClass:[NSDictionary class]] && [value[@"cursor"] isKindOfClass:[NSString class]] ? value[@"cursor"] : nil;
    [self fetchPostViewsForURIs:targetURIs.array completion:^(NSDictionary<NSString *,NSDictionary *> *postsByURI, NSError *hydrateError) {
      (void)hydrateError;
      NSMutableArray *items = [NSMutableArray arrayWithCapacity:draftItems.count];
      for (NSDictionary *draft in draftItems) {
        NSString *targetURI = [draft[@"targetURI"] isKindOfClass:NSString.class] ? draft[@"targetURI"] : @"";
        NSDictionary *notification = [draft[@"notification"] isKindOfClass:NSDictionary.class] ? draft[@"notification"] : @{};
        NSDictionary *hydratedPost = targetURI.length > 0 ? postsByURI[targetURI] : nil;
        NSDictionary *post = hydratedPost ?: ([draft[@"post"] isKindOfClass:NSDictionary.class] ? draft[@"post"] : @{});
        NSDictionary *author = [notification[@"author"] isKindOfClass:NSDictionary.class] ? notification[@"author"] : @{};
        NSString *reason = [draft[@"reason"] isKindOfClass:NSString.class] ? draft[@"reason"] : @"";
        NSString *route = [draft[@"route"] isKindOfClass:NSString.class] ? draft[@"route"] : @"post";
        NSString *createdAt = [notification[@"indexedAt"] isKindOfClass:NSString.class] ? notification[@"indexedAt"] : @"";
        id isRead = [notification[@"isRead"] respondsToSelector:@selector(boolValue)] ? notification[@"isRead"] : @NO;
        NSString *replyParentURI = [self.class replyParentURIForPost:post];
        NSDictionary *replyParentPost = replyParentURI.length > 0 && [postsByURI[replyParentURI] isKindOfClass:NSDictionary.class] ? postsByURI[replyParentURI] : nil;
        NSMutableDictionary *item = [@{
          @"type": @"notification",
          @"post": post,
          @"reason": reason,
          @"route": route,
          @"targetURI": targetURI ?: @"",
          @"notification": notification,
          @"author": author,
          @"createdAt": createdAt,
          @"isRead": isRead
        } mutableCopy];
        if (replyParentURI.length > 0) item[@"replyParentURI"] = replyParentURI;
        if (replyParentPost) item[@"replyParentPost"] = replyParentPost;
        [items addObject:item];
      }
      if (completion) completion(items, nextCursor, nil);
    }];
  }];
}

- (void)acceptUpdatedProfile:(NSDictionary *)profile {
  NSMutableDictionary *clean = [profile mutableCopy];
  [clean removeObjectForKey:@"_nfbLoadedAvatar"];
  [clean removeObjectForKey:@"_nfbLoadedBanner"];
  NSString *did = NFBProfileString(clean[@"did"]);
  if (!did.length || ![did isEqual:NFBAtprotoSession.sharedSession.did]) return;
  @synchronized (self) {
    self.profileEditRevision++;
    if (!self.recentProfileEdits) self.recentProfileEdits = [NSMutableDictionary new];
    self.recentProfileEdits[did] = clean;
    [self.profileCache removeAllObjects]; [self.profileCacheDates removeAllObjects];
    for (NSString *actor in @[did,NFBProfileString(clean[@"handle"])]) {
      if (!actor.length) continue;
      NSString *key = [self resourceCacheKeyWithName:@"profile" qualifier:actor.lowercaseString];
      self.profileCache[key] = clean; self.profileCacheDates[key] = NSDate.date;
    }
    [NFBAtprotoSession.sharedSession updateProfileFromDictionary:clean];
  }
  dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:NFBAtprotoProfileUpdatedNotification object:clean]; });
}

- (void)fetchProfileForActor:(NSString *)actor completion:(NFBAtprotoDictionaryCompletion)completion {
  if (actor.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:1 userInfo:@{NSLocalizedDescriptionKey: @"No actor was provided."}]);
    return;
  }

  NSUInteger profileRevision = self.profileEditRevision;
  // Profiles include viewer-specific follow/block state.
  NSString *cacheKey = [self resourceCacheKeyWithName:@"profile" qualifier:actor.lowercaseString ?: actor];
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  NSString *requestKey = [cacheKey stringByAppendingFormat:@"|request:%lu", (unsigned long)accountGeneration];
  NSDate *now = [NSDate date];
  @synchronized (self) {
    NSDictionary *cached = self.profileCache[cacheKey];
    NSDate *cachedDate = self.profileCacheDates[cacheKey];
    if (cached && cachedDate && [now timeIntervalSinceDate:cachedDate] <= NFBAtprotoProfileCacheTTL) {
      if (completion) completion(cached, nil);
      return;
    }

    NSMutableArray *pending = self.profilePendingCompletions[requestKey];
    if (pending) {
      if (completion) [pending addObject:[completion copy]];
      return;
    }
    pending = [NSMutableArray array];
    if (completion) [pending addObject:[completion copy]];
    self.profilePendingCompletions[requestKey] = pending;
  }

  [self fetchAppViewGET:@"app.bsky.actor.getProfile"
                 params:@{@"actor": actor}
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:[NSDictionary class]]) {
      NSArray *requests = nil;
      @synchronized (self) {
        requests = [self.profilePendingCompletions[requestKey] copy];
        [self.profilePendingCompletions removeObjectForKey:requestKey];
      }
      [self completePendingDictionaryRequests:requests value:nil error:error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Profile not found."}]];
      return;
    }
    NSDictionary *profile = value;
    NSString *did = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
    [self fetchProfileRecordForDID:did completion:^(NSDictionary *record, NSString *endpoint) {
      if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
        NSArray *requests = nil;
        @synchronized (self) {
          requests = [self.profilePendingCompletions[requestKey] copy];
          [self.profilePendingCompletions removeObjectForKey:requestKey];
        }
        [self completePendingDictionaryRequests:requests value:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
        return;
      }
      NSMutableDictionary *merged = record.count ? [NFBProfileViewApplyingRecord(profile,record,endpoint) mutableCopy] : [profile mutableCopy];
      NSDictionary *pinned = [record[@"pinnedPost"] isKindOfClass:NSDictionary.class] ? record[@"pinnedPost"] : nil;
      if (pinned) merged[@"pinnedPost"] = pinned;
      if (record[@"birthday"] && !NFBProfileString(record[@"com.nottwitter.birthDate"]).length) merged[@"birthday"] = record[@"birthday"];
      NSDictionary *result = [merged copy];
      NSArray *requests = nil;
      @synchronized (self) {
        // Arbitrate and publish together: Save may finish during either read.
        if (profileRevision != self.profileEditRevision && self.recentProfileEdits[did]) result = self.recentProfileEdits[did];
        if ([[NFBAtprotoSession sharedSession].did isEqualToString:result[@"did"]]) {
          [[NFBAtprotoSession sharedSession] updateProfileFromDictionary:result];
        }
        self.profileCache[cacheKey] = result;
        self.profileCacheDates[cacheKey] = [NSDate date];
        requests = [self.profilePendingCompletions[requestKey] copy];
        [self.profilePendingCompletions removeObjectForKey:requestKey];
      }
      [self completePendingDictionaryRequests:requests value:result error:nil];
    }];
  }];
}

- (void)markNotificationsSeenWithCompletion:(NFBAtprotoDictionaryCompletion)completion {
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaAppViewProxy:@"app.bsky.notification.updateSeen"
                                                        body:@{@"seenAt": [self.class isoDateNow]}
                                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)setActivitySubscriptionForSubject:(NSString *)subject post:(BOOL)post reply:(BOOL)reply completion:(NFBAtprotoDictionaryCompletion)completion {
  if (subject.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:92 userInfo:@{NSLocalizedDescriptionKey: @"That account could not be found."}]);
    return;
  }

  NSDictionary *body = @{
    @"subject": subject ?: @"",
    @"activitySubscription": @{
      @"post": @(post),
      @"reply": @(reply)
    }
  };
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaAppViewProxy:@"app.bsky.notification.putActivitySubscription"
                                                        body:body
                                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (NSDictionary *)pushRegistrationBodyForToken:(NSString *)token appID:(NSString *)appID {
  return @{
    @"serviceDid": NFBAtprotoNotificationServiceDID,
    @"token": token ?: @"",
    @"platform": NFBAtprotoPushPlatformIOS,
    @"appId": appID ?: @""
  };
}

- (void)registerPushToken:(NSString *)token appID:(NSString *)appID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (token.length == 0 || appID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:90 userInfo:@{NSLocalizedDescriptionKey: @"Push registration was missing the app token."}]);
    return;
  }

  NSDictionary *body = [self pushRegistrationBodyForToken:token appID:appID];
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"app.bsky.notification.registerPush"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)unregisterPushToken:(NSString *)token appID:(NSString *)appID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (token.length == 0 || appID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:91 userInfo:@{NSLocalizedDescriptionKey: @"Push registration was missing the app token."}]);
    return;
  }

  NSDictionary *body = [self pushRegistrationBodyForToken:token appID:appID];
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"app.bsky.notification.unregisterPush"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)fetchChatConversationsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSMutableDictionary *params = [@{@"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.listConvos"
                                                  params:params
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *convos = [value isKindOfClass:NSDictionary.class] && [value[@"convos"] isKindOfClass:NSArray.class] ? value[@"convos"] : @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:convos.count];
    for (NSDictionary *convo in convos) {
      if ([convo isKindOfClass:NSDictionary.class]) [items addObject:convo];
    }
    NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)fetchChatConversationRequestsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  NSMutableDictionary *params = [@{@"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.listConvoRequests"
                                                  params:params
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *requests = [value isKindOfClass:NSDictionary.class] && [value[@"requests"] isKindOfClass:NSArray.class] ? value[@"requests"] : @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:requests.count];
    for (NSDictionary *request in requests) {
      if ([request isKindOfClass:NSDictionary.class]) [items addObject:request];
    }
    NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)searchMessageableActors:(NSString *)query limit:(NSUInteger)limit completion:(NFBAtprotoArrayCompletion)completion {
  NSUInteger clampedLimit = MIN(MAX(limit, (NSUInteger)1), (NSUInteger)25);
  [self searchActors:query limit:clampedLimit completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    if (error || items.count == 0) {
      if (completion) completion(error ? nil : @[], cursor, error);
      return;
    }
    [self filterMessageableActors:items limit:clampedLimit completion:^(NSArray<NSDictionary *> *filtered, NSString *unusedCursor, NSError *filterError) {
      (void)unusedCursor;
      if (completion) completion(filtered ?: @[], cursor, filterError);
    }];
  }];
}

- (void)filterMessageableActors:(NSArray<NSDictionary *> *)actors limit:(NSUInteger)limit completion:(NFBAtprotoArrayCompletion)completion {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (viewerDID.length == 0 || actors.count == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableArray<NSDictionary *> *orderedResults = [NSMutableArray arrayWithCapacity:actors.count];
  for (NSUInteger index = 0; index < actors.count; index++) [orderedResults addObject:@{}];
  dispatch_group_t group = dispatch_group_create();

  for (NSUInteger index = 0; index < actors.count; index++) {
    NSDictionary *actor = actors[index];
    if (![actor isKindOfClass:NSDictionary.class]) continue;
    NSString *did = NFBClientStringValue(actor[@"did"]);
    if (did.length == 0 || [did isEqualToString:viewerDID]) continue;

    dispatch_group_enter(group);
    [self messagePermissionForProfile:actor completion:^(BOOL canMessage, BOOL followsViewer) {
      if (canMessage) {
        NSDictionary *result = actor;
        if (followsViewer) {
          NSMutableDictionary *mutableActor = [actor mutableCopy];
          mutableActor[NFBMessageableActorFollowsViewerKey] = @YES;
          result = [mutableActor copy];
        }
        @synchronized (orderedResults) {
          orderedResults[index] = result;
        }
      }
      dispatch_group_leave(group);
    }];
  }

  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
    for (NSDictionary *actor in orderedResults) {
      if (actor.count == 0) continue;
      [filtered addObject:actor];
      if (filtered.count >= limit) break;
    }
    if (completion) completion(filtered, nil, nil);
  });
}

- (void)canMessageProfile:(NSDictionary *)profile completion:(void (^)(BOOL canMessage))completion {
  [self messagePermissionForProfile:profile completion:^(BOOL canMessage, BOOL followsViewer) {
    (void)followsViewer;
    if (completion) completion(canMessage);
  }];
}

- (void)messagePermissionForProfile:(NSDictionary *)profile completion:(void (^)(BOOL canMessage, BOOL followsViewer))completion {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSString *targetDID = NFBClientStringValue(profile[@"did"]);
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  if (viewerDID.length == 0 || targetDID.length == 0 || [viewerDID isEqualToString:targetDID] ||
      NFBProfileViewerIsBlocking(viewer) || NFBProfileViewerIsBlockedBy(viewer)) {
    if (completion) completion(NO, NO);
    return;
  }
  // The chat service accounts for declarations (all/none/following), the
  // recipient following the sender, and exceptions for existing conversations.
  // Missing declarations or lookup failures must never become permission.
  [self fetchChatConversationAvailabilityForMembers:@[targetDID] completion:^(NSDictionary *value, NSError *error) {
    BOOL allowed = !error && NFBChatAvailabilityAllowsMessaging(value);
    if (completion) completion(allowed, allowed && NFBProfileRelationshipPresent(viewer[@"followedBy"]));
  }];
}

- (void)fetchChatConversationWithID:(NSString *)conversationID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:71 userInfo:@{NSLocalizedDescriptionKey: @"Conversation was not available."}]);
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getConvo"
                                                  params:@{@"convoId": conversationID}
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:72 userInfo:@{NSLocalizedDescriptionKey: @"Could not load that conversation."}]);
      return;
    }
    NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
    if (completion) completion(convo, nil);
  }];
}

- (void)fetchChatConversationAvailabilityForMembers:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion {
  NSArray<NSString *> *dids = NFBClientUniqueNonEmptyStrings(members);
  if (dids.count == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:60 userInfo:@{NSLocalizedDescriptionKey: @"Choose someone to message."}]);
    return;
  }
  NSUInteger generation = [NFBAtprotoSession sharedSession].accountGeneration;
  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getConvoAvailability"
                                                  params:@{@"members": dids}
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (generation != [NFBAtprotoSession sharedSession].accountGeneration) {
      if (completion) completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      return;
    }
    if (error || ![value isKindOfClass:NSDictionary.class] || ![value[@"canChat"] isKindOfClass:NSNumber.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:61 userInfo:@{NSLocalizedDescriptionKey: @"Could not check messaging availability. Please try again."}]);
      return;
    }
    if (completion) completion(value, nil);
  }];
}

- (void)fetchChatConversationForMembers:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion {
  NSArray<NSString *> *dids = NFBClientUniqueNonEmptyStrings(members);
  NSUInteger generation = [NFBAtprotoSession sharedSession].accountGeneration;
  // Check again on entry: the profile or recipient-picker state may be stale.
  [self fetchChatConversationAvailabilityForMembers:dids completion:^(NSDictionary *availability, NSError *error) {
    if (error || !NFBChatAvailabilityAllowsMessaging(availability)) {
      if (completion) completion(nil, error ?: NFBChatPermissionDeniedError());
      return;
    }
    NSDictionary *existing = [availability[@"convo"] isKindOfClass:NSDictionary.class] ? availability[@"convo"] : nil;
    if (NFBClientStringValue(existing[@"id"]).length > 0) {
      if (completion) completion(existing, nil);
      return;
    }
    if (generation != [NFBAtprotoSession sharedSession].accountGeneration) {
      if (completion) completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      return;
    }
    [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getConvoForMembers"
                                                    params:@{@"members": dids}
                                                completion:^(id value, NSHTTPURLResponse *response, NSError *createError) {
      (void)response;
      if (createError || ![value isKindOfClass:NSDictionary.class]) {
        if (completion) completion(nil, createError ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:61 userInfo:@{NSLocalizedDescriptionKey: @"Could not open that conversation."}]);
        return;
      }
      NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
      if (completion) completion(convo, nil);
    }];
  }];
}

- (void)createChatGroupWithMembers:(NSArray<NSString *> *)members name:(NSString *)name completion:(NFBAtprotoDictionaryCompletion)completion {
  NSArray<NSString *> *dids = NFBClientUniqueNonEmptyStrings(members);
  NSString *trimmedName = [[NFBClientStringValue(name) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
  if (dids.count == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:73 userInfo:@{NSLocalizedDescriptionKey: @"Choose people for this group."}]);
    return;
  }
  if (dids.count > 49) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:80 userInfo:@{NSLocalizedDescriptionKey: @"Group chats can include up to 49 invited people."}]);
    return;
  }
  if (trimmedName.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:74 userInfo:@{NSLocalizedDescriptionKey: @"Name this group first."}]);
    return;
  }
  trimmedName = NFBClientStringByLimitingComposedCharacters(trimmedName, 50, 500);

  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.group.createGroup"
                                                     body:@{@"members": dids, @"name": trimmedName}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:75 userInfo:@{NSLocalizedDescriptionKey: @"Could not create that group."}]);
      return;
    }
    NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
    if (completion) completion(convo, nil);
  }];
}

- (void)addChatMembersToConversationID:(NSString *)conversationID members:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion {
  NSArray<NSString *> *dids = NFBClientUniqueNonEmptyStrings(members);
  if (conversationID.length == 0 || dids.count == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:76 userInfo:@{NSLocalizedDescriptionKey: @"Choose people to add."}]);
    return;
  }

  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.group.addMembers"
                                                     body:@{@"convoId": conversationID, @"members": dids}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:77 userInfo:@{NSLocalizedDescriptionKey: @"Could not add those people."}]);
      return;
    }
    NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
    if (completion) completion(convo, nil);
  }];
}

- (void)removeChatMembersFromConversationID:(NSString *)conversationID members:(NSArray<NSString *> *)members completion:(NFBAtprotoDictionaryCompletion)completion {
  NSArray<NSString *> *dids = NFBClientUniqueNonEmptyStrings(members);
  if (conversationID.length == 0 || dids.count == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:81 userInfo:@{NSLocalizedDescriptionKey: @"Choose people to remove."}]);
    return;
  }

  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.group.removeMembers"
                                                     body:@{@"convoId": conversationID, @"members": dids}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:82 userInfo:@{NSLocalizedDescriptionKey: @"Could not remove those people."}]);
      return;
    }
    NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
    if (completion) completion(convo, nil);
  }];
}

- (void)editChatGroupWithConversationID:(NSString *)conversationID name:(NSString *)name completion:(NFBAtprotoDictionaryCompletion)completion {
  NSString *trimmedName = [[NFBClientStringValue(name) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
  if (conversationID.length == 0 || trimmedName.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:78 userInfo:@{NSLocalizedDescriptionKey: @"Group name was not available."}]);
    return;
  }
  trimmedName = NFBClientStringByLimitingComposedCharacters(trimmedName, 128, 1280);

  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.group.editGroup"
                                                     body:@{@"convoId": conversationID, @"name": trimmedName}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:79 userInfo:@{NSLocalizedDescriptionKey: @"Could not rename that group."}]);
      return;
    }
    NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
    if (completion) completion(convo, nil);
  }];
}

- (void)fetchChatMembersForConversationID:(NSString *)conversationID cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"convoId": conversationID, @"limit": @"100"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getConvoMembers"
                                                  params:params
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *members = [value isKindOfClass:NSDictionary.class] && [value[@"members"] isKindOfClass:NSArray.class] ? value[@"members"] : @[];
    NSMutableArray<NSDictionary *> *profiles = [NSMutableArray arrayWithCapacity:members.count];
    for (NSDictionary *member in members) {
      if ([member isKindOfClass:NSDictionary.class]) [profiles addObject:member];
    }
    NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    if (completion) completion(profiles, nextCursor, nil);
  }];
}

- (void)fetchChatMessagesForConversationID:(NSString *)conversationID cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }

  NSMutableDictionary *params = [@{@"convoId": conversationID, @"limit": @"50"} mutableCopy];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getMessages"
                                                  params:params
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(nil, nil, error);
      return;
    }
    NSArray *messages = [value isKindOfClass:NSDictionary.class] && [value[@"messages"] isKindOfClass:NSArray.class] ? value[@"messages"] : @[];
    NSArray *relatedProfiles = [value isKindOfClass:NSDictionary.class] && [value[@"relatedProfiles"] isKindOfClass:NSArray.class] ? value[@"relatedProfiles"] : @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:messages.count];
    for (NSDictionary *message in messages) {
      if (![message isKindOfClass:NSDictionary.class]) continue;
      NSDictionary *messageView = [message[@"message"] isKindOfClass:NSDictionary.class] ? message[@"message"] : message;
      if (![messageView isKindOfClass:NSDictionary.class]) continue;
      NSMutableDictionary *item = [messageView mutableCopy];
      if (![item[@"reactions"] isKindOfClass:NSArray.class] && [message[@"reactions"] isKindOfClass:NSArray.class]) item[@"reactions"] = message[@"reactions"];
      if (![item[@"readBy"] isKindOfClass:NSArray.class] && [message[@"readBy"] isKindOfClass:NSArray.class]) item[@"readBy"] = message[@"readBy"];
      if (![item[@"seenBy"] isKindOfClass:NSArray.class] && [message[@"seenBy"] isKindOfClass:NSArray.class]) item[@"seenBy"] = message[@"seenBy"];
      if (relatedProfiles.count > 0) item[@"__relatedProfiles"] = relatedProfiles;
      [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
      NSString *leftDate = [left[@"sentAt"] isKindOfClass:NSString.class] ? left[@"sentAt"] : @"";
      NSString *rightDate = [right[@"sentAt"] isKindOfClass:NSString.class] ? right[@"sentAt"] : @"";
      return [leftDate compare:rightDate];
    }];
    NSString *nextCursor = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    NSLog(@"NotTwitter chat getMessages convo=%@ count=%lu cursor=%@ related=%lu", conversationID ?: @"", (unsigned long)items.count, nextCursor ?: @"none", (unsigned long)relatedProfiles.count);
    if (completion) completion(items, nextCursor, nil);
  }];
}

- (void)fetchChatLogMessagesForConversationID:(NSString *)conversationID completion:(NFBAtprotoArrayCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(@[], nil, nil);
    return;
  }
  [self fetchChatLogMessagesForConversationID:conversationID
                                       cursor:nil
                               remainingPages:8
                                 messagesByID:[NSMutableDictionary dictionary]
                                   nextCursor:nil
                                   completion:completion];
}

- (void)fetchChatLogMessagesForConversationID:(NSString *)conversationID
                                       cursor:(NSString *)cursor
                               remainingPages:(NSUInteger)remainingPages
                                 messagesByID:(NSMutableDictionary<NSString *, NSDictionary *> *)messagesByID
                                   nextCursor:(NSString *)nextCursor
                                   completion:(NFBAtprotoArrayCompletion)completion {
  if (remainingPages == 0) {
    NSArray *items = messagesByID.allValues ?: @[];
    NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
      NSString *leftDate = [left[@"sentAt"] isKindOfClass:NSString.class] ? left[@"sentAt"] : @"";
      NSString *rightDate = [right[@"sentAt"] isKindOfClass:NSString.class] ? right[@"sentAt"] : @"";
      return [leftDate compare:rightDate];
    }];
    if (completion) completion(sorted, nextCursor, nil);
    return;
  }

  NSMutableDictionary *params = [NSMutableDictionary dictionary];
  if (cursor.length > 0) params[@"cursor"] = cursor;

  [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getLog"
                                                  params:params
                                              completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(messagesByID.allValues ?: @[], nextCursor, error);
      return;
    }
    NSArray *logs = [value isKindOfClass:NSDictionary.class] && [value[@"logs"] isKindOfClass:NSArray.class] ? value[@"logs"] : @[];
    for (NSDictionary *log in logs) {
      if (![log isKindOfClass:NSDictionary.class]) continue;
      if (![NFBClientStringValue(log[@"convoId"]) isEqualToString:conversationID]) continue;
      NSDictionary *message = [log[@"message"] isKindOfClass:NSDictionary.class] ? log[@"message"] : nil;
      if (!message) continue;
      NSMutableDictionary *item = [message mutableCopy];
      NSArray *relatedProfiles = [log[@"relatedProfiles"] isKindOfClass:NSArray.class] ? log[@"relatedProfiles"] : @[];
      if (relatedProfiles.count > 0) item[@"__relatedProfiles"] = relatedProfiles;
      NSString *messageID = NFBClientStringValue(item[@"id"]);
      if (messageID.length > 0) messagesByID[messageID] = item;
    }

    NSString *cursorValue = [value isKindOfClass:NSDictionary.class] && [value[@"cursor"] isKindOfClass:NSString.class] ? value[@"cursor"] : nil;
    BOOL enoughForThread = messagesByID.count >= 50;
    if (cursorValue.length == 0 || enoughForThread) {
      [self fetchChatLogMessagesForConversationID:conversationID cursor:nil remainingPages:0 messagesByID:messagesByID nextCursor:cursorValue ?: nextCursor completion:completion];
      return;
    }
    [self fetchChatLogMessagesForConversationID:conversationID
                                         cursor:cursorValue
                                 remainingPages:remainingPages - 1
                                   messagesByID:messagesByID
                                     nextCursor:cursorValue
                                     completion:completion];
  }];
}

- (void)prepareFacetsForText:(NSString *)text completion:(void (^)(NSArray *, NSError *))completion {
  NFBRichTextResolve(text, ^(NSString *handle, void (^resolved)(NSString *, NSError *)) {
    [[NFBAtprotoSession sharedSession] xrpcGET:@"com.atproto.identity.resolveHandle"
                                     service:NFBAtprotoPublicAppViewURL
                                      params:@{@"handle":handle}
                               authenticated:NO
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)response;
      NSString *did = [value isKindOfClass:NSDictionary.class] ? NFBClientStringValue(value[@"did"]) : @"";
      resolved(did, error);
    }];
  }, completion);
}

- (void)sendChatMessageToConversationID:(NSString *)conversationID text:(NSString *)text completion:(NFBAtprotoDictionaryCompletion)completion {
  NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (conversationID.length == 0 || trimmed.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:62 userInfo:@{NSLocalizedDescriptionKey: @"Type a message first."}]);
    return;
  }

  NSUInteger generation = [NFBAtprotoSession sharedSession].accountGeneration;
  [self prepareFacetsForText:trimmed completion:^(NSArray *facets, NSError *facetError) {
    if (facetError || generation != [NFBAtprotoSession sharedSession].accountGeneration) {
      if (completion) completion(nil, facetError ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      return;
    }
    NSMutableDictionary *message = [@{@"text": trimmed} mutableCopy];
    if (facets.count > 0) message[@"facets"] = facets;
    NSDictionary *body = @{
      @"convoId": conversationID,
      @"message": message
    };
    [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.convo.sendMessage"
                                                       body:body
                                                 completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)response;
      if (error || ![value isKindOfClass:NSDictionary.class]) {
        if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:63 userInfo:@{NSLocalizedDescriptionKey: @"Could not send that message."}]);
        return;
      }
      if (completion) completion((NSDictionary *)value, nil);
    }];
  }];
}

- (void)addChatReactionToConversationID:(NSString *)conversationID messageID:(NSString *)messageID value:(NSString *)value completion:(NFBAtprotoDictionaryCompletion)completion {
  [self updateChatReactionWithMethod:@"chat.bsky.convo.addReaction" conversationID:conversationID messageID:messageID value:value completion:completion];
}

- (void)removeChatReactionFromConversationID:(NSString *)conversationID messageID:(NSString *)messageID value:(NSString *)value completion:(NFBAtprotoDictionaryCompletion)completion {
  [self updateChatReactionWithMethod:@"chat.bsky.convo.removeReaction" conversationID:conversationID messageID:messageID value:value completion:completion];
}

- (void)deleteChatMessageForSelfInConversationID:(NSString *)conversationID messageID:(NSString *)messageID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0 || messageID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:64 userInfo:@{NSLocalizedDescriptionKey: @"Message was not available."}]);
    return;
  }

  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.convo.deleteMessageForSelf"
                                                     body:@{@"convoId": conversationID, @"messageId": messageID}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)markChatConversationRead:(NSString *)conversationID messageID:(NSString *)messageID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(@{}, nil);
    return;
  }
  NSMutableDictionary *body = [@{@"convoId": conversationID} mutableCopy];
  if (messageID.length > 0) body[@"messageId"] = messageID;
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.convo.updateRead"
                                                     body:body
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)acceptChatConversation:(NSString *)conversationID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:69 userInfo:@{NSLocalizedDescriptionKey: @"Conversation was not available."}]);
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.convo.acceptConvo"
                                                     body:@{@"convoId": conversationID}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)value;
    (void)response;
    if (error) {
      if (completion) completion(nil, error);
      return;
    }
    [[NFBAtprotoSession sharedSession] xrpcGETViaChatProxy:@"chat.bsky.convo.getConvo"
                                                    params:@{@"convoId": conversationID}
                                                completion:^(id convoValue, NSHTTPURLResponse *convoResponse, NSError *convoError) {
      (void)convoResponse;
      if (convoError || ![convoValue isKindOfClass:NSDictionary.class]) {
        if (completion) completion(nil, convoError ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:70 userInfo:@{NSLocalizedDescriptionKey: @"Could not accept that request."}]);
        return;
      }
      NSDictionary *convo = [convoValue[@"convo"] isKindOfClass:NSDictionary.class] ? convoValue[@"convo"] : (NSDictionary *)convoValue;
      if (completion) completion(convo, nil);
    }];
  }];
}

- (void)setChatConversationMuted:(NSString *)conversationID muted:(BOOL)muted completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:65 userInfo:@{NSLocalizedDescriptionKey: @"Conversation was not available."}]);
    return;
  }
  NSString *method = muted ? @"chat.bsky.convo.muteConvo" : @"chat.bsky.convo.unmuteConvo";
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:method
                                                     body:@{@"convoId": conversationID}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:66 userInfo:@{NSLocalizedDescriptionKey: @"Could not update that conversation."}]);
      return;
    }
    NSDictionary *convo = [value[@"convo"] isKindOfClass:NSDictionary.class] ? value[@"convo"] : (NSDictionary *)value;
    if (completion) completion(convo, nil);
  }];
}

- (void)leaveChatConversation:(NSString *)conversationID completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0) {
    if (completion) completion(@{}, nil);
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:@"chat.bsky.convo.leaveConvo"
                                                     body:@{@"convoId": conversationID}
                                               completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)updateChatReactionWithMethod:(NSString *)method conversationID:(NSString *)conversationID messageID:(NSString *)messageID value:(NSString *)value completion:(NFBAtprotoDictionaryCompletion)completion {
  if (conversationID.length == 0 || messageID.length == 0 || value.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:67 userInfo:@{NSLocalizedDescriptionKey: @"Reaction was not available."}]);
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaChatProxy:method
                                                     body:@{@"convoId": conversationID, @"messageId": messageID, @"value": value}
                                               completion:^(id responseValue, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![responseValue isKindOfClass:NSDictionary.class]) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:68 userInfo:@{NSLocalizedDescriptionKey: @"Could not update that reaction."}]);
      return;
    }
    NSDictionary *message = [responseValue[@"message"] isKindOfClass:NSDictionary.class] ? responseValue[@"message"] : (NSDictionary *)responseValue;
    if (completion) completion(message, nil);
  }];
}

- (void)createPostWithText:(NSString *)text completion:(NFBAtprotoDictionaryCompletion)completion {
  [self createPostWithText:text replyToPost:nil completion:completion];
}

- (void)createPostWithText:(NSString *)text replyToPost:(NSDictionary *)parentPost completion:(NFBAtprotoDictionaryCompletion)completion {
  [self createPostWithText:text replyToPost:parentPost quotePost:nil completion:completion];
}

- (void)createPostWithText:(NSString *)text replyToPost:(NSDictionary *)parentPost quotePost:(NSDictionary *)quotePost completion:(NFBAtprotoDictionaryCompletion)completion {
  [self createPostWithText:text replyToPost:parentPost quotePost:quotePost mediaItems:nil replyGate:nil completion:completion];
}

- (void)createPostWithText:(NSString *)text
               replyToPost:(NSDictionary *)parentPost
                 quotePost:(NSDictionary *)quotePost
                mediaItems:(NSArray<NSDictionary *> *)mediaItems
                 replyGate:(NSString *)replyGate
                completion:(NFBAtprotoDictionaryCompletion)completion {
  if (!self.postingAccountDID) {
    [[self.class postingClientForAccountDID:[NFBAtprotoSession sharedSession].did ?: @""] createPostWithText:text replyToPost:parentPost quotePost:quotePost mediaItems:mediaItems replyGate:replyGate completion:completion];
    return;
  }
  NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  BOOL hasMedia = mediaItems.count > 0;
  BOOL hasQuote = [self.class postRefForPost:quotePost] != nil;
  if (trimmed.length == 0 && !hasMedia && !hasQuote) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Write something first."}]);
    return;
  }

  NSArray<NSDictionary *> *items = [mediaItems isKindOfClass:NSArray.class] ? mediaItems : @[];
  NSUInteger imageCount = 0;
  NSUInteger videoCount = 0;
  for (NSDictionary *item in items) {
    NSString *type = NFBClientStringValue(item[@"type"]);
    if ([type isEqualToString:@"video"] || ([type isEqualToString:@"gif"] && [NFBClientStringValue(item[@"mimeType"]) isEqualToString:@"video/mp4"])) videoCount++;
    else imageCount++;
  }
  if (imageCount > NFBMaxPhotosPerPost) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"Bluesky allows up to 10 photos in one post." code:301]);
    return;
  }
  if (!NFBMediaCountsAreValid(imageCount, videoCount)) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"Bluesky allows either one video/GIF or up to 10 photos, not mixed media." code:302]);
    return;
  }

  if (NFBMediaUsesGallery(imageCount)) {
    for (NSDictionary *item in items) {
      if (![item[@"width"] isKindOfClass:NSNumber.class] || [item[@"width"] integerValue] <= 0 ||
          ![item[@"height"] isKindOfClass:NSNumber.class] || [item[@"height"] integerValue] <= 0) {
        if (completion) completion(nil, [self.class composeErrorWithMessage:@"Reattach this photo so its dimensions can be read." code:307]);
        return;
      }
    }
  }

  [self prepareFacetsForText:trimmed completion:^(NSArray *facets, NSError *facetError) {
    if (facetError) {
      if (completion) completion(nil, facetError);
      return;
    }
    [self uploadMediaItems:items completion:^(NSArray<NSDictionary *> *uploadedItems, NSError *uploadError) {
      if (uploadError) {
        if (completion) completion(nil, uploadError);
        return;
      }

      NSMutableDictionary *record = [@{
        @"$type": @"app.bsky.feed.post",
        @"text": trimmed ?: @"",
        @"createdAt": [self.class isoDateNow]
      } mutableCopy];
      if (facets.count > 0) record[@"facets"] = facets;
      NSMutableOrderedSet *warnings = [NSMutableOrderedSet orderedSet];
      for (NSDictionary *item in uploadedItems) {
        for (NSString *warning in item[@"contentWarnings"] ?: @[]) {
          if ([@[@"nudity", @"gore", @"!warn"] containsObject:warning]) [warnings addObject:warning];
        }
      }
      if (warnings.count) {
        NSMutableArray *labels = [NSMutableArray array];
        for (NSString *warning in warnings) [labels addObject:@{@"val":warning}];
        record[@"labels"] = @{@"$type":@"com.atproto.label.defs#selfLabels", @"values":labels};
      }
      NSDictionary *replyRef = [self.class replyRefForParentPost:parentPost];
      if (replyRef) record[@"reply"] = replyRef;
      NSDictionary *quoteRef = [self.class postRefForPost:quotePost];
      NSDictionary *embed = [self.class embedForUploadedMediaItems:uploadedItems quoteRef:quoteRef];
      if (embed) record[@"embed"] = embed;

      NSDictionary *body = @{
        @"repo": self.postingAccountDID ?: @"",
        @"collection": @"app.bsky.feed.post",
        @"record": record
      };

      [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                          forAccountDID:self.postingAccountDID
                                             body:body
                                       completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        (void)response;
        NSDictionary *createdPost = [value isKindOfClass:[NSDictionary class]] ? value : nil;
        if (error || !createdPost) {
          if (completion) completion(createdPost, error);
          return;
        }

        // Retain reply.root when the next composed Tweet replies to this result.
        NSMutableDictionary *createdWithRecord = [createdPost mutableCopy];
        createdWithRecord[@"record"] = record;
        createdPost = createdWithRecord;
        [[NFBAtprotoClient sharedClient] invalidateThreadPayloadCache];
        NSString *gate = replyGate.length > 0 ? replyGate : NFBComposeReplyGateEveryone;
        if (parentPost || [gate isEqualToString:NFBComposeReplyGateEveryone]) {
          if (completion) completion(createdPost, nil);
          return;
        }
        [self createThreadgateForPostURI:NFBClientStringValue(createdPost[@"uri"]) replyGate:gate completion:^(NSDictionary *gateValue, NSError *gateError) {
          (void)gateValue;
          if (completion) completion(createdPost, gateError);
        }];
      }];
    }];
  }];
}

- (void)uploadMediaItems:(NSArray<NSDictionary *> *)mediaItems completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
  [self uploadMediaItems:mediaItems ?: @[] index:0 uploadedItems:[NSMutableArray array] completion:completion];
}

- (void)uploadMediaItems:(NSArray<NSDictionary *> *)mediaItems index:(NSUInteger)index uploadedItems:(NSMutableArray<NSDictionary *> *)uploadedItems completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
  if (index >= mediaItems.count) {
    if (completion) completion([uploadedItems copy], nil);
    return;
  }
  NSDictionary *item = [mediaItems[index] isKindOfClass:NSDictionary.class] ? mediaItems[index] : @{};
  NSData *data = [item[@"data"] isKindOfClass:NSData.class] ? item[@"data"] : nil;
  NSString *mimeType = NFBClientStringValue(item[@"mimeType"]);
  NSString *type = NFBClientStringValue(item[@"type"]);
  if (data.length == 0 || mimeType.length == 0) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"That media file could not be read." code:303]);
    return;
  }
  BOOL isVideo = [type isEqualToString:@"video"] || ([type isEqualToString:@"gif"] && [mimeType isEqualToString:@"video/mp4"]);
  if (isVideo && data.length > NFBMaxVideoUploadBytes) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"Bluesky videos must be 300 MB or smaller." code:304]);
    return;
  }
  if (!isVideo && data.length > NFBMaxImageUploadBytes) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"Bluesky images and GIFs must be 2 MB or smaller." code:305]);
    return;
  }

  if (isVideo && (![mimeType isEqualToString:@"video/mp4"] || !NFBVideoUploadIsValid(data.length, [item[@"duration"] doubleValue]))) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"Choose an MP4 video up to 10 minutes and 300 MB. Reattach it if its duration could not be read." code:308]);
    return;
  }

  [self uploadBlobData:data mimeType:mimeType completion:^(NSDictionary *blob, NSError *error) {
    if (error || !blob) {
      if (completion) completion(nil, error ?: [self.class composeErrorWithMessage:@"Media upload failed." code:306]);
      return;
    }
    NSMutableDictionary *uploaded = [item mutableCopy];
    uploaded[@"blob"] = blob;
    [uploadedItems addObject:uploaded];
    [self uploadMediaItems:mediaItems index:index + 1 uploadedItems:uploadedItems completion:completion];
  }];
}

- (void)uploadBlobData:(NSData *)data mimeType:(NSString *)mimeType completion:(NFBAtprotoDictionaryCompletion)completion {
  [[NFBAtprotoSession sharedSession] xrpcPOSTData:@"com.atproto.repo.uploadBlob"
                                          forAccountDID:self.postingAccountDID
                                             data:data ?: [NSData data]
                                      contentType:mimeType.length > 0 ? mimeType : @"application/octet-stream"
                                       completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    NSDictionary *blob = [value isKindOfClass:NSDictionary.class] && [value[@"blob"] isKindOfClass:NSDictionary.class] ? value[@"blob"] : nil;
    if (completion) completion(blob, error);
  }];
}

- (void)createThreadgateForPostURI:(NSString *)postURI replyGate:(NSString *)replyGate completion:(NFBAtprotoDictionaryCompletion)completion {
  NSString *rkey = [self.class rkeyFromAtURI:postURI];
  if (postURI.length == 0 || rkey.length == 0) {
    if (completion) completion(nil, [self.class composeErrorWithMessage:@"Could not set who can reply." code:307]);
    return;
  }
  NSArray *allow = [self.class threadgateAllowRulesForReplyGate:replyGate];
  NSDictionary *record = @{
    @"$type": @"app.bsky.feed.threadgate",
    @"post": postURI,
    @"allow": allow ?: @[],
    @"createdAt": [self.class isoDateNow]
  };
  NSDictionary *body = @{
    @"repo": self.postingAccountDID ?: @"",
    @"collection": @"app.bsky.feed.threadgate",
    @"rkey": rkey,
    @"record": record
  };
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                      forAccountDID:self.postingAccountDID
                                           body:body
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : nil, error);
  }];
}

- (void)fetchPostThreadForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion {
  if (uri.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:30 userInfo:@{NSLocalizedDescriptionKey: @"Post was missing a URI."}]);
    return;
  }

  NSString *cacheKey = [self resourceCacheKeyWithName:@"thread" qualifier:uri];
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  NSString *requestKey = [cacheKey stringByAppendingFormat:@"|request:%lu", (unsigned long)accountGeneration];
  NSDate *now = [NSDate date];
  @synchronized (self) {
    NSDictionary *cached = self.threadPayloadCache[cacheKey];
    NSDate *cachedDate = self.threadPayloadCacheDates[cacheKey];
    if (cached && cachedDate && [now timeIntervalSinceDate:cachedDate] <= NFBAtprotoThreadCacheTTL) {
      if (completion) completion(cached, nil);
      return;
    }

    NSMutableArray *pending = self.threadPendingCompletions[requestKey];
    if (pending) {
      if (completion) [pending addObject:[completion copy]];
      return;
    }
    pending = [NSMutableArray array];
    if (completion) [pending addObject:[completion copy]];
    self.threadPendingCompletions[requestKey] = pending;
  }

  void (^finishThreadRequest)(NSDictionary *, NSError *) = ^(NSDictionary *payload, NSError *requestError) {
    if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
      payload = nil;
      requestError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    }
    NSArray *requests = nil;
    @synchronized (self) {
      if (payload && !requestError) {
        self.threadPayloadCache[cacheKey] = payload;
        self.threadPayloadCacheDates[cacheKey] = [NSDate date];
      }
      requests = [self.threadPendingCompletions[requestKey] copy];
      [self.threadPendingCompletions removeObjectForKey:requestKey];
    }
    [self completePendingDictionaryRequests:requests value:payload error:requestError];
  };

  // One bounded request produces the first screen, including explicit expansion
  // metadata. The stable endpoint remains the fallback if this API changes.
  [self fetchAppViewGET:@"app.bsky.unspecced.getPostThreadV2"
                 params:@{@"anchor": uri, @"above": @YES, @"below": @6, @"branchingFactor": @10, @"sort": @"oldest"}
           requiresAuth:NO completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
      finishThreadRequest(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      return;
    }
    NSDictionary *payload = !error && [value isKindOfClass:NSDictionary.class] ? [self.class threadPayloadFromV2:value anchorURI:uri additional:NO] : nil;
    if (payload[@"tweet"]) { finishThreadRequest(payload, nil); return; }
    [self fetchAppViewGET:@"app.bsky.feed.getPostThread" params:@{@"uri": uri, @"depth": @6, @"parentHeight": @80} requiresAuth:NO
               completion:^(id fallback, NSHTTPURLResponse *fallbackResponse, NSError *fallbackError) {
      (void)fallbackResponse;
      NSDictionary *thread = [fallback isKindOfClass:NSDictionary.class] && [fallback[@"thread"] isKindOfClass:NSDictionary.class] ? fallback[@"thread"] : nil;
      if (fallbackError || !thread) {
        finishThreadRequest(nil, fallbackError ?: [NSError errorWithDomain:@"NFBAtprotoClient" code:31 userInfo:@{NSLocalizedDescriptionKey: @"Could not load this post."}]);
        return;
      }
      NSMutableDictionary *hiddenReasons = [NSMutableDictionary dictionary];
      [self.class collectHiddenAuthorReasonsFromThreadNode:thread intoDictionary:hiddenReasons];
      NSMutableArray *nodes = [NSMutableArray array];
      [self.class appendThreadNodes:thread parentURI:nil hiddenAuthorReasons:hiddenReasons intoArray:nodes];
      NSDictionary *tweet = [self.class postOrTombstoneFromThreadNode:thread hiddenAuthorReasons:hiddenReasons];
      finishThreadRequest(@{@"tweet": tweet ?: @{}, @"nodes": nodes}, nil);
    }];
  }];
}

- (void)invalidatePostThreadForURI:(NSString *)uri {
  NSString *key = [self resourceCacheKeyWithName:@"thread" qualifier:uri];
  @synchronized (self) { [self.threadPayloadCache removeObjectForKey:key]; [self.threadPayloadCacheDates removeObjectForKey:key]; }
}

- (void)fetchAdditionalPostRepliesForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion {
  [self fetchAppViewGET:@"app.bsky.unspecced.getPostThreadOtherV2" params:@{@"anchor": uri} requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    NSDictionary *payload = !error && [value isKindOfClass:NSDictionary.class] ? [self.class threadPayloadFromV2:value anchorURI:uri additional:YES] : nil;
    if (completion) completion(payload, error ?: (payload ? nil : [NSError errorWithDomain:@"NFBAtprotoClient" code:31 userInfo:@{NSLocalizedDescriptionKey: @"Could not load additional replies."}]));
  }];
}

+ (NSDictionary *)threadPayloadFromV2:(NSDictionary *)response anchorURI:(NSString *)anchorURI additional:(BOOL)additional {
  if (![response[@"thread"] isKindOfClass:NSArray.class]) return nil;
  NSMutableArray *nodes = [NSMutableArray array];
  NSMutableDictionary<NSNumber *, NSString *> *ancestry = [NSMutableDictionary dictionary];
  NSDictionary *tweet = nil;
  for (NSDictionary *item in response[@"thread"]) {
    if (![item isKindOfClass:NSDictionary.class] || ![item[@"value"] isKindOfClass:NSDictionary.class]) continue;
    NSDictionary *value = item[@"value"];
    NSString *uri = NFBClientStringValue(item[@"uri"]);
    if (!uri.length) continue;
    NSInteger depth = [item[@"depth"] integerValue];
    // A new sibling ends the previous branch. Do not attach a tombstone with
    // no record to an old deeper branch if a response skips a depth.
    for (NSNumber *level in ancestry.allKeys) if (level.integerValue >= depth) [ancestry removeObjectForKey:level];
    NSDictionary *post = [value[@"post"] isKindOfClass:NSDictionary.class] ? value[@"post"] : nil;
    NSString *parentURI = post ? [self replyParentURIForPost:post] : @"";
    if (!parentURI.length) parentURI = ancestry[@(depth - 1)] ?: (depth == 1 ? anchorURI : @"");
    BOOL unavailable = post == nil;
    if (!post) {
      BOOL blocked = [NFBClientStringValue(value[@"$type"]).lowercaseString containsString:@"blocked"];
      NSMutableDictionary *source = [@{@"uri": uri, @"$type": blocked ? @"app.bsky.feed.defs#blockedPost" : @"app.bsky.feed.defs#notFoundPost"} mutableCopy];
      if ([value[@"author"] isKindOfClass:NSDictionary.class]) source[@"author"] = value[@"author"];
      post = [self tombstonePostFromSource:source fallbackType:source[@"$type"]];
    } else {
      NSString *hiddenReason = [self hiddenReasonForPostAuthor:post[@"author"] ?: @{}];
      if (hiddenReason.length) { post = [self tombstonePostFromPost:post reason:hiddenReason]; unavailable = YES; }
      else if ([value[@"hiddenByThreadgate"] boolValue] && !additional) {
        post = [self tombstonePostFromSource:@{@"uri": uri, @"$type": @"app.bsky.embed.record#viewDetached"} fallbackType:@""];
        unavailable = YES;
      }
    }
    if (!post) continue;
    NSMutableDictionary *node = [@{@"post": post, @"parentURI": parentURI ?: @"", @"replyCount": post[@"replyCount"] ?: @0,
      @"remainingReplies": value[@"moreReplies"] ?: @0, @"childrenLoaded": @(depth >= 0), @"unavailable": @(unavailable)} mutableCopy];
    if ([uri isEqual:anchorURI]) {
      tweet = post;
      node[@"hasOtherReplies"] = @(!additional && [response[@"hasOtherReplies"] boolValue]);
    }
    [nodes addObject:node];
    ancestry[@(depth)] = uri;
  }
  NSMutableDictionary *payload = [@{@"nodes": nodes} mutableCopy];
  if (tweet) payload[@"tweet"] = tweet;
  return payload;
}

+ (void)appendThreadNodes:(NSDictionary *)thread parentURI:(NSString *)parentURI hiddenAuthorReasons:(NSDictionary *)hiddenReasons intoArray:(NSMutableArray *)nodes {
  if (![thread isKindOfClass:NSDictionary.class]) return;
  NSDictionary *post = [self postOrTombstoneFromThreadNode:thread hiddenAuthorReasons:hiddenReasons];
  NSString *uri = NFBClientStringValue(post[@"uri"]);
  if (!uri.length) return;
  NSDictionary *parent = [thread[@"parent"] isKindOfClass:NSDictionary.class] ? thread[@"parent"] : nil;
  NSString *recordParent = [self replyParentURIForPost:post];
  if (!parentURI.length) parentURI = recordParent;
  if (!parentURI.length && parent) parentURI = NFBClientStringValue([self postOrTombstoneFromThreadNode:parent][@"uri"]);
  NSArray *replies = [thread[@"replies"] isKindOfClass:NSArray.class] ? thread[@"replies"] : @[];
  BOOL unavailable = ![thread[@"post"] isKindOfClass:NSDictionary.class] || [self hiddenReasonForPostAuthor:post[@"author"] ?: @{}].length > 0;
  [nodes addObject:@{@"post": post, @"parentURI": parentURI ?: @"", @"replyCount": @([post[@"replyCount"] unsignedIntegerValue]),
                    @"childrenLoaded": @([thread[@"replies"] isKindOfClass:NSArray.class]), @"remainingReplies": @(![thread[@"replies"] isKindOfClass:NSArray.class] ? [post[@"replyCount"] unsignedIntegerValue] : 0), @"unavailable": @(unavailable)}];
  if (parent) [self appendThreadNodes:parent parentURI:nil hiddenAuthorReasons:hiddenReasons intoArray:nodes];
  for (NSDictionary *reply in replies) [self appendThreadNodes:reply parentURI:uri hiddenAuthorReasons:hiddenReasons intoArray:nodes];
}

- (void)toggleLikeForPost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion {
  [self toggleReaction:@"app.bsky.feed.like" viewerKey:@"like" post:post completion:completion];
}

- (void)toggleRepostForPost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion {
  [self toggleReaction:@"app.bsky.feed.repost" viewerKey:@"repost" post:post completion:completion];
}

- (void)toggleBookmarkForPost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  NSDictionary *postRef = [self.class postRefForPost:post];
  if (!postRef) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:42 userInfo:@{NSLocalizedDescriptionKey: @"Post reference was not available."}]);
    return;
  }

  NSDictionary *body = bookmarked ? @{@"uri": postRef[@"uri"] ?: @""} : postRef;
  NSString *method = bookmarked ? @"app.bsky.bookmark.deleteBookmark" : @"app.bsky.bookmark.createBookmark";
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaAppViewProxy:method
                                                        body:body
                                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)toggleFollowForProfile:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  NSString *existingURI = [viewer[@"following"] isKindOfClass:NSString.class] ? viewer[@"following"] : @"";
  if (existingURI.length > 0) {
    [self deleteRecordAtURI:existingURI completion:completion];
    return;
  }

  NSString *subjectDID = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (subjectDID.length == 0 || sessionDID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:45 userInfo:@{NSLocalizedDescriptionKey: @"Profile reference was not available."}]);
    return;
  }
  if ([subjectDID isEqualToString:sessionDID]) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:46 userInfo:@{NSLocalizedDescriptionKey: @"You cannot follow yourself."}]);
    return;
  }

  NSDictionary *body = @{
    @"repo": sessionDID,
    @"collection": @"app.bsky.graph.follow",
    @"record": @{
      @"$type": @"app.bsky.graph.follow",
      @"subject": subjectDID,
      @"createdAt": [self.class isoDateNow]
    }
  };
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : nil, error);
  }];
}

- (void)followProfileIfNeeded:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  NSString *existingURI = [viewer[@"following"] isKindOfClass:NSString.class] ? viewer[@"following"] : @"";
  if (existingURI.length > 0) {
    if (completion) completion(profile ?: @{}, nil);
    return;
  }

  NSString *subjectDID = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (subjectDID.length == 0 || sessionDID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:45 userInfo:@{NSLocalizedDescriptionKey: @"Profile reference was not available."}]);
    return;
  }
  if ([subjectDID isEqualToString:sessionDID]) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:46 userInfo:@{NSLocalizedDescriptionKey: @"You cannot follow yourself."}]);
    return;
  }

  NSDictionary *body = @{
    @"repo": sessionDID,
    @"collection": @"app.bsky.graph.follow",
    @"record": @{
      @"$type": @"app.bsky.graph.follow",
      @"subject": subjectDID,
      @"createdAt": [self.class isoDateNow]
    }
  };
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : nil, error);
  }];
}

- (void)blockProfileIfNeeded:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  NSString *existingURI = [viewer[@"blocking"] isKindOfClass:NSString.class] ? viewer[@"blocking"] : @"";
  BOOL alreadyBlocked = existingURI.length > 0 || ([viewer[@"blocking"] respondsToSelector:@selector(boolValue)] && [viewer[@"blocking"] boolValue]);
  if (alreadyBlocked) {
    if (completion) completion(profile ?: @{}, nil);
    return;
  }

  NSString *subjectDID = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (subjectDID.length == 0 || sessionDID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:47 userInfo:@{NSLocalizedDescriptionKey: @"Profile reference was not available."}]);
    return;
  }
  if ([subjectDID isEqualToString:sessionDID]) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:48 userInfo:@{NSLocalizedDescriptionKey: @"You cannot block yourself."}]);
    return;
  }

  NSDictionary *body = @{
    @"repo": sessionDID,
    @"collection": @"app.bsky.graph.block",
    @"record": @{
      @"$type": @"app.bsky.graph.block",
      @"subject": subjectDID,
      @"createdAt": [self.class isoDateNow]
    }
  };
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : nil, error);
  }];
}

- (void)toggleBlockForProfile:(NSDictionary *)profile completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  NSString *existingURI = [viewer[@"blocking"] isKindOfClass:NSString.class] ? viewer[@"blocking"] : @"";
  if (existingURI.length > 0) {
    [self deleteRecordAtURI:existingURI completion:completion];
    return;
  }

  NSString *subjectDID = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (subjectDID.length == 0 || sessionDID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:47 userInfo:@{NSLocalizedDescriptionKey: @"Profile reference was not available."}]);
    return;
  }
  if ([subjectDID isEqualToString:sessionDID]) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:48 userInfo:@{NSLocalizedDescriptionKey: @"You cannot block yourself."}]);
    return;
  }

  NSDictionary *body = @{
    @"repo": sessionDID,
    @"collection": @"app.bsky.graph.block",
    @"record": @{
      @"$type": @"app.bsky.graph.block",
      @"subject": subjectDID,
      @"createdAt": [self.class isoDateNow]
    }
  };
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : nil, error);
  }];
}

- (void)deletePost:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion {
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *authorDID = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (uri.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:43 userInfo:@{NSLocalizedDescriptionKey: @"Post reference was not available."}]);
    return;
  }
  if (authorDID.length > 0 && sessionDID.length > 0 && ![authorDID isEqualToString:sessionDID]) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:44 userInfo:@{NSLocalizedDescriptionKey: @"You can only delete your own posts."}]);
    return;
  }
  [self deleteRecordAtURI:uri completion:^(NSDictionary *value, NSError *error) {
    if (!error) [self invalidateThreadPayloadCache];
    if (completion) completion(value, error);
  }];
}

- (void)fetchStandardSiteArticleForCard:(NSDictionary *)card completion:(NFBAtprotoDictionaryCompletion)completion {
  if (!NSThread.isMainThread) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self fetchStandardSiteArticleForCard:card completion:completion]; });
    return;
  }
  NSString *cacheKey = [self.class standardSiteArticleCacheKeyForCard:card];
  if (cacheKey.length == 0) {
    if (completion) completion(nil, nil);
    return;
  }

  if (!self.standardSiteArticleRequests) self.standardSiteArticleRequests = [NSMutableDictionary dictionary];
  if (self.standardSiteArticleRequests[cacheKey]) {
    if (completion) [self.standardSiteArticleRequests[cacheKey] addObject:[completion copy]];
    return;
  }
  self.standardSiteArticleRequests[cacheKey] = [NSMutableArray array];
  if (completion) [self.standardSiteArticleRequests[cacheKey] addObject:[completion copy]];
  NFBAtprotoDictionaryCompletion finish = ^(NSDictionary *article, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSArray *waiting = [self.standardSiteArticleRequests[cacheKey] copy];
      [self.standardSiteArticleRequests removeObjectForKey:cacheKey];
      for (NFBAtprotoDictionaryCompletion callback in waiting) callback(article, error);
    });
  };

  NSArray<NSString *> *uris = [self.class standardSiteAssociatedURIsForCard:card];
  if (uris.count == 0) {
    finish(nil, nil);
    return;
  }

  NSString *url = NFBClientStringValue(card[@"url"]);
  NSDictionary *params = @{
    @"url": url.length > 0 ? url : @"",
    @"uris": uris
  };
  [self fetchAppViewGET:@"app.bsky.embed.getEmbedExternalView"
                 params:params
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error || ![value isKindOfClass:NSDictionary.class]) {
      finish(nil, error);
      return;
    }

    NSDictionary *responseDictionary = (NSDictionary *)value;
    NSArray *associatedRecords = [responseDictionary[@"associatedRecords"] isKindOfClass:NSArray.class] ? responseDictionary[@"associatedRecords"] : @[];
    NSDictionary *documentRecord = [self.class standardSiteDocumentRecordFromAssociatedRecords:associatedRecords];
    NSString *textContent = [self.class standardSiteDocumentTextFromRecord:documentRecord];
    if (documentRecord.count == 0) {
      finish(nil, nil);
      return;
    }

    NSDictionary *view = [responseDictionary[@"view"] isKindOfClass:NSDictionary.class] ? responseDictionary[@"view"] : @{};
    NSDictionary *external = [view[@"external"] isKindOfClass:NSDictionary.class] ? view[@"external"] : @{};
    NSString *articleURL = [self.class recordString:documentRecord key:@"canonicalUrl"];
    if (articleURL.length == 0) articleURL = NFBClientStringValue(external[@"uri"]);
    if (articleURL.length == 0) articleURL = url;

    NSString *articleTitle = [self.class recordString:documentRecord key:@"title"];
    if (articleTitle.length == 0) articleTitle = NFBClientStringValue(card[@"title"]);
    if (articleTitle.length == 0) articleTitle = articleURL;

    NSString *articleDescription = [self.class recordString:documentRecord key:@"description"];
    if (articleDescription.length == 0) articleDescription = NFBClientStringValue(card[@"description"]);

    NSMutableDictionary *article = [@{
      @"url": articleURL.length > 0 ? articleURL : @"",
      @"title": articleTitle.length > 0 ? articleTitle : @"Article",
      @"description": articleDescription.length > 0 ? articleDescription : @"",
      @"textContent": textContent.length > 0 ? textContent : @"",
      @"tags": [self.class standardSiteTagsFromRecord:documentRecord]
    } mutableCopy];

    NSArray<NSString *> *documentURIs = [uris filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *uri, NSDictionary *bindings) {
      (void)bindings;
      return [uri rangeOfString:@"/site.standard.document/"].location != NSNotFound;
    }]];
    if (documentURIs.count > 0) article[@"documentURI"] = documentURIs.firstObject;
    id content = documentRecord[@"content"];
    if (content) article[@"content"] = content;

    NSString *publishedAt = [self.class recordString:documentRecord key:@"publishedAt"];
    if (publishedAt.length == 0) publishedAt = NFBClientStringValue(card[@"createdAt"]);
    if (publishedAt.length > 0) article[@"publishedAt"] = publishedAt;

    NSString *updatedAt = [self.class recordString:documentRecord key:@"updatedAt"];
    if (updatedAt.length == 0) updatedAt = NFBClientStringValue(card[@"updatedAt"]);
    if (updatedAt.length > 0) article[@"updatedAt"] = updatedAt;

    NSString *rawText = [self.class recordString:documentRecord key:@"textContent"];
    if (rawText.length) article[@"rawTextContent"] = rawText;
    NSArray *refs = [responseDictionary[@"associatedRefs"] isKindOfClass:NSArray.class] ? responseDictionary[@"associatedRefs"] : @[];
    for (NSDictionary *ref in refs) {
      if ([ref isKindOfClass:NSDictionary.class] && [ref[@"uri"] isEqual:article[@"documentURI"]] && [ref[@"cid"] isKindOfClass:NSString.class]) article[@"revision"] = ref[@"cid"];
    }
    if (!article[@"revision"]) article[@"revision"] = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:documentRecord options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding] ?: @"";
    finish([article copy], nil);
  }];
}

- (void)fetchAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)requiresAuth completion:(NFBAtprotoValueCompletion)completion {
  NSUInteger generation = [NFBAtprotoSession sharedSession].accountGeneration;
  [self fetchRawAppViewGET:method params:params requiresAuth:requiresAuth completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    if (error || !value) { if (completion) completion(value, response, error); return; }
    [NFBPostLinkResolver resolveValue:value fetch:^(NSString *lookup, NSDictionary *lookupParams, void (^finish)(NSDictionary *, NSError *)) {
      if (generation != [NFBAtprotoSession sharedSession].accountGeneration) {
        finish(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        return;
      }
      // Raw requests prevent recursive cards. Respect authenticated block state;
      // a failed preview leaves the original post/link available.
      [self fetchRawAppViewGET:lookup params:lookupParams requiresAuth:YES completion:^(id result, NSHTTPURLResponse *unused, NSError *lookupError) {
        finish([result isKindOfClass:NSDictionary.class] ? result : nil, lookupError);
      }];
    } completion:^(id enriched) {
      if (generation != [NFBAtprotoSession sharedSession].accountGeneration) {
        if (completion) completion(nil, response, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      } else if (completion) completion(enriched, response, nil);
    }];
  }];
}

- (void)fetchRawAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)requiresAuth completion:(NFBAtprotoValueCompletion)completion {
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  NFBAtprotoValueCompletion originalCompletion = completion;
  completion = ^(id value, NSHTTPURLResponse *response, NSError *error) {
    if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
      if (originalCompletion) originalCompletion(nil, response, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
      return;
    }
    if (originalCompletion) originalCompletion(value, response, error);
  };
  BOOL hasSession = [[NFBAtprotoSession sharedSession] hasSession];
  if (hasSession) {
    [[NFBAtprotoSession sharedSession] xrpcGETViaAppViewProxy:method
                                                       params:params
                                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
        if (completion) completion(nil, response, error);
        return;
      }
      if (!error || requiresAuth) {
        if (completion) completion(value, response, error);
        return;
      }

      [[NFBAtprotoSession sharedSession] xrpcGET:method
                                         service:NFBAtprotoPublicAppViewURL
                                          params:params
                                   authenticated:NO
                                      completion:completion];
    }];
    return;
  }

  [[NFBAtprotoSession sharedSession] xrpcGET:method
                                     service:NFBAtprotoAppViewURL
                                      params:params
                               authenticated:NO
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) {
      if (completion) completion(nil, response, error);
      return;
    }
    if (!error) {
      if (completion) completion(value, response, error);
      return;
    }

    [[NFBAtprotoSession sharedSession] xrpcGET:method
                                       service:NFBAtprotoPublicAppViewURL
                                        params:params
                                 authenticated:NO
                                    completion:completion];
  }];
}

- (void)fetchFeedGeneratorViewsForURIs:(NSArray<NSString *> *)uris completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *generatorsByURI))completion {
  NSMutableArray<NSString *> *uniqueURIs = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (NSString *uri in uris) {
    if (![uri isKindOfClass:NSString.class] || uri.length == 0 || [seen containsObject:uri]) continue;
    [seen addObject:uri];
    [uniqueURIs addObject:uri];
  }
  if (uniqueURIs.count == 0) {
    if (completion) completion(@{});
    return;
  }

  NSMutableDictionary<NSString *, NSDictionary *> *generatorsByURI = [NSMutableDictionary dictionary];
  [self fetchFeedGeneratorViewsForURIs:uniqueURIs offset:0 generatorsByURI:generatorsByURI completion:completion];
}

- (void)fetchFeedGeneratorViewsForURIs:(NSArray<NSString *> *)uris offset:(NSUInteger)offset generatorsByURI:(NSMutableDictionary<NSString *, NSDictionary *> *)generatorsByURI completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *generatorsByURI))completion {
  if (offset >= uris.count) {
    if (completion) completion(generatorsByURI);
    return;
  }

  NSUInteger count = MIN((NSUInteger)25, uris.count - offset);
  NSArray *batch = [uris subarrayWithRange:NSMakeRange(offset, count)];
  [self fetchAppViewGET:@"app.bsky.feed.getFeedGenerators"
                 params:@{@"feeds": batch}
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
      if (completion) completion(@{});
      return;
    }
    if (!error && [value isKindOfClass:NSDictionary.class] && [value[@"feeds"] isKindOfClass:NSArray.class]) {
      for (NSDictionary *generator in value[@"feeds"]) {
        if (![generator isKindOfClass:NSDictionary.class]) continue;
        NSString *uri = [generator[@"uri"] isKindOfClass:NSString.class] ? generator[@"uri"] : @"";
        if (uri.length > 0) generatorsByURI[uri] = generator;
      }
    }
    [self fetchFeedGeneratorViewsForURIs:uris offset:offset + count generatorsByURI:generatorsByURI completion:completion];
  }];
}

- (void)fetchPostViewsForURIs:(NSArray<NSString *> *)uris completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *postsByURI, NSError *error))completion {
  NSMutableArray<NSString *> *uniqueURIs = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (NSString *uri in uris) {
    if (![uri isKindOfClass:NSString.class] || uri.length == 0 || [seen containsObject:uri]) continue;
    [seen addObject:uri];
    [uniqueURIs addObject:uri];
  }
  if (uniqueURIs.count == 0) {
    if (completion) completion(@{}, nil);
    return;
  }

  NSMutableDictionary<NSString *, NSDictionary *> *postsByURI = [NSMutableDictionary dictionary];
  [self fetchPostViewsForURIs:uniqueURIs offset:0 postsByURI:postsByURI firstError:nil completion:completion];
}

- (void)fetchPostForURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion {
  if (uri.length == 0) {
    if (completion) completion(nil, nil);
    return;
  }
  [self fetchPostViewsForURIs:@[uri] completion:^(NSDictionary<NSString *,NSDictionary *> *postsByURI, NSError *error) {
    NSDictionary *post = [postsByURI[uri] isKindOfClass:NSDictionary.class] ? postsByURI[uri] : nil;
    if (completion) completion(post, error);
  }];
}

- (void)fetchPostViewsForURIs:(NSArray<NSString *> *)uris offset:(NSUInteger)offset postsByURI:(NSMutableDictionary<NSString *, NSDictionary *> *)postsByURI firstError:(NSError *)firstError completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *postsByURI, NSError *error))completion {
  if (offset >= uris.count) {
    if (completion) completion(postsByURI, firstError);
    return;
  }

  NSUInteger count = MIN((NSUInteger)25, uris.count - offset);
  NSArray *batch = [uris subarrayWithRange:NSMakeRange(offset, count)];
  [self fetchAppViewGET:@"app.bsky.feed.getPosts"
                 params:@{@"uris": batch}
           requiresAuth:NO
             completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    NSError *nextError = firstError ?: error;
    NSArray *posts = [value isKindOfClass:NSDictionary.class] && [value[@"posts"] isKindOfClass:NSArray.class] ? value[@"posts"] : @[];
    for (NSDictionary *post in posts) {
      if (![post isKindOfClass:NSDictionary.class]) continue;
      NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
      if (uri.length > 0) postsByURI[uri] = post;
    }
    [self fetchPostViewsForURIs:uris offset:offset + count postsByURI:postsByURI firstError:nextError completion:completion];
  }];
}

- (void)fetchProfileRecordForDID:(NSString *)did completion:(void (^)(NSDictionary *record, NSString *endpoint))completion {
  if (did.length == 0) {
    if (completion) completion(@{}, nil);
    return;
  }

  [[NFBAtprotoSession sharedSession] resolvePDSForDID:did completion:^(NSString *serviceEndpoint) {
    if (serviceEndpoint.length == 0) {
      if (completion) completion(@{}, nil);
      return;
    }

    [[NFBAtprotoSession sharedSession] xrpcGET:@"com.atproto.repo.getRecord"
                                       service:serviceEndpoint
                                        params:@{
                                          @"repo": did,
                                          @"collection": @"app.bsky.actor.profile",
                                          @"rkey": @"self"
                                        }
                                 authenticated:NO
                                    completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)response;
      if (error || ![value isKindOfClass:NSDictionary.class]) {
        if (completion) completion(@{}, nil);
        return;
      }
      NSDictionary *record = [value[@"value"] isKindOfClass:NSDictionary.class] ? value[@"value"] : @{};
      if (completion) completion(record, serviceEndpoint);
    }];
  }];
}





- (NSString *)targetPostURIForNotification:(NSDictionary *)notification {
  NSString *reason = [notification[@"reason"] isKindOfClass:NSString.class] ? notification[@"reason"] : @"";
  NSString *reasonSubject = [notification[@"reasonSubject"] isKindOfClass:NSString.class] ? notification[@"reasonSubject"] : @"";
  NSString *uri = [notification[@"uri"] isKindOfClass:NSString.class] ? notification[@"uri"] : @"";
  if (([reason isEqualToString:@"like"] || [reason isEqualToString:@"repost"]) && reasonSubject.length > 0) return reasonSubject;
  if ([reason isEqualToString:@"follow"]) return @"";
  return uri;
}

- (BOOL)notificationReasonRoutesToProfile:(NSString *)reason {
  return [reason isEqualToString:@"follow"] || [reason isEqualToString:@"starterpack-joined"];
}

- (NSDictionary *)syntheticPostForNotification:(NSDictionary *)notification targetURI:(NSString *)targetURI {
  NSDictionary *author = [notification[@"author"] isKindOfClass:[NSDictionary class]] ? notification[@"author"] : @{};
  NSDictionary *record = [notification[@"record"] isKindOfClass:[NSDictionary class]] ? notification[@"record"] : @{};
  NSString *text = [record[@"text"] isKindOfClass:[NSString class]] ? record[@"text"] : @"";
  NSString *reason = [notification[@"reason"] isKindOfClass:[NSString class]] ? notification[@"reason"] : @"notification";
  NSString *uri = targetURI.length > 0 ? targetURI : ([notification[@"uri"] isKindOfClass:[NSString class]] ? notification[@"uri"] : [[NSUUID UUID] UUIDString]);
  BOOL targetIsNotificationRecord = targetURI.length == 0 || [targetURI isEqualToString:notification[@"uri"]];
  NSString *cid = targetIsNotificationRecord && [notification[@"cid"] isKindOfClass:[NSString class]] ? notification[@"cid"] : @"";
  NSString *indexedAt = [notification[@"indexedAt"] isKindOfClass:[NSString class]] ? notification[@"indexedAt"] : [self.class isoDateNow];
  NSMutableDictionary *postRecord = [record mutableCopy] ?: [NSMutableDictionary dictionary];
  if (![postRecord[@"text"] isKindOfClass:[NSString class]]) postRecord[@"text"] = text.length > 0 ? text : reason;
  if (![postRecord[@"createdAt"] isKindOfClass:[NSString class]]) postRecord[@"createdAt"] = indexedAt;
  return @{
    @"uri": uri ?: @"",
    @"cid": cid ?: @"",
    @"author": author,
    @"record": postRecord,
    @"indexedAt": indexedAt,
    @"replyCount": @0,
    @"repostCount": @0,
    @"likeCount": @0,
    @"quoteCount": @0
  };
}

- (void)finishFeedResponse:(id)value key:(NSString *)key error:(NSError *)error completion:(NFBAtprotoArrayCompletion)completion {
  if (error) {
    if (completion) completion(nil, nil, error);
    return;
  }
  NSArray *items = [value isKindOfClass:[NSDictionary class]] && [value[key] isKindOfClass:[NSArray class]] ? value[key] : @[];
  NSString *cursor = [value isKindOfClass:[NSDictionary class]] && [value[@"cursor"] isKindOfClass:[NSString class]] ? value[@"cursor"] : nil;
  if (completion) completion(items, cursor, nil);
}

- (void)finishResourceResponse:(id)value key:(NSString *)key type:(NSString *)type error:(NSError *)error completion:(NFBAtprotoArrayCompletion)completion {
  if (error) {
    if (completion) completion(nil, nil, error);
    return;
  }
  NSArray *resources = [value isKindOfClass:[NSDictionary class]] && [value[key] isKindOfClass:[NSArray class]] ? value[key] : @[];
  NSMutableArray *items = [NSMutableArray arrayWithCapacity:resources.count];
  for (NSDictionary *resource in resources) {
    if (![resource isKindOfClass:[NSDictionary class]]) continue;
    [items addObject:@{@"resource": resource, @"type": type ?: @""}];
  }
  NSString *cursor = [value isKindOfClass:[NSDictionary class]] && [value[@"cursor"] isKindOfClass:[NSString class]] ? value[@"cursor"] : nil;
  if (completion) completion(items, cursor, nil);
}

- (NSArray<NSDictionary *> *)savedHomeFeedsFromPreferences:(NSArray *)preferences {
  NSMutableArray<NSDictionary *> *feeds = [NSMutableArray array];
  for (NSDictionary *item in [self savedFeedItemsFromPreferences:preferences]) {
    if ([item[@"type"] isEqualToString:@"feed"] && [self.class isFeedGeneratorURI:NFBClientStringValue(item[@"value"])]) {
      [feeds addObject:item];
    }
  }
  return feeds;
}

- (NSArray<NSDictionary *> *)savedFeedItemsFromPreferences:(NSArray *)preferences {
  NSArray *items = @[];
  for (NSInteger index = (NSInteger)preferences.count - 1; index >= 0; index--) {
    NSDictionary *preference = [preferences[(NSUInteger)index] isKindOfClass:NSDictionary.class] ? preferences[(NSUInteger)index] : nil;
    if (![preference[@"$type"] isEqualToString:@"app.bsky.actor.defs#savedFeedsPrefV2"]) continue;
    if ([preference[@"items"] isKindOfClass:NSArray.class]) {
      items = preference[@"items"];
      break;
    }
  }

  NSMutableArray<NSDictionary *> *savedFeeds = [NSMutableArray array];
  NSMutableSet<NSString *> *seenValues = [NSMutableSet set];
  if (items.count > 0) {
    for (NSDictionary *item in items) {
      if (![item isKindOfClass:NSDictionary.class]) continue;
      NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"";
      NSString *value = [item[@"value"] isKindOfClass:NSString.class] ? item[@"value"] : @"";
      if ((![type isEqualToString:@"feed"] && ![type isEqualToString:@"list"]) || value.length == 0 || [seenValues containsObject:value]) continue;
      [seenValues addObject:value];
      [savedFeeds addObject:item];
    }
    return savedFeeds;
  }

  NSDictionary *legacy = nil;
  for (NSInteger index = (NSInteger)preferences.count - 1; index >= 0; index--) {
    NSDictionary *preference = [preferences[(NSUInteger)index] isKindOfClass:NSDictionary.class] ? preferences[(NSUInteger)index] : nil;
    if ([preference[@"$type"] isEqualToString:@"app.bsky.actor.defs#savedFeedsPref"]) {
      legacy = preference;
      break;
    }
  }
  NSArray *legacySaved = [legacy[@"saved"] isKindOfClass:NSArray.class] ? legacy[@"saved"] : @[];
  NSArray *legacyPinned = [legacy[@"pinned"] isKindOfClass:NSArray.class] ? legacy[@"pinned"] : @[];
  NSMutableArray *legacyURIs = [NSMutableArray arrayWithArray:legacyPinned];
  for (NSString *uri in legacySaved) {
    if (![legacyURIs containsObject:uri]) [legacyURIs addObject:uri];
  }
  for (NSString *uri in legacyURIs) {
    if (![uri isKindOfClass:NSString.class] || uri.length == 0 || [seenValues containsObject:uri]) continue;
    NSString *type = [self.class isFeedGeneratorURI:uri] ? @"feed" : ([uri rangeOfString:@"/app.bsky.graph.list/"].location != NSNotFound ? @"list" : @"");
    if (type.length == 0) continue;
    [seenValues addObject:uri];
    [savedFeeds addObject:@{@"type": type, @"value": uri, @"id": uri, @"pinned": @([legacyPinned containsObject:uri])}];
  }
  return savedFeeds;
}

- (void)fetchSavedFeedItemsWithCompletion:(void (^)(NSArray<NSDictionary *> *items, NSArray *preferences, NSError *error))completion {
  [[NFBAtprotoSession sharedSession] xrpcGET:@"app.bsky.actor.getPreferences"
                                     service:nil
                                      params:nil
                               authenticated:YES
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (error) {
      if (completion) completion(@[], @[], error);
      return;
    }
    NSArray *preferences = [value isKindOfClass:NSDictionary.class] && [value[@"preferences"] isKindOfClass:NSArray.class] ? value[@"preferences"] : @[];
    if (completion) completion([self savedFeedItemsFromPreferences:preferences], preferences, nil);
  }];
}

- (void)putSavedFeedItems:(NSArray<NSDictionary *> *)items preferences:(NSArray *)preferences completion:(NFBAtprotoDictionaryCompletion)completion {
  NSMutableArray<NSDictionary *> *unique = [NSMutableArray array];
  NSMutableSet<NSString *> *seenValues = [NSMutableSet set];
  for (NSDictionary *item in items ?: @[]) {
    if (![item isKindOfClass:NSDictionary.class]) continue;
    NSString *type = NFBClientStringValue(item[@"type"]);
    NSString *value = NFBClientStringValue(item[@"value"]);
    if ((![type isEqualToString:@"feed"] && ![type isEqualToString:@"list"]) || value.length == 0 || [seenValues containsObject:value]) continue;
    [seenValues addObject:value];
    [unique addObject:@{
      @"id": NFBClientStringValue(item[@"id"]).length > 0 ? item[@"id"] : value,
      @"type": type,
      @"value": value,
      @"pinned": [item[@"pinned"] respondsToSelector:@selector(boolValue)] ? item[@"pinned"] : @YES
    }];
  }

  NSMutableArray *updatedPreferences = [NSMutableArray array];
  NSDictionary *legacySavedFeedsPref = nil;
  for (NSDictionary *preference in preferences ?: @[]) {
    if (![preference isKindOfClass:NSDictionary.class]) continue;
    NSString *type = NFBClientStringValue(preference[@"$type"]);
    if ([type isEqualToString:@"app.bsky.actor.defs#savedFeedsPrefV2"]) continue;
    if ([type isEqualToString:@"app.bsky.actor.defs#savedFeedsPref"]) {
      legacySavedFeedsPref = preference;
      continue;
    }
    [updatedPreferences addObject:preference];
  }
  [updatedPreferences addObject:@{@"$type": @"app.bsky.actor.defs#savedFeedsPrefV2", @"items": unique}];

  if (legacySavedFeedsPref) {
    NSMutableArray *saved = [NSMutableArray array];
    NSMutableArray *pinned = [NSMutableArray array];
    for (NSDictionary *item in unique) {
      NSString *value = NFBClientStringValue(item[@"value"]);
      if (value.length == 0) continue;
      [saved addObject:value];
      if ([item[@"pinned"] boolValue]) [pinned addObject:value];
    }
    NSMutableDictionary *legacy = [legacySavedFeedsPref mutableCopy];
    legacy[@"saved"] = saved;
    legacy[@"pinned"] = pinned;
    [updatedPreferences addObject:legacy];
  }

  [[NFBAtprotoSession sharedSession] xrpcPOST:@"app.bsky.actor.putPreferences"
                                      service:nil
                                         body:@{@"preferences": updatedPreferences}
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (!error) [self invalidateCachedFeedAndListResources];
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

- (void)toggleReaction:(NSString *)collection viewerKey:(NSString *)viewerKey post:(NSDictionary *)post completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  NSString *existingURI = [viewer[viewerKey] isKindOfClass:NSString.class] ? viewer[viewerKey] : @"";
  if (existingURI.length > 0) {
    [self deleteRecordAtURI:existingURI completion:completion];
    return;
  }

  NSString *postURI = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  NSString *postCID = [post[@"cid"] isKindOfClass:NSString.class] ? post[@"cid"] : @"";
  if (postURI.length == 0 || postCID.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:40 userInfo:@{NSLocalizedDescriptionKey: @"Post reference was not available."}]);
    return;
  }

  NSDictionary *body = @{
    @"repo": [NFBAtprotoSession sharedSession].did ?: @"",
    @"collection": collection,
    @"record": @{
      @"$type": collection,
      @"subject": @{@"uri": postURI, @"cid": postCID},
      @"createdAt": [self.class isoDateNow]
    }
  };
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.createRecord"
                                      service:nil
                                         body:body
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : nil, error);
  }];
}

- (void)deleteRecordAtURI:(NSString *)uri completion:(NFBAtprotoDictionaryCompletion)completion {
  NSDictionary *parts = [self.class recordPartsFromAtURI:uri];
  if (!parts) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBAtprotoClient" code:41 userInfo:@{NSLocalizedDescriptionKey: @"Reaction reference was not available."}]);
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.deleteRecord"
                                      service:nil
                                         body:parts
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (completion) completion([value isKindOfClass:NSDictionary.class] ? value : @{}, error);
  }];
}

+ (NSDictionary *)post:(NSDictionary *)post applyingToggleForViewerKey:(NSString *)viewerKey countKey:(NSString *)countKey response:(NSDictionary *)response {
  if (![post isKindOfClass:NSDictionary.class] || viewerKey.length == 0) return @{};
  NSMutableDictionary *updatedPost = [post mutableCopy];
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  NSMutableDictionary *updatedViewer = [viewer mutableCopy] ?: [NSMutableDictionary dictionary];
  NSString *existingURI = [viewer[viewerKey] isKindOfClass:NSString.class] ? viewer[viewerKey] : @"";
  BOOL activating = existingURI.length == 0;
  if (activating) {
    NSString *recordURI = [response[@"uri"] isKindOfClass:NSString.class] ? response[@"uri"] : @"";
    if (recordURI.length == 0) {
      NSString *postURI = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : [[NSUUID UUID] UUIDString];
      recordURI = [NSString stringWithFormat:@"local:%@:%@", viewerKey, postURI];
    }
    updatedViewer[viewerKey] = recordURI;
  } else {
    [updatedViewer removeObjectForKey:viewerKey];
  }
  updatedPost[@"viewer"] = updatedViewer;

  if (countKey.length > 0) {
    NSInteger count = [post[countKey] respondsToSelector:@selector(integerValue)] ? [post[countKey] integerValue] : 0;
    count += activating ? 1 : -1;
    updatedPost[countKey] = @(MAX(0, count));
  }
  return updatedPost;
}

+ (NSDictionary *)postByApplyingBookmarkToggleForPost:(NSDictionary *)post response:(NSDictionary *)response {
  (void)response;
  if (![post isKindOfClass:NSDictionary.class]) return @{};
  NSMutableDictionary *updatedPost = [post mutableCopy];
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  NSMutableDictionary *updatedViewer = [viewer mutableCopy] ?: [NSMutableDictionary dictionary];
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  updatedViewer[@"bookmarked"] = @(!bookmarked);
  updatedPost[@"viewer"] = updatedViewer;
  return updatedPost;
}

+ (NSDictionary *)profile:(NSDictionary *)profile applyingFollowToggleWithResponse:(NSDictionary *)response {
  if (![profile isKindOfClass:NSDictionary.class]) return @{};
  NSMutableDictionary *updatedProfile = [profile mutableCopy];
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  NSMutableDictionary *updatedViewer = [viewer mutableCopy] ?: [NSMutableDictionary dictionary];
  NSString *existingURI = [viewer[@"following"] isKindOfClass:NSString.class] ? viewer[@"following"] : @"";
  BOOL activating = existingURI.length == 0;
  if (activating) {
    NSString *recordURI = [response[@"uri"] isKindOfClass:NSString.class] ? response[@"uri"] : @"";
    if (recordURI.length == 0) {
      NSString *did = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : [[NSUUID UUID] UUIDString];
      recordURI = [NSString stringWithFormat:@"local:follow:%@", did];
    }
    updatedViewer[@"following"] = recordURI;
  } else {
    [updatedViewer removeObjectForKey:@"following"];
  }
  updatedProfile[@"viewer"] = updatedViewer;

  NSInteger followers = [profile[@"followersCount"] respondsToSelector:@selector(integerValue)] ? [profile[@"followersCount"] integerValue] : 0;
  followers += activating ? 1 : -1;
  updatedProfile[@"followersCount"] = @(MAX(0, followers));
  return updatedProfile;
}

+ (NSDictionary *)profile:(NSDictionary *)profile applyingBlockToggleWithResponse:(NSDictionary *)response {
  if (![profile isKindOfClass:NSDictionary.class]) return @{};
  NSMutableDictionary *updatedProfile = [profile mutableCopy];
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  NSMutableDictionary *updatedViewer = [viewer mutableCopy] ?: [NSMutableDictionary dictionary];
  NSString *existingURI = [viewer[@"blocking"] isKindOfClass:NSString.class] ? viewer[@"blocking"] : @"";
  BOOL activating = existingURI.length == 0;
  BOOL wasFollowing = [viewer[@"following"] isKindOfClass:NSString.class] && [viewer[@"following"] length] > 0;

  if (activating) {
    NSString *recordURI = [response[@"uri"] isKindOfClass:NSString.class] ? response[@"uri"] : @"";
    if (recordURI.length == 0) {
      NSString *did = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : [[NSUUID UUID] UUIDString];
      recordURI = [NSString stringWithFormat:@"local:block:%@", did];
    }
    updatedViewer[@"blocking"] = recordURI;
    [updatedViewer removeObjectForKey:@"following"];
    [updatedViewer removeObjectForKey:@"followedBy"];
  } else {
    [updatedViewer removeObjectForKey:@"blocking"];
  }
  updatedProfile[@"viewer"] = updatedViewer;

  if (activating && wasFollowing) {
    NSInteger followers = [profile[@"followersCount"] respondsToSelector:@selector(integerValue)] ? [profile[@"followersCount"] integerValue] : 0;
    updatedProfile[@"followersCount"] = @(MAX(0, followers - 1));
  }

  return updatedProfile;
}

+ (NSDictionary *)postFromFeedItem:(NSDictionary *)item {
  if ([item[@"post"] isKindOfClass:[NSDictionary class]]) return item[@"post"];
  return [item isKindOfClass:[NSDictionary class]] ? item : @{};
}

+ (NSString *)postURIFromFeedItem:(NSDictionary *)item {
  NSDictionary *post = [self postFromFeedItem:item];
  return [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
}

+ (NSDictionary *)replyParentPostFromFeedItem:(NSDictionary *)item {
  NSDictionary *parentPost = [item[@"replyParentPost"] isKindOfClass:NSDictionary.class] ? item[@"replyParentPost"] : nil;
  if (parentPost.count > 0) return parentPost;
  NSDictionary *reply = [item[@"reply"] isKindOfClass:NSDictionary.class] ? item[@"reply"] : nil;
  NSDictionary *parent = [reply[@"parent"] isKindOfClass:NSDictionary.class] ? reply[@"parent"] : nil;
  if (parent.count > 0) return [self postFromRecordView:parent] ?: parent;
  return @{};
}

+ (NSArray<NSDictionary *> *)feedItemsSortedNewestFirst:(NSArray<NSDictionary *> *)items {
  NSArray<NSDictionary *> *safeItems = [items isKindOfClass:NSArray.class] ? items : @[];
  return [safeItems sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *leftItem, NSDictionary *rightItem) {
    NSDictionary *leftPost = [self postFromFeedItem:leftItem ?: @{}];
    NSDictionary *rightPost = [self postFromFeedItem:rightItem ?: @{}];
    NSString *leftDate = [self createdAtStringForThreadPost:leftPost];
    NSString *rightDate = [self createdAtStringForThreadPost:rightPost];
    NSComparisonResult result = [rightDate compare:leftDate];
    if (result != NSOrderedSame) return result;
    return [[self postURIFromFeedItem:rightItem ?: @{}] compare:[self postURIFromFeedItem:leftItem ?: @{}]];
  }];
}

+ (NSString *)replyParentURIForRecord:(NSDictionary *)record {
  if (![record isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *reply = [record[@"reply"] isKindOfClass:NSDictionary.class] ? record[@"reply"] : nil;
  NSDictionary *parent = [reply[@"parent"] isKindOfClass:NSDictionary.class] ? reply[@"parent"] : nil;
  NSString *uri = [parent[@"uri"] isKindOfClass:NSString.class] ? parent[@"uri"] : @"";
  return uri ?: @"";
}

+ (NSString *)replyParentURIForPost:(NSDictionary *)post {
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  return [self replyParentURIForRecord:record];
}

+ (NSString *)replyRootURIForRecord:(NSDictionary *)record {
  if (![record isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *reply = [record[@"reply"] isKindOfClass:NSDictionary.class] ? record[@"reply"] : nil;
  NSDictionary *root = [reply[@"root"] isKindOfClass:NSDictionary.class] ? reply[@"root"] : nil;
  NSString *uri = [root[@"uri"] isKindOfClass:NSString.class] ? root[@"uri"] : @"";
  return uri ?: @"";
}

+ (NSString *)replyRootURIForPost:(NSDictionary *)post {
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  return [self replyRootURIForRecord:record];
}

+ (NSString *)authorDIDFromAtURI:(NSString *)uri {
  if (![uri isKindOfClass:NSString.class] || ![uri hasPrefix:@"at://"]) return @"";
  NSString *rest = [uri substringFromIndex:@"at://".length];
  NSRange slash = [rest rangeOfString:@"/"];
  if (slash.location == NSNotFound) return rest;
  return [rest substringToIndex:slash.location];
}

+ (NSString *)replyTargetTextForFeedItem:(NSDictionary *)item {
  NSDictionary *parentPost = [item[@"replyParentPost"] isKindOfClass:NSDictionary.class] ? item[@"replyParentPost"] : nil;
  NSDictionary *parentAuthor = [parentPost[@"author"] isKindOfClass:NSDictionary.class] ? parentPost[@"author"] : nil;
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSString *parentDID = [parentAuthor[@"did"] isKindOfClass:NSString.class] ? parentAuthor[@"did"] : @"";
  NSString *parentURI = [item[@"replyParentURI"] isKindOfClass:NSString.class] ? item[@"replyParentURI"] : @"";
  if (parentDID.length == 0) parentDID = [self authorDIDFromAtURI:parentURI];
  if (viewerDID.length > 0 && parentDID.length > 0 && [viewerDID isEqualToString:parentDID]) return @"you";
  if (parentAuthor.count > 0) {
    NSString *displayName = [self displayNameForProfile:parentAuthor];
    if (displayName.length > 0) return displayName;
  }
  return @"";
}

+ (NSString *)webURLStringForPost:(NSDictionary *)post {
  if (![post isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *actor = [author[@"handle"] isKindOfClass:NSString.class] ? author[@"handle"] : [self canonicalHandleForProfile:author];
  NSString *rkey = [self rkeyFromAtURI:[post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @""];
  if (actor.length == 0 || rkey.length == 0) return @"";
  NSCharacterSet *allowed = NSCharacterSet.URLPathAllowedCharacterSet;
  NSString *encodedActor = [actor stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: actor;
  NSString *encodedRkey = [rkey stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: rkey;
  return [NSString stringWithFormat:@"https://bsky.app/profile/%@/post/%@", encodedActor, encodedRkey];
}

+ (NSDictionary *)trendItemForTopic:(NSDictionary *)topic kind:(NSString *)kind rank:(NSInteger)rank {
  NSString *name = [topic[@"topic"] isKindOfClass:NSString.class] ? topic[@"topic"] : @"";
  NSString *displayName = [topic[@"displayName"] isKindOfClass:NSString.class] ? topic[@"displayName"] : name;
  NSString *description = [topic[@"description"] isKindOfClass:NSString.class] ? topic[@"description"] : @"";
  NSString *link = [topic[@"link"] isKindOfClass:NSString.class] ? topic[@"link"] : @"";
  NSString *category = [kind isEqualToString:@"topic"] ? ([self categoryForTrendTopic:topic] ?: @"") : @"Feeds";
  if (name.length == 0 && displayName.length == 0) displayName = @"Trending";
  NSString *query = name.length > 0 ? name : displayName ?: @"";

  return @{
    @"type": @"trend",
    @"kind": kind ?: @"topic",
    @"rank": @(rank),
    @"name": name ?: @"",
    @"query": query,
    @"displayName": displayName ?: @"",
    @"description": description ?: @"",
    @"category": category ?: @"",
    @"url": link ?: @""
  };
}

+ (NSString *)categoryForTrendTopic:(NSDictionary *)topic {
  NSString *providedCategory = [self providedCategoryForTrendTopic:topic];
  if (providedCategory.length > 0) return providedCategory;

  NSString *normalizedTopic = [self normalizedCategoryText:[topic[@"topic"] isKindOfClass:NSString.class] ? topic[@"topic"] : @""];
  NSDictionary<NSString *, NSString *> *overrides = @{
    @"andy burnham": @"Politics",
    @"ben palmer": @"Politics",
    @"bfc registration": @"Events",
    @"blue sky art show": @"Arts",
    @"bluesky art show": @"Arts",
    @"canadian gp": @"Sports",
    @"colbert show": @"Entertainment",
    @"digital art": @"Entertainment",
    @"desantis": @"Politics",
    @"epstein files": @"Politics",
    @"epstein scandals": @"Politics",
    @"european cities": @"World",
    @"formula 1": @"Sports",
    @"gop bill delay": @"Politics",
    @"habs": @"Sports",
    @"hull fc": @"Sports",
    @"ice protests": @"Politics",
    @"indie games": @"Gaming",
    @"knicks": @"Sports",
    @"missile threat": @"World",
    @"nba playoffs": @"Sports",
    @"royals": @"Sports",
    @"stephen colbert": @"Entertainment",
    @"svengoolie": @"Entertainment",
    @"tall photography": @"Arts",
    @"texier": @"Sports",
    @"the mandalorian": @"Entertainment",
    @"trans rights": @"Politics"
  };
  NSString *override = overrides[normalizedTopic];
  if (override.length > 0) return override;

  NSString *topicText = [topic[@"topic"] isKindOfClass:NSString.class] ? topic[@"topic"] : @"";
  NSString *displayName = [topic[@"displayName"] isKindOfClass:NSString.class] ? topic[@"displayName"] : @"";
  NSString *description = [topic[@"description"] isKindOfClass:NSString.class] ? topic[@"description"] : @"";
  NSString *searchableText = [self normalizedCategoryText:[NSString stringWithFormat:@"%@ %@ %@", topicText, displayName, description]];
  NSArray<NSDictionary *> *rules = @[
    @{@"category": @"World", @"keywords": @[@"conflict", @"diplomacy", @"foreign policy", @"geopolitics", @"global", @"iran", @"middle east", @"missile", @"nato", @"nuclear", @"palestine", @"russia", @"treaty", @"ukraine", @"war", @"world"]},
    @{@"category": @"Politics", @"keywords": @[@"administration", @"biden", @"bill", @"cabinet", @"civil rights", @"congress", @"court", @"democrat", @"democratic", @"election", @"gop", @"government", @"governor", @"harris", @"human rights", @"ice", @"immigration", @"lgbtq", @"mayor", @"minister", @"obama", @"parliament", @"party", @"policy", @"politics", @"president", @"prime minister", @"protest", @"republican", @"senate", @"scandal", @"supreme court", @"transgender", @"trump", @"white house"]},
    @{@"category": @"Sports", @"keywords": @[@"baseball", @"basketball", @"champions league", @"championship", @"f1", @"fc", @"football", @"grand prix", @"hockey", @"mlb", @"nba", @"nfl", @"nhl", @"olympics", @"playoffs", @"rugby", @"soccer", @"sports", @"uefa", @"uwcl", @"wrestling", @"wnba", @"world cup"]},
    @{@"category": @"Entertainment", @"keywords": @[@"album", @"anime", @"art", @"artist", @"celebrity", @"cinema", @"comedian", @"comedy", @"film", @"films", @"mando", @"movie", @"movies", @"music", @"oscars", @"pop culture", @"review", @"show", @"star wars", @"television", @"tv"]},
    @{@"category": @"Gaming", @"keywords": @[@"game dev", @"game development", @"gaming", @"indie game", @"nintendo", @"playstation", @"steam", @"video game", @"xbox"]},
    @{@"category": @"Technology", @"keywords": @[@"ai", @"android", @"apple", @"bluesky", @"google", @"ios", @"openai", @"programming", @"software", @"tech", @"technology", @"web dev"]},
    @{@"category": @"Business", @"keywords": @[@"business", @"crypto", @"economy", @"market", @"stock", @"stocks", @"tariff"]},
    @{@"category": @"Arts", @"keywords": @[@"art show", @"painting", @"photo", @"photography", @"pixelart", @"watercolor"]},
    @{@"category": @"Events", @"keywords": @[@"conference", @"convention", @"event", @"festival", @"tickets"]},
    @{@"category": @"Science", @"keywords": @[@"climate", @"nasa", @"science", @"space"]},
    @{@"category": @"Lifestyle", @"keywords": @[@"beauty", @"fashion", @"fitness", @"food", @"gardening", @"health"]},
    @{@"category": @"News", @"keywords": @[@"breaking news", @"headline", @"news", @"report"]}
  ];

  for (NSDictionary *rule in rules) {
    NSArray *keywords = [rule[@"keywords"] isKindOfClass:NSArray.class] ? rule[@"keywords"] : @[];
    for (NSString *keyword in keywords) {
      if ([self categoryText:searchableText containsKeyword:keyword]) return rule[@"category"];
    }
  }

  return nil;
}

+ (NSString *)providedCategoryForTrendTopic:(NSDictionary *)topic {
  NSArray<NSString *> *keys = @[@"category", @"categoryName", @"topicCategory"];
  NSDictionary<NSString *, NSString *> *displayNames = @{
    @"ai": @"Technology",
    @"arts": @"Arts",
    @"arts/culture": @"Arts",
    @"arts culture": @"Arts",
    @"business": @"Business",
    @"entertainment": @"Entertainment",
    @"events": @"Events",
    @"feeds": @"Feeds",
    @"gaming": @"Gaming",
    @"lifestyle": @"Lifestyle",
    @"movies": @"Entertainment",
    @"music": @"Entertainment",
    @"news": @"News",
    @"politics": @"Politics",
    @"science": @"Science",
    @"sports": @"Sports",
    @"technology": @"Technology",
    @"world": @"World"
  };

  for (NSString *key in keys) {
    NSString *value = [topic[key] isKindOfClass:NSString.class] ? topic[key] : nil;
    NSString *normalized = [self normalizedCategoryText:value ?: @""];
    if (normalized.length == 0) continue;
    NSString *displayName = displayNames[normalized];
    if (displayName.length > 0) return displayName;

    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in [normalized componentsSeparatedByString:@" "]) {
      if (word.length == 0) continue;
      [words addObject:word.capitalizedString];
    }
    return [words componentsJoinedByString:@" "];
  }
  return nil;
}

+ (NSString *)normalizedCategoryText:(NSString *)value {
  if (![value isKindOfClass:NSString.class]) return @"";
  NSString *lower = value.lowercaseString;
  NSMutableString *normalized = [NSMutableString stringWithCapacity:lower.length];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789&/ "];
  for (NSUInteger index = 0; index < lower.length; index++) {
    unichar character = [lower characterAtIndex:index];
    if ([allowed characterIsMember:character]) {
      [normalized appendFormat:@"%C", character];
    } else {
      [normalized appendString:@" "];
    }
  }
  while ([normalized rangeOfString:@"  "].location != NSNotFound) {
    [normalized replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, normalized.length)];
  }
  return [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (BOOL)categoryText:(NSString *)value containsKeyword:(NSString *)keyword {
  NSString *text = [self normalizedCategoryText:value];
  NSString *needle = [self normalizedCategoryText:keyword];
  if (needle.length == 0) return NO;
  NSString *paddedText = [NSString stringWithFormat:@" %@ ", text];
  NSString *paddedNeedle = [NSString stringWithFormat:@" %@ ", needle];
  return [paddedText rangeOfString:paddedNeedle].location != NSNotFound;
}

+ (BOOL)isFeedGeneratorURI:(NSString *)uri {
  return [uri rangeOfString:@"/app.bsky.feed.generator/"].location != NSNotFound && [uri hasPrefix:@"at://"];
}

+ (NSString *)fallbackFeedNameForURI:(NSString *)uri {
  NSString *rkey = [self rkeyFromAtURI:uri];
  if (rkey.length == 0) return @"Feed";
  NSArray *words = [[rkey stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"];
  NSMutableArray *capitalized = [NSMutableArray array];
  for (NSString *word in words) {
    if (word.length == 0) continue;
    [capitalized addObject:word.capitalizedString];
  }
  return capitalized.count > 0 ? [capitalized componentsJoinedByString:@" "] : @"Feed";
}

+ (NSString *)rkeyFromAtURI:(NSString *)uri {
  NSArray *parts = [uri componentsSeparatedByString:@"/"];
  return parts.count > 0 ? parts.lastObject : @"";
}

+ (NSDictionary *)recordPartsFromAtURI:(NSString *)uri {
  if (![uri hasPrefix:@"at://"]) return nil;
  NSString *rest = [uri substringFromIndex:5];
  NSArray *parts = [rest componentsSeparatedByString:@"/"];
  if (parts.count < 3) return nil;
  return @{@"repo": parts[0], @"collection": parts[1], @"rkey": parts[2]};
}

+ (NSDictionary *)postRefForPost:(NSDictionary *)post {
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  NSString *cid = [post[@"cid"] isKindOfClass:NSString.class] ? post[@"cid"] : @"";
  if (uri.length == 0 || cid.length == 0) return nil;
  return @{@"uri": uri, @"cid": cid};
}

+ (NSDictionary *)replyRefForParentPost:(NSDictionary *)parentPost {
  if (![parentPost isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *parentRef = [self postRefForPost:parentPost];
  if (!parentRef) return nil;
  NSDictionary *record = [parentPost[@"record"] isKindOfClass:NSDictionary.class] ? parentPost[@"record"] : @{};
  NSDictionary *reply = [record[@"reply"] isKindOfClass:NSDictionary.class] ? record[@"reply"] : @{};
  NSDictionary *root = [reply[@"root"] isKindOfClass:NSDictionary.class] ? reply[@"root"] : parentRef;
  return @{@"root": root, @"parent": parentRef};
}

+ (NSDictionary *)embedForUploadedMediaItems:(NSArray<NSDictionary *> *)uploadedItems quoteRef:(NSDictionary *)quoteRef {
  NSDictionary *mediaEmbed = nil;
  if (uploadedItems.count == 1) {
    NSDictionary *item = uploadedItems.firstObject;
    NSString *type = NFBClientStringValue(item[@"type"]);
    NSString *mimeType = NFBClientStringValue(item[@"mimeType"]);
    NSDictionary *blob = [item[@"blob"] isKindOfClass:NSDictionary.class] ? item[@"blob"] : nil;
    BOOL asVideo = [type isEqualToString:@"video"] || ([type isEqualToString:@"gif"] && [mimeType isEqualToString:@"video/mp4"]);
    if (asVideo && blob) {
      NSMutableDictionary *video = [@{
        @"$type": @"app.bsky.embed.video",
        @"video": blob,
        @"alt": NFBClientStringValue(item[@"alt"])
      } mutableCopy];
      NSNumber *width = [item[@"width"] isKindOfClass:NSNumber.class] ? item[@"width"] : nil;
      NSNumber *height = [item[@"height"] isKindOfClass:NSNumber.class] ? item[@"height"] : nil;
      if (width.integerValue > 0 && height.integerValue > 0) video[@"aspectRatio"] = @{@"width": width, @"height": height};
      if ([type isEqualToString:@"gif"]) video[@"presentation"] = @"gif";
      mediaEmbed = video;
    }
  }

  if (!mediaEmbed && uploadedItems.count > 0) {
    BOOL gallery = NFBMediaUsesGallery(uploadedItems.count);
    NSMutableArray *images = [NSMutableArray array];
    for (NSDictionary *item in uploadedItems) {
      NSDictionary *blob = [item[@"blob"] isKindOfClass:NSDictionary.class] ? item[@"blob"] : nil;
      if (!blob) continue;
      NSMutableDictionary *image = [@{
        @"alt": NFBClientStringValue(item[@"alt"]),
        @"image": blob
      } mutableCopy];
      NSNumber *width = [item[@"width"] isKindOfClass:NSNumber.class] ? item[@"width"] : nil;
      NSNumber *height = [item[@"height"] isKindOfClass:NSNumber.class] ? item[@"height"] : nil;
      if (width.integerValue > 0 && height.integerValue > 0) image[@"aspectRatio"] = @{@"width": width, @"height": height};
      if (gallery) image[@"$type"] = @"app.bsky.embed.gallery#image";
      [images addObject:image];
    }
    if (images.count > 0) mediaEmbed = gallery
      ? @{@"$type": @"app.bsky.embed.gallery", @"items": images}
      : @{@"$type": @"app.bsky.embed.images", @"images": images};
  }

  if (quoteRef && mediaEmbed) {
    return @{
      @"$type": @"app.bsky.embed.recordWithMedia",
      @"record": @{@"$type": @"app.bsky.embed.record", @"record": quoteRef},
      @"media": mediaEmbed
    };
  }
  if (quoteRef) return @{@"$type": @"app.bsky.embed.record", @"record": quoteRef};
  return mediaEmbed;
}

+ (NSArray<NSDictionary *> *)threadgateAllowRulesForReplyGate:(NSString *)replyGate {
  if ([replyGate isEqualToString:NFBComposeReplyGateMentioned]) {
    return @[@{@"$type": @"app.bsky.feed.threadgate#mentionRule"}];
  }
  if ([replyGate isEqualToString:NFBComposeReplyGateFollowing]) {
    return @[
      @{@"$type": @"app.bsky.feed.threadgate#mentionRule"},
      @{@"$type": @"app.bsky.feed.threadgate#followingRule"}
    ];
  }
  if ([replyGate isEqualToString:NFBComposeReplyGateNobody]) return @[];
  return nil;
}

+ (NSError *)composeErrorWithMessage:(NSString *)message code:(NSInteger)code {
  return [NSError errorWithDomain:@"NFBAtprotoClient" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Could not compose this post."}];
}

+ (BOOL)typeStringIndicatesBlueskyTombstone:(NSString *)type {
  NSString *lower = type.lowercaseString ?: @"";
  return [lower rangeOfString:@"notfoundpost"].location != NSNotFound ||
         [lower rangeOfString:@"blockedpost"].location != NSNotFound ||
         [lower rangeOfString:@"viewnotfound"].location != NSNotFound ||
         [lower rangeOfString:@"viewblocked"].location != NSNotFound ||
         [lower rangeOfString:@"viewdetached"].location != NSNotFound ||
         [lower rangeOfString:@"notfound"].location != NSNotFound ||
         [lower rangeOfString:@"blocked"].location != NSNotFound ||
         [lower rangeOfString:@"detached"].location != NSNotFound;
}

+ (NSDictionary *)tombstonePostFromSource:(NSDictionary *)source fallbackType:(NSString *)fallbackType {
  if (![source isKindOfClass:NSDictionary.class]) return nil;
  NSString *type = NFBClientStringValue(source[@"$type"]);
  if (type.length == 0) type = fallbackType ?: @"";
  NSString *lower = type.lowercaseString ?: @"";
  BOOL notFound = [source[@"notFound"] respondsToSelector:@selector(boolValue)] && [source[@"notFound"] boolValue];
  BOOL blocked = [source[@"blocked"] respondsToSelector:@selector(boolValue)] && [source[@"blocked"] boolValue];
  BOOL detached = [source[@"detached"] respondsToSelector:@selector(boolValue)] && [source[@"detached"] boolValue];
  if ([lower rangeOfString:@"notfound"].location != NSNotFound) notFound = YES;
  if ([lower rangeOfString:@"blocked"].location != NSNotFound) blocked = YES;
  if ([lower rangeOfString:@"detached"].location != NSNotFound) detached = YES;
  if (!notFound && !blocked && !detached) return nil;

  NSString *resolvedType = type;
  if (resolvedType.length == 0) {
    resolvedType = blocked ? @"app.bsky.feed.defs#blockedPost" : (detached ? @"app.bsky.embed.record#viewDetached" : @"app.bsky.feed.defs#notFoundPost");
  }
  NSMutableDictionary *tombstone = [NSMutableDictionary dictionary];
  tombstone[@"$type"] = resolvedType;
  tombstone[@"_nfbModerationType"] = resolvedType;
  tombstone[@"record"] = @{@"text": @""};
  for (NSString *key in @[@"uri", @"cid", @"indexedAt"]) {
    id value = source[key];
    if (value) tombstone[key] = value;
  }
  NSDictionary *author = [source[@"author"] isKindOfClass:NSDictionary.class] ? source[@"author"] : nil;
  if (author) tombstone[@"author"] = author;
  return tombstone;
}

+ (NSDictionary *)tombstonePostFromPost:(NSDictionary *)post reason:(NSString *)reason {
  if (![post isKindOfClass:NSDictionary.class]) return nil;
  NSMutableDictionary *source = [NSMutableDictionary dictionary];
  source[@"$type"] = @"app.bsky.feed.defs#blockedPost";
  source[@"blocked"] = @YES;
  for (NSString *key in @[@"uri", @"cid", @"indexedAt"]) {
    id value = post[key];
    if (value) source[key] = value;
  }
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : nil;
  if (record) {
    NSMutableDictionary *sourceRecord = [@{@"text": @""} mutableCopy];
    id reply = record[@"reply"];
    if ([reply isKindOfClass:NSDictionary.class]) sourceRecord[@"reply"] = reply;
    id createdAt = record[@"createdAt"];
    if ([createdAt isKindOfClass:NSString.class]) sourceRecord[@"createdAt"] = createdAt;
    source[@"record"] = sourceRecord;
  }
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : nil;
  if (author) {
    NSMutableDictionary *mutableAuthor = [author mutableCopy];
    NSDictionary *viewerSource = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
    NSMutableDictionary *viewer = [viewerSource mutableCopy];
    if ([reason isEqualToString:@"blocked-by"]) viewer[@"blockedBy"] = @YES;
    else viewer[@"blocking"] = @YES;
    mutableAuthor[@"viewer"] = viewer;
    source[@"author"] = mutableAuthor;
  }
  NSMutableDictionary *tombstone = [[self tombstonePostFromSource:source fallbackType:@"app.bsky.feed.defs#blockedPost"] mutableCopy];
  if (source[@"record"]) tombstone[@"record"] = source[@"record"];
  return tombstone;
}

+ (NSDictionary *)postOrTombstoneFromThreadNode:(NSDictionary *)threadNode {
  return [self postOrTombstoneFromThreadNode:threadNode hiddenAuthorReasons:@{}];
}

+ (NSDictionary *)postOrTombstoneFromThreadNode:(NSDictionary *)threadNode hiddenAuthorReasons:(NSDictionary *)hiddenAuthorReasons {
  if (![threadNode isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *post = [threadNode[@"post"] isKindOfClass:NSDictionary.class] ? threadNode[@"post"] : nil;
  if (post.count > 0) {
    NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
    NSString *did = NFBClientStringValue(author[@"did"]);
    NSString *reason = did.length > 0 ? NFBClientStringValue(hiddenAuthorReasons[did]) : @"";
    if (reason.length > 0) return [self tombstonePostFromPost:post reason:reason];
    return post;
  }
  NSString *type = NFBClientStringValue(threadNode[@"$type"]);
  if ([self typeStringIndicatesBlueskyTombstone:type] ||
      [threadNode[@"notFound"] respondsToSelector:@selector(boolValue)] ||
      [threadNode[@"blocked"] respondsToSelector:@selector(boolValue)] ||
      [threadNode[@"detached"] respondsToSelector:@selector(boolValue)]) {
    return [self tombstonePostFromSource:threadNode fallbackType:type];
  }
  return nil;
}

+ (void)appendParentPostsFromThread:(id)threadNode toArray:(NSMutableArray *)posts {
  [self appendParentPostsFromThread:threadNode toArray:posts hiddenAuthorReasons:@{}];
}

+ (void)appendParentPostsFromThread:(id)threadNode toArray:(NSMutableArray *)posts hiddenAuthorReasons:(NSDictionary *)hiddenAuthorReasons {
  if (![threadNode isKindOfClass:NSDictionary.class]) return;
  NSDictionary *thread = threadNode;
  [self appendParentPostsFromThread:thread[@"parent"] toArray:posts hiddenAuthorReasons:hiddenAuthorReasons];
  NSDictionary *post = [self postOrTombstoneFromThreadNode:thread hiddenAuthorReasons:hiddenAuthorReasons];
  if (post) [posts addObject:@{@"post": post}];
}

+ (NSString *)hiddenReasonForPostAuthor:(NSDictionary *)author {
  NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
  if ([viewer[@"blockedBy"] isKindOfClass:NSString.class] && [viewer[@"blockedBy"] length] > 0) return @"blocked-by";
  if ([viewer[@"blockedBy"] respondsToSelector:@selector(boolValue)] && [viewer[@"blockedBy"] boolValue]) return @"blocked-by";
  if ([viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0) return @"blocked";
  if ([viewer[@"blocking"] respondsToSelector:@selector(boolValue)] && [viewer[@"blocking"] boolValue]) return @"blocked";
  if ([viewer[@"blockingByList"] isKindOfClass:NSDictionary.class]) return @"blocked";
  return @"";
}

+ (void)collectHiddenAuthorReasonsFromThreadNode:(id)threadNode intoDictionary:(NSMutableDictionary *)reasons {
  if (![threadNode isKindOfClass:NSDictionary.class]) return;
  NSDictionary *thread = threadNode;
  NSDictionary *post = [thread[@"post"] isKindOfClass:NSDictionary.class] ? thread[@"post"] : nil;
  NSDictionary *author = nil;
  NSString *reason = @"";
  if (post.count > 0) {
    author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : nil;
    reason = [self hiddenReasonForPostAuthor:author ?: @{}];
  } else if ([thread[@"author"] isKindOfClass:NSDictionary.class]) {
    author = thread[@"author"];
    reason = [self hiddenReasonForPostAuthor:author ?: @{}];
    if (reason.length == 0 && [thread[@"blocked"] respondsToSelector:@selector(boolValue)] && [thread[@"blocked"] boolValue]) reason = @"blocked";
  }
  NSString *did = NFBClientStringValue(author[@"did"]);
  if (did.length > 0 && reason.length > 0) {
    NSString *existing = NFBClientStringValue(reasons[did]);
    if (existing.length == 0 || [reason isEqualToString:@"blocked-by"]) reasons[did] = reason;
  }
  [self collectHiddenAuthorReasonsFromThreadNode:thread[@"parent"] intoDictionary:reasons];
  NSArray *replies = [thread[@"replies"] isKindOfClass:NSArray.class] ? thread[@"replies"] : @[];
  for (id reply in replies) [self collectHiddenAuthorReasonsFromThreadNode:reply intoDictionary:reasons];
}

+ (NSString *)createdAtStringForThreadPost:(NSDictionary *)post {
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  NSString *createdAt = NFBClientStringValue(record[@"createdAt"]);
  if (createdAt.length > 0) return createdAt;
  return NFBClientStringValue(post[@"indexedAt"]);
}


+ (NSString *)stableIDForPost:(NSDictionary *)post {
  NSString *source = [post[@"uri"] isKindOfClass:[NSString class]] ? post[@"uri"] : nil;
  if (source.length == 0) source = [post[@"cid"] isKindOfClass:[NSString class]] ? post[@"cid"] : post.description;
  uint64_t hash = 1469598103934665603ULL;
  NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  const unsigned char *bytes = data.bytes;
  for (NSUInteger i = 0; i < data.length; i++) {
    hash ^= bytes[i];
    hash *= 1099511628211ULL;
  }
  return [NSString stringWithFormat:@"%llu", (unsigned long long)(hash & 0x7fffffffffffffffULL)];
}


+ (NSString *)displayNameForProfile:(NSDictionary *)profile {
  NSString *displayName = [profile[@"displayName"] isKindOfClass:[NSString class]] ? profile[@"displayName"] : @"";
  NSString *handle = [self displayHandleForProfile:profile];
  return displayName.length > 0 ? displayName : handle;
}

+ (NSString *)canonicalHandleForProfile:(NSDictionary *)profile {
  NSString *handle = [profile[@"handle"] isKindOfClass:[NSString class]] ? profile[@"handle"] : @"";
  return handle.length > 0 ? handle : @"unknown.bsky.social";
}

+ (NSString *)displayHandleForProfile:(NSDictionary *)profile {
  NSString *handle = [self canonicalHandleForProfile:profile];
  BOOL hideSuffix = [NSUserDefaults.standardUserDefaults boolForKey:@"bh_hide_bsky_social_suffix"];
  if (hideSuffix && [handle.lowercaseString hasSuffix:@".bsky.social"]) {
    return [handle substringToIndex:handle.length - @".bsky.social".length];
  }
  return handle;
}

+ (NSString *)handleForProfile:(NSDictionary *)profile {
  return [self displayHandleForProfile:profile];
}

+ (NSString *)avatarURLForProfile:(NSDictionary *)profile {
  return [profile[@"avatar"] isKindOfClass:[NSString class]] ? profile[@"avatar"] : @"";
}

+ (NSString *)textForPost:(NSDictionary *)post {
  NSDictionary *record = [post[@"record"] isKindOfClass:[NSDictionary class]] ? post[@"record"] : @{};
  return [record[@"text"] isKindOfClass:[NSString class]] ? record[@"text"] : @"";
}

+ (NSString *)mediaURLForPost:(NSDictionary *)post {
  NSDictionary *first = [self mediaItemsForPost:post].firstObject;
  NSString *thumb = [first[@"thumbnailURL"] isKindOfClass:[NSString class]] ? first[@"thumbnailURL"] : @"";
  if (thumb.length > 0) return thumb;
  NSString *fullsize = [first[@"fullsizeURL"] isKindOfClass:[NSString class]] ? first[@"fullsizeURL"] : @"";
  return fullsize ?: @"";
}

+ (NSArray<NSDictionary *> *)mediaItemsForPost:(NSDictionary *)post {
  NSDictionary *embed = [post[@"embed"] isKindOfClass:[NSDictionary class]] ? post[@"embed"] : @{};
  NSArray *items = [self mediaItemsFromEmbed:embed];
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  NSDictionary *media = [record[@"embed"] isKindOfClass:NSDictionary.class] ? record[@"embed"] : @{};
  if ([media[@"media"] isKindOfClass:NSDictionary.class]) media = media[@"media"];
  if ([media[@"presentation"] isEqual:@"gif"] && items.count == 1 && [items[0][@"type"] isEqual:@"video"]) {
    NSMutableDictionary *item = [items[0] mutableCopy]; item[@"type"] = @"gif"; return @[item];
  }
  return items;
}

+ (NSDictionary *)externalCardForPost:(NSDictionary *)post {
  NSDictionary *embed = [post[@"embed"] isKindOfClass:[NSDictionary class]] ? post[@"embed"] : @{};
  NSDictionary *card = [self externalCardFromEmbed:embed];
  if ([post[@"__nfbLinkedPost"] isKindOfClass:NSDictionary.class]) {
    NSDictionary *link = NFBPostLink(card[@"url"]);
    if ([link[@"uri"] isEqual:post[@"__nfbLinkedPostURI"]]) return nil;
  }
  return card;
}

+ (NSDictionary *)externalCardFromEmbed:(NSDictionary *)embed {
  if (![embed isKindOfClass:[NSDictionary class]] || embed.count == 0) return nil;

  NSDictionary *media = [embed[@"media"] isKindOfClass:[NSDictionary class]] ? embed[@"media"] : nil;
  if (media.count > 0) {
    NSDictionary *mediaCard = [self externalCardFromEmbed:media];
    if (mediaCard.count > 0) return mediaCard;
  }

  NSDictionary *external = [embed[@"external"] isKindOfClass:[NSDictionary class]] ? embed[@"external"] : nil;
  if (external.count == 0) return nil;

  NSString *uri = [external[@"uri"] isKindOfClass:[NSString class]] ? external[@"uri"] : @"";
  NSString *title = [external[@"title"] isKindOfClass:[NSString class]] ? external[@"title"] : @"";
  NSString *description = [external[@"description"] isKindOfClass:[NSString class]] ? external[@"description"] : @"";
  NSString *thumb = [external[@"thumb"] isKindOfClass:[NSString class]] ? external[@"thumb"] : @"";
  if ([self GIFPlaybackForExternalURL:uri]) return nil;
  if (uri.length == 0 && title.length == 0 && description.length == 0 && thumb.length == 0) return nil;

  NSMutableDictionary *card = [NSMutableDictionary dictionary];
  card[@"url"] = uri;
  card[@"title"] = title.length > 0 ? title : uri;
  card[@"description"] = description;
  card[@"thumbnailURL"] = thumb;
  card[@"domain"] = [self hostnameForURLString:uri];

  NSString *createdAt = [external[@"createdAt"] isKindOfClass:[NSString class]] ? external[@"createdAt"] : @"";
  NSString *updatedAt = [external[@"updatedAt"] isKindOfClass:[NSString class]] ? external[@"updatedAt"] : @"";
  if (createdAt.length > 0) card[@"createdAt"] = createdAt;
  if (updatedAt.length > 0) card[@"updatedAt"] = updatedAt;

  NSNumber *readingTime = [external[@"readingTime"] respondsToSelector:@selector(integerValue)] ? external[@"readingTime"] : nil;
  if (readingTime.integerValue > 0) card[@"readingTime"] = @(MAX(1, readingTime.integerValue));

  NSDictionary *source = [external[@"source"] isKindOfClass:[NSDictionary class]] ? external[@"source"] : nil;
  if (source.count > 0) {
    NSMutableDictionary *sourceCard = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"uri", @"title", @"description", @"icon"]) {
      NSString *value = [source[key] isKindOfClass:[NSString class]] ? source[key] : @"";
      if (value.length > 0) sourceCard[key] = value;
    }
    NSDictionary *theme = [source[@"theme"] isKindOfClass:[NSDictionary class]] ? source[@"theme"] : nil;
    if (theme.count > 0) sourceCard[@"theme"] = theme;
    if (sourceCard.count > 0) card[@"source"] = sourceCard;
  }

  NSArray *associatedRefs = [external[@"associatedRefs"] isKindOfClass:[NSArray class]] ? external[@"associatedRefs"] : nil;
  if (associatedRefs.count > 0) card[@"associatedRefs"] = associatedRefs;
  NSArray *associatedProfiles = [external[@"associatedProfiles"] isKindOfClass:[NSArray class]] ? external[@"associatedProfiles"] : nil;
  if (associatedProfiles.count > 0) card[@"associatedProfiles"] = associatedProfiles;
  if ([self associatedRefsContainStandardSiteRecord:associatedRefs]) card[@"standardSite"] = @YES;
  return card;
}

+ (NSArray<NSDictionary *> *)mediaItemsFromEmbed:(NSDictionary *)embed {
  if (![embed isKindOfClass:[NSDictionary class]] || embed.count == 0) return @[];

  NSDictionary *media = [embed[@"media"] isKindOfClass:[NSDictionary class]] ? embed[@"media"] : nil;
  if (media.count > 0) return [self mediaItemsFromEmbed:media];

  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  BOOL gallery = [embed[@"$type"] isEqual:@"app.bsky.embed.gallery#view"];
  NSArray *images = [embed[gallery ? @"items" : @"images"] isKindOfClass:NSArray.class] ? embed[gallery ? @"items" : @"images"] : nil;
  for (id imageObject in images) {
    NSDictionary *image = [imageObject isKindOfClass:[NSDictionary class]] ? imageObject : nil;
    if (!image || (gallery && ![image[@"$type"] isEqual:@"app.bsky.embed.gallery#viewImage"])) continue;
    NSString *thumbKey = gallery ? @"thumbnail" : @"thumb";
    NSString *thumb = [image[thumbKey] isKindOfClass:NSString.class] ? image[thumbKey] : @"";
    NSString *fullsize = [image[@"fullsize"] isKindOfClass:[NSString class]] ? image[@"fullsize"] : @"";
    NSString *alt = [image[@"alt"] isKindOfClass:[NSString class]] ? image[@"alt"] : @"";
    NSString *type = [self urlLooksLikeGIF:thumb] || [self urlLooksLikeGIF:fullsize] ? @"gif" : @"photo";
    NSMutableDictionary *item = [@{
      @"type": type,
      @"thumbnailURL": thumb.length > 0 ? thumb : fullsize,
      @"fullsizeURL": fullsize.length > 0 ? fullsize : thumb,
      @"alt": alt
    } mutableCopy];
    NSDictionary *aspectRatio = [image[@"aspectRatio"] isKindOfClass:[NSDictionary class]] ? image[@"aspectRatio"] : nil;
    if (aspectRatio) item[@"aspectRatio"] = aspectRatio;
    if ([item[@"thumbnailURL"] length] > 0 || [item[@"fullsizeURL"] length] > 0) [items addObject:item];
  }
  if (items.count > 0) return items;

  NSString *embedType = [embed[@"$type"] isKindOfClass:[NSString class]] ? embed[@"$type"] : @"";
  NSString *playlist = [embed[@"playlist"] isKindOfClass:[NSString class]] ? embed[@"playlist"] : @"";
  NSString *thumbnail = [embed[@"thumbnail"] isKindOfClass:[NSString class]] ? embed[@"thumbnail"] : @"";
  if (thumbnail.length == 0) thumbnail = [embed[@"thumb"] isKindOfClass:[NSString class]] ? embed[@"thumb"] : @"";
  if (playlist.length > 0 || [embedType rangeOfString:@"video"].location != NSNotFound) {
    NSString *alt = [embed[@"alt"] isKindOfClass:[NSString class]] ? embed[@"alt"] : @"";
    NSMutableDictionary *item = [@{
      @"type": @"video",
      @"thumbnailURL": thumbnail ?: @"",
      @"fullsizeURL": thumbnail ?: @"",
      @"videoURL": playlist ?: @"",
      @"alt": alt
    } mutableCopy];
    NSDictionary *aspectRatio = [embed[@"aspectRatio"] isKindOfClass:[NSDictionary class]] ? embed[@"aspectRatio"] : nil;
    if (aspectRatio) item[@"aspectRatio"] = aspectRatio;
    return @[item];
  }

  NSDictionary *external = [embed[@"external"] isKindOfClass:[NSDictionary class]] ? embed[@"external"] : nil;
  NSString *externalThumb = [external[@"thumb"] isKindOfClass:[NSString class]] ? external[@"thumb"] : @"";
  if (external) {
    NSString *uri = [external[@"uri"] isKindOfClass:[NSString class]] ? external[@"uri"] : @"";
    NSString *title = [external[@"title"] isKindOfClass:[NSString class]] ? external[@"title"] : @"";
    NSDictionary *playback = [self GIFPlaybackForExternalURL:uri];
    if (playback) {
      NSMutableDictionary *item = [@{
        @"type": @"gif",
        @"thumbnailURL": externalThumb ?: @"",
        @"fullsizeURL": playback[@"imageURL"] ?: externalThumb ?: @"",
        @"externalURL": uri,
        @"videoURL": playback[@"videoURL"] ?: @"",
        @"alt": [playback[@"alt"] length] ? playback[@"alt"] : (title ?: @"")
      } mutableCopy];
      if (playback[@"aspectRatio"]) item[@"aspectRatio"] = playback[@"aspectRatio"];
      return @[item];
    }
  }

  return @[];
}

+ (NSDictionary *)GIFPlaybackForExternalURL:(NSString *)value {
  NSURLComponents *url = [NSURLComponents componentsWithString:value];
  if (![@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) return nil;
  NSString *host = url.host.lowercaseString, *ext = url.path.pathExtension.lowercaseString;
  BOOL provider = NO;
  for (NSString *domain in @[@"tenor.com", @"giphy.com", @"klipy.com", @"gifs.bsky.app"])
    if ([host isEqual:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) provider = YES;
  NSMutableDictionary *query = [NSMutableDictionary dictionary];
  for (NSURLQueryItem *q in url.queryItems) if (q.value) query[q.name] = q.value;
  NSString *playback = value;
  if ([host isEqual:@"media.tenor.com"] && [ext isEqual:@"gif"]) {
    // Same iOS-compatible MP4 route used by the web client, not the static card thumbnail.
    NSString *path = url.path;
    if ([path containsString:@"AAAAC"]) path = [[[path stringByReplacingOccurrencesOfString:@"AAAAC" withString:@"AAAP1"] stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"];
    playback = [@"https://t.gifs.bsky.app" stringByAppendingString:path];
    ext = path.pathExtension.lowercaseString;
  } else if (([host isEqual:@"giphy.com"] || [host hasSuffix:@".giphy.com"]) && ![@[@"gif", @"mp4", @"webp"] containsObject:ext]) {
    NSArray *parts = [url.path componentsSeparatedByString:@"/"];
    NSUInteger media = [parts indexOfObject:@"media"];
    NSString *identifier = media != NSNotFound && media + 1 < parts.count ? parts[media + 1] : url.path.lastPathComponent;
    identifier = [identifier componentsSeparatedByString:@"-"].lastObject;
    NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"];
    if (!identifier.length || [identifier rangeOfCharacterFromSet:valid.invertedSet].location != NSNotFound) return nil;
    playback = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.gif", identifier];
    ext = @"gif";
  }
  if (![ext isEqual:@"gif"] && !(provider && [@[@"mp4", @"webp"] containsObject:ext])) return nil;
  NSMutableDictionary *result = [@{[ext isEqual:@"mp4"] ? @"videoURL" : @"imageURL": playback, @"alt": query[@"alt"] ?: @""} mutableCopy];
  NSInteger width = [(query[@"ww"] ?: query[@"w"]) integerValue], height = [(query[@"hh"] ?: query[@"h"]) integerValue];
  if (width > 0 && height > 0) result[@"aspectRatio"] = @{@"width": @(width), @"height": @(height)};
  return result;
}

+ (NSString *)hostnameForURLString:(NSString *)urlString {
  if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) return @"";
  NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
  NSString *host = components.host ?: @"";
  if (host.length == 0) host = [NSURL URLWithString:urlString].host ?: @"";
  if ([host.lowercaseString hasPrefix:@"www."]) host = [host substringFromIndex:4];
  return host.lowercaseString ?: @"";
}

+ (BOOL)externalCardIsStandardSiteArticle:(NSDictionary *)card {
  if (![card isKindOfClass:NSDictionary.class] || card.count == 0) return NO;
  if ([card[@"standardSite"] respondsToSelector:@selector(boolValue)] && [card[@"standardSite"] boolValue]) return YES;
  if ([card[@"source"] isKindOfClass:NSDictionary.class] ||
      [card[@"readingTime"] respondsToSelector:@selector(integerValue)] ||
      ([card[@"createdAt"] isKindOfClass:NSString.class] && [card[@"createdAt"] length] > 0)) return YES;
  NSString *domain = [card[@"domain"] isKindOfClass:NSString.class] ? [card[@"domain"] lowercaseString] : @"";
  if ([domain isEqualToString:@"standard.site"] || [domain isEqualToString:@"www.standard.site"]) return YES;
  NSString *url = [card[@"url"] isKindOfClass:NSString.class] ? [card[@"url"] lowercaseString] : @"";
  if ([url hasPrefix:@"https://standard.site/"] || [url hasPrefix:@"http://standard.site/"] ||
      [url hasPrefix:@"https://www.standard.site/"] || [url hasPrefix:@"http://www.standard.site/"]) return YES;
  NSArray<NSString *> *uris = [self standardSiteAssociatedURIsForCard:card];
  for (NSString *uri in uris) {
    if ([uri rangeOfString:@"/site.standard."].location != NSNotFound) return YES;
  }
  return NO;
}

+ (NSArray<NSString *> *)standardSiteAssociatedURIsForCard:(NSDictionary *)card {
  if (![card isKindOfClass:NSDictionary.class]) return @[];
  NSArray *associatedRefs = [card[@"associatedRefs"] isKindOfClass:NSArray.class] ? card[@"associatedRefs"] : @[];
  NSMutableArray<NSString *> *uris = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  BOOL hasDocument = NO;
  for (NSDictionary *ref in associatedRefs) {
    if (![ref isKindOfClass:NSDictionary.class]) continue;
    NSString *uri = [ref[@"uri"] isKindOfClass:NSString.class] ? ref[@"uri"] : @"";
    if (uri.length == 0 || [seen containsObject:uri]) continue;
    if ([uri rangeOfString:@"/site.standard.document/"].location != NSNotFound) hasDocument = YES;
    [seen addObject:uri];
    [uris addObject:uri];
  }
  if (!hasDocument) return @[];
  [uris sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    BOOL ad = [a containsString:@"/site.standard.document/"];
    BOOL bd = [b containsString:@"/site.standard.document/"];
    return ad == bd ? NSOrderedSame : (ad ? NSOrderedAscending : NSOrderedDescending);
  }];
  if (uris.count <= 4) return [uris copy];
  return [uris subarrayWithRange:NSMakeRange(0, 4)];
}

+ (NSString *)standardSiteArticleCacheKeyForCard:(NSDictionary *)card {
  NSArray<NSString *> *uris = [self standardSiteAssociatedURIsForCard:card];
  if (uris.count == 0) return nil;
  NSArray<NSString *> *sortedURIs = [uris sortedArrayUsingSelector:@selector(compare:)];
  return [NSString stringWithFormat:@"%@|%@", NFBClientStringValue(card[@"url"]), [sortedURIs componentsJoinedByString:@"|"]];
}

+ (NSDictionary *)standardSiteDocumentRecordFromAssociatedRecords:(NSArray *)records {
  for (NSDictionary *record in records) {
    if (![record isKindOfClass:NSDictionary.class]) continue;
    NSString *type = [record[@"$type"] isKindOfClass:NSString.class] ? record[@"$type"] : @"";
    if ([type isEqualToString:@"site.standard.document"]) return record;
  }
  return nil;
}

+ (NSString *)recordString:(NSDictionary *)record key:(NSString *)key {
  NSString *value = [record[key] isKindOfClass:NSString.class] ? record[key] : @"";
  value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return value.length > 0 ? value : nil;
}

+ (NSArray<NSString *> *)standardSiteTagsFromRecord:(NSDictionary *)record {
  NSArray *rawTags = [record[@"tags"] isKindOfClass:NSArray.class] ? record[@"tags"] : @[];
  NSMutableArray<NSString *> *tags = [NSMutableArray array];
  for (NSString *tag in rawTags) {
    if (![tag isKindOfClass:NSString.class]) continue;
    NSString *trimmed = [tag stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 0) [tags addObject:trimmed];
  }
  return [tags copy];
}

+ (void)appendTextFromUnknownContent:(id)value depth:(NSUInteger)depth toArray:(NSMutableArray<NSString *> *)texts {
  if (depth > 5 || !value || value == NSNull.null) return;
  if ([value isKindOfClass:NSString.class]) {
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 0) [texts addObject:(NSString *)value];
    return;
  }
  if ([value isKindOfClass:NSArray.class]) {
    for (id item in (NSArray *)value) [self appendTextFromUnknownContent:item depth:depth + 1 toArray:texts];
    return;
  }
  if (![value isKindOfClass:NSDictionary.class]) return;
  NSDictionary *dictionary = (NSDictionary *)value;
  for (NSString *key in @[@"text", @"plainText", @"markdown", @"content", @"children", @"value"]) {
    [self appendTextFromUnknownContent:dictionary[key] depth:depth + 1 toArray:texts];
  }
}

+ (NSString *)standardSiteDocumentTextFromRecord:(NSDictionary *)record {
  if (![record isKindOfClass:NSDictionary.class]) return nil;
  NSString *text = [self recordString:record key:@"textContent"];
  if (text.length == 0) {
    NSMutableArray<NSString *> *textParts = [NSMutableArray array];
    [self appendTextFromUnknownContent:record[@"content"] depth:0 toArray:textParts];
    text = [textParts componentsJoinedByString:@"\n\n"];
  }
  if (text.length == 0) return nil;

  NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
  NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
  NSMutableArray<NSString *> *cleanLines = [NSMutableArray array];
  BOOL skippingComponentBlock = NO;
  for (NSString *line in lines) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (skippingComponentBlock) {
      if ([self string:trimmed matchesRegex:@"/>\\s*$"] || [self string:trimmed matchesRegex:@"^</[A-Z]"]) {
        skippingComponentBlock = NO;
      }
      continue;
    }

    if ([self string:trimmed matchesRegex:@"^import\\s"] || [self string:trimmed matchesRegex:@"^export\\s"]) continue;
    if ([self string:trimmed matchesRegex:@"^<[A-Z][\\w.:-]*(\\s|>|/>)"]) {
      if (![self string:trimmed matchesRegex:@"/>\\s*$"]) skippingComponentBlock = YES;
      continue;
    }

    [cleanLines addObject:[self stringByReplacingRegex:@"</?[^>]+>" inString:line withString:@""]];
  }

  NSString *cleaned = [cleanLines componentsJoinedByString:@"\n"];
  cleaned = [self stringByReplacingRegex:@"[ \\t]+\\n" inString:cleaned withString:@"\n"];
  cleaned = [self stringByReplacingRegex:@"\\n{3,}" inString:cleaned withString:@"\n\n"];
  cleaned = [cleaned stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  cleaned = [self standardSiteTextByRemovingReaderPreamble:cleaned];
  return cleaned.length > 0 ? cleaned : nil;
}

+ (NSString *)standardSiteTextByRemovingReaderPreamble:(NSString *)text {
  if (![text isKindOfClass:NSString.class] || text.length == 0) return @"";
  NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
  NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
  NSUInteger scanLimit = MIN(lines.count, (NSUInteger)12);
  BOOL sawTitle = NO;
  BOOL sawURLSource = NO;

  for (NSUInteger index = 0; index < scanLimit; index++) {
    NSString *line = [lines[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([self string:line matchesRegex:@"(?i)^title:\\s+"]) sawTitle = YES;
    if ([self string:line matchesRegex:@"(?i)^url source:\\s+"]) sawURLSource = YES;
    if ([self string:line matchesRegex:@"(?i)^markdown content:\\s*$"] && sawTitle && sawURLSource) {
      NSArray<NSString *> *bodyLines = index + 1 < lines.count ? [lines subarrayWithRange:NSMakeRange(index + 1, lines.count - index - 1)] : @[];
      NSString *body = [bodyLines componentsJoinedByString:@"\n"];
      return [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
  }

  return [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)standardSiteArticleExcerptFromText:(NSString *)text maxLength:(NSUInteger)maxLength {
  if (![text isKindOfClass:NSString.class] || text.length == 0) return @"";
  NSString *normalized = [self standardSiteTextByRemovingReaderPreamble:text];
  normalized = [self stringByReplacingRegex:@"\\s+" inString:normalized withString:@" "];
  normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (normalized.length <= maxLength) return normalized;
  NSString *excerpt = [normalized substringToIndex:MIN(maxLength, normalized.length)];
  excerpt = [self stringByReplacingRegex:@"\\s+\\S*$" inString:excerpt withString:@""];
  excerpt = [excerpt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return [excerpt stringByAppendingString:@"..."];
}

+ (NSString *)stringByReplacingRegex:(NSString *)pattern inString:(NSString *)string withString:(NSString *)replacement {
  if (string.length == 0 || pattern.length == 0) return string ?: @"";
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error || !regex) return string;
  NSRange range = NSMakeRange(0, string.length);
  return [regex stringByReplacingMatchesInString:string options:0 range:range withTemplate:replacement ?: @""];
}

+ (BOOL)string:(NSString *)string matchesRegex:(NSString *)pattern {
  if (string.length == 0 || pattern.length == 0) return NO;
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error || !regex) return NO;
  return [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)] != nil;
}

+ (BOOL)associatedRefsContainStandardSiteRecord:(NSArray *)refs {
  for (NSDictionary *ref in refs) {
    if (![ref isKindOfClass:NSDictionary.class]) continue;
    NSString *uri = [ref[@"uri"] isKindOfClass:NSString.class] ? ref[@"uri"] : @"";
    if ([uri rangeOfString:@"/site.standard."].location != NSNotFound) return YES;
  }
  return NO;
}

+ (NSDictionary *)quotedPostForPost:(NSDictionary *)post {
  NSDictionary *linked = [post[@"__nfbLinkedPost"] isKindOfClass:NSDictionary.class] ? post[@"__nfbLinkedPost"] : nil;
  NSDictionary *embed = [post[@"embed"] isKindOfClass:[NSDictionary class]] ? post[@"embed"] : @{};
  NSDictionary *recordEmbed = [embed[@"record"] isKindOfClass:[NSDictionary class]] ? embed[@"record"] : nil;
  NSDictionary *record = nil;
  if ([recordEmbed[@"record"] isKindOfClass:[NSDictionary class]]) {
    record = recordEmbed[@"record"];
  } else if (recordEmbed.count > 0) {
    record = recordEmbed;
  }
  if (![record isKindOfClass:[NSDictionary class]] || record.count == 0) return linked;
  return [self postFromRecordView:record];
}

+ (NSDictionary *)postFromRecordView:(NSDictionary *)record {
  NSString *type = [record[@"$type"] isKindOfClass:[NSString class]] ? record[@"$type"] : @"";
  if ([self typeStringIndicatesBlueskyTombstone:type] ||
      [record[@"notFound"] respondsToSelector:@selector(boolValue)] ||
      [record[@"blocked"] respondsToSelector:@selector(boolValue)] ||
      [record[@"detached"] respondsToSelector:@selector(boolValue)]) {
    NSMutableDictionary *tombstone = [[self tombstonePostFromSource:record fallbackType:(type.length > 0 ? type : @"app.bsky.embed.record#viewNotFound")] mutableCopy];
    if (tombstone.count == 0) return nil;
    NSDictionary *author = [record[@"author"] isKindOfClass:[NSDictionary class]] ? record[@"author"] : nil;
    if (author) tombstone[@"author"] = author;
    return tombstone;
  }

  NSMutableDictionary *post = [NSMutableDictionary dictionary];
  for (NSString *key in @[@"uri", @"cid", @"replyCount", @"repostCount", @"likeCount", @"quoteCount", @"indexedAt"]) {
    id value = record[key];
    if (value) post[key] = value;
  }
  NSDictionary *author = [record[@"author"] isKindOfClass:[NSDictionary class]] ? record[@"author"] : nil;
  if (author) post[@"author"] = author;

  NSDictionary *value = [record[@"value"] isKindOfClass:[NSDictionary class]] ? record[@"value"] : nil;
  NSDictionary *rawRecord = [record[@"record"] isKindOfClass:[NSDictionary class]] ? record[@"record"] : nil;
  if (value) post[@"record"] = value;
  else if (rawRecord) post[@"record"] = rawRecord;
  else post[@"record"] = record;

  NSDictionary *embed = [record[@"embed"] isKindOfClass:[NSDictionary class]] ? record[@"embed"] : nil;
  NSArray *embeds = [record[@"embeds"] isKindOfClass:[NSArray class]] ? record[@"embeds"] : nil;
  if (!embed && [embeds.firstObject isKindOfClass:[NSDictionary class]]) embed = embeds.firstObject;
  if (embed) post[@"embed"] = embed;
  return post;
}

+ (BOOL)urlLooksLikeGIF:(NSString *)urlString {
  if (![urlString isKindOfClass:[NSString class]]) return NO;
  NSString *lower = urlString.lowercaseString;
  return [lower containsString:@".gif"] || [lower containsString:@"format=gif"] || [lower containsString:@"image/gif"];
}

+ (BOOL)stringLooksLikeGIFProvider:(NSString *)string {
  if (![string isKindOfClass:[NSString class]]) return NO;
  NSString *lower = string.lowercaseString;
  return [lower containsString:@"giphy"] || [lower containsString:@"tenor"] || [lower containsString:@"gif"];
}

+ (NSString *)relativeTimeForPost:(NSDictionary *)post {
  NSDictionary *record = [post[@"record"] isKindOfClass:[NSDictionary class]] ? post[@"record"] : @{};
  NSString *dateString = [record[@"createdAt"] isKindOfClass:[NSString class]] ? record[@"createdAt"] : nil;
  if (dateString.length == 0) dateString = [post[@"indexedAt"] isKindOfClass:[NSString class]] ? post[@"indexedAt"] : nil;
  NSDate *date = [self dateFromISOString:dateString];
  if (!date) return @"now";

  NSTimeInterval seconds = fabs([date timeIntervalSinceNow]);
  if (seconds < 60) return @"now";
  if (seconds < 3600) return [NSString stringWithFormat:@"%lum", (unsigned long)(seconds / 60.0)];
  if (seconds < 86400) return [NSString stringWithFormat:@"%luh", (unsigned long)(seconds / 3600.0)];
  if (seconds < 604800) return [NSString stringWithFormat:@"%lud", (unsigned long)(seconds / 86400.0)];

  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateFormat = @"MMM d";
  return [formatter stringFromDate:date];
}

+ (NSString *)reasonTextForFeedItem:(NSDictionary *)item {
  if (NFBFeedReposter(item)) return NFBRepostContextText(item, [NFBAtprotoSession sharedSession].did);
  NSString *reason = [item[@"reason"] isKindOfClass:[NSString class]] ? item[@"reason"] : @"";
  NSDictionary *post = [self postFromFeedItem:item];
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  BOOL targetIsReply = [record[@"reply"] isKindOfClass:NSDictionary.class];
  if ([reason isEqualToString:@"like"]) return targetIsReply ? @"Liked your reply" : @"Liked your Tweet";
  if ([reason isEqualToString:@"repost"]) return targetIsReply ? @"Retweeted your reply" : @"Retweeted your Tweet";
  if ([reason isEqualToString:@"follow"]) return @"Followed you";
  if ([reason isEqualToString:@"reply"]) {
    NSString *replyTarget = [self replyTargetTextForFeedItem:item];
    return replyTarget.length > 0 ? [NSString stringWithFormat:@"Replied to %@", replyTarget] : @"Replied to you";
  }
  if ([reason isEqualToString:@"quote"]) return targetIsReply ? @"Quoted your reply" : @"Quoted your Tweet";
  if ([reason isEqualToString:@"mention"]) return @"Mentioned you";
  if ([reason isEqualToString:@"pinned"]) return @"Pinned Tweet";
  if ([reason isEqualToString:@"subscribed-post"]) {
    if (targetIsReply) {
      NSString *replyTarget = [self replyTargetTextForFeedItem:item];
      return replyTarget.length > 0 ? [NSString stringWithFormat:@"Replied to %@", replyTarget] : @"Replied";
    }
    return @"Tweeted";
  }
  if ([reason isEqualToString:@"starterpack-joined"]) return @"Joined from your Starter Pack";
  return reason.length > 0 ? reason : @"";
}

+ (BOOL)isProfileVerified:(NSDictionary *)profile {
  NSDictionary *verification = [profile[@"verification"] isKindOfClass:[NSDictionary class]] ? profile[@"verification"] : nil;
  if (!verification) return NO;
  if ([self isPositiveVerificationFlag:verification[@"verifiedStatus"]]) return YES;
  if ([self isPositiveVerificationFlag:verification[@"trustedVerifierStatus"]]) return YES;
  NSArray *records = [verification[@"verifications"] isKindOfClass:[NSArray class]] ? verification[@"verifications"] : nil;
  for (id record in records) {
    if ([self hasVerificationRecordCheckmark:record]) return YES;
  }
  return NO;
}

+ (BOOL)hasVerificationRecordCheckmark:(id)record {
  if (![record isKindOfClass:[NSDictionary class]]) return NO;
  NSDictionary *dictionary = record;
  id valid = dictionary[@"isValid"];
  if ([valid isKindOfClass:[NSNumber class]] && ![(NSNumber *)valid boolValue]) return NO;
  if ([self isPositiveVerificationFlag:valid]) return YES;
  NSArray *statuses = @[dictionary[@"status"] ?: [NSNull null],
                        dictionary[@"verifiedStatus"] ?: [NSNull null],
                        dictionary[@"trustedVerifierStatus"] ?: [NSNull null]];
  for (id status in statuses) {
    if ([self isPositiveVerificationFlag:status]) return YES;
  }
  for (id status in statuses) {
    if ([self isAbsentVerificationStatus:status]) return NO;
  }
  return YES;
}

+ (BOOL)isPositiveVerificationFlag:(id)value {
  if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value boolValue];
  if (![value isKindOfClass:[NSString class]]) return NO;
  NSString *lower = [(NSString *)value lowercaseString];
  return [lower isEqualToString:@"valid"] || [lower isEqualToString:@"verified"];
}

+ (BOOL)isAbsentVerificationStatus:(id)value {
  if (![value isKindOfClass:[NSString class]]) return NO;
  NSString *lower = [(NSString *)value lowercaseString];
  return [@[@"invalid", @"none", @"unverified", @"not_verified"] containsObject:lower];
}

+ (NSDate *)dateFromISOString:(NSString *)dateString {
  if (dateString.length == 0) return nil;
  static NSDateFormatter *millisecondsFormatter = nil;
  static NSDateFormatter *secondsFormatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    millisecondsFormatter = [[NSDateFormatter alloc] init];
    millisecondsFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    millisecondsFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    millisecondsFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

    secondsFormatter = [[NSDateFormatter alloc] init];
    secondsFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    secondsFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    secondsFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  });
  return [millisecondsFormatter dateFromString:dateString] ?: [secondsFormatter dateFromString:dateString];
}

+ (NSString *)isoDateNow {
  static NSDateFormatter *formatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  });
  return [formatter stringFromDate:[NSDate date]];
}

@end
