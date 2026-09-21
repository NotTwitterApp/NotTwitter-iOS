#import <Foundation/Foundation.h>

static inline NSDictionary *NFBFeedReposter(NSDictionary *item) {
  NSDictionary *reason = [item objectForKey:@"reason"];
  if (![reason isKindOfClass:NSDictionary.class] ||
      ![[reason objectForKey:@"$type"] isEqual:@"app.bsky.feed.defs#reasonRepost"]) return nil;
  NSDictionary *author = [reason objectForKey:@"by"];
  return [author isKindOfClass:NSDictionary.class] ? author : nil;
}

static inline NSString *NFBRepostContextText(NSDictionary *item, NSString *viewerDID) {
  NSDictionary *author = NFBFeedReposter(item);
  if (!author) return @"";
  if (viewerDID.length > 0 && [[author objectForKey:@"did"] isEqual:viewerDID]) return @"You Retweeted";
  NSString *name = [author objectForKey:@"displayName"];
  if ([name isKindOfClass:NSString.class]) name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (![name isKindOfClass:NSString.class] || name.length == 0) name = [author objectForKey:@"handle"];
  return [name isKindOfClass:NSString.class] && name.length > 0 ? [NSString stringWithFormat:@"%@ Retweeted", name] : @"Retweeted";
}
