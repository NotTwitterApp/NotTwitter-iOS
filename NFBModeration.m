#import "NFBModeration.h"

#import "NFBAtprotoSession.h"
#import "NFBTheme.h"

NSString * const NFBModerationPreferencesDidChangeNotification = @"NFBModerationPreferencesDidChangeNotification";
NSString * const NFBModerationTombstoneLearnMoreURLString = @"/help-center/articles/tweet-tombstones-and-notices";
NSString * const NFBModerationTombstoneRulesURLString = @"https://bsky.social/about/support/community-guidelines";

static NSString * const NFBModerationPreferencesCacheKey = @"nfb_moderation_preferences_cache";
static NSString * const NFBModerationPreferencesFetchedAtKey = @"nfb_moderation_preferences_fetched_at";
static NSString * const NFBModerationSettingsURLString = @"/settings";
static NSTimeInterval const NFBModerationPreferencesMaxAge = 300.0;

static BOOL NFBModerationFetchInFlight = NO;

static NSString *NFBModerationStringValue(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray<NSDictionary *> *NFBModerationCachedPreferences(void) {
  NSArray *raw = [NSUserDefaults.standardUserDefaults arrayForKey:NFBModerationPreferencesCacheKey];
  NSMutableArray *preferences = [NSMutableArray array];
  for (NSDictionary *item in raw) {
    if ([item isKindOfClass:NSDictionary.class]) [preferences addObject:item];
  }
  return preferences;
}

void NFBModerationCachePreferences(NSArray<NSDictionary *> *preferences) {
  if (!NSThread.isMainThread) {
    NSArray<NSDictionary *> *capturedPreferences = [preferences copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      NFBModerationCachePreferences(capturedPreferences);
    });
    return;
  }
  if (![preferences isKindOfClass:NSArray.class]) return;
  NSMutableArray *serializable = [NSMutableArray array];
  for (NSDictionary *preference in preferences) {
    if ([preference isKindOfClass:NSDictionary.class]) [serializable addObject:preference];
  }
  [NSUserDefaults.standardUserDefaults setObject:serializable forKey:NFBModerationPreferencesCacheKey];
  [NSUserDefaults.standardUserDefaults setDouble:NSDate.date.timeIntervalSince1970 forKey:NFBModerationPreferencesFetchedAtKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBModerationPreferencesDidChangeNotification object:nil];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

void NFBModerationRefreshPreferencesIfNeeded(void) {
  if (NFBModerationFetchInFlight) return;
  if (![[NFBAtprotoSession sharedSession] hasSession]) return;
  NSTimeInterval fetchedAt = [NSUserDefaults.standardUserDefaults doubleForKey:NFBModerationPreferencesFetchedAtKey];
  if (fetchedAt > 0.0 && NSDate.date.timeIntervalSince1970 - fetchedAt < NFBModerationPreferencesMaxAge) return;

  NFBModerationFetchInFlight = YES;
  [[NFBAtprotoSession sharedSession] xrpcGET:@"app.bsky.actor.getPreferences"
                                     service:nil
                                      params:nil
                               authenticated:YES
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    dispatch_async(dispatch_get_main_queue(), ^{
      NFBModerationFetchInFlight = NO;
      if (error || ![value isKindOfClass:NSDictionary.class] || ![value[@"preferences"] isKindOfClass:NSArray.class]) return;
      NFBModerationCachePreferences(value[@"preferences"]);
    });
  }];
}

static NSString *NFBModerationNormalizedVisibility(NSString *visibility) {
  NSString *lower = visibility.lowercaseString ?: @"";
  if ([lower isEqualToString:@"show"] || [lower isEqualToString:@"ignore"] || [lower isEqualToString:@"off"]) return @"ignore";
  if ([lower isEqualToString:@"hide"] || [lower isEqualToString:@"blur"] || [lower isEqualToString:@"block"]) return @"hide";
  return @"warn";
}

