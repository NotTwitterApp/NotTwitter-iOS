#import <Foundation/Foundation.h>

static inline NSArray<NSString *> *NFBSearchTokens(NSString *query) {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:[^\\s\\\"]|\\\"(?:[^\\\"\\\\]|\\\\.)*\\\")+" options:0 error:NULL];
  NSMutableArray *tokens = [NSMutableArray array];
  for (NSTextCheckingResult *match in [regex matchesInString:query ?: @"" options:0 range:NSMakeRange(0, query.length)]) [tokens addObject:[query substringWithRange:match.range]];
  return tokens;
}
static inline NSString *NFBSearchAccountIdentifier(NSString *value, NSString *viewerDID) {
  if ([value hasPrefix:@"@"]) value = [value substringFromIndex:1];
  if ([value.lowercaseString isEqualToString:@"me"] && viewerDID.length) return viewerDID;
  if (![value hasPrefix:@"did:"] && [value rangeOfString:@"."].location == NSNotFound) value = [value stringByAppendingString:@".bsky.social"];
  return value;
}
static inline NSDictionary *NFBSearchRequestParameters(NSString *query, NSString *sort, BOOL following, NSInteger mediaTab, NSString *viewerDID) {
  NSMutableDictionary *params = [@{@"limit":@50, @"sort":[sort isEqualToString:@"latest"] ? @"recent" : @"top", @"allTime":@"true"} mutableCopy];
  NSMutableArray *words = [NSMutableArray array];
  NSDictionary *arrays = @{@"from":@"authors", @"mentions":@"mentions", @"lang":@"languages", @"domain":@"domains", @"url":@"urls", @"tag":@"hashtags"};
  for (NSString *token in NFBSearchTokens(query)) {
    NSRange colon = [token rangeOfString:@":"];
    NSString *key = colon.location == NSNotFound ? @"" : [[token substringToIndex:colon.location] lowercaseString];
    NSString *value = colon.location == NSNotFound ? @"" : [token substringFromIndex:colon.location + 1];
    BOOL negative = [key hasPrefix:@"-"];
    NSString *positiveKey = negative ? [key substringFromIndex:1] : key;
    NSString *arrayKey = arrays[positiveKey];
    if (arrayKey && value.length && ![value hasPrefix:@"\""]) {
      if ([positiveKey isEqualToString:@"from"] || [positiveKey isEqualToString:@"mentions"]) value = NFBSearchAccountIdentifier(value, viewerDID);
      if ([positiveKey isEqualToString:@"tag"] && [value hasPrefix:@"#"]) value = [value substringFromIndex:1];
      if (negative) arrayKey = [@"exclude" stringByAppendingString:[arrayKey stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[arrayKey substringToIndex:1] uppercaseString]]];
      NSMutableArray *values = params[arrayKey]; if (!values) { values = [NSMutableArray array]; params[arrayKey] = values; }
      if (value.length) [values addObject:value];
    } else if (([key isEqualToString:@"since"] || [key isEqualToString:@"until"]) && value.length) params[key] = value;
    else if ([key isEqualToString:@"filter"] && [value isEqualToString:@"follows"]) params[@"following"] = @"true";
    else if ([key isEqualToString:@"filter"] && [value isEqualToString:@"links"]) { /* Match media or facet links after hydration. */ }
    else if ([key isEqualToString:@"filter"] && [value isEqualToString:@"media"]) params[@"hasMedia"] = @"true";
    else if ([key isEqualToString:@"filter"] && [value isEqualToString:@"videos"]) params[@"hasVideo"] = @"true";
    else if ([key isEqualToString:@"filter"] && [value isEqualToString:@"replies"]) params[@"repliesOnly"] = @"true";
    else if ([key isEqualToString:@"-filter"] && [value isEqualToString:@"replies"]) params[@"excludeReplies"] = @"true";
    else if ([@[@"min_faves", @"min_retweets", @"min_replies"] containsObject:key] && value.length && [value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) { /* Counts are checked on hydrated results. */ }
    else [words addObject:token];
  }
  if (words.count) params[@"query"] = [words componentsJoinedByString:@" "];
  // Local-only conditions still need a candidate query.
  if (params.count == 3) params[@"query"] = @"*";
  if (following) params[@"following"] = @"true";
  if (mediaTab == 3) params[@"hasMedia"] = @"true";
  if (mediaTab == 4) params[@"hasVideo"] = @"true";
  return params;
}
static inline BOOL NFBSearchCountsMatch(NSDictionary *post, NSString *query) {
  NSDictionary *keys = @{@"min_faves":@"likeCount", @"min_retweets":@"repostCount", @"min_replies":@"replyCount"};
  for (NSString *token in NFBSearchTokens(query)) {
    NSRange colon = [token rangeOfString:@":"]; if (colon.location == NSNotFound) continue;
    if ([token isEqualToString:@"filter:links"]) {
      NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
      BOOL hasLink = [post[@"embed"] isKindOfClass:NSDictionary.class];
      for (NSDictionary *facet in record[@"facets"]) for (NSDictionary *feature in facet[@"features"]) if ([feature[@"$type"] isEqualToString:@"app.bsky.richtext.facet#link"]) hasLink = YES;
      if (!hasLink) return NO;
    }
    NSString *key = [keys objectForKey:[[token substringToIndex:colon.location] lowercaseString]];
    NSString *value = [token substringFromIndex:colon.location + 1];
    if (key && value.length && [value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound && [post[key] longLongValue] < value.longLongValue) return NO;
  }
  return YES;
}
