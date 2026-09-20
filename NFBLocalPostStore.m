#import "NFBLocalPostStore.h"

#import <UIKit/UIKit.h>

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"

NSString * const NFBLocalPostStoreDidChangeNotification = @"NFBLocalPostStoreDidChangeNotification";

static NSString * const NFBLocalPostKindDraft = @"draft";
static NSString * const NFBLocalPostKindScheduled = @"scheduled";

@interface NFBLocalPostStore ()
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation NFBLocalPostStore

+ (instancetype)sharedStore {
  static NFBLocalPostStore *store = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    store = [[NFBLocalPostStore alloc] init];
  });
  return store;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _queue = dispatch_queue_create("com.nottwitter.local-post-store", DISPATCH_QUEUE_SERIAL);
    [self ensureStorageDirectories];
  }
  return self;
}

- (NSArray<NSDictionary *> *)draftPosts {
  return [self postsWithKind:NFBLocalPostKindDraft];
}

- (NSArray<NSDictionary *> *)scheduledPosts {
  return [self postsWithKind:NFBLocalPostKindScheduled];
}

- (NSArray<NSDictionary *> *)draftPostsForAccountDID:(NSString *)did { return [self postsWithKind:NFBLocalPostKindDraft accountDID:did]; }
- (NSArray<NSDictionary *> *)scheduledPostsForAccountDID:(NSString *)did { return [self postsWithKind:NFBLocalPostKindScheduled accountDID:did]; }

- (NSDictionary *)saveDraftText:(NSString *)text
	                      replyGate:(NSString *)replyGate
	                     mediaItems:(NSArray<NSDictionary *> *)mediaItems {
  return [self saveDraftText:text replyGate:replyGate mediaItems:mediaItems threadTexts:nil];
}

- (NSDictionary *)saveDraftText:(NSString *)text
	                      replyGate:(NSString *)replyGate
	                     mediaItems:(NSArray<NSDictionary *> *)mediaItems
	                    threadTexts:(NSArray<NSString *> *)threadTexts {
  return [self savePostWithKind:NFBLocalPostKindDraft text:text replyGate:replyGate mediaItems:mediaItems threadTexts:threadTexts quotePost:nil scheduledDate:nil];
}

- (NSDictionary *)saveDraftText:(NSString *)text replyGate:(NSString *)replyGate mediaItems:(NSArray<NSDictionary *> *)mediaItems threadTexts:(NSArray<NSString *> *)threadTexts quotePost:(NSDictionary *)quotePost {
  return [self savePostWithKind:NFBLocalPostKindDraft text:text replyGate:replyGate mediaItems:mediaItems threadTexts:threadTexts quotePost:quotePost scheduledDate:nil];
}

- (NSDictionary *)saveScheduledPostText:(NSString *)text
	                              replyGate:(NSString *)replyGate
	                             mediaItems:(NSArray<NSDictionary *> *)mediaItems
	                          scheduledDate:(NSDate *)scheduledDate {
  return [self savePostWithKind:NFBLocalPostKindScheduled text:text replyGate:replyGate mediaItems:mediaItems threadTexts:nil quotePost:nil scheduledDate:scheduledDate ?: [NSDate dateWithTimeIntervalSinceNow:3600.0]];
}

- (NSDictionary *)saveDraftText:(NSString *)text replyGate:(NSString *)replyGate mediaItems:(NSArray<NSDictionary *> *)mediaItems threadPosts:(NSArray<NSDictionary *> *)threadPosts quotePost:(NSDictionary *)quotePost account:(NSDictionary *)account {
  return [self savePostWithKind:NFBLocalPostKindDraft text:text replyGate:replyGate mediaItems:mediaItems threadTexts:nil quotePost:quotePost scheduledDate:nil account:account threadPosts:threadPosts];
}

- (NSDictionary *)saveScheduledPostText:(NSString *)text replyGate:(NSString *)replyGate mediaItems:(NSArray<NSDictionary *> *)mediaItems scheduledDate:(NSDate *)date account:(NSDictionary *)account {
  return [self savePostWithKind:NFBLocalPostKindScheduled text:text replyGate:replyGate mediaItems:mediaItems threadTexts:nil quotePost:nil scheduledDate:date account:account threadPosts:nil];
}

- (NSDictionary *)savePostWithKind:(NSString *)kind text:(NSString *)text replyGate:(NSString *)replyGate mediaItems:(NSArray<NSDictionary *> *)mediaItems threadTexts:(NSArray<NSString *> *)threadTexts quotePost:(NSDictionary *)quotePost scheduledDate:(NSDate *)date {
  return [self savePostWithKind:kind text:text replyGate:replyGate mediaItems:mediaItems threadTexts:threadTexts quotePost:quotePost scheduledDate:date account:[NFBAtprotoSession sharedSession].currentAccountDictionary threadPosts:nil];
}