static NSDictionary<NSString *, NSString *> *NFBModerationDefaultVisibilities(void) {
  return @{
    @"porn": @"hide",
    @"sexual": @"warn",
    @"nudity": @"warn",
	    @"sexual-figurative": @"warn",
	    @"nsfw": @"warn",
	    @"adult": @"warn",
	    @"graphic-media": @"warn",
	    @"graphic": @"warn",
	    @"gore": @"warn",
	    @"violence": @"warn",
	    @"violent": @"warn",
	    @"graphic-violence": @"warn",
	    @"self-harm": @"warn",
	    @"sensitive": @"warn",
    @"politics": @"warn",
    @"political": @"warn",
    @"political-content": @"warn",
    @"conspiracy": @"warn",
    @"conspiracy-theory": @"warn",
    @"conspiracy-theories": @"warn",
    @"misinformation": @"warn",
    @"misleading": @"warn",
    @"rumor": @"warn",
    @"intolerant": @"warn",
    @"extremist": @"hide",
    @"threat": @"hide",
	    @"rude": @"hide",
	    @"hate": @"hide",
	    @"hate-speech": @"hide",
	    @"harassment": @"hide",
	    @"illicit": @"hide",
    @"security": @"hide",
    @"unsafe-link": @"hide",
    @"impersonation": @"hide",
    @"scam": @"hide",
    @"spam": @"hide",
    @"engagement-farming": @"hide",
    @"inauthentic": @"hide",
    @"!hide": @"hide",
    @"!takedown": @"hide",
    @"!warn": @"warn"
  };
}

static BOOL NFBModerationAdultContentEnabled(void) {
  for (NSDictionary *preference in NFBModerationCachedPreferences()) {
    if (![NFBModerationStringValue(preference[@"$type"]) isEqualToString:@"app.bsky.actor.defs#adultContentPref"]) continue;
    return [preference[@"enabled"] respondsToSelector:@selector(boolValue)] && [preference[@"enabled"] boolValue];
  }
  return NO;
}

static BOOL NFBModerationLabelIsAdult(NSString *label) {
  static NSSet *adultLabels = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    adultLabels = [NSSet setWithArray:@[@"porn", @"sexual", @"nudity", @"sexual-figurative"]];
  });
  return [adultLabels containsObject:label.lowercaseString ?: @""];
}

static BOOL NFBModerationLabelIsRuleViolationTombstone(NSString *label) {
  static NSSet *ruleViolationLabels = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    ruleViolationLabels = [NSSet setWithArray:@[
      @"extremist",
      @"intolerant",
      @"threat",
      @"illicit",
      @"security",
      @"unsafe-link",
      @"impersonation",
      @"misinformation",
      @"scam",
      @"engagement-farming",
      @"spam",
      @"rumor",
      @"misleading",
      @"inauthentic",
      @"!takedown"
    ]];
  });
  return [ruleViolationLabels containsObject:label.lowercaseString ?: @""];
}

static NSString *NFBModerationVisibilityForLabel(NSString *label, NSString *labelerDid) {
  NSString *normalizedLabel = label.lowercaseString ?: @"";
  NSString *normalizedLabeler = labelerDid ?: @"";
  if (normalizedLabel.length == 0) return @"ignore";
  if (NFBModerationLabelIsAdult(normalizedLabel) && !NFBModerationAdultContentEnabled()) return @"hide";

  for (NSDictionary *preference in NFBModerationCachedPreferences()) {
    if (![NFBModerationStringValue(preference[@"$type"]) isEqualToString:@"app.bsky.actor.defs#contentLabelPref"]) continue;
    NSString *candidateLabel = NFBModerationStringValue(preference[@"label"]).lowercaseString;
    if (![candidateLabel isEqualToString:normalizedLabel]) continue;
    NSString *candidateLabeler = NFBModerationStringValue(preference[@"labelerDid"]);
    if (candidateLabeler.length > 0 && normalizedLabeler.length > 0 && ![candidateLabeler isEqualToString:normalizedLabeler]) continue;
    return NFBModerationNormalizedVisibility(NFBModerationStringValue(preference[@"visibility"]));
  }

  NSString *defaultVisibility = NFBModerationDefaultVisibilities()[normalizedLabel];
  return defaultVisibility ?: @"ignore";
}

