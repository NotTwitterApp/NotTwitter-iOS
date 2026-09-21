#import <Foundation/Foundation.h>

// Filter hydrated result views so account relationships and embeds, not text
// guesses, determine following/media membership. Quoted media isn't own media.
static inline BOOL NFBSearchResultMatches(NSDictionary *item, BOOL people, BOOL followingOnly, NSInteger mediaTab, BOOL hideSensitive, BOOL excludeMuted) {
  NSDictionary *post = [item[@"post"] isKindOfClass:NSDictionary.class] ? item[@"post"] : @{};
  NSDictionary *actor = people ? item : ([post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{});
  NSDictionary *viewer = [actor[@"viewer"] isKindOfClass:NSDictionary.class] ? actor[@"viewer"] : @{};
  if (followingOnly && !([viewer[@"following"] isKindOfClass:NSString.class] && [viewer[@"following"] length])) return NO;
  if (excludeMuted && ([viewer[@"muted"] boolValue] || [viewer[@"blockedBy"] boolValue] || [viewer[@"blocking"] length] || [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class] || [viewer[@"blockedByList"] isKindOfClass:NSDictionary.class])) return NO;
  if (hideSensitive) {
    NSSet *sensitive = [NSSet setWithArray:@[@"porn", @"sexual", @"nudity", @"graphic-media", @"!hide"]];
    for (NSDictionary *source in @[actor, post]) {
      NSArray *labels = [source[@"labels"] isKindOfClass:NSArray.class] ? source[@"labels"] : @[];
      for (id label in labels) {
        if ([label isKindOfClass:NSDictionary.class] && ![label[@"neg"] boolValue] && [sensitive containsObject:label[@"val"] ?: @""]) return NO;
      }
    }
  }
  if (!people && (mediaTab == 3 || mediaTab == 4)) {
    NSDictionary *embed = [post[@"embed"] isKindOfClass:NSDictionary.class] ? post[@"embed"] : @{};
    if ([embed[@"$type"] isEqualToString:@"app.bsky.embed.recordWithMedia#view"])
      embed = [embed[@"media"] isKindOfClass:NSDictionary.class] ? embed[@"media"] : @{};
    return mediaTab == 3 ? ([embed[@"$type"] isEqualToString:@"app.bsky.embed.images#view"] && [embed[@"images"] count] > 0) : [embed[@"$type"] isEqualToString:@"app.bsky.embed.video#view"];
  }
  return YES;
}