- (NSDictionary *)savePostWithKind:(NSString *)kind
	                              text:(NSString *)text
	                         replyGate:(NSString *)replyGate
	                        mediaItems:(NSArray<NSDictionary *> *)mediaItems
	                       threadTexts:(NSArray<NSString *> *)threadTexts
                             quotePost:(NSDictionary *)quotePost
	                     scheduledDate:(NSDate *)scheduledDate account:(NSDictionary *)account threadPosts:(NSArray<NSDictionary *> *)threadPosts {
  NSString *postID = NSUUID.UUID.UUIDString;
  NSMutableDictionary *post = [NSMutableDictionary dictionary];
  post[@"id"] = postID;
  post[@"kind"] = kind ?: NFBLocalPostKindDraft;
  post[@"text"] = text ?: @"";
  if (quotePost && [NSJSONSerialization isValidJSONObject:quotePost]) post[@"quotePost"] = quotePost;
  post[@"replyGate"] = replyGate ?: @"everyone";
  post[@"createdAt"] = @([[NSDate date] timeIntervalSince1970]);
  if (scheduledDate) post[@"scheduledAt"] = @([scheduledDate timeIntervalSince1970]);
  NSString *did = [account[@"did"] isKindOfClass:NSString.class] ? account[@"did"] : @"";
  NSString *handle = [account[@"handle"] isKindOfClass:NSString.class] ? account[@"handle"] : @"";
	  if (did.length > 0) post[@"accountDID"] = did;
	  if (handle.length > 0) post[@"accountHandle"] = handle;
	  NSMutableArray<NSString *> *storedThreadTexts = [NSMutableArray array];
	  for (id value in threadTexts ?: @[]) {
	    if ([value isKindOfClass:NSString.class]) [storedThreadTexts addObject:value];
	  }
	  if (storedThreadTexts.count > 0) post[@"threadTexts"] = storedThreadTexts;
	  post[@"mediaItems"] = [self storedMediaItemsFromMediaItems:mediaItems ?: @[] postID:postID];

  if (threadPosts.count) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *row in threadPosts) {
      NSString *rowID = [NSString stringWithFormat:@"%@-row-%lu", postID, (unsigned long)rows.count];
      [rows addObject:@{@"text":row[@"text"] ?: @"", @"mediaItems":[self storedMediaItemsFromMediaItems:row[@"mediaItems"] ?: @[] postID:rowID]}];
    }
    post[@"threadPosts"] = rows;
  }

  NSMutableArray<NSDictionary *> *items = [[self allPosts] mutableCopy];
  [items insertObject:post atIndex:0];
  [self writeAllPosts:items];
  [self postChangeNotification];
  return post;
}

- (NSArray<NSDictionary *> *)postsWithKind:(NSString *)kind {
  return [self postsWithKind:kind accountDID:[NFBAtprotoSession sharedSession].did];
}
- (NSArray<NSDictionary *> *)postsWithKind:(NSString *)kind accountDID:(NSString *)currentDID {
  NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
  for (NSDictionary *post in [self allPosts]) {
    if (![post[@"kind"] isEqualToString:kind]) continue;
    NSString *accountDID = [post[@"accountDID"] isKindOfClass:NSString.class] ? post[@"accountDID"] : @"";
    if (currentDID.length > 0 && accountDID.length > 0 && ![accountDID isEqualToString:currentDID]) continue;
    [filtered addObject:post];
  }
  return filtered;
}

- (NSArray<NSDictionary *> *)mediaItemsForLocalPost:(NSDictionary *)post {
  NSArray *storedItems = [post[@"mediaItems"] isKindOfClass:NSArray.class] ? post[@"mediaItems"] : @[];
  NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:storedItems.count];
  for (NSDictionary *stored in storedItems) {
    if (![stored isKindOfClass:NSDictionary.class]) continue;
    NSString *relativePath = [stored[@"mediaPath"] isKindOfClass:NSString.class] ? stored[@"mediaPath"] : @"";
    NSData *data = relativePath.length > 0 ? [NSData dataWithContentsOfURL:[[self storageDirectoryURL] URLByAppendingPathComponent:relativePath]] : nil;
    if (data.length == 0) continue;

    NSMutableDictionary *item = [stored mutableCopy];
    [item removeObjectForKey:@"mediaPath"];
    item[@"data"] = data;

    NSString *thumbnailPath = [stored[@"thumbnailPath"] isKindOfClass:NSString.class] ? stored[@"thumbnailPath"] : @"";
    NSData *thumbnailData = thumbnailPath.length > 0 ? [NSData dataWithContentsOfURL:[[self storageDirectoryURL] URLByAppendingPathComponent:thumbnailPath]] : nil;
    UIImage *image = thumbnailData.length > 0 ? [UIImage imageWithData:thumbnailData] : [UIImage imageWithData:data];
    if (image) item[@"image"] = image;
    [items addObject:item];
  }
  return items;
}