static NSString *NFBModerationDisplayNameForLabel(NSString *label) {
  NSDictionary *display = @{
    @"porn": @"Adult content",
    @"sexual": @"Sexual content",
    @"nudity": @"Nudity",
	    @"sexual-figurative": @"Suggestive content",
	    @"nsfw": @"Adult content",
	    @"adult": @"Adult content",
	    @"graphic-media": @"Graphic media",
	    @"graphic": @"Graphic media",
	    @"gore": @"Graphic violence",
	    @"violence": @"Violence",
	    @"violent": @"Violence",
	    @"graphic-violence": @"Graphic violence",
    @"self-harm": @"Self-harm",
    @"sensitive": @"Sensitive content",
    @"politics": @"Politics",
    @"political": @"Politics",
    @"political-content": @"Politics",
    @"conspiracy": @"Conspiracy theories",
    @"conspiracy-theory": @"Conspiracy theories",
    @"conspiracy-theories": @"Conspiracy theories",
    @"misinformation": @"Misinformation",
    @"misleading": @"Misleading content",
    @"rumor": @"Unconfirmed claim",
    @"extremist": @"Extremist content",
	    @"intolerant": @"Intolerance",
	    @"hate": @"Hateful conduct",
	    @"hate-speech": @"Hateful conduct",
	    @"harassment": @"Harassment",
	    @"threat": @"Threats",
    @"rude": @"Rude content",
    @"illicit": @"Illicit content",
    @"unsafe-link": @"Unsafe link",
    @"impersonation": @"Impersonation",
    @"scam": @"Scam",
    @"spam": @"Spam"
  };
  NSString *normalized = label.lowercaseString ?: @"";
  NSString *name = display[normalized];
  if (name.length > 0) return name;
  NSArray *parts = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]];
  NSMutableArray *words = [NSMutableArray array];
  for (NSString *part in parts) if (part.length > 0) [words addObject:part.capitalizedString];
  return words.count > 0 ? [words componentsJoinedByString:@" "] : @"Sensitive content";
}

static void NFBModerationAppendLabelsFromObject(id object, NSMutableArray<NSDictionary *> *labels) {
  if (![object isKindOfClass:NSDictionary.class]) return;
  NSDictionary *dictionary = object;
  NSArray *rawLabels = [dictionary[@"labels"] isKindOfClass:NSArray.class] ? dictionary[@"labels"] : @[];
  for (NSDictionary *label in rawLabels) {
    if (![label isKindOfClass:NSDictionary.class]) continue;
    if ([label[@"neg"] respondsToSelector:@selector(boolValue)] && [label[@"neg"] boolValue]) continue;
    NSString *value = NFBModerationStringValue(label[@"val"]);
    if (value.length == 0) value = NFBModerationStringValue(label[@"label"]);
    if (value.length == 0) value = NFBModerationStringValue(label[@"value"]);
    if (value.length == 0) continue;
    NSString *source = NFBModerationStringValue(label[@"src"]);
    [labels addObject:@{@"label": value.lowercaseString, @"labelerDid": source ?: @""}];
  }
}

static void NFBModerationAppendLabelsRecursivelyFromObject(id object, NSMutableArray<NSDictionary *> *labels, NSUInteger depth) {
  if (depth > 6 || !object) return;
  if ([object isKindOfClass:NSDictionary.class]) {
    NSDictionary *dictionary = object;
    NFBModerationAppendLabelsFromObject(dictionary, labels);
    for (id value in dictionary.allValues) {
      if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
        NFBModerationAppendLabelsRecursivelyFromObject(value, labels, depth + 1);
      }
    }
    return;
  }
  if ([object isKindOfClass:NSArray.class]) {
    for (id value in (NSArray *)object) {
      if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
        NFBModerationAppendLabelsRecursivelyFromObject(value, labels, depth + 1);
      }
    }
  }
}

static NSArray<NSDictionary *> *NFBModerationLabelsForPost(NSDictionary *post) {
  NSMutableArray *labels = [NSMutableArray array];
  NFBModerationAppendLabelsRecursivelyFromObject(post, labels, 0);
  return labels;
}

