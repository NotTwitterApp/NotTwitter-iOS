#import <Foundation/Foundation.h>

// Feed identity comes from the destination, never the trend's search label.
static inline NSDictionary *NFBFeedRouteFromString(NSString *link) {
  if (![link isKindOfClass:NSString.class] || link.length == 0) return nil;
  if ([link hasPrefix:@"profile/"]) link = [@"/" stringByAppendingString:link];
  NSURL *url = [NSURL URLWithString:link];
  if ([url.scheme isEqualToString:@"at"]) {
    NSArray *parts = [link componentsSeparatedByString:@"/"];
    if (parts.count == 5 && [parts[3] isEqualToString:@"app.bsky.feed.generator"] && [parts[2] length] && [parts[4] length])
      return @{@"actor": parts[2], @"rkey": parts[4]};
    return nil;
  }
  if (url.scheme.length && ![@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) return nil;
  if (url.host.length && ![@[@"bsky.app", @"nottwitterapp.github.io"] containsObject:url.host.lowercaseString]) return nil;
  NSArray *parts = [url.path componentsSeparatedByString:@"/"];
  if (parts.count != 5 || ![parts[1] isEqualToString:@"profile"] || ![parts[3] isEqualToString:@"feed"]) return nil;
  NSString *actor = [parts[2] stringByRemovingPercentEncoding];
  NSString *rkey = [parts[4] stringByRemovingPercentEncoding];
  if (!actor.length || !rkey.length || [actor containsString:@"/"] || [rkey containsString:@"/"]) return nil;
  return @{@"actor": actor, @"rkey": rkey};
}