- (void)deleteLocalPostWithID:(NSString *)postID {
  if (postID.length == 0) return;
  NSMutableArray<NSDictionary *> *remaining = [NSMutableArray array];
  NSDictionary *removed = nil;
  for (NSDictionary *post in [self allPosts]) {
    NSString *candidateID = [post[@"id"] isKindOfClass:NSString.class] ? post[@"id"] : @"";
    if ([candidateID isEqualToString:postID]) {
      removed = post;
      continue;
    }
    [remaining addObject:post];
  }
  [self removeMediaForPost:removed];
  [self writeAllPosts:remaining];
  [self postChangeNotification];
}

- (void)processDueScheduledPostsWithCompletion:(NFBLocalPostStoreProcessCompletion)completion {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    if (completion) completion(0, 0);
    return;
  }
  NSString *currentDID = [NFBAtprotoSession sharedSession].currentAccountDictionary[@"did"];
  NSTimeInterval now = [NSDate date].timeIntervalSince1970;
  NSMutableArray<NSDictionary *> *due = [NSMutableArray array];
  for (NSDictionary *post in [self allPosts]) {
    if (![post[@"kind"] isEqualToString:NFBLocalPostKindScheduled]) continue;
    NSString *accountDID = [post[@"accountDID"] isKindOfClass:NSString.class] ? post[@"accountDID"] : @"";
    if (currentDID.length > 0 && accountDID.length > 0 && ![accountDID isEqualToString:currentDID]) continue;
    NSNumber *scheduledAt = [post[@"scheduledAt"] isKindOfClass:NSNumber.class] ? post[@"scheduledAt"] : nil;
    if (scheduledAt.doubleValue <= now) [due addObject:post];
  }
  [self processScheduledPosts:due index:0 posted:0 failed:0 completion:completion];
}

- (void)processScheduledPosts:(NSArray<NSDictionary *> *)posts
                        index:(NSUInteger)index
                       posted:(NSUInteger)posted
                       failed:(NSUInteger)failed
                   completion:(NFBLocalPostStoreProcessCompletion)completion {
  if (index >= posts.count) {
    if (completion) completion(posted, failed);
    if (posted > 0) [self postChangeNotification];
    return;
  }

  NSDictionary *post = posts[index];
  NSString *text = [post[@"text"] isKindOfClass:NSString.class] ? post[@"text"] : @"";
  NSString *replyGate = [post[@"replyGate"] isKindOfClass:NSString.class] ? post[@"replyGate"] : @"everyone";
  NSArray *mediaItems = [self mediaItemsForLocalPost:post];
  [[NFBAtprotoClient postingClientForAccountDID:post[@"accountDID"] ?: [NFBAtprotoSession sharedSession].did] createPostWithText:text
                                          replyToPost:nil
                                            quotePost:nil
                                           mediaItems:mediaItems
                                            replyGate:replyGate
                                           completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        [self markScheduledPost:post failedWithError:error.localizedDescription ?: @"Failed to send"];
        [self processScheduledPosts:posts index:index + 1 posted:posted failed:failed + 1 completion:completion];
      } else {
        NSString *postID = [post[@"id"] isKindOfClass:NSString.class] ? post[@"id"] : @"";
        [self deleteLocalPostWithID:postID];
        [self processScheduledPosts:posts index:index + 1 posted:posted + 1 failed:failed completion:completion];
      }
    });
  }];
}