static NSDictionary *NFBModerationStrongestLabelDecision(NSDictionary *post) {
  NSArray<NSDictionary *> *labels = NFBModerationLabelsForPost(post ?: @{});
  NSString *warningLabel = nil;
  for (NSDictionary *label in labels) {
    NSString *value = NFBModerationStringValue(label[@"label"]);
    NSString *labelerDid = NFBModerationStringValue(label[@"labelerDid"]);
    NSString *visibility = NFBModerationVisibilityForLabel(value, labelerDid);
    if ([visibility isEqualToString:@"hide"]) {
      return @{@"visibility": @"hide", @"label": value, @"displayName": NFBModerationDisplayNameForLabel(value)};
    }
    if ([visibility isEqualToString:@"warn"] && warningLabel.length == 0) warningLabel = value;
  }
  if (warningLabel.length > 0) {
    return @{@"visibility": @"warn", @"label": warningLabel, @"displayName": NFBModerationDisplayNameForLabel(warningLabel)};
  }
  return @{};
}

static NSDictionary *NFBModerationTombstoneLink(NSString *text, NSString *urlString, BOOL strong) {
  if (text.length == 0 || urlString.length == 0) return @{};
  return @{@"text": text, @"url": urlString, @"strong": @(strong)};
}

static NSArray<NSDictionary *> *NFBModerationTombstoneLearnMoreLinks(BOOL strong) {
  return @[NFBModerationTombstoneLink(@"Learn more", NFBModerationTombstoneLearnMoreURLString, strong)];
}

static NSDictionary *NFBModerationTombstone(NSString *kind) {
  NSString *normalizedKind = kind.length > 0 ? kind : @"unavailable";
  NSString *message = nil;
  NSArray<NSDictionary *> *links = @[];

  if ([normalizedKind isEqualToString:@"limited-visibility"]) {
    message = @"You’re unable to view this Tweet because this account owner limits who can view their Tweets. Learn more";
    links = NFBModerationTombstoneLearnMoreLinks(NO);
  } else if ([normalizedKind isEqualToString:@"sensitive"]) {
    message = @"This Tweet may include sensitive content.";
  } else if ([normalizedKind isEqualToString:@"age-restricted"]) {
    message = @"Age-restricted adult content. This content might not be appropriate for people under 18 years old. Learn more";
    links = NFBModerationTombstoneLearnMoreLinks(YES);
  } else if ([normalizedKind isEqualToString:@"sensitive-media"]) {
    message = @"The following media includes potentially sensitive content. Change settings";
    links = @[NFBModerationTombstoneLink(@"Change settings", NFBModerationSettingsURLString, NO)];
  } else if ([normalizedKind isEqualToString:@"reported"]) {
    message = @"You reported this Tweet.";
  } else if ([normalizedKind isEqualToString:@"muted-account"]) {
    message = @"This Tweet is from an account you muted.";
  } else if ([normalizedKind isEqualToString:@"muted-word"]) {
    message = @"This Tweet includes a word you muted.";
  } else if ([normalizedKind isEqualToString:@"rules-violation"]) {
    message = @"This Tweet violated the Bluesky Community Guidelines. Learn more";
    links = @[
      NFBModerationTombstoneLink(@"Bluesky Community Guidelines", NFBModerationTombstoneRulesURLString, NO),
      NFBModerationTombstoneLink(@"Learn more", NFBModerationTombstoneLearnMoreURLString, NO)
    ];
  } else if ([normalizedKind isEqualToString:@"suspended"]) {
    message = @"This Tweet is from a suspended account. Learn more";
    links = NFBModerationTombstoneLearnMoreLinks(NO);
  } else if ([normalizedKind isEqualToString:@"withheld"]) {
    message = @"This Tweet from @username has been withheld in <country> based on local law(s). Learn more";
    links = NFBModerationTombstoneLearnMoreLinks(NO);
  } else if ([normalizedKind isEqualToString:@"no-longer-exists"]) {
    message = @"This Tweet is from an account that no longer exists. Learn more";
    links = NFBModerationTombstoneLearnMoreLinks(NO);
  } else {
    normalizedKind = @"unavailable";
    message = @"This Tweet is unavailable. Learn more";
    links = NFBModerationTombstoneLearnMoreLinks(NO);
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"title"] = message.length > 0 ? message : @"This Tweet is unavailable. Learn more";
  result[@"subtitle"] = @"";
  result[@"message"] = result[@"title"];
  result[@"links"] = links ?: @[];
  result[@"kind"] = normalizedKind;
  return result;
}

