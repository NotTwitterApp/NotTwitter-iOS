#import "NFBRichText.h"
#import "NFBKnownTLDs.h"

static NSString *String(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }
static NSDictionary *Dictionary(id v) { return [v isKindOfClass:NSDictionary.class] ? v : @{}; }
static NSArray *Array(id v) { return [v isKindOfClass:NSArray.class] ? v : @[]; }
static NSRegularExpression *Regex(NSString *pattern) {
  static NSMutableDictionary *expressions;
  @synchronized(NSRegularExpression.class) {
    if (!expressions) expressions = [[NSMutableDictionary alloc] init];
    NSRegularExpression *regex = [expressions objectForKey:pattern];
    if (!regex) {
      regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
      if (regex) [expressions setObject:regex forKey:pattern];
    }
    return regex;
  }
}
static BOOL Overlaps(NSArray *spans, NSRange range) {
  for (NSDictionary *span in spans) if (NSIntersectionRange([[span objectForKey:@"range"] rangeValue], range).length) return YES;
  return NO;
}
static void Sort(NSMutableArray *spans) {
  [spans sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    NSUInteger x = [[a objectForKey:@"range"] rangeValue].location, y = [[b objectForKey:@"range"] rangeValue].location;
    return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
  }];
}
static BOOL ValidDomain(NSString *host) {
  static NSSet *tlds;
  @synchronized(NSSet.class) {
    if (!tlds) tlds = [[NSSet alloc] initWithArray:[NFBKnownTLDs componentsSeparatedByString:@" "]];
  }
  return [tlds containsObject:host.pathExtension.lowercaseString];
}
static NSRange TrimURL(NSString *text, NSRange range) {
  NSCharacterSet *punctuation = [NSCharacterSet characterSetWithCharactersInString:@".,!?;:\"'’”"];
  while (range.length) {
    unichar c = [text characterAtIndex:NSMaxRange(range) - 1];
    BOOL trim = [punctuation characterIsMember:c];
    if (c == ')' || c == ']') {
      unichar opening = c == ')' ? '(' : '[';
      NSInteger balance = 0;
      for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
        unichar current = [text characterAtIndex:i];
        if (current == opening) balance++;
        if (current == c) balance--;
      }
      trim = balance < 0;
    }
    if (!trim) break;
    range.length--;
  }
  return range;
}
static NSDictionary *Span(NSRange range, NSDictionary *feature) {
  return @{@"range": [NSValue valueWithRange:range], @"feature":feature};
}
static NSArray *Detect(NSString *text) {
  NSMutableArray *spans = [NSMutableArray array];
  // Email addresses and domain-shaped text inside handles are not URLs.
  NSString *pattern = @"(?i)(?<![\\p{L}\\p{N}_@#＃./:-])((?:https?://|www\\.)[^\\s<>\"“”]+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,63}(?::[0-9]+)?(?:[/?#][^\\s<>\"“”]*)?)(?![\\p{L}\\p{N}_-])";
  for (NSTextCheckingResult *match in [Regex(pattern) matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
    NSRange range = TrimURL(text, [match rangeAtIndex:1]);
    NSString *token = [text substringWithRange:range];
    BOOL explicit = [token.lowercaseString hasPrefix:@"https://"] || [token.lowercaseString hasPrefix:@"http://"];
    NSString *uri = explicit ? token : [@"https://" stringByAppendingString:token];
    NSURLComponents *url = [NSURLComponents componentsWithString:uri];
    if (!url.host.length || (!explicit && !ValidDomain(url.host))) continue;
    [spans addObject:Span(range, @{@"$type":@"app.bsky.richtext.facet#link", @"uri":uri})];
  }
  NSString *mentionPattern = @"(?i)(?:^|[\\s(])(@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?)(?![a-z0-9_.-]*[a-z0-9_-])";
  for (NSTextCheckingResult *match in [Regex(mentionPattern) matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
    NSRange range = [match rangeAtIndex:1];
    NSString *handle = [[text substringWithRange:NSMakeRange(range.location + 1, range.length - 1)] lowercaseString];
    if (handle.length > 253 || Overlaps(spans, range)) continue;
    [spans addObject:Span(range, @{@"$type":@"app.bsky.richtext.facet#mention", @"handle":handle})];
  }
  NSString *tagPattern = @"(?:^|\\s)[#＃]((?!\\x{FE0F})[^\\s\\x{00AD}\\x{2060}\\x{200A}-\\x{200D}\\x{20E2}]+)";
  for (NSTextCheckingResult *match in [Regex(tagPattern) matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
    NSRange range = [match rangeAtIndex:1];
    NSString *tag = [text substringWithRange:range];
    tag = [Regex(@"\\p{P}+$") stringByReplacingMatchesInString:tag options:0 range:NSMakeRange(0, tag.length) withTemplate:@""];
    if (![Regex(@"[^\\p{N}\\p{P}\\s]") firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)] || [tag lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 640) continue;
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < tag.length && count <= 64; count++) i = NSMaxRange([tag rangeOfComposedCharacterSequenceAtIndex:i]);
    range = NSMakeRange(range.location - 1, tag.length + 1);
    if (count > 64 || Overlaps(spans, range)) continue;
    [spans addObject:Span(range, @{@"$type":@"app.bsky.richtext.facet#tag", @"tag":tag})];
  }
  Sort(spans);
  return spans;
}
NSRange NFBRichTextRange(NSString *text, NSDictionary *index) {
  id start = [index objectForKey:@"byteStart"], end = [index objectForKey:@"byteEnd"];
  NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (![start isKindOfClass:NSNumber.class] || ![end isKindOfClass:NSNumber.class] ||
      [start doubleValue] != [start integerValue] || [end doubleValue] != [end integerValue] ||
      [start integerValue] < 0 || [end integerValue] <= [start integerValue] || [end unsignedIntegerValue] > bytes.length) return NSMakeRange(NSNotFound, 0);
  NSString *prefix = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(0, [start unsignedIntegerValue])] encoding:NSUTF8StringEncoding];
  NSString *token = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange([start unsignedIntegerValue], [end unsignedIntegerValue] - [start unsignedIntegerValue])] encoding:NSUTF8StringEncoding];
  return prefix && token ? NSMakeRange(prefix.length, token.length) : NSMakeRange(NSNotFound, 0);
}
NSArray<NSDictionary *> *NFBRichTextSpans(NSString *text, NSArray *facets) {
  text = String(text);
  NSMutableArray *spans = [NSMutableArray array];
  for (id raw in Array(facets)) {
    NSDictionary *facet = Dictionary(raw);
    NSRange range = NFBRichTextRange(text, Dictionary([facet objectForKey:@"index"]));
    if (range.location == NSNotFound || Overlaps(spans, range)) continue;
    for (id rawFeature in Array([facet objectForKey:@"features"])) {
      NSDictionary *feature = Dictionary(rawFeature);
      NSString *type = String([feature objectForKey:@"$type"]);
      BOOL valid = NO;
      if ([type isEqual:@"app.bsky.richtext.facet#link"]) {
        NSURLComponents *url = [NSURLComponents componentsWithString:String([feature objectForKey:@"uri"])];
        valid = url.host.length && [@[@"http", @"https"] containsObject:url.scheme.lowercaseString];
      } else if ([type isEqual:@"app.bsky.richtext.facet#mention"]) {
        valid = [String([feature objectForKey:@"did"]) hasPrefix:@"did:"];
      } else if ([type isEqual:@"app.bsky.richtext.facet#tag"]) valid = String([feature objectForKey:@"tag"]).length > 0;
      if (valid) { [spans addObject:Span(range, feature)]; break; }
    }
  }
  for (NSDictionary *span in Detect(text)) if (!Overlaps(spans, [[span objectForKey:@"range"] rangeValue])) [spans addObject:span];
  Sort(spans);
  return spans;
}
static NSDictionary *Facet(NSString *text, NSDictionary *span, NSDictionary *feature) {
  NSRange range = [[span objectForKey:@"range"] rangeValue];
  NSUInteger start = [[text substringToIndex:range.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  NSUInteger end = start + [[text substringWithRange:range] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  return @{@"index":@{@"byteStart":@(start), @"byteEnd":@(end)}, @"features":@[feature]};
}
NSArray<NSDictionary *> *NFBRichTextLocalFacets(NSString *text) {
  NSMutableArray *facets = [NSMutableArray array];
  for (NSDictionary *span in Detect(String(text))) {
    NSDictionary *feature = [span objectForKey:@"feature"];
    if (![feature objectForKey:@"handle"]) [facets addObject:Facet(text, span, feature)];
  }
  return facets;
}
static void ResolveNext(NSString *text, NSArray *spans, NSUInteger index, NSMutableDictionary *dids, NSMutableArray *facets, NFBResolveMention resolve, void (^completion)(NSArray *, NSError *)) {
  while (index < spans.count) {
    NSDictionary *span = [spans objectAtIndex:index], *feature = [span objectForKey:@"feature"];
    NSString *handle = [feature objectForKey:@"handle"], *did = handle ? [dids objectForKey:handle] : nil;
    if (handle && !did) {
      resolve(handle, ^(NSString *value, NSError *error) {
        if (error || ![String(value) hasPrefix:@"did:"]) {
          completion(nil, [NSError errorWithDomain:@"NFBRichText" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Could not resolve @%@. Check the handle or try sending again.",handle]}]);
          return;
        }
        [dids setObject:value forKey:handle];
        ResolveNext(text, spans, index, dids, facets, resolve, completion);
      });
      return;
    }
    if (handle) feature = @{@"$type":@"app.bsky.richtext.facet#mention", @"did":did};
    [facets addObject:Facet(text, span, feature)];
    index++;
  }
  completion([facets copy], nil);
}
void NFBRichTextResolve(NSString *text, NFBResolveMention resolve, void (^completion)(NSArray *, NSError *)) {
  NSString *snapshot = [String(text) copy];
  ResolveNext(snapshot, Detect(snapshot), 0, [NSMutableDictionary dictionary], [NSMutableArray array], resolve, completion);
}
