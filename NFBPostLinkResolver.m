#import "NFBPostLinkResolver.h"
#import "NFBPostLink.h"

static NSDictionary *NFBDictionary(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSArray *NFBArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSString *NFBString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }

NSDictionary *NFBPostDisplayRecord(NSDictionary *post) {
  id display = [post objectForKey:@"__nfbLinkedPostDisplayRecord"];
  return NFBDictionary(display ?: [post objectForKey:@"record"]);
}

static NSDictionary *NFBRecordByHidingLinkedURL(NSDictionary *record, NSString *target) {
  NSString *text = NFBString([record objectForKey:@"text"]);
  NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableIndexSet *removed = [NSMutableIndexSet indexSet];
  for (id rawFacet in NFBArray([record objectForKey:@"facets"])) {
    NSDictionary *facet = NFBDictionary(rawFacet);
    BOOL matches = NO;
    for (id rawFeature in NFBArray([facet objectForKey:@"features"])) {
      NSDictionary *link = NFBPostLink(NFBString([NFBDictionary(rawFeature) objectForKey:@"uri"]));
      if ([[link objectForKey:@"uri"] isEqual:target]) matches = YES;
    }
    if (!matches) continue;
    NSDictionary *index = NFBDictionary([facet objectForKey:@"index"]);
    id startValue = [index objectForKey:@"byteStart"], endValue = [index objectForKey:@"byteEnd"];
    if (![startValue respondsToSelector:@selector(integerValue)] || ![endValue respondsToSelector:@selector(integerValue)]) continue;
    NSInteger start = [startValue integerValue], end = [endValue integerValue];
    if (start < 0 || end <= start || (NSUInteger)end > utf8.length) continue;
    // Reject malformed offsets that bisect a Unicode scalar.
    if (![[NSString alloc] initWithData:[utf8 subdataWithRange:NSMakeRange(0, (NSUInteger)start)] encoding:NSUTF8StringEncoding] ||
        ![[NSString alloc] initWithData:[utf8 subdataWithRange:NSMakeRange(0, (NSUInteger)end)] encoding:NSUTF8StringEncoding]) continue;
    [removed addIndexesInRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
  }
  for (NSString *token in NFBPostLinkTokens(text)) {
    if (![[NFBPostLink(token) objectForKey:@"uri"] isEqual:target]) continue;
    NSUInteger offset = 0;
    while (offset < text.length) {
      NSRange range = [text rangeOfString:token options:0 range:NSMakeRange(offset, text.length - offset)];
      if (range.location == NSNotFound) break;
      NSUInteger start = [[text substringToIndex:range.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
      [removed addIndexesInRange:NSMakeRange(start, [token lengthOfBytesUsingEncoding:NSUTF8StringEncoding])];
      offset = NSMaxRange(range);
    }
  }
  if (removed.count == 0) return record;
  // Trim newly exposed leading/trailing ASCII whitespace, without altering the
  // interior prose or invalidating UTF-8 facet byte offsets.
  const unsigned char *bytes = utf8.bytes;
  NSUInteger first = 0, last = utf8.length;
  while (first < last && ([removed containsIndex:first] || bytes[first] == ' ' || bytes[first] == '\n' || bytes[first] == '\r' || bytes[first] == '\t')) { [removed addIndex:first]; first++; }
  while (last > first && ([removed containsIndex:last - 1] || bytes[last - 1] == ' ' || bytes[last - 1] == '\n' || bytes[last - 1] == '\r' || bytes[last - 1] == '\t')) { last--; [removed addIndex:last]; }
  NSMutableData *remaining = [NSMutableData data];
  for (NSUInteger i = 0; i < utf8.length; i++) if (![removed containsIndex:i]) [remaining appendBytes:bytes + i length:1];
  NSString *display = [[NSString alloc] initWithData:remaining encoding:NSUTF8StringEncoding];
  if (!display) return record;
  NSMutableArray *facets = [NSMutableArray array];
  for (id rawFacet in NFBArray([record objectForKey:@"facets"])) {
    NSDictionary *facet = NFBDictionary(rawFacet), *index = NFBDictionary([facet objectForKey:@"index"]);
    id startValue = [index objectForKey:@"byteStart"], endValue = [index objectForKey:@"byteEnd"];
    if (![startValue respondsToSelector:@selector(integerValue)] || ![endValue respondsToSelector:@selector(integerValue)]) continue;
    NSInteger start = [startValue integerValue], end = [endValue integerValue];
    if (start < 0 || end <= start || (NSUInteger)end > utf8.length || [removed intersectsIndexesInRange:NSMakeRange(start, end - start)]) continue;
    NSUInteger shift = [removed countOfIndexesInRange:NSMakeRange(0, start)];
    NSMutableDictionary *next = [facet mutableCopy];
    [next setObject:@{@"byteStart": @((NSUInteger)start - shift), @"byteEnd": @((NSUInteger)end - shift)} forKey:@"index"];
    [facets addObject:next];
  }
  NSMutableDictionary *result = [record mutableCopy];
  [result setObject:display forKey:@"text"];
  [result setObject:facets forKey:@"facets"];
  return result;
}

static NSDictionary *NFBLinkedPostCandidate(NSDictionary *post) {
  NSDictionary *record = NFBDictionary([post objectForKey:@"record"]);
  if (!NFBDictionary([post objectForKey:@"author"]).count || !NFBString([post objectForKey:@"uri"]).length || !record.count) return nil;
  NSDictionary *embed = NFBDictionary([post objectForKey:@"embed"]);
  // Explicit quotes (including unavailable ones) have priority over text links.
  if (NFBDictionary([embed objectForKey:@"record"]).count || [post objectForKey:@"__nfbLinkedPost"]) return nil;
  NSMutableArray *urls = [NSMutableArray array];
  NSString *external = NFBString([NFBDictionary([embed objectForKey:@"external"]) objectForKey:@"uri"]);
  if (external.length) [urls addObject:external];
  for (id rawFacet in NFBArray([record objectForKey:@"facets"])) {
    for (id rawFeature in NFBArray([NFBDictionary(rawFacet) objectForKey:@"features"])) {
      NSString *uri = NFBString([NFBDictionary(rawFeature) objectForKey:@"uri"]);
      if (uri.length) [urls addObject:uri];
    }
  }
  [urls addObjectsFromArray:NFBPostLinkTokens(NFBString([record objectForKey:@"text"]))];
  for (NSString *url in urls) {
    NSDictionary *link = NFBPostLink(url);
    if (link && ![[link objectForKey:@"uri"] isEqual:[post objectForKey:@"uri"]]) return link;
  }
  return nil;
}

static void NFBCollectPostLinks(id value, NSMutableDictionary *links) {
  if ([value isKindOfClass:NSArray.class]) {
    for (id item in value) NFBCollectPostLinks(item, links);
  } else if ([value isKindOfClass:NSDictionary.class]) {
    NSDictionary *link = NFBLinkedPostCandidate(value);
    if (link) [links setObject:link forKey:[link objectForKey:@"uri"]];
    // Do not traverse user record contents, external metadata, or synthetic cards.
    for (NSString *key in value) {
      if ([@[@"record", @"embed", @"__nfbLinkedPost"] containsObject:key]) continue;
      NFBCollectPostLinks([value objectForKey:key], links);
    }
  }
}

static id NFBApplyLinkedPosts(id value, NSDictionary *resolved) {
  if ([value isKindOfClass:NSArray.class]) {
    NSMutableArray *items = [NSMutableArray array];
    for (id item in value) [items addObject:NFBApplyLinkedPosts(item, resolved)];
    return items;
  }
  if (![value isKindOfClass:NSDictionary.class]) return value;
  NSMutableDictionary *result = [value mutableCopy];
  NSDictionary *link = NFBLinkedPostCandidate(value);
  NSDictionary *post = [resolved objectForKey:[link objectForKey:@"uri"] ?: @""];
  if (post && ![[post objectForKey:@"uri"] isEqual:[value objectForKey:@"uri"]]) {
    [result setObject:post forKey:@"__nfbLinkedPost"];
    [result setObject:[link objectForKey:@"uri"] forKey:@"__nfbLinkedPostURI"];
    [result setObject:NFBRecordByHidingLinkedURL(NFBDictionary([value objectForKey:@"record"]), [link objectForKey:@"uri"]) forKey:@"__nfbLinkedPostDisplayRecord"];
  }
  for (NSString *key in value) {
    if ([@[@"record", @"embed", @"__nfbLinkedPost"] containsObject:key]) continue;
    [result setObject:NFBApplyLinkedPosts([value objectForKey:key], resolved) forKey:key];
  }
  return result;
}

@implementation NFBPostLinkResolver
+ (void)fetchValues:(NSArray *)values offset:(NSUInteger)offset method:(NSString *)method parameter:(NSString *)parameter resultKey:(NSString *)resultKey fetch:(NFBPostLinkFetch)fetch accumulated:(NSMutableArray *)accumulated completion:(void (^)(NSArray *))completion {
  if (offset >= values.count) { completion(accumulated); return; }
  NSUInteger count = MIN((NSUInteger)25, values.count - offset);
  NSArray *batch = [values subarrayWithRange:NSMakeRange(offset, count)];
  fetch(method, @{parameter: batch}, ^(NSDictionary *value, NSError *error) {
    if (!error) [accumulated addObjectsFromArray:NFBArray([value objectForKey:resultKey])];
    [self fetchValues:values offset:offset + count method:method parameter:parameter resultKey:resultKey fetch:fetch accumulated:accumulated completion:completion];
  });
}

+ (void)resolveValue:(id)value fetch:(NFBPostLinkFetch)fetch completion:(void (^)(id))completion {
  NSMutableDictionary *links = [NSMutableDictionary dictionary];
  NFBCollectPostLinks(value, links);
  if (links.count == 0) { completion(value); return; }
  NSMutableOrderedSet *handles = [NSMutableOrderedSet orderedSet];
  for (NSDictionary *link in links.allValues) {
    NSString *actor = [link objectForKey:@"actor"];
    if (![actor hasPrefix:@"did:"]) [handles addObject:actor];
  }
  [self fetchValues:handles.array offset:0 method:@"app.bsky.actor.getProfiles" parameter:@"actors" resultKey:@"profiles" fetch:fetch accumulated:[NSMutableArray array] completion:^(NSArray *profiles) {
    NSMutableDictionary *dids = [NSMutableDictionary dictionary];
    for (id item in profiles) {
      NSDictionary *profile = NFBDictionary(item);
      NSString *did = NFBString([profile objectForKey:@"did"]);
      NSString *handle = NFBString([profile objectForKey:@"handle"]).lowercaseString;
      if ([did hasPrefix:@"did:"] && handle.length) [dids setObject:did forKey:handle];
    }
    NSMutableDictionary *uris = [NSMutableDictionary dictionary];
    for (NSString *key in links) {
      NSDictionary *link = [links objectForKey:key];
      NSString *actor = [link objectForKey:@"actor"];
      NSString *did = [actor hasPrefix:@"did:"] ? actor : [dids objectForKey:actor];
      if (did.length) [uris setObject:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, [link objectForKey:@"rkey"]] forKey:key];
    }
    NSArray *uniqueURIs = [NSOrderedSet orderedSetWithArray:uris.allValues].array;
    [self fetchValues:uniqueURIs offset:0 method:@"app.bsky.feed.getPosts" parameter:@"uris" resultKey:@"posts" fetch:fetch accumulated:[NSMutableArray array] completion:^(NSArray *posts) {
      NSMutableDictionary *byURI = [NSMutableDictionary dictionary];
      for (id item in posts) {
        NSDictionary *post = NFBDictionary(item);
        NSString *uri = NFBString([post objectForKey:@"uri"]);
        NSDictionary *author = NFBDictionary([post objectForKey:@"author"]);
        NSDictionary *viewer = NFBDictionary([author objectForKey:@"viewer"]);
        if (!uri.length || !author.count || !NFBDictionary([post objectForKey:@"record"]).count ||
            [viewer objectForKey:@"blocking"] || [[viewer objectForKey:@"blockedBy"] boolValue]) continue;
        [byURI setObject:post forKey:uri];
      }
      NSMutableDictionary *resolved = [NSMutableDictionary dictionary];
      for (NSString *key in uris) {
        NSDictionary *post = [byURI objectForKey:[uris objectForKey:key]];
        if (post) [resolved setObject:post forKey:key];
      }
      completion(NFBApplyLinkedPosts(value, resolved));
    }];
  }];
}
@end
