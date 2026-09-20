#import <Foundation/Foundation.h>

// Recognize only supported post routes; arbitrary links remain ordinary links.
static inline NSDictionary *NFBPostLink(NSString *string) {
  NSURLComponents *url = [NSURLComponents componentsWithString:string];
  if (![@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) return nil;
  NSString *host = url.host.lowercaseString;
  NSMutableArray *parts = [NSMutableArray array];
  for (NSString *part in [url.path componentsSeparatedByString:@"/"]) if (part.length) [parts addObject:part];
  NSString *actor = nil, *key = nil;
  if (([host isEqual:@"bsky.app"] || [host isEqual:@"www.bsky.app"]) && parts.count == 4 && [parts[0] isEqual:@"profile"] && [parts[2] isEqual:@"post"]) {
    actor = parts[1]; key = parts[3];
  } else if ([host isEqual:@"nottwitterapp.github.io"] || [host isEqual:@"erickrouss.github.io"]) {
    if (parts.count && ([parts[0] isEqual:@"nottwitter"] || [parts[0] isEqual:@"not-twitter"])) [parts removeObjectAtIndex:0];
    if (parts.count != 3 || ![parts[1] isEqual:@"status"]) return nil;
    NSString *encoded = [[parts[2] stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (encoded.length % 4) encoded = [encoded stringByAppendingString:@"="];
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (!decoded.length) return nil;
    NSString *uri = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    if (![uri hasPrefix:@"at://"]) return nil;
    NSArray *record = [[uri substringFromIndex:5] componentsSeparatedByString:@"/"];
    if (record.count != 3 || ![record[1] isEqual:@"app.bsky.feed.post"]) return nil;
    actor = record[0]; key = record[2];
  }
  if (!actor.length || !key.length) return nil;
  NSCharacterSet *recordCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~:-"];
  if ([key rangeOfCharacterFromSet:recordCharacters.invertedSet].location != NSNotFound || [@[@".", @".."] containsObject:key]) return nil;
  if ([actor rangeOfCharacterFromSet:recordCharacters.invertedSet].location != NSNotFound) return nil;
  return @{@"actor": actor, @"rkey": key, @"url": [NSString stringWithFormat:@"https://bsky.app/profile/%@/post/%@", actor, key]};
}