NSAttributedString *NFBModerationTombstoneAttributedString(NSDictionary *tombstone, UIFont *font) {
  NSString *message = NFBModerationStringValue(tombstone[@"message"]);
  if (message.length == 0) {
    NSString *title = NFBModerationStringValue(tombstone[@"title"]);
    NSString *subtitle = NFBModerationStringValue(tombstone[@"subtitle"]);
    if (title.length == 0) title = @"This Tweet is unavailable. Learn more";
    message = subtitle.length > 0 ? [NSString stringWithFormat:@"%@\n%@", title, subtitle] : title;
  }

  UIFont *resolvedFont = font ?: NFBFont(15.0, NFBFontWeightRegular);
  NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
  paragraph.lineBreakMode = NSLineBreakByWordWrapping;
  paragraph.alignment = NSTextAlignmentLeft;
  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:message attributes:@{
    NSFontAttributeName: resolvedFont,
    NSForegroundColorAttributeName: NFBColorSecondaryText(),
    NSParagraphStyleAttributeName: paragraph
  }];

  NSArray *links = [tombstone[@"links"] isKindOfClass:NSArray.class] ? tombstone[@"links"] : @[];
  for (NSDictionary *link in links) {
    if (![link isKindOfClass:NSDictionary.class]) continue;
    NSString *linkText = NFBModerationStringValue(link[@"text"]);
    NSString *urlString = NFBModerationStringValue(link[@"url"]);
    if (linkText.length == 0 || urlString.length == 0) continue;
    NSRange range = [message rangeOfString:linkText];
    if (range.location == NSNotFound || range.length == 0) continue;
    id linkValue = [NSURL URLWithString:urlString] ?: urlString;
    NSMutableDictionary *linkAttributes = [@{
      NSLinkAttributeName: linkValue,
      NSForegroundColorAttributeName: NFBColorAccent()
    } mutableCopy];
    if ([link[@"strong"] respondsToSelector:@selector(boolValue)] && [link[@"strong"] boolValue]) {
      linkAttributes[NSFontAttributeName] = NFBFont(resolvedFont.pointSize, NFBFontWeightBold);
    }
    [attributed addAttributes:linkAttributes range:range];
  }
  return attributed;
}

