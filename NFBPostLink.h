#pragma once
#import <Foundation/Foundation.h>

// These routes mirror the native share links and Not Twitter's routes.ts.
static inline NSDictionary *NFBPostLink(NSString *string) {
  if (![string isKindOfClass:NSString.class]) return nil;
  string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([[string lowercaseString] hasPrefix:@"www."]) string = [@"https://" stringByAppendingString:string];
  NSURLComponents *url = [NSURLComponents componentsWithString:string];
  NSString *actor = nil, *key = nil;
  NSMutableArray *parts = [NSMutableArray array];
  for (NSString *part in [url.path componentsSeparatedByString:@"/"]) if (part.length) [parts addObject:part];
  NSString *host = url.host.lowercaseString;
  if ([string hasPrefix:@"at://"]) {
    // NSURL treats DID colons as a port. Parse AT authority explicitly instead.
    NSString *rest = [string substringFromIndex:5];
    NSArray *record = [rest componentsSeparatedByString:@"/"];
    if (record.count != 3 || ![[record objectAtIndex:1] isEqual:@"app.bsky.feed.post"]) return nil;
    actor = [record objectAtIndex:0]; key = [record objectAtIndex:2];
  } else {
    if (![@[@"https", @"http"] containsObject:url.scheme.lowercaseString] || url.user.length || url.password.length) return nil;
    if (([host isEqual:@"bsky.app"] || [host isEqual:@"www.bsky.app"]) && parts.count == 4 && [[parts objectAtIndex:0] isEqual:@"profile"] && [[parts objectAtIndex:2] isEqual:@"post"]) {
      actor = [parts objectAtIndex:1]; key = [parts objectAtIndex:3];
    } else if ([host isEqual:@"nottwitterapp.github.io"] || [host isEqual:@"erickrouss.github.io"]) {
      if (parts.count && ([@[@"nottwitter", @"not-twitter"] containsObject:[parts objectAtIndex:0]])) [parts removeObjectAtIndex:0];
      NSString *encoded = nil;
      if (parts.count == 3 && [[parts objectAtIndex:1] isEqual:@"status"]) encoded = [parts objectAtIndex:2];
      if (parts.count == 2 && [[parts objectAtIndex:0] isEqual:@"tweet"]) encoded = [parts objectAtIndex:1];
      if (!encoded.length) return nil;
      encoded = [[encoded stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
      while (encoded.length % 4) encoded = [encoded stringByAppendingString:@"="];
      NSData *decoded = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
      NSString *uri = decoded ? [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] : nil;
      if (![uri hasPrefix:@"at://"]) return nil;
      NSArray *record = [[uri substringFromIndex:5] componentsSeparatedByString:@"/"];
      if (record.count != 3 || ![[record objectAtIndex:1] isEqual:@"app.bsky.feed.post"]) return nil;
      actor = [record objectAtIndex:0]; key = [record objectAtIndex:2];
    }
  }
  if (!actor.length || !key.length) return nil;
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~:-"];
  if ([key rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound || [@[@".", @".."] containsObject:key]) return nil;
  if ([actor rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound || [@[@".", @".."] containsObject:actor]) return nil;
  if (![actor hasPrefix:@"did:"]) actor = actor.lowercaseString;
  return @{@"actor": actor, @"rkey": key, @"url": [NSString stringWithFormat:@"https://bsky.app/profile/%@/post/%@", actor, key], @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", actor, key]};
}

static inline NSArray<NSString *> *NFBPostLinkTokens(NSString *text) {
  if (![text isKindOfClass:NSString.class] || text.length == 0) return @[];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\b(?:https?://|www\\.|at://)[^\\s<>()]+" options:0 error:NULL];
  NSMutableArray *tokens = [NSMutableArray array];
  NSCharacterSet *punctuation = [NSCharacterSet characterSetWithCharactersInString:@".,!?;:)]}"];
  for (NSTextCheckingResult *match in [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
    NSString *token = [text substringWithRange:match.range];
    while (token.length && [punctuation characterIsMember:[token characterAtIndex:token.length - 1]]) token = [token substringToIndex:token.length - 1];
    if (token.length) [tokens addObject:token];
  }
  return tokens;
}