- (NSArray<NSDictionary *> *)storedMediaItemsFromMediaItems:(NSArray<NSDictionary *> *)mediaItems postID:(NSString *)postID {
  if (mediaItems.count == 0) return @[];
  NSMutableArray<NSDictionary *> *stored = [NSMutableArray arrayWithCapacity:mediaItems.count];
  NSUInteger index = 0;
  for (NSDictionary *item in mediaItems) {
    NSData *data = [item[@"data"] isKindOfClass:NSData.class] ? item[@"data"] : nil;
    if (data.length == 0) continue;

    NSString *mimeType = [item[@"mimeType"] isKindOfClass:NSString.class] ? item[@"mimeType"] : @"application/octet-stream";
    NSString *extension = [self extensionForMIMEType:mimeType type:item[@"type"]];
    NSString *fileName = [NSString stringWithFormat:@"%@-%lu.%@", postID, (unsigned long)index, extension];
    NSURL *mediaURL = [[self mediaDirectoryURL] URLByAppendingPathComponent:fileName];
    [data writeToURL:mediaURL atomically:YES];

    NSMutableDictionary *storedItem = [NSMutableDictionary dictionary];
    storedItem[@"type"] = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"photo";
    storedItem[@"mimeType"] = mimeType;
    storedItem[@"width"] = [item[@"width"] isKindOfClass:NSNumber.class] ? item[@"width"] : @1;
    storedItem[@"height"] = [item[@"height"] isKindOfClass:NSNumber.class] ? item[@"height"] : @1;
    if ([item[@"duration"] isKindOfClass:NSNumber.class]) storedItem[@"duration"] = item[@"duration"];
    if ([item[@"alt"] isKindOfClass:NSString.class]) storedItem[@"alt"] = item[@"alt"];
    if ([item[@"contentWarnings"] isKindOfClass:NSArray.class]) storedItem[@"contentWarnings"] = item[@"contentWarnings"];
    storedItem[@"mediaPath"] = [@"Media" stringByAppendingPathComponent:fileName];

    UIImage *thumbnail = [item[@"image"] isKindOfClass:UIImage.class] ? item[@"image"] : nil;
    if (thumbnail) {
      NSData *thumbnailData = UIImageJPEGRepresentation(thumbnail, 0.72);
      if (thumbnailData.length > 0) {
        NSString *thumbnailName = [NSString stringWithFormat:@"%@-%lu-thumb.jpg", postID, (unsigned long)index];
        NSURL *thumbnailURL = [[self mediaDirectoryURL] URLByAppendingPathComponent:thumbnailName];
        [thumbnailData writeToURL:thumbnailURL atomically:YES];
        storedItem[@"thumbnailPath"] = [@"Media" stringByAppendingPathComponent:thumbnailName];
      }
    }
    [stored addObject:storedItem];
    index++;
  }
  return stored;
}

- (void)markScheduledPost:(NSDictionary *)post failedWithError:(NSString *)message {
  NSString *postID = [post[@"id"] isKindOfClass:NSString.class] ? post[@"id"] : @"";
  if (postID.length == 0) return;
  NSMutableArray<NSDictionary *> *items = [[self allPosts] mutableCopy];
  for (NSUInteger index = 0; index < items.count; index++) {
    NSDictionary *item = items[index];
    if (![item[@"id"] isEqualToString:postID]) continue;
    NSMutableDictionary *updated = [item mutableCopy];
    updated[@"lastError"] = message ?: @"Failed to send";
    items[index] = updated;
    break;
  }
  [self writeAllPosts:items];
  [self postChangeNotification];
}

- (void)removeMediaForPost:(NSDictionary *)post {
  for (NSDictionary *row in post[@"threadPosts"] ?: @[]) [self removeMediaForPost:row];
  NSArray *mediaItems = [post[@"mediaItems"] isKindOfClass:NSArray.class] ? post[@"mediaItems"] : @[];
  for (NSDictionary *item in mediaItems) {
    if (![item isKindOfClass:NSDictionary.class]) continue;
    for (NSString *key in @[@"mediaPath", @"thumbnailPath"]) {
      NSString *path = [item[key] isKindOfClass:NSString.class] ? item[key] : @"";
      if (path.length == 0) continue;
      [NSFileManager.defaultManager removeItemAtURL:[[self storageDirectoryURL] URLByAppendingPathComponent:path] error:nil];
    }
  }
}

- (NSString *)extensionForMIMEType:(NSString *)mimeType type:(NSString *)type {
  if ([mimeType isEqualToString:@"image/gif"]) return @"gif";
  if ([mimeType isEqualToString:@"image/png"]) return @"png";
  if ([mimeType isEqualToString:@"video/mp4"] || [type isEqualToString:@"video"]) return @"mp4";
  return @"jpg";
}

- (NSArray<NSDictionary *> *)allPosts {
  NSData *data = [NSData dataWithContentsOfURL:[self indexURL]];
  if (data.length == 0) return @[];
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [json isKindOfClass:NSArray.class] ? json : @[];
}

- (void)writeAllPosts:(NSArray<NSDictionary *> *)posts {
  [self ensureStorageDirectories];
  NSData *data = [NSJSONSerialization dataWithJSONObject:posts ?: @[] options:0 error:nil];
  [data writeToURL:[self indexURL] atomically:YES];
}

- (NSURL *)storageDirectoryURL {
  NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  return [base URLByAppendingPathComponent:@"NotTwitterLocalPosts" isDirectory:YES];
}

- (NSURL *)mediaDirectoryURL {
  return [[self storageDirectoryURL] URLByAppendingPathComponent:@"Media" isDirectory:YES];
}

- (NSURL *)indexURL {
  return [[self storageDirectoryURL] URLByAppendingPathComponent:@"posts.json"];
}

- (void)ensureStorageDirectories {
  [NSFileManager.defaultManager createDirectoryAtURL:[self mediaDirectoryURL] withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)postChangeNotification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:NFBLocalPostStoreDidChangeNotification object:self];
  });
}

@end