NSDictionary *NFBModerationTombstoneForFeedItem(NSDictionary *feedItem, NSDictionary *post) {
  NFBModerationRefreshPreferencesIfNeeded();
  NSDictionary *source = [feedItem isKindOfClass:NSDictionary.class] ? feedItem : @{};
  NSDictionary *candidatePost = [post isKindOfClass:NSDictionary.class] ? post : @{};
  NSString *rawType = NFBModerationStringValue(source[@"$type"]);
  if (rawType.length == 0) rawType = NFBModerationStringValue(candidatePost[@"$type"]);
  NSString *type = rawType.lowercaseString;
  NSString *moderationType = NFBModerationStringValue(candidatePost[@"_nfbModerationType"]).lowercaseString;
  NSDictionary *embed = [source[@"embed"] isKindOfClass:NSDictionary.class] ? source[@"embed"] : @{};
  NSString *embedType = NFBModerationStringValue(embed[@"$type"]).lowercaseString;
  NSString *combinedType = [NSString stringWithFormat:@"%@ %@ %@", type ?: @"", moderationType ?: @"", embedType ?: @""];
  if ([combinedType rangeOfString:@"notfound"].location != NSNotFound ||
      [combinedType rangeOfString:@"deleted"].location != NSNotFound) {
    return NFBModerationTombstone(@"unavailable");
  }
  if ([combinedType rangeOfString:@"detached"].location != NSNotFound) {
    return NFBModerationTombstone(@"unavailable");
  }
  if ([combinedType rangeOfString:@"takedown"].location != NSNotFound ||
      [combinedType rangeOfString:@"takendown"].location != NSNotFound) {
    return NFBModerationTombstone(@"rules-violation");
  }
  if ([combinedType rangeOfString:@"blockedauthor"].location != NSNotFound) {
    return NFBModerationTombstone(@"limited-visibility");
  }
  if ([combinedType rangeOfString:@"unsupported"].location != NSNotFound) {
    return NFBModerationTombstone(@"unavailable");
  }

  NSDictionary *author = [candidatePost[@"author"] isKindOfClass:NSDictionary.class] ? candidatePost[@"author"] : @{};
  NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
  if ([viewer[@"blocking"] isKindOfClass:NSString.class] || [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class]) {
    return NFBModerationTombstone(@"limited-visibility");
  }
  if ([viewer[@"blocking"] respondsToSelector:@selector(boolValue)] && [viewer[@"blocking"] boolValue]) {
    return NFBModerationTombstone(@"limited-visibility");
  }
  if ([viewer[@"blockedBy"] isKindOfClass:NSString.class] && [viewer[@"blockedBy"] length] > 0) {
    return NFBModerationTombstone(@"limited-visibility");
  }
  if ([viewer[@"blockedBy"] respondsToSelector:@selector(boolValue)] && [viewer[@"blockedBy"] boolValue]) {
    return NFBModerationTombstone(@"limited-visibility");
  }
  if ([combinedType rangeOfString:@"blocked"].location != NSNotFound) {
    return NFBModerationTombstone(@"limited-visibility");
  }
  if ([viewer[@"muted"] respondsToSelector:@selector(boolValue)] && [viewer[@"muted"] boolValue]) {
    return NFBModerationTombstone(@"muted-account");
  }

  NSDictionary *decision = NFBModerationStrongestLabelDecision(candidatePost);
  if ([NFBModerationStringValue(decision[@"visibility"]) isEqualToString:@"hide"]) {
    NSString *label = NFBModerationStringValue(decision[@"label"]);
    if (NFBModerationLabelIsAdult(label)) return NFBModerationTombstone(@"age-restricted");
    if (NFBModerationLabelIsRuleViolationTombstone(label)) return NFBModerationTombstone(@"rules-violation");
    return NFBModerationTombstone(@"sensitive");
  }
  NSString *status = NFBModerationStringValue(author[@"status"]).lowercaseString;
  if ([status rangeOfString:@"takedown"].location != NSNotFound ||
      [status rangeOfString:@"takendown"].location != NSNotFound) {
    return NFBModerationTombstone(@"rules-violation");
  }
  if ([status rangeOfString:@"suspend"].location != NSNotFound ||
      [status rangeOfString:@"banned"].location != NSNotFound ||
      [status rangeOfString:@"disabled"].location != NSNotFound) {
    return NFBModerationTombstone(@"suspended");
  }
  if ([status rangeOfString:@"deactiv"].location != NSNotFound ||
      [status rangeOfString:@"deleted"].location != NSNotFound) {
    return NFBModerationTombstone(@"no-longer-exists");
  }
  return nil;
}

NSDictionary *NFBModerationMediaWarningForPost(NSDictionary *post) {
  NFBModerationRefreshPreferencesIfNeeded();
  NSDictionary *decision = NFBModerationStrongestLabelDecision(post ?: @{});
  if (![NFBModerationStringValue(decision[@"visibility"]) isEqualToString:@"warn"]) return nil;
	  NSString *displayName = NFBModerationStringValue(decision[@"displayName"]);
	  return @{
	    @"title": [NSString stringWithFormat:@"Content warning: %@", displayName.length > 0 ? displayName : @"Sensitive content"],
	    @"subtitle": @"The Tweet author flagged this Tweet as showing sensitive content.",
	    @"action": @"Show"
	  };
	}

NSArray<NSDictionary *> *NFBModerationMediaItemsByApplyingWarnings(NSArray<NSDictionary *> *mediaItems, NSDictionary *post) {
  if (![mediaItems isKindOfClass:NSArray.class] || mediaItems.count == 0) return @[];
  NSDictionary *warning = NFBModerationMediaWarningForPost(post);
  if (warning.count == 0) return mediaItems;
  NSMutableArray *updated = [NSMutableArray arrayWithCapacity:mediaItems.count];
  for (NSDictionary *item in mediaItems) {
    if (![item isKindOfClass:NSDictionary.class]) continue;
    NSMutableDictionary *next = [item mutableCopy];
    next[@"moderationWarning"] = warning;
    [updated addObject:next];
  }
  return updated;
}
