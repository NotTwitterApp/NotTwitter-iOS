#pragma once
#include <math.h>

static inline double NFBChatPaginationPrefetchDistance(double viewportHeight) {
  return fmin(480.0, fmax(240.0, viewportHeight * 0.75));
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>

// Cursors are opaque and endpoint-specific. Empty/overlapping pages may advance,
// but a repeated cursor (including A -> B -> A) must never start a request loop.
static inline NSString *NFBChatNextPageCursor(NSString *requested, NSString *next, NSMutableSet<NSString *> *consumed) {
  if (requested.length > 0) [consumed addObject:requested];
  if (next.length == 0 || [next isEqualToString:requested] || [consumed containsObject:next]) return nil;
  return next;
}

static inline NSArray *NFBChatCacheSlice(NSArray *items, NSUInteger limit, BOOL newestAtEnd) {
  if (items.count <= limit) return items ?: @[];
  return [items subarrayWithRange:NSMakeRange(newestAtEnd ? items.count - limit : 0, limit)];
}
#endif
