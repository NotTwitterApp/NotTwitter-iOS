#import <Foundation/Foundation.h>

// Parse once per edit/page, then reuse the query for every saved post.
static inline NSDictionary *NFBParseBookmarkSearch(NSString *query) {
  NSMutableArray<NSString *> *authors = [NSMutableArray array];
  NSMutableArray<NSString *> *textParts = [NSMutableArray array];
  NSRegularExpression *tokens = [NSRegularExpression regularExpressionWithPattern:@"\"[^\"]*\"|\\S+" options:0 error:NULL];
  query = query ?: @"";
  for (NSTextCheckingResult *match in [tokens matchesInString:query options:0 range:NSMakeRange(0, query.length)]) {
    NSString *token = [query substringWithRange:match.range];
    if ([token.lowercaseString hasPrefix:@"from:"]) {
      NSString *author = [token substringFromIndex:5].lowercaseString;
      if ([author hasPrefix:@"@"]) author = [author substringFromIndex:1];
      // Short usernames refer to the default Bluesky domain, never a prefix match.
      if (author.length > 0 && [author rangeOfString:@"."].location == NSNotFound &&
          [author rangeOfString:@":"].location == NSNotFound) author = [author stringByAppendingString:@".bsky.social"];
      [authors addObject:author];
    } else {
      if (token.length >= 2 && [token hasPrefix:@"\""] && [token hasSuffix:@"\""]) {
        token = [token substringWithRange:NSMakeRange(1, token.length - 2)];
      }
      [textParts addObject:token];
    }
  }
  return @{@"authors": authors, @"text": [textParts componentsJoinedByString:@" "]};
}

static inline BOOL NFBBookmarkPostMatchesSearch(NSDictionary *post, NSDictionary *query) {
  NSArray<NSString *> *authors = [query objectForKey:@"authors"];
  if (authors.count > 0) {
    NSDictionary *author = [post objectForKey:@"author"];
    if (![author isKindOfClass:NSDictionary.class]) return NO;
    id handleValue = [author objectForKey:@"handle"], didValue = [author objectForKey:@"did"];
    NSString *handle = [handleValue isKindOfClass:NSString.class] ? [handleValue lowercaseString] : @"";
    NSString *did = [didValue isKindOfClass:NSString.class] ? [didValue lowercaseString] : @"";
    BOOL matchesAuthor = NO;
    for (NSString *candidate in authors) {
      if (candidate.length > 0 && ([candidate isEqualToString:handle] || [candidate isEqualToString:did])) {
        matchesAuthor = YES;
        break;
      }
    }
    if (!matchesAuthor) return NO;
  }
  NSString *searchText = [query objectForKey:@"text"];
  if (searchText.length == 0) return YES;
  NSDictionary *record = [post objectForKey:@"record"];
  if (![record isKindOfClass:NSDictionary.class]) return NO;
  NSString *text = [record objectForKey:@"text"];
  return [text isKindOfClass:NSString.class] &&
      [text rangeOfString:searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}
