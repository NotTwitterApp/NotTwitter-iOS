#import "NFBThreadModel.h"
#import "NFBThreadLayout.h"

@interface NFBThreadModel ()
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *order;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *nodes;
@end

@implementation NFBThreadModel
- (instancetype)init {
  if ((self = [super init])) { _order = [NSMutableOrderedSet orderedSet]; _nodes = [NSMutableDictionary dictionary]; }
  return self;
}
- (void)mergeNodes:(NSArray<NSDictionary *> *)nodes {
  for (NSDictionary *node in nodes) {
    NSString *uri = node[@"post"][@"uri"];
    if (![uri isKindOfClass:NSString.class] || !uri.length) continue;
    NSDictionary *old = self.nodes[uri];
    NSMutableDictionary *merged = [old mutableCopy] ?: [NSMutableDictionary dictionary];
    [merged addEntriesFromDictionary:node];
    // An ancestor or a depth-boundary response has less information than an
    // already expanded branch; never erase that branch's known reply count.
    if (![node[@"childrenLoaded"] boolValue] && [old[@"childrenLoaded"] boolValue]) {
      merged[@"childrenLoaded"] = old[@"childrenLoaded"];
      merged[@"replyCount"] = old[@"replyCount"] ?: @0;
      merged[@"remainingReplies"] = old[@"remainingReplies"] ?: @0;
    }
    if (![merged[@"parentURI"] length] && [old[@"parentURI"] length]) merged[@"parentURI"] = old[@"parentURI"];
    self.nodes[uri] = merged;
    [self.order addObject:uri];
  }
}
- (NSUInteger)postCount { return self.nodes.count; }
- (void)markRepliesExhaustedForURI:(NSString *)uri {
  NSMutableDictionary *node = [self.nodes[uri] mutableCopy];
  if (node) { node[@"repliesExhausted"] = @YES; self.nodes[uri] = node; }
}
- (void)markAdditionalRepliesLoadedForURI:(NSString *)uri {
  NSMutableDictionary *node = [self.nodes[uri] mutableCopy];
  if (node) { node[@"hasOtherReplies"] = @NO; self.nodes[uri] = node; }
}
- (NSArray<NSDictionary *> *)displayItems {
  NSArray<NSString *> *uris = self.order.array;
  NSUInteger count = uris.count, anchor = [uris indexOfObject:self.anchorURI];
  if (!count || anchor == NSNotFound) return @[];
  NFBThreadNode *nodes = calloc(count, sizeof(NFBThreadNode));
  NFBThreadRow *rows = calloc(count * 2, sizeof(NFBThreadRow));
  if (!nodes || !rows) { free(nodes); free(rows); return @[]; }
  NSMutableDictionary *indices = [NSMutableDictionary dictionary];
  NSMutableDictionary *authors = [NSMutableDictionary dictionary];
  for (NSUInteger i = 0; i < count; i++) indices[uris[i]] = @(i);
  for (NSUInteger i = 0; i < count; i++) {
    NSDictionary *node = self.nodes[uris[i]], *post = node[@"post"];
    NSString *did = post[@"author"][@"did"];
    if ([did isKindOfClass:NSString.class] && did.length && !authors[did]) authors[did] = @(authors.count + 1);
    NSNumber *parent = indices[node[@"parentURI"] ?: @""];
    nodes[i].parent = parent ? parent.integerValue : -1;
    nodes[i].author = [did isKindOfClass:NSString.class] ? [authors[did] unsignedIntegerValue] : 0;
    nodes[i].unavailable = [node[@"unavailable"] boolValue];
    BOOL missing = ![node[@"repliesExhausted"] boolValue] && [node[@"remainingReplies"] unsignedIntegerValue] > 0;
    nodes[i].moreReplies = missing || [node[@"hasOtherReplies"] boolValue];
  }
  size_t length = NFBThreadBuildRows(nodes, count, anchor, rows);
  NSMutableArray *items = [NSMutableArray arrayWithCapacity:length];
  if (length) {
    NSDictionary *first = self.nodes[uris[rows[0].node]];
    NSString *missingParent = first[@"parentURI"];
    if (missingParent.length && !indices[missingParent]) [items addObject:@{@"post": @{@"uri": missingParent}, @"_nfbThreadRole": @"gap", @"_nfbExpandURI": missingParent, @"_nfbEarlierReplies": @YES}];
  }
  for (size_t i = 0; i < length; i++) {
    NFBThreadRow row = rows[i];
    NSDictionary *node = self.nodes[uris[row.node]];
    NSMutableDictionary *item = [@{@"post": node[@"post"], @"_nfbThreadRole": row.gap ? @"gap" : (row.ancestor ? @"parent" : (row.node == anchor ? @"focal" : (row.authorContinuation ? @"threadReply" : @"reply"))),
      @"_nfbUnavailable": @(nodes[row.node].unavailable), @"_nfbConnectorAbove": @(row.above), @"_nfbConnectorBelow": @(row.below)} mutableCopy];
    NSString *parentURI = node[@"parentURI"];
    NSDictionary *parentPost = self.nodes[parentURI ?: @""][@"post"];
    if (parentPost) item[@"reply"] = @{@"parent": parentPost};
    // The reference ships tweet_detail_conversation_context_removal=true.
    item[@"_nfbShowReplyContext"] = @NO;
    if (row.gap) {
      item[@"_nfbExpandURI"] = uris[row.node];
      item[@"_nfbAdditionalReplies"] = @([node[@"hasOtherReplies"] boolValue] && ([node[@"remainingReplies"] unsignedIntegerValue] == 0 || [node[@"repliesExhausted"] boolValue]));
    }
    [items addObject:item];
  }
  free(nodes); free(rows);
  return items;
}
@end
