#import "NFBPostLink.h"
#import "NFBChatPermission.h"
#import "NFBChatPagination.h"
#import "NFBMessagesViewController.h"

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBAccountAvatar.h"
#import "NFBComposeViewController.h"
#import "NFBLinkRouter.h"
#import "NFBMediaViewerViewController.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBNotificationCoordinator.h"
#import "NFBQuotedPostView.h"
#import "NFBSettingsViewController.h"
#import "NFBSideMenuViewController.h"
#import "NFBTheme.h"
#import "NFBTimelineViewController.h"
#import "NFBTweetDetailViewController.h"

static NSString * const NFBConversationCellIdentifier = @"NFBConversationCell";
static NSString * const NFBMessageRequestCellIdentifier = @"NFBMessageRequestCell";
static NSString * const NFBMessageBubbleCellIdentifier = @"NFBMessageBubbleCell";
static NSString * const NFBActorResultCellIdentifier = @"NFBActorResultCell";
static NSString * const NFBChatSharedPostKey = @"__sharedPost";
static NSString * const NFBChatSharedPostURIKey = @"__sharedPostURI";
static NSString * const NFBMessageableActorFollowsViewerKey = @"__nfbFollowsViewer";
static NSUInteger const NFBChatGroupMaxInvitedMembers = 49;
static NSUInteger const NFBChatGroupMaxTotalMembers = 50;

static NSString *NFBStringValue(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *NFBTweetieLocalizedString(NSString *key, NSString *fallback) {
  static NSBundle *localizationBundle = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Localization_Localization" ofType:@"bundle" inDirectory:@"NeoFreeBirdMain"];
    if (path.length > 0) localizationBundle = [NSBundle bundleWithPath:path];
  });
  NSString *value = localizationBundle ? [localizationBundle localizedStringForKey:key value:nil table:nil] : nil;
  if (value.length > 0 && ![value isEqualToString:key]) return value;
  return fallback ?: key ?: @"";
}

static NSString *NFBChatPresentedErrorMessage(NSError *error) {
  if (NFBChatErrorIsPermissionDenied(error)) {
    if ([error.userInfo[NFBChatErrorNameKey] isEqual:@"ConvoLocked"]) {
      return NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_READ_ONLY_REASON_UNKNOWN_TITLE", @"You are unable to send messages in this conversation.");
    }
    return NFBTweetieLocalizedString(@"DIRECT_MESSAGE_ERROR_CANNOT_SEND_DIRECT_MESSAGE", @"Sorry! You cannot message this account.");
  }
  return error.localizedDescription;
}

static NSString *NFBTweetiePlainText(NSString *value) {
  NSString *plain = [value ?: @"" stringByReplacingOccurrencesOfString:@"•|•" withString:@""];
  plain = [plain stringByReplacingOccurrencesOfString:@"{{" withString:@""];
  plain = [plain stringByReplacingOccurrencesOfString:@"}}" withString:@""];
  return plain;
}

static NSString *NFBTweetiePlainLocalizedString(NSString *key, NSString *fallback) {
  return NFBTweetiePlainText(NFBTweetieLocalizedString(key, fallback));
}

static NSString *NFBTweetieOKTitle(void) {
  return NFBTweetieLocalizedString(@"OK_ACTION_LABEL", @"OK");
}

static NSString *NFBTweetieCancelTitle(void) {
  return NFBTweetieLocalizedString(@"CANCEL_ACTION_LABEL", @"Cancel");
}

static NSString *NFBTweetieSaveTitle(void) {
  return NFBTweetieLocalizedString(@"SAVE_ACTION_LABEL", @"Save");
}

static NSString *NFBChatStringByLimitingComposedCharacters(NSString *value, NSUInteger maxCharacters, NSUInteger maxLength) {
  if (value.length == 0) return @"";
  NSString *limited = value;
  if (maxLength > 0 && limited.length > maxLength) {
    NSRange range = [limited rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, maxLength)];
    limited = [limited substringWithRange:range];
  }
  if (maxCharacters == 0) return limited;
  __block NSUInteger count = 0;
  __block NSUInteger end = limited.length;
  [limited enumerateSubstringsInRange:NSMakeRange(0, limited.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
    (void)substring;
    (void)enclosingRange;
    count++;
    if (count > maxCharacters) {
      end = substringRange.location;
      *stop = YES;
    }
  }];
  return end < limited.length ? [limited substringToIndex:end] : limited;
}

static NSDictionary *NFBChatRawMessage(NSDictionary *message) {
  if (![message isKindOfClass:NSDictionary.class]) return @{};
  NSDictionary *wrapped = [message[@"message"] isKindOfClass:NSDictionary.class] ? message[@"message"] : nil;
  if (wrapped && ![message[@"id"] isKindOfClass:NSString.class]) return wrapped;
  return message;
}

static NSArray<NSDictionary *> *NFBChatMembers(NSDictionary *conversation) {
  NSArray *members = [conversation[@"members"] isKindOfClass:NSArray.class] ? conversation[@"members"] : @[];
  NSMutableArray<NSDictionary *> *profiles = [NSMutableArray arrayWithCapacity:members.count];
  for (NSDictionary *member in members) {
    if ([member isKindOfClass:NSDictionary.class]) [profiles addObject:member];
  }
  return profiles;
}

static NSArray<NSDictionary *> *NFBChatNonViewerMembers(NSDictionary *conversation) {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSMutableArray<NSDictionary *> *profiles = [NSMutableArray array];
  for (NSDictionary *member in NFBChatMembers(conversation)) {
    NSString *did = NFBStringValue(member[@"did"]);
    if (did.length > 0 && [did isEqualToString:viewerDID]) continue;
    [profiles addObject:member];
  }
  return profiles;
}

static NSDictionary *NFBChatKindDictionary(NSDictionary *conversation) {
  NSDictionary *kind = [conversation[@"kind"] isKindOfClass:NSDictionary.class] ? conversation[@"kind"] : nil;
  if (kind) return kind;
  NSDictionary *group = [conversation[@"group"] isKindOfClass:NSDictionary.class] ? conversation[@"group"] : nil;
  return group ?: @{};
}

static BOOL NFBChatConversationIsGroup(NSDictionary *conversation) {
  NSDictionary *kind = NFBChatKindDictionary(conversation);
  NSString *kindType = NFBStringValue(kind[@"$type"]).lowercaseString;
  if ([kindType containsString:@"group"]) return YES;
  NSString *flatKind = NFBStringValue(conversation[@"kind"]).lowercaseString;
  if ([flatKind containsString:@"group"]) return YES;
  NSString *flatType = NFBStringValue(conversation[@"type"]).lowercaseString;
  if ([flatType containsString:@"group"]) return YES;
  if ([kind[@"memberCount"] respondsToSelector:@selector(integerValue)] || NFBStringValue(kind[@"name"]).length > 0) return YES;
  if ([conversation[@"memberCount"] respondsToSelector:@selector(integerValue)] || NFBStringValue(conversation[@"name"]).length > 0) return YES;
  return NFBChatMembers(conversation).count > 2 || NFBChatNonViewerMembers(conversation).count > 1;
}

static NSString *NFBChatConversationGroupName(NSDictionary *conversation) {
  NSDictionary *kind = NFBChatKindDictionary(conversation);
  NSArray<NSString *> *names = @[
    NFBStringValue(kind[@"name"]),
    NFBStringValue(conversation[@"name"]),
    NFBStringValue(conversation[@"groupName"]),
    NFBStringValue(conversation[@"title"])
  ];
  for (NSString *name in names) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 0) return trimmed;
  }
  return @"";
}

static NSUInteger NFBChatConversationMemberCount(NSDictionary *conversation) {
  NSDictionary *kind = NFBChatKindDictionary(conversation);
  id countValue = kind[@"memberCount"];
  if (![countValue respondsToSelector:@selector(unsignedIntegerValue)]) countValue = conversation[@"memberCount"];
  NSUInteger count = [countValue respondsToSelector:@selector(unsignedIntegerValue)] ? [countValue unsignedIntegerValue] : 0;
  return count > 0 ? count : NFBChatMembers(conversation).count;
}

static NSUInteger NFBChatConversationMemberLimit(NSDictionary *conversation) {
  NSDictionary *kind = NFBChatKindDictionary(conversation);
  id limitValue = kind[@"memberLimit"];
  if (![limitValue respondsToSelector:@selector(unsignedIntegerValue)]) limitValue = conversation[@"memberLimit"];
  return [limitValue respondsToSelector:@selector(unsignedIntegerValue)] ? [limitValue unsignedIntegerValue] : 0;
}

static BOOL NFBChatConversationIsLocked(NSDictionary *conversation) {
  NSDictionary *kind = NFBChatKindDictionary(conversation);
  NSString *lockStatus = NFBStringValue(kind[@"lockStatus"]).lowercaseString;
  if (lockStatus.length == 0) lockStatus = NFBStringValue(conversation[@"lockStatus"]).lowercaseString;
  return lockStatus.length > 0 && ![lockStatus isEqualToString:@"unlocked"];
}

static NSString *NFBChatGroupRoleForProfile(NSDictionary *profile) {
  NSDictionary *kind = [profile[@"kind"] isKindOfClass:NSDictionary.class] ? profile[@"kind"] : @{};
  NSString *role = NFBStringValue(kind[@"role"]);
  if (role.length == 0) role = NFBStringValue(profile[@"role"]);
  return role.lowercaseString;
}

static BOOL NFBChatViewerIsGroupOwner(NSArray<NSDictionary *> *members) {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (viewerDID.length == 0) return NO;
  for (NSDictionary *member in members ?: @[]) {
    if (![NFBStringValue(member[@"did"]) isEqualToString:viewerDID]) continue;
    return [NFBChatGroupRoleForProfile(member) isEqualToString:@"owner"];
  }
  return NO;
}

static BOOL NFBChatProfileIsViewer(NSDictionary *profile) {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSString *did = NFBStringValue(profile[@"did"]);
  return viewerDID.length > 0 && did.length > 0 && [did isEqualToString:viewerDID];
}

static BOOL NFBChatProfileIsGroupOwner(NSDictionary *profile) {
  return [NFBChatGroupRoleForProfile(profile) isEqualToString:@"owner"];
}

static NSDictionary *NFBChatViewerMemberForConversation(NSDictionary *conversation) {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (viewerDID.length == 0) return @{};
  for (NSDictionary *member in NFBChatMembers(conversation)) {
    if ([NFBStringValue(member[@"did"]) isEqualToString:viewerDID]) return member;
  }
  return @{};
}

static BOOL NFBChatProfileIsPastGroupMember(NSDictionary *profile) {
  NSDictionary *kind = [profile[@"kind"] isKindOfClass:NSDictionary.class] ? profile[@"kind"] : @{};
  NSString *kindType = NFBStringValue(kind[@"$type"]).lowercaseString;
  return [kindType containsString:@"pastgroup"];
}

static BOOL NFBChatConversationViewerIsPastGroupMember(NSDictionary *conversation) {
  if (!NFBChatConversationIsGroup(conversation)) return NO;
  NSDictionary *viewerMember = NFBChatViewerMemberForConversation(conversation);
  return viewerMember.count > 0 && NFBChatProfileIsPastGroupMember(viewerMember);
}

static BOOL NFBChatConversationHasOpenMemberSlots(NSDictionary *conversation) {
  NSUInteger limit = NFBChatConversationMemberLimit(conversation);
  if (limit == 0) limit = NFBChatGroupMaxTotalMembers;
  return NFBChatConversationMemberCount(conversation) < limit;
}

static NSString *NFBChatDefaultGroupNameForProfiles(NSArray<NSDictionary *> *profiles) {
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  for (NSDictionary *profile in profiles ?: @[]) {
    if (![profile isKindOfClass:NSDictionary.class]) continue;
    NSString *name = [NFBAtprotoClient displayNameForProfile:profile];
    if (name.length == 0) name = [NFBAtprotoClient handleForProfile:profile];
    if (name.length > 0 && ![names containsObject:name]) [names addObject:name];
    if (names.count >= 4) break;
  }
  NSString *name = names.count > 0 ? [names componentsJoinedByString:@", "] : NFBTweetieLocalizedString(@"DIRECT_MESSAGE_GROUP_LABEL", @"Group");
  return NFBChatStringByLimitingComposedCharacters(name, 50, 500);
}

static NSDictionary *NFBChatPrimaryMember(NSDictionary *conversation) {
  NSArray<NSDictionary *> *members = NFBChatMembers(conversation);
  NSDictionary *firstNonViewer = NFBChatNonViewerMembers(conversation).firstObject;
  if (firstNonViewer) return firstNonViewer;
  return members.firstObject ?: @{};
}

static NSString *NFBChatConversationTitle(NSDictionary *conversation) {
  if (NFBChatConversationIsGroup(conversation)) {
    NSString *groupName = NFBChatConversationGroupName(conversation);
    if (groupName.length > 0) return groupName;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSArray<NSDictionary *> *members = NFBChatNonViewerMembers(conversation);
    for (NSDictionary *member in members) {
      NSString *name = [NFBAtprotoClient displayNameForProfile:member];
      if (name.length > 0) [names addObject:name];
      if (names.count >= 3) break;
    }
    if (names.count > 0) {
      NSUInteger memberCount = NFBChatConversationMemberCount(conversation);
      NSUInteger hiddenCount = memberCount > names.count + 1 ? memberCount - names.count - 1 : 0;
      NSString *joined = [names componentsJoinedByString:@", "];
      return hiddenCount > 0 ? [joined stringByAppendingFormat:@" +%lu", (unsigned long)hiddenCount] : joined;
    }
    return NFBTweetieLocalizedString(@"DIRECT_MESSAGE_GROUP_LABEL", @"Group");
  }
  return [NFBAtprotoClient displayNameForProfile:NFBChatPrimaryMember(conversation)];
}

static NSString *NFBChatConversationHandle(NSDictionary *conversation) {
  if (NFBChatConversationIsGroup(conversation)) {
    NSUInteger memberCount = NFBChatConversationMemberCount(conversation);
    if (memberCount == 1) return NFBTweetieLocalizedString(@"DM_CONVERSATION_MEMBERS_COUNT_SINGULAR_TITLE", @"1 member");
    NSString *format = NFBTweetieLocalizedString(@"DM_CONVERSATION_MEMBERS_COUNT_PLURAL_TITLE", @"%@ members");
    return [NSString stringWithFormat:format, [NSString stringWithFormat:@"%lu", (unsigned long)memberCount]];
  }
  NSString *handle = [NFBAtprotoClient handleForProfile:NFBChatPrimaryMember(conversation)];
  return handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"";
}

static NSString *NFBChatConversationInfoTitle(NSDictionary *conversation) {
  return NFBChatConversationIsGroup(conversation)
    ? NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_GROUP_CONVERSATION_TITLE_LABEL", @"Group info")
    : NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_ONE_TO_ONE_CONVERSATION_TITLE_LABEL", @"Conversation info");
}

static NSString *NFBChatDeleteConversationActionTitle(NSDictionary *conversation) {
  return NFBChatConversationIsGroup(conversation)
    ? NFBTweetieLocalizedString(@"DIRECT_MESSAGE_DELETE_GROUP_CONVERSATION_ACTION_LABEL", @"Leave conversation")
    : NFBTweetieLocalizedString(@"DIRECT_MESSAGE_DELETE_CONVERSATION_ACTION_LABEL", @"Delete conversation");
}

static NSString *NFBChatDeleteConversationAlertTitle(NSDictionary *conversation) {
  return NFBChatConversationIsGroup(conversation)
    ? NFBTweetieLocalizedString(@"DIRECT_MESSAGE_DELETE_CONVERSATION_ALERT_TITLE_GROUP", @"Leave conversation?")
    : NFBTweetieLocalizedString(@"DIRECT_MESSAGE_DELETE_CONVERSATION_ALERT_TITLE_ONE_TO_ONE", @"Delete conversation?");
}

static NSString *NFBChatDeleteConversationMessage(void) {
  return NFBTweetieLocalizedString(@"DIRECT_MESSAGE_DELETE_CONVERSATION_ALERT_MESSAGE", @"This conversation will be deleted from your inbox. Other people in the conversation will still be able to see it.");
}

static NSString *NFBChatMuteConversationTitle(BOOL muted) {
  return muted
    ? NFBTweetieLocalizedString(@"DM_CONVERSATION_ACTION_UNMUTE_TITLE_SHORT", @"Unmute")
    : NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_SNOOZE_CONVERSATION_LABEL", @"Snooze notifications");
}

static BOOL NFBChatConversationCanSendMessages(NSDictionary *conversation) {
  NSString *status = NFBStringValue(conversation[@"status"]).lowercaseString;
  if ([status containsString:@"request"]) return NO;
  if (NFBChatConversationIsGroup(conversation)) {
    if (NFBChatConversationIsLocked(conversation)) return NO;
    if (NFBChatConversationViewerIsPastGroupMember(conversation)) return NO;
  }
  return YES;
}

static NSString *NFBChatConversationReadOnlyMessage(NSDictionary *conversation) {
  NSString *status = NFBStringValue(conversation[@"status"]).lowercaseString;
  if ([status containsString:@"request"]) return NFBTweetiePlainLocalizedString(@"DM_INBOX_REQUESTS_HEADER_TITLE", @"Accept this request to reply.");
  if (NFBChatConversationViewerIsPastGroupMember(conversation)) {
    return NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_READ_ONLY_REASON_REMOVED_FROM_GROUP_TITLE", @"You must be re-added to this group in order to send messages.");
  }
  if (NFBChatConversationIsLocked(conversation)) {
    return NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_READ_ONLY_REASON_UNKNOWN_TITLE", @"You are unable to send messages in this conversation.");
  }
  return NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_READ_ONLY_REASON_UNKNOWN_TITLE", @"You are unable to send messages in this conversation.");
}

static NSString *NFBChatConversationRequestMessage(NSDictionary *conversation) {
  if (NFBChatConversationIsGroup(conversation)) {
    return NFBTweetiePlainLocalizedString(@"DM_INBOX_REQUESTS_HEADER_TITLE", @"Accept this request to reply.");
  }
  NSString *name = NFBChatConversationTitle(conversation);
  if (name.length > 0) {
    NSString *format = NFBTweetiePlainLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_USER_TITLE", @"Do you want to let %@ message you? They won't know you've seen their message until you accept.");
    return [NSString stringWithFormat:format, name];
  }
  return NFBTweetiePlainLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_UNNAMED_TITLE", @"Do you want to let this user message you? They won't know you've seen their message until you accept.");
}

static NSDictionary *NFBChatMemberForDID(NSDictionary *conversation, NSString *did) {
  if (did.length == 0) return @{};
  for (NSDictionary *member in NFBChatMembers(conversation)) {
    if ([NFBStringValue(member[@"did"]) isEqualToString:did]) return member;
  }
  return @{};
}

static NSString *NFBChatMessageID(NSDictionary *message) {
  message = NFBChatRawMessage(message);
  return NFBStringValue(message[@"id"]);
}

static NSString *NFBChatMessageText(NSDictionary *message) {
  message = NFBChatRawMessage(message);
  NSString *text = NFBStringValue(message[@"text"]);
  if (text.length == 0 && [message[@"data"] isKindOfClass:NSDictionary.class]) {
    NSString *type = NFBStringValue(message[@"data"][@"$type"]);
    if ([type containsString:@"AddMember"]) return @"A member was added";
    if ([type containsString:@"RemoveMember"]) return @"A member was removed";
    if ([type containsString:@"MemberJoin"]) return @"A member joined";
    if ([type containsString:@"MemberLeave"]) return @"A member left";
    if ([type containsString:@"LockConvo"]) return @"This conversation was locked";
    if ([type containsString:@"UnlockConvo"]) return @"This conversation was unlocked";
    if ([type containsString:@"EditGroup"]) return @"Group info was updated";
    return @"Conversation updated";
  }
  return text.length > 0 ? text : @"This message was deleted";
}

static NSString *NFBChatMessageSenderDID(NSDictionary *message) {
  message = NFBChatRawMessage(message);
  NSDictionary *sender = [message[@"sender"] isKindOfClass:NSDictionary.class] ? message[@"sender"] : @{};
  NSString *did = NFBStringValue(sender[@"did"]);
  if (did.length > 0) return did;
  return NFBStringValue(message[@"senderId"]);
}

static BOOL NFBChatMessageIsMine(NSDictionary *message) {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSString *senderDID = NFBChatMessageSenderDID(message);
  return senderDID.length > 0 && [senderDID isEqualToString:viewerDID];
}

static NSDictionary *NFBChatSenderProfileFromMessage(NSDictionary *message) {
  NSString *senderDID = NFBChatMessageSenderDID(message);
  if (senderDID.length == 0) return @{};
  NSDictionary *rawMessage = NFBChatRawMessage(message);
  NSArray *relatedProfiles = [message[@"__relatedProfiles"] isKindOfClass:NSArray.class] ? message[@"__relatedProfiles"] : @[];
  if (relatedProfiles.count == 0 && rawMessage != message) {
    relatedProfiles = [rawMessage[@"__relatedProfiles"] isKindOfClass:NSArray.class] ? rawMessage[@"__relatedProfiles"] : @[];
  }
  for (NSDictionary *profile in relatedProfiles) {
    if ([profile isKindOfClass:NSDictionary.class] && [NFBStringValue(profile[@"did"]) isEqualToString:senderDID]) return profile;
  }
  NSDictionary *sender = [rawMessage[@"sender"] isKindOfClass:NSDictionary.class] ? rawMessage[@"sender"] : @{};
  if ([NFBStringValue(sender[@"did"]) isEqualToString:senderDID]) return sender;
  return @{};
}

static NSString *NFBChatSenderDisplayNameForMessageInConversation(NSDictionary *message, NSDictionary *conversation) {
  if (!NFBChatConversationIsGroup(conversation) || NFBChatMessageIsMine(message)) return @"";
  NSDictionary *senderProfile = NFBChatMemberForDID(conversation, NFBChatMessageSenderDID(message));
  if (senderProfile.count == 0) senderProfile = NFBChatSenderProfileFromMessage(message);
  NSString *senderName = senderProfile.count > 0 ? [NFBAtprotoClient displayNameForProfile:senderProfile] : @"";
  if (senderName.length == 0 && senderProfile.count > 0) senderName = [NFBAtprotoClient handleForProfile:senderProfile];
  return senderName ?: @"";
}

static NSString *NFBChatMessageSentAt(NSDictionary *message) {
  message = NFBChatRawMessage(message);
  return NFBStringValue(message[@"sentAt"]);
}

static NSSet<NSString *> *NFBChatMessageViewerReactionValues(NSDictionary *message) {
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  if (viewerDID.length == 0) return [NSSet set];
  NSArray *reactions = [NFBChatRawMessage(message)[@"reactions"] isKindOfClass:NSArray.class] ? NFBChatRawMessage(message)[@"reactions"] : @[];
  NSMutableSet<NSString *> *values = [NSMutableSet set];
  for (NSDictionary *reaction in reactions) {
    if (![reaction isKindOfClass:NSDictionary.class]) continue;
    NSString *value = NFBStringValue(reaction[@"value"]);
    if (value.length == 0) continue;
    NSDictionary *sender = [reaction[@"sender"] isKindOfClass:NSDictionary.class] ? reaction[@"sender"] : @{};
    NSString *senderDID = NFBStringValue(sender[@"did"]);
    if (senderDID.length == 0) senderDID = NFBStringValue(reaction[@"senderId"]);
    if ([senderDID isEqualToString:viewerDID]) [values addObject:value];
  }
  return values;
}

static NSString *NFBChatConversationID(NSDictionary *conversation) {
  NSString *conversationID = NFBStringValue(conversation[@"id"]);
  if (conversationID.length == 0) conversationID = NFBStringValue(conversation[@"convoId"]);
  return conversationID;
}

static NSString *NFBRelativeTimeForISOString(NSString *dateString) {
  if (dateString.length == 0) return @"";
  return [NFBAtprotoClient relativeTimeForPost:@{@"indexedAt": dateString}];
}

static NSString *NFBFullTimeForISOString(NSString *dateString) {
  if (dateString.length == 0) return @"";
  static NSDateFormatter *inputMilliseconds = nil;
  static NSDateFormatter *inputSeconds = nil;
  static NSDateFormatter *output = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    inputMilliseconds = [[NSDateFormatter alloc] init];
    inputMilliseconds.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    inputMilliseconds.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    inputMilliseconds.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    inputSeconds = [[NSDateFormatter alloc] init];
    inputSeconds.locale = inputMilliseconds.locale;
    inputSeconds.timeZone = inputMilliseconds.timeZone;
    inputSeconds.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    output = [[NSDateFormatter alloc] init];
    output.dateFormat = @"MMM d, h:mm a";
  });
  NSDate *date = [inputMilliseconds dateFromString:dateString] ?: [inputSeconds dateFromString:dateString];
  return date ? [output stringFromDate:date] : @"";
}

static NSString *NFBChatMessageDisplayText(NSDictionary *message);
static NSDictionary *NFBChatSharedPostForMessage(NSDictionary *message);

static CGFloat NFBSharedPostCardHeightForWidth(NSDictionary *post, CGFloat width) {
  if (post.count == 0 || width <= 0.0) return 0.0;
  NFBQuotedPostView *sizingView = [[NFBQuotedPostView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 1.0)];
  [sizingView configureWithPost:post];
  [sizingView setNeedsLayout];
  [sizingView layoutIfNeeded];
  CGSize size = [sizingView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
  return ceil(MAX(78.0, size.height));
}

static CGFloat NFBSharedPostClusterHeightForWidth(NSDictionary *post, CGFloat width) {
  if (post.count == 0 || width <= 0.0) return 0.0;
  CGFloat height = NFBSharedPostCardHeightForWidth(post, width);
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  if (quotedPost.count > 0) height += 6.0 + NFBSharedPostCardHeightForWidth(quotedPost, width);
  return height;
}

static CGFloat NFBMessageBubbleHeightForWidth(NSDictionary *message, CGFloat width, BOOL showTimestamp, NSString *senderName) {
  CGFloat usableWidth = MAX(width, 320.0);
  CGFloat maxBubbleWidth = MAX(180.0, usableWidth * 0.72);
  CGFloat textWidth = MAX(120.0, maxBubbleWidth - 32.0);
  NSString *text = NFBChatMessageDisplayText(message);
  NSDictionary *sharedPost = NFBChatSharedPostForMessage(message);
  BOOL hasTextBubble = text.length > 0 || sharedPost.count == 0;
  CGFloat bubbleHeight = 0.0;
  if (hasTextBubble) {
    CGRect textRect = [text boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                     attributes:@{NSFontAttributeName: NFBFont(NFBIPAMetricValue(NFBIPAMetricMessageBodyFontSize), NFBFontWeightRegular)}
                                        context:nil];
    bubbleHeight = MAX(44.0, ceil(textRect.size.height) + 20.0);
  }
  CGFloat cardWidth = MIN(maxBubbleWidth, usableWidth - 76.0);
  CGFloat cardHeight = sharedPost.count > 0 ? NFBSharedPostClusterHeightForWidth(sharedPost, cardWidth) : 0.0;
  CGFloat cardGap = sharedPost.count > 0 && hasTextBubble ? 6.0 : 0.0;
  NSArray *reactions = [NFBChatRawMessage(message)[@"reactions"] isKindOfClass:NSArray.class] ? NFBChatRawMessage(message)[@"reactions"] : @[];
  CGFloat reactionHeight = reactions.count > 0 ? 24.0 : 0.0;
  CGFloat timeHeight = showTimestamp ? 18.0 : 0.0;
  CGFloat verticalGap = showTimestamp ? 12.0 : 4.0;
  CGFloat senderNameHeight = senderName.length > 0 ? 18.0 : 0.0;
  CGFloat senderNameGap = senderName.length > 0 ? 2.0 : 0.0;
  return MAX(48.0, senderNameHeight + senderNameGap + bubbleHeight + cardGap + cardHeight + reactionHeight + timeHeight + verticalGap);
}

static CGPathRef NFBCreateBubblePath(CGRect bounds, CGFloat topLeft, CGFloat topRight, CGFloat bottomRight, CGFloat bottomLeft) {
  CGFloat maxRadius = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) / 2.0;
  topLeft = MIN(topLeft, maxRadius);
  topRight = MIN(topRight, maxRadius);
  bottomRight = MIN(bottomRight, maxRadius);
  bottomLeft = MIN(bottomLeft, maxRadius);

  CGFloat minX = CGRectGetMinX(bounds);
  CGFloat midX = CGRectGetMidX(bounds);
  CGFloat maxX = CGRectGetMaxX(bounds);
  CGFloat minY = CGRectGetMinY(bounds);
  CGFloat midY = CGRectGetMidY(bounds);
  CGFloat maxY = CGRectGetMaxY(bounds);
  (void)midX;
  (void)midY;

  UIBezierPath *path = [UIBezierPath bezierPath];
  [path moveToPoint:CGPointMake(minX + topLeft, minY)];
  [path addLineToPoint:CGPointMake(maxX - topRight, minY)];
  [path addArcWithCenter:CGPointMake(maxX - topRight, minY + topRight) radius:topRight startAngle:(CGFloat)(-M_PI_2) endAngle:0.0 clockwise:YES];
  [path addLineToPoint:CGPointMake(maxX, maxY - bottomRight)];
  [path addArcWithCenter:CGPointMake(maxX - bottomRight, maxY - bottomRight) radius:bottomRight startAngle:0.0 endAngle:(CGFloat)M_PI_2 clockwise:YES];
  [path addLineToPoint:CGPointMake(minX + bottomLeft, maxY)];
  [path addArcWithCenter:CGPointMake(minX + bottomLeft, maxY - bottomLeft) radius:bottomLeft startAngle:(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI clockwise:YES];
  [path addLineToPoint:CGPointMake(minX, minY + topLeft)];
  [path addArcWithCenter:CGPointMake(minX + topLeft, minY + topLeft) radius:topLeft startAngle:(CGFloat)M_PI endAngle:(CGFloat)(M_PI + M_PI_2) clockwise:YES];
  [path closePath];
  return CGPathCreateCopy(path.CGPath);
}

static void NFBApplyMessageBubbleShape(UIView *bubble, BOOL mine, BOOL groupedWithPrevious, BOOL groupedWithNext) {
  CGFloat large = 22.0;
  CGFloat small = 7.0;
  CGFloat topLeft = large;
  CGFloat topRight = large;
  CGFloat bottomRight = large;
  CGFloat bottomLeft = large;
  if (mine) {
    if (groupedWithPrevious) topRight = small;
    if (groupedWithNext) bottomRight = small;
  } else {
    if (groupedWithPrevious) topLeft = small;
    if (groupedWithNext) bottomLeft = small;
  }
  CAShapeLayer *mask = [CAShapeLayer layer];
  mask.frame = bubble.bounds;
  CGPathRef path = NFBCreateBubblePath(bubble.bounds, topLeft, topRight, bottomRight, bottomLeft);
  mask.path = path;
  CGPathRelease(path);
  bubble.layer.mask = mask;
}

static NSDictionary *NFBChatLastMessage(NSDictionary *conversation) {
  return [conversation[@"lastMessage"] isKindOfClass:NSDictionary.class] ? conversation[@"lastMessage"] : nil;
}

static BOOL NFBChatConversationIsRequest(NSDictionary *conversation) {
  NSString *status = NFBStringValue(conversation[@"status"]).lowercaseString;
  return [status containsString:@"request"];
}

static NSDictionary *NFBChatRequestBlockProfile(NSDictionary *conversation) {
  if (!NFBChatConversationIsRequest(conversation) || NFBChatConversationIsGroup(conversation)) return @{};
  NSDictionary *profile = NFBChatPrimaryMember(conversation);
  if (NFBChatProfileIsViewer(profile)) return @{};
  return NFBStringValue(profile[@"did"]).length > 0 ? profile : @{};
}

static NSArray<NSDictionary *> *NFBChatConversationsForList(NSArray<NSDictionary *> *conversations, BOOL requestsList) {
  NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
  for (NSDictionary *conversation in conversations ?: @[]) {
    if (![conversation isKindOfClass:NSDictionary.class]) continue;
    BOOL request = NFBChatConversationIsRequest(conversation);
    if (requestsList) {
      if (!request && NFBStringValue(conversation[@"status"]).length > 0) continue;
      [filtered addObject:conversation];
    } else if (!request) {
      [filtered addObject:conversation];
    }
  }
  return filtered;
}

static NSString *NFBChatTrimTrailingURLPunctuation(NSString *value) {
  NSString *trimmed = value ?: @"";
  NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@".,!?;:)"];
  while (trimmed.length > 0) {
    unichar character = [trimmed characterAtIndex:trimmed.length - 1];
    if (![trailing characterIsMember:character]) break;
    trimmed = [trimmed substringToIndex:trimmed.length - 1];
  }
  return trimmed;
}

static NSString *NFBChatPostURIFromURLString(NSString *urlString) {
  NSString *candidate = NFBChatTrimTrailingURLPunctuation(urlString);
  return NFBPostLink(candidate)[@"uri"] ?: @"";
}

static NSString *NFBChatPostActorFromURI(NSString *uri) {
  if (![uri hasPrefix:@"at://"]) return @"";
  NSString *rest = [uri substringFromIndex:@"at://".length];
  NSRange slash = [rest rangeOfString:@"/"];
  if (slash.location == NSNotFound) return @"";
  return [rest substringToIndex:slash.location];
}

static NSString *NFBChatPostRkeyFromURI(NSString *uri) {
  NSString *marker = @"/app.bsky.feed.post/";
  NSRange range = [uri rangeOfString:marker];
  if (range.location == NSNotFound) return @"";
  NSString *rkey = [uri substringFromIndex:NSMaxRange(range)];
  NSRange slash = [rkey rangeOfString:@"/"];
  if (slash.location != NSNotFound) rkey = [rkey substringToIndex:slash.location];
  return rkey;
}

static NSArray<NSString *> *NFBChatURLTokensInText(NSString *text) {
  return NFBPostLinkTokens(text);
}

static NSString *NFBChatSharedPostURIFromMessage(NSDictionary *message) {
  NSString *outerCachedURI = NFBStringValue(message[NFBChatSharedPostURIKey]);
  if (outerCachedURI.length > 0) return outerCachedURI;
  message = NFBChatRawMessage(message);
  NSString *cachedURI = NFBStringValue(message[NFBChatSharedPostURIKey]);
  if (cachedURI.length > 0) return cachedURI;
  for (NSString *token in NFBChatURLTokensInText(NFBChatMessageText(message))) {
    NSString *uri = NFBChatPostURIFromURLString(token);
    if (uri.length > 0) return uri;
  }
  NSArray *facets = [message[@"facets"] isKindOfClass:NSArray.class] ? message[@"facets"] : @[];
  for (NSDictionary *facet in facets) {
    if (![facet isKindOfClass:NSDictionary.class]) continue;
    NSArray *features = [facet[@"features"] isKindOfClass:NSArray.class] ? facet[@"features"] : @[];
    for (NSDictionary *feature in features) {
      NSString *uri = NFBChatPostURIFromURLString(NFBStringValue(feature[@"uri"]));
      if (uri.length > 0) return uri;
    }
  }
  return @"";
}

static NSDictionary *NFBChatSharedPostForMessage(NSDictionary *message) {
  if ([message[NFBChatSharedPostKey] isKindOfClass:NSDictionary.class]) return message[NFBChatSharedPostKey];
  message = NFBChatRawMessage(message);
  return [message[NFBChatSharedPostKey] isKindOfClass:NSDictionary.class] ? message[NFBChatSharedPostKey] : nil;
}

static NSString *NFBChatMessageDisplayText(NSDictionary *message) {
  NSString *text = NFBChatMessageText(message);
  if (NFBChatSharedPostForMessage(message).count == 0) return text;
  NSMutableString *displayText = [text mutableCopy] ?: [NSMutableString string];
  for (NSString *token in NFBChatURLTokensInText(text)) {
    NSString *uri = NFBChatPostURIFromURLString(token);
    if (uri.length == 0 || ![uri isEqualToString:NFBChatSharedPostURIFromMessage(message)]) continue;
    [displayText replaceOccurrencesOfString:token withString:@"" options:0 range:NSMakeRange(0, displayText.length)];
  }
  return [displayText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *NFBChatPostAuthorHandle(NSDictionary *post) {
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *handle = [NFBAtprotoClient handleForProfile:author];
  return handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"a post";
}

static NSString *NFBChatConversationPreview(NSDictionary *conversation) {
  NSDictionary *message = NFBChatLastMessage(conversation);
  if (!message) return @"No messages yet";
  NSDictionary *sharedPost = NFBChatSharedPostForMessage(message);
  NSString *displayText = NFBChatMessageDisplayText(message);
  BOOL mine = NFBChatMessageIsMine(message);
  BOOL group = NFBChatConversationIsGroup(conversation);
  NSDictionary *senderProfile = group && !mine ? NFBChatMemberForDID(conversation, NFBChatMessageSenderDID(message)) : @{};
  NSString *senderName = senderProfile.count > 0 ? [NFBAtprotoClient displayNameForProfile:senderProfile] : @"";
  if (senderName.length == 0 && senderProfile.count > 0) senderName = [NFBAtprotoClient handleForProfile:senderProfile];
  if (sharedPost.count > 0) {
    NSString *postHandle = NFBChatPostAuthorHandle(sharedPost);
    if (mine) {
      return displayText.length > 0 ? [NSString stringWithFormat:@"You sent %@'s Tweet: %@", postHandle, displayText] : [NSString stringWithFormat:@"You sent %@'s Tweet", postHandle];
    }
    if (group && senderName.length > 0) {
      return displayText.length > 0 ? [NSString stringWithFormat:@"%@ sent %@'s Tweet: %@", senderName, postHandle, displayText] : [NSString stringWithFormat:@"%@ sent %@'s Tweet", senderName, postHandle];
    }
    return displayText.length > 0 ? [NSString stringWithFormat:@"Sent you %@'s Tweet: %@", postHandle, displayText] : [NSString stringWithFormat:@"Sent you %@'s Tweet", postHandle];
  }
  if (mine) return [@"You: " stringByAppendingString:displayText];
  if (group && senderName.length > 0) return [NSString stringWithFormat:@"%@: %@", senderName, displayText];
  return displayText;
}

static NSString *NFBChatConversationSearchText(NSDictionary *conversation) {
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithArray:@[
    NFBChatConversationTitle(conversation),
    NFBChatConversationHandle(conversation),
    NFBChatConversationPreview(conversation)
  ]];
  for (NSDictionary *member in NFBChatMembers(conversation)) {
    NSString *name = [NFBAtprotoClient displayNameForProfile:member];
    NSString *handle = [NFBAtprotoClient handleForProfile:member];
    if (name.length > 0) [parts addObject:name];
    if (handle.length > 0) [parts addObject:handle];
  }
  return [[parts componentsJoinedByString:@" "] lowercaseString];
}

static NSArray<NSDictionary *> *NFBSortedChatMessages(NSArray<NSDictionary *> *messages) {
  NSMutableArray<NSDictionary *> *clean = [NSMutableArray arrayWithCapacity:messages.count];
  for (NSDictionary *message in messages) {
    if ([message isKindOfClass:NSDictionary.class]) [clean addObject:message];
  }
  [clean sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSString *leftDate = NFBChatMessageSentAt(left);
    NSString *rightDate = NFBChatMessageSentAt(right);
    NSComparisonResult result = [leftDate compare:rightDate];
    if (result != NSOrderedSame) return result;
    return [NFBChatMessageID(left) compare:NFBChatMessageID(right)];
  }];
  return clean;
}

static NSArray<NSDictionary *> *NFBMergedChatMessages(NSArray<NSDictionary *> *currentMessages, NSArray<NSDictionary *> *nextMessages) {
  NSMutableDictionary<NSString *, NSDictionary *> *messagesByKey = [NSMutableDictionary dictionary];
  NSMutableArray<NSDictionary *> *messagesWithoutStableKey = [NSMutableArray array];
  void (^addMessages)(NSArray<NSDictionary *> *) = ^(NSArray<NSDictionary *> *messages) {
    for (NSDictionary *message in messages) {
      if (![message isKindOfClass:NSDictionary.class]) continue;
      NSString *messageID = NFBChatMessageID(message);
      if (messageID.length == 0) {
        NSString *fallbackKey = [NSString stringWithFormat:@"%@|%@|%@",
                                 NFBChatMessageSentAt(message),
                                 NFBChatMessageSenderDID(message),
                                 NFBChatMessageText(message)];
        if (fallbackKey.length > 2) {
          messagesByKey[fallbackKey] = message;
        } else {
          [messagesWithoutStableKey addObject:message];
        }
      } else {
        messagesByKey[messageID] = message;
      }
    }
  };
  addMessages(currentMessages ?: @[]);
  addMessages(nextMessages ?: @[]);
  NSMutableArray<NSDictionary *> *merged = [NSMutableArray arrayWithArray:messagesByKey.allValues ?: @[]];
  [merged addObjectsFromArray:messagesWithoutStableKey];
  return NFBSortedChatMessages(merged);
}

static NSArray<NSDictionary *> *NFBMergedChatConversations(NSArray<NSDictionary *> *currentConversations, NSArray<NSDictionary *> *nextConversations) {
  NSMutableDictionary<NSString *, NSDictionary *> *conversationsByID = [NSMutableDictionary dictionary];
  NSMutableArray<NSDictionary *> *conversationsWithoutID = [NSMutableArray array];
  void (^addConversations)(NSArray<NSDictionary *> *) = ^(NSArray<NSDictionary *> *conversations) {
    for (NSDictionary *conversation in conversations) {
      if (![conversation isKindOfClass:NSDictionary.class]) continue;
      NSString *conversationID = NFBChatConversationID(conversation);
      if (conversationID.length > 0) {
        conversationsByID[conversationID] = conversation;
      } else {
        [conversationsWithoutID addObject:conversation];
      }
    }
  };
  addConversations(currentConversations ?: @[]);
  addConversations(nextConversations ?: @[]);
  NSMutableArray<NSDictionary *> *merged = [NSMutableArray arrayWithArray:conversationsByID.allValues ?: @[]];
  [merged addObjectsFromArray:conversationsWithoutID];
  [merged sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSString *leftDate = NFBChatMessageSentAt(NFBChatLastMessage(left) ?: @{});
    NSString *rightDate = NFBChatMessageSentAt(NFBChatLastMessage(right) ?: @{});
    NSComparisonResult order = [rightDate compare:leftDate];
    return order != NSOrderedSame ? order : [NFBChatConversationID(left) compare:NFBChatConversationID(right)];
  }];
  return merged;
}

static NSString *NFBChatCacheSafeComponent(NSString *value) {
  if (value.length == 0) return @"anonymous";
  NSMutableString *safe = [NSMutableString stringWithCapacity:value.length];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
  for (NSUInteger index = 0; index < value.length; index++) {
    unichar character = [value characterAtIndex:index];
    [safe appendString:[allowed characterIsMember:character] ? [NSString stringWithCharacters:&character length:1] : @"_"];
  }
  return safe.length > 0 ? safe : @"anonymous";
}

static NSString *NFBChatCacheAccountKey(void) {
  NFBAtprotoSession *session = [NFBAtprotoSession sharedSession];
  NSString *identifier = session.did.length > 0 ? session.did : session.handle;
  return NFBChatCacheSafeComponent(identifier ?: @"anonymous");
}

static NSString *NFBChatCacheDirectory(void) {
  NSArray<NSString *> *directories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *base = directories.firstObject ?: NSTemporaryDirectory();
  NSString *directory = [[base stringByAppendingPathComponent:@"NotTwitterMessages"] stringByAppendingPathComponent:NFBChatCacheAccountKey()];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  return directory;
}

static NSString *NFBChatCachePathForName(NSString *name) {
  NSString *safeName = NFBChatCacheSafeComponent(name ?: @"cache");
  return [NFBChatCacheDirectory() stringByAppendingPathComponent:[safeName stringByAppendingPathExtension:@"json"]];
}

static id NFBChatJSONSafeObject(id object) {
  if (!object || object == NSNull.null) return NSNull.null;
  if ([object isKindOfClass:NSString.class] || [object isKindOfClass:NSNumber.class]) return object;
  if ([object isKindOfClass:NSArray.class]) {
    NSMutableArray *array = [NSMutableArray array];
    for (id item in (NSArray *)object) {
      id safe = NFBChatJSONSafeObject(item);
      if (safe) [array addObject:safe];
    }
    return array;
  }
  if ([object isKindOfClass:NSDictionary.class]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
      (void)stop;
      NSString *stringKey = [key isKindOfClass:NSString.class] ? key : [key description];
      if (stringKey.length == 0) return;
      id safe = NFBChatJSONSafeObject(value);
      if (safe) dictionary[stringKey] = safe;
    }];
    return dictionary;
  }
  return [object respondsToSelector:@selector(description)] ? [object description] : NSNull.null;
}

static NSArray<NSDictionary *> *NFBChatLimitedDictionaries(NSArray<NSDictionary *> *items, NSUInteger limit) {
  if (items.count <= limit) return items ?: @[];
  return [items subarrayWithRange:NSMakeRange(0, limit)];
}

static NSDictionary *NFBChatLoadCacheNamed(NSString *name) {
  NSData *data = [NSData dataWithContentsOfFile:NFBChatCachePathForName(name)];
  if (data.length == 0) return nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static void NFBChatSaveCacheNamed(NSString *name, NSDictionary *payload) {
  if (![payload isKindOfClass:NSDictionary.class]) return;
  id safePayload = NFBChatJSONSafeObject(payload);
  NSMutableDictionary *cache = [([safePayload isKindOfClass:NSDictionary.class] ? safePayload : @{}) mutableCopy];
  cache[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
  cache[@"version"] = @1;
  if (![NSJSONSerialization isValidJSONObject:cache]) return;
  NSData *data = [NSJSONSerialization dataWithJSONObject:cache options:0 error:nil];
  if (data.length == 0) return;
  [data writeToFile:NFBChatCachePathForName(name) options:NSDataWritingAtomic error:nil];
}

static void NFBChatRemoveCacheNamed(NSString *name) {
  if (name.length == 0) return;
  [[NSFileManager defaultManager] removeItemAtPath:NFBChatCachePathForName(name) error:nil];
}

static NSString *NFBChatConversationCacheName(NSString *conversationID) {
  return [@"conversation-" stringByAppendingString:NFBChatCacheSafeComponent(conversationID ?: @"unknown")];
}

static NSInteger NFBChatUnreadCount(NSDictionary *conversation) {
  return [conversation[@"unreadCount"] respondsToSelector:@selector(integerValue)] ? [conversation[@"unreadCount"] integerValue] : 0;
}

// Twitter 9.67 uses a placeholder layer behind its DM avatar artwork.
// Keep this separate from the 24-point people icon used by menu actions.
static UIImage *NFBChatGroupAvatarImage(CGFloat side) {
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    (void)context;
    [NFBIPAColor(NFBIPAColorRoleGroupedDivider) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0.0, 0.0, side, side)] fill];
    UIImage *people = [NFBTemplateIcon(@"nfb_people_group") imageWithTintColor:NFBColorText()
                                                            renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGFloat inset = side * (12.0 / 56.0);
    [people drawInRect:CGRectInset(CGRectMake(0.0, 0.0, side, side), inset, inset)];
  }];
}

static void NFBLoadRemoteImage(UIImageView *imageView, NSString *urlString, UIImage *placeholder) {
  imageView.image = placeholder;
  imageView.accessibilityIdentifier = urlString ?: @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (urlString.length == 0 || !url) return;
  __weak UIImageView *weakImageView = imageView;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      UIImageView *strongImageView = weakImageView;
      if (!strongImageView) return;
      if (![strongImageView.accessibilityIdentifier isEqualToString:urlString ?: @""]) return;
      strongImageView.image = image;
    });
  }];
  [task resume];
}

@class NFBConversationCell;

@protocol NFBConversationCellDelegate <NSObject>
- (void)conversationCellDidTapAvatar:(NFBConversationCell *)cell;
- (void)conversationCellDidLongPress:(NFBConversationCell *)cell sourceView:(UIView *)sourceView;
@end

@interface NFBConversationCell : UITableViewCell
@property (nonatomic, weak) id<NFBConversationCellDelegate> delegate;
@property (nonatomic, copy) NSDictionary *conversation;
@property (nonatomic, copy) NSDictionary *profile;
- (void)configureWithConversation:(NSDictionary *)conversation;
@end

@implementation NFBConversationCell {
  UIImageView *_avatarView;
  UILabel *_nameLabel;
  UIImageView *_verifiedView;
  UILabel *_handleLabel;
  UILabel *_timeLabel;
  UILabel *_previewLabel;
  UIView *_unreadDot;
  UIButton *_avatarButton;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleDefault);

    _avatarView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = 28.0;

    _avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _avatarButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_avatarButton addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.textColor = NFBColorText();
    _nameLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _verifiedView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
    _verifiedView.translatesAutoresizingMaskIntoConstraints = NO;
    _verifiedView.tintColor = NFBColorBlue();
    _verifiedView.contentMode = UIViewContentModeScaleAspectFit;

    _handleLabel = [[UILabel alloc] init];
    _handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _handleLabel.textColor = NFBColorSecondaryText();
    _handleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    _handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _timeLabel = [[UILabel alloc] init];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timeLabel.textColor = NFBColorSecondaryText();
    _timeLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    _timeLabel.textAlignment = NSTextAlignmentRight;
    [_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _previewLabel = [[UILabel alloc] init];
    _previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _previewLabel.textColor = NFBColorSecondaryText();
    _previewLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    _previewLabel.numberOfLines = 2;
    _previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _unreadDot = [[UIView alloc] init];
    _unreadDot.translatesAutoresizingMaskIntoConstraints = NO;
    _unreadDot.backgroundColor = NFBColorAccent();
    _unreadDot.layer.cornerRadius = 5.0;

    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    NFBIPAApplyTableSeparatorAppearance(divider);

    UIStackView *identityStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _verifiedView, _handleLabel]];
    identityStack.translatesAutoresizingMaskIntoConstraints = NO;
    identityStack.axis = UILayoutConstraintAxisHorizontal;
    identityStack.alignment = UIStackViewAlignmentCenter;
    identityStack.spacing = 4.0;

    [self.contentView addSubview:_avatarView];
    [self.contentView addSubview:_avatarButton];
    [self.contentView addSubview:identityStack];
    [self.contentView addSubview:_timeLabel];
    [self.contentView addSubview:_previewLabel];
    [self.contentView addSubview:_unreadDot];
    [self.contentView addSubview:divider];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    [self.contentView addGestureRecognizer:longPress];

    [NSLayoutConstraint activateConstraints:@[
      [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
      [_avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
      [_avatarView.widthAnchor constraintEqualToConstant:56.0],
      [_avatarView.heightAnchor constraintEqualToConstant:56.0],
      [_avatarButton.leadingAnchor constraintEqualToAnchor:_avatarView.leadingAnchor],
      [_avatarButton.trailingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor],
      [_avatarButton.topAnchor constraintEqualToAnchor:_avatarView.topAnchor],
      [_avatarButton.bottomAnchor constraintEqualToAnchor:_avatarView.bottomAnchor],
      [identityStack.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12.0],
      [identityStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:13.0],
      [identityStack.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8.0],
      [_verifiedView.widthAnchor constraintEqualToConstant:16.0],
      [_verifiedView.heightAnchor constraintEqualToConstant:16.0],
      [_timeLabel.topAnchor constraintEqualToAnchor:identityStack.topAnchor],
      [_timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
      [_timeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:34.0],
      [_previewLabel.leadingAnchor constraintEqualToAnchor:identityStack.leadingAnchor],
      [_previewLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-28.0],
      [_previewLabel.topAnchor constraintEqualToAnchor:identityStack.bottomAnchor constant:4.0],
      [_previewLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
      [_unreadDot.centerYAnchor constraintEqualToAnchor:_previewLabel.centerYAnchor],
      [_unreadDot.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
      [_unreadDot.widthAnchor constraintEqualToConstant:10.0],
      [_unreadDot.heightAnchor constraintEqualToConstant:10.0],
      [divider.leadingAnchor constraintEqualToAnchor:_previewLabel.leadingAnchor],
      [divider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [divider.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
      [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
      [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:80.0]
    ]];
  }
  return self;
}

- (void)configureWithConversation:(NSDictionary *)conversation {
  self.conversation = conversation ?: @{};
  BOOL group = NFBChatConversationIsGroup(conversation);
  self.profile = group ? @{} : NFBChatPrimaryMember(conversation);
  _nameLabel.text = NFBChatConversationTitle(conversation);
  _verifiedView.hidden = group || ![NFBAtprotoClient isProfileVerified:self.profile];
  _handleLabel.text = NFBChatConversationHandle(conversation);
  NSDictionary *lastMessage = NFBChatLastMessage(conversation);
  _timeLabel.text = NFBRelativeTimeForISOString(NFBChatMessageSentAt(lastMessage ?: @{}));
  _previewLabel.text = NFBChatConversationPreview(conversation);
  BOOL unread = NFBChatUnreadCount(conversation) > 0;
  _unreadDot.hidden = !unread;
  _nameLabel.font = NFBFont(16.0, unread ? NFBFontWeightHeavy : NFBFontWeightBold);
  _previewLabel.font = NFBFont(15.0, unread ? NFBFontWeightBold : NFBFontWeightRegular);
  _previewLabel.textColor = unread ? NFBColorText() : NFBColorSecondaryText();
  if (group) {
    NFBLoadRemoteImage(_avatarView, nil, NFBChatGroupAvatarImage(56.0));
    _avatarView.tintColor = NFBColorText();
    _avatarView.backgroundColor = UIColor.clearColor;
    _avatarView.layer.borderWidth = 0.0;
    _avatarView.contentMode = UIViewContentModeScaleAspectFit;
  } else {
    _avatarView.backgroundColor = UIColor.clearColor;
    _avatarView.layer.borderWidth = 0.0;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    NFBLoadRemoteImage(_avatarView, [NFBAtprotoClient avatarURLForProfile:self.profile], NFBDefaultAvatarImage());
  }
}

- (void)avatarTapped {
  [self.delegate conversationCellDidTapAvatar:self];
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan) return;
  [self.delegate conversationCellDidLongPress:self sourceView:self.contentView];
}

@end

@interface NFBMessageRequestCell : UITableViewCell
- (void)configure;
@end

@implementation NFBMessageRequestCell {
  UIImageView *_iconView;
  UILabel *_titleLabel;
  UILabel *_subtitleLabel;
  UIView *_divider;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleDefault);
    _iconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_messages")];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = NFBColorText();
    _iconView.contentMode = UIViewContentModeCenter;
    _iconView.layer.cornerRadius = 24.0;
    _iconView.layer.borderColor = NFBColorBorder().CGColor;
    _iconView.layer.borderWidth = 1.0;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.textColor = NFBColorText();
    _titleLabel.font = NFBFont(16.0, NFBFontWeightHeavy);

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.textColor = NFBColorSecondaryText();
    _subtitleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _divider = [[UIView alloc] init];
    _divider.translatesAutoresizingMaskIntoConstraints = NO;
    NFBIPAApplyTableSeparatorAppearance(_divider);

    [self.contentView addSubview:_iconView];
    [self.contentView addSubview:_titleLabel];
    [self.contentView addSubview:_subtitleLabel];
    [self.contentView addSubview:_divider];

    [NSLayoutConstraint activateConstraints:@[
      [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
      [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
      [_iconView.widthAnchor constraintEqualToConstant:48.0],
      [_iconView.heightAnchor constraintEqualToConstant:48.0],
      [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12.0],
      [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
      [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14.0],
      [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
      [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
      [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
      [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-13.0],
      [_divider.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
      [_divider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [_divider.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
      [_divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
      [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:72.0]
    ]];
  }
  return self;
}

- (void)configure {
  _titleLabel.text = @"Message requests";
  _subtitleLabel.text = @"Messages from people you may know";
  _iconView.tintColor = NFBColorText();
  _iconView.layer.borderColor = NFBColorBorder().CGColor;
}

@end

@class NFBMessageBubbleCell;

@protocol NFBMessageBubbleCellDelegate <NSObject>
- (void)messageBubbleCellDidLongPress:(NFBMessageBubbleCell *)cell sourceView:(UIView *)sourceView;
- (void)messageBubbleCellDidTapAvatar:(NFBMessageBubbleCell *)cell;
@end

@interface NFBMessageBubbleCell : UITableViewCell
@property (nonatomic, weak) id<NFBMessageBubbleCellDelegate> delegate;
@property (nonatomic, copy) NSDictionary *message;
@property (nonatomic, copy) NSDictionary *senderProfile;
- (void)configureWithMessage:(NSDictionary *)message senderProfile:(NSDictionary *)profile showAvatar:(BOOL)showAvatar showTimestamp:(BOOL)showTimestamp senderName:(NSString *)senderName;
@end

@implementation NFBMessageBubbleCell {
  UIImageView *_avatarView;
  UIButton *_avatarButton;
  UILabel *_senderNameLabel;
  UIView *_bubbleView;
  UILabel *_bodyLabel;
  UILabel *_timeLabel;
  UILabel *_reactionLabel;
  BOOL _mine;
  BOOL _showAvatar;
  BOOL _showTimestamp;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

    _avatarView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
    _avatarView.translatesAutoresizingMaskIntoConstraints = YES;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = 18.0;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;

    _avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _avatarButton.translatesAutoresizingMaskIntoConstraints = YES;
    [_avatarButton addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];

    _senderNameLabel = [[UILabel alloc] init];
    _senderNameLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _senderNameLabel.textColor = NFBColorSecondaryText();
    _senderNameLabel.font = NFBFont(12.0, NFBFontWeightMedium);
    _senderNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _senderNameLabel.hidden = YES;

    _bubbleView = [[UIView alloc] init];
    _bubbleView.translatesAutoresizingMaskIntoConstraints = YES;
    NFBIPAApplyMessageBubbleAppearance(_bubbleView, NO);

    _bodyLabel = [[UILabel alloc] init];
    _bodyLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _bodyLabel.numberOfLines = 0;
    _bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricMessageBodyFontSize), NFBFontWeightRegular);
    _bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;

    _timeLabel = [[UILabel alloc] init];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _timeLabel.textColor = NFBColorSecondaryText();
    _timeLabel.font = NFBFont(12.0, NFBFontWeightRegular);

    _reactionLabel = [[UILabel alloc] init];
    _reactionLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _reactionLabel.font = NFBFont(14.0, NFBFontWeightRegular);
    _reactionLabel.userInteractionEnabled = YES;
    _reactionLabel.accessibilityLabel = @"Message reactions";
    NFBIPAApplyMessageReactionPillAppearance(_reactionLabel);

    [_bubbleView addSubview:_bodyLabel];
    [self.contentView addSubview:_avatarView];
    [self.contentView addSubview:_avatarButton];
    [self.contentView addSubview:_senderNameLabel];
    [self.contentView addSubview:_bubbleView];
    [self.contentView addSubview:_timeLabel];
    [self.contentView addSubview:_reactionLabel];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    [_bubbleView addGestureRecognizer:longPress];
    UITapGestureRecognizer *reactionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reactionTapped:)];
    [_reactionLabel addGestureRecognizer:reactionTap];
    UILongPressGestureRecognizer *reactionLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    [_reactionLabel addGestureRecognizer:reactionLongPress];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat width = MAX(320.0, self.contentView.bounds.size.width);
  CGFloat maxBubbleWidth = MAX(180.0, width * 0.72);
  CGFloat textWidth = MAX(120.0, maxBubbleWidth - 32.0);
  NSAttributedString *bodyText = _bodyLabel.attributedText;
  CGRect textRect = bodyText.length > 0
    ? [bodyText boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                             context:nil]
    : CGRectZero;
  CGFloat bubbleWidth = MIN(maxBubbleWidth, MAX(44.0, ceil(textRect.size.width) + 32.0));
  CGFloat bubbleHeight = MAX(44.0, ceil(textRect.size.height) + 20.0);
  CGFloat bubbleX = _mine ? self.contentView.bounds.size.width - 16.0 - bubbleWidth : 60.0;
  BOOL showSenderName = !_mine && _senderNameLabel.text.length > 0;
  if (showSenderName) {
    _senderNameLabel.hidden = NO;
    _senderNameLabel.frame = CGRectMake(60.0, 3.0, maxBubbleWidth, 18.0);
  } else {
    _senderNameLabel.hidden = YES;
    _senderNameLabel.frame = CGRectZero;
  }
  CGFloat bubbleY = showSenderName ? 23.0 : 3.0;
  _bubbleView.frame = CGRectMake(bubbleX, bubbleY, bubbleWidth, bubbleHeight);
  _bodyLabel.frame = CGRectInset(_bubbleView.bounds, 16.0, 10.0);

  CGFloat nextY = CGRectGetMaxY(_bubbleView.frame) + 2.0;
  if (_reactionLabel.hidden) {
    _reactionLabel.frame = CGRectZero;
  } else {
    CGSize reactionSize = [_reactionLabel sizeThatFits:CGSizeMake(180.0, 22.0)];
    reactionSize.width = MIN(180.0, MAX(36.0, ceil(reactionSize.width)));
    reactionSize.height = 22.0;
    CGFloat reactionX = _mine ? CGRectGetMaxX(_bubbleView.frame) - reactionSize.width - 4.0 : CGRectGetMinX(_bubbleView.frame) + 4.0;
    _reactionLabel.frame = CGRectMake(reactionX, nextY, reactionSize.width, reactionSize.height);
    nextY = CGRectGetMaxY(_reactionLabel.frame) + 2.0;
  }

  if (_showTimestamp && !_timeLabel.hidden) {
    CGSize timeSize = [_timeLabel sizeThatFits:CGSizeMake(maxBubbleWidth, 16.0)];
    timeSize.width = MIN(maxBubbleWidth, ceil(timeSize.width));
    timeSize.height = 16.0;
    CGFloat timeX = _mine ? CGRectGetMaxX(_bubbleView.frame) - timeSize.width - 8.0 : CGRectGetMinX(_bubbleView.frame) + 8.0;
    _timeLabel.frame = CGRectMake(timeX, nextY, timeSize.width, timeSize.height);
  } else {
    _timeLabel.frame = CGRectZero;
  }

  BOOL avatarHidden = _mine || !_showAvatar;
  _avatarView.hidden = avatarHidden;
  _avatarButton.hidden = avatarHidden;
  if (!avatarHidden) {
    _avatarView.frame = CGRectMake(16.0, CGRectGetMaxY(_bubbleView.frame) - 36.0, 36.0, 36.0);
    _avatarButton.frame = _avatarView.frame;
  } else {
    _avatarView.frame = CGRectZero;
    _avatarButton.frame = CGRectZero;
  }
}

- (void)prepareForReuse {
  [super prepareForReuse];
  _avatarView.hidden = NO;
  _avatarButton.hidden = NO;
  _reactionLabel.hidden = YES;
  _timeLabel.hidden = YES;
  _mine = NO;
  _showAvatar = NO;
  _showTimestamp = NO;
  _senderNameLabel.text = @"";
  _senderNameLabel.hidden = YES;
}

- (void)configureWithMessage:(NSDictionary *)message senderProfile:(NSDictionary *)profile showAvatar:(BOOL)showAvatar showTimestamp:(BOOL)showTimestamp senderName:(NSString *)senderName {
  self.message = message ?: @{};
  self.senderProfile = profile ?: @{};
  BOOL mine = NFBChatMessageIsMine(message);
  _mine = mine;
  _showAvatar = showAvatar;
  _showTimestamp = showTimestamp;
  _senderNameLabel.text = senderName ?: @"";
  NSString *messageText = NFBChatMessageDisplayText(message);
  _bodyLabel.textColor = mine ? UIColor.whiteColor : NFBColorText();
  NSMutableAttributedString *body = [[NSMutableAttributedString alloc] initWithString:messageText ?: @"" attributes:@{
    NSFontAttributeName: _bodyLabel.font ?: NFBFont(NFBIPAMetricValue(NFBIPAMetricMessageBodyFontSize), NFBFontWeightRegular),
    NSForegroundColorAttributeName: mine ? UIColor.whiteColor : NFBColorText()
  }];
  _bodyLabel.attributedText = NFBAttributedStringByReplacingEmojiWithTwemoji(body, _bodyLabel.font ?: NFBFont(NFBIPAMetricValue(NFBIPAMetricMessageBodyFontSize), NFBFontWeightRegular));
  NFBIPAApplyMessageBubbleAppearance(_bubbleView, mine);
  _timeLabel.text = showTimestamp ? NFBFullTimeForISOString(NFBChatMessageSentAt(message)) : @"";
  _timeLabel.hidden = !showTimestamp;
  _timeLabel.textAlignment = mine ? NSTextAlignmentRight : NSTextAlignmentLeft;
  _avatarView.hidden = mine || !showAvatar;
  _avatarButton.hidden = _avatarView.hidden;
  NFBLoadRemoteImage(_avatarView, [NFBAtprotoClient avatarURLForProfile:profile], NFBDefaultAvatarImage());

  NSArray *reactions = [message[@"reactions"] isKindOfClass:NSArray.class] ? message[@"reactions"] : @[];
  if (reactions.count > 0) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSDictionary *reaction in reactions) {
      NSString *value = [reaction isKindOfClass:NSDictionary.class] ? NFBStringValue(reaction[@"value"]) : @"";
      if (value.length > 0 && ![values containsObject:value]) [values addObject:value];
      if (values.count >= 3) break;
    }
    NSString *reactionText = values.count > 0 ? [NSString stringWithFormat:@"  %@  ", [values componentsJoinedByString:@" "]] : @"";
    NSMutableAttributedString *reaction = [[NSMutableAttributedString alloc] initWithString:reactionText attributes:@{
      NSFontAttributeName: _reactionLabel.font ?: NFBFont(14.0, NFBFontWeightRegular),
      NSForegroundColorAttributeName: NFBColorText()
    }];
    _reactionLabel.attributedText = NFBAttributedStringByReplacingEmojiWithTwemoji(reaction, _reactionLabel.font ?: NFBFont(14.0, NFBFontWeightRegular));
  } else {
    _reactionLabel.attributedText = nil;
    _reactionLabel.text = @"";
  }
  NFBIPAApplyMessageReactionPillAppearance(_reactionLabel);
  _reactionLabel.hidden = _reactionLabel.attributedText.length == 0 && _reactionLabel.text.length == 0;
  [self setNeedsLayout];
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan) return;
  [self.delegate messageBubbleCellDidLongPress:self sourceView:gesture.view ?: _bubbleView];
}

- (void)reactionTapped:(UITapGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateEnded || _reactionLabel.hidden) return;
  [self.delegate messageBubbleCellDidLongPress:self sourceView:_reactionLabel];
}

- (void)avatarTapped {
  [self.delegate messageBubbleCellDidTapAvatar:self];
}

@end

typedef void (^NFBMessageReactionMenuHandler)(NSString *action, NSString *value);

@interface NFBMessageReactionMenuViewController : UIViewController
- (instancetype)initWithSourceRect:(CGRect)sourceRect canDelete:(BOOL)canDelete selectedReactions:(NSSet<NSString *> *)selectedReactions handler:(NFBMessageReactionMenuHandler)handler;
@end

@implementation NFBMessageReactionMenuViewController {
  CGRect _sourceRect;
  BOOL _canDelete;
  NSSet<NSString *> *_selectedReactions;
  NFBMessageReactionMenuHandler _handler;
  UIButton *_backdropButton;
  UIView *_reactionTray;
  UIView *_actionPanel;
}

- (instancetype)initWithSourceRect:(CGRect)sourceRect canDelete:(BOOL)canDelete selectedReactions:(NSSet<NSString *> *)selectedReactions handler:(NFBMessageReactionMenuHandler)handler {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _sourceRect = sourceRect;
    _canDelete = canDelete;
    _selectedReactions = [selectedReactions copy] ?: [NSSet set];
    _handler = [handler copy];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.clearColor;

  _backdropButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _backdropButton.backgroundColor = NFBIPAModalSheetScrimColor();
  [_backdropButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_backdropButton];

  _reactionTray = [[UIView alloc] initWithFrame:CGRectZero];
  NFBIPAApplyMessageReactionTrayAppearance(_reactionTray);
  [self.view addSubview:_reactionTray];

  UIStackView *reactionStack = [[UIStackView alloc] init];
  reactionStack.translatesAutoresizingMaskIntoConstraints = NO;
  reactionStack.axis = UILayoutConstraintAxisHorizontal;
  reactionStack.alignment = UIStackViewAlignmentCenter;
  reactionStack.distribution = UIStackViewDistributionFillEqually;
  reactionStack.spacing = 2.0;
  [_reactionTray addSubview:reactionStack];

  for (NSString *emoji in @[@"❤️", @"👍", @"😂", @"😮", @"😢", @"🔥"]) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *twemoji = NFBTwemojiImageForEmoji(emoji);
    if (twemoji) {
      [button setImage:[twemoji imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
      button.imageView.contentMode = UIViewContentModeScaleAspectFit;
      button.contentEdgeInsets = UIEdgeInsetsMake(9.0, 9.0, 9.0, 9.0);
    } else {
      [button setTitle:emoji forState:UIControlStateNormal];
      button.titleLabel.font = [UIFont systemFontOfSize:28.0];
    }
    button.accessibilityLabel = emoji;
    BOOL selected = [_selectedReactions containsObject:emoji];
    button.backgroundColor = selected ? [NFBColorAccent() colorWithAlphaComponent:0.18] : UIColor.clearColor;
    button.layer.cornerRadius = 22.0;
    button.layer.masksToBounds = selected;
    button.clipsToBounds = selected;
    [button addTarget:self action:@selector(reactionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [reactionStack addArrangedSubview:button];
  }

  [NSLayoutConstraint activateConstraints:@[
    [reactionStack.leadingAnchor constraintEqualToAnchor:_reactionTray.leadingAnchor constant:10.0],
    [reactionStack.trailingAnchor constraintEqualToAnchor:_reactionTray.trailingAnchor constant:-10.0],
    [reactionStack.topAnchor constraintEqualToAnchor:_reactionTray.topAnchor constant:4.0],
    [reactionStack.bottomAnchor constraintEqualToAnchor:_reactionTray.bottomAnchor constant:-4.0]
  ]];

  _actionPanel = [[UIView alloc] initWithFrame:CGRectZero];
  [self applyTweetMenuPanelAppearance:_actionPanel];
  [self.view addSubview:_actionPanel];

  UIView *actionMaterialView = [self actionMenuMaterialView];
  [_actionPanel addSubview:actionMaterialView];

  UIStackView *actionStack = [[UIStackView alloc] init];
  actionStack.translatesAutoresizingMaskIntoConstraints = NO;
  actionStack.axis = UILayoutConstraintAxisVertical;
  actionStack.spacing = 0.0;
  actionStack.layoutMargins = UIEdgeInsetsZero;
  actionStack.layoutMarginsRelativeArrangement = YES;
  [_actionPanel addSubview:actionStack];

  [self addActionButtonWithTitle:@"Copy message" action:@"copy" iconName:@"nfb_link" destructive:NO toStack:actionStack];
  if (_canDelete) [self addActionButtonWithTitle:@"Delete for you" action:@"delete" iconName:@"nfb_trash" destructive:YES toStack:actionStack];
  [self addActionButtonWithTitle:@"Cancel" action:@"cancel" iconName:@"nfb_close" destructive:NO toStack:actionStack];

  [NSLayoutConstraint activateConstraints:@[
    [actionMaterialView.leadingAnchor constraintEqualToAnchor:_actionPanel.leadingAnchor],
    [actionMaterialView.trailingAnchor constraintEqualToAnchor:_actionPanel.trailingAnchor],
    [actionMaterialView.topAnchor constraintEqualToAnchor:_actionPanel.topAnchor],
    [actionMaterialView.bottomAnchor constraintEqualToAnchor:_actionPanel.bottomAnchor],
    [actionStack.leadingAnchor constraintEqualToAnchor:_actionPanel.leadingAnchor],
    [actionStack.trailingAnchor constraintEqualToAnchor:_actionPanel.trailingAnchor],
    [actionStack.topAnchor constraintEqualToAnchor:_actionPanel.topAnchor],
    [actionStack.bottomAnchor constraintEqualToAnchor:_actionPanel.bottomAnchor]
  ]];
}

- (void)applyTweetMenuPanelAppearance:(UIView *)panel {
  panel.backgroundColor = UIColor.clearColor;
  panel.layer.cornerRadius = 14.0;
  if (@available(iOS 13.0, *)) {
    panel.layer.cornerCurve = kCACornerCurveContinuous;
  }
  panel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  panel.layer.borderColor = [self actionMenuSeparatorColor].CGColor;
  panel.layer.shadowColor = UIColor.blackColor.CGColor;
  panel.layer.shadowOpacity = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? 0.18 : 0.38;
  panel.layer.shadowOffset = CGSizeMake(0.0, 8.0);
  panel.layer.shadowRadius = 18.0;
  panel.layer.masksToBounds = NO;
  panel.clipsToBounds = NO;
}

- (UIView *)actionMenuMaterialView {
  UIBlurEffectStyle style = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeDark] ? UIBlurEffectStyleDark : UIBlurEffectStyleExtraLight;
  if (@available(iOS 13.0, *)) {
    style = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? UIBlurEffectStyleSystemMaterialLight : UIBlurEffectStyleSystemMaterialDark;
  }
  UIVisualEffectView *materialView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
  materialView.translatesAutoresizingMaskIntoConstraints = NO;
  materialView.backgroundColor = UIColor.clearColor;
  materialView.userInteractionEnabled = NO;
  materialView.layer.cornerRadius = 14.0;
  if (@available(iOS 13.0, *)) {
    materialView.layer.cornerCurve = kCACornerCurveContinuous;
  }
  materialView.layer.masksToBounds = YES;
  materialView.clipsToBounds = YES;
  return materialView;
}

- (UIColor *)actionMenuLabelColor {
  if (@available(iOS 13.0, *)) return UIColor.labelColor;
  return [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? UIColor.blackColor : UIColor.whiteColor;
}

- (UIColor *)actionMenuSeparatorColor {
  if (@available(iOS 13.0, *)) return UIColor.separatorColor;
  return NFBIPAColor(NFBIPAColorRoleGroupedDivider);
}

- (void)addActionButtonWithTitle:(NSString *)title
                          action:(NSString *)action
                        iconName:(NSString *)iconName
                     destructive:(BOOL)destructive
                         toStack:(UIStackView *)stack {
  if (stack.arrangedSubviews.count > 0) [stack addArrangedSubview:[self actionSeparatorView]];
  [stack addArrangedSubview:[self actionButtonWithTitle:title action:action iconName:iconName destructive:destructive]];
}

- (UIView *)actionSeparatorView {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.backgroundColor = UIColor.clearColor;
  UIView *separator = [[UIView alloc] init];
  separator.translatesAutoresizingMaskIntoConstraints = NO;
  separator.backgroundColor = [self actionMenuSeparatorColor];
  [container addSubview:separator];
  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [separator.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:48.0],
    [separator.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [separator.topAnchor constraintEqualToAnchor:container.topAnchor],
    [separator.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
  ]];
  return container;
}

- (UIButton *)actionButtonWithTitle:(NSString *)title action:(NSString *)action iconName:(NSString *)iconName destructive:(BOOL)destructive {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 15.0, 0.0, 15.0);
  button.imageEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 13.0);
  button.titleEdgeInsets = UIEdgeInsetsMake(0.0, 13.0, 0.0, 0.0);
  button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
  [button setTitle:title forState:UIControlStateNormal];
  UIColor *tint = destructive ? UIColor.systemRedColor : [self actionMenuLabelColor];
  [button setTitleColor:tint forState:UIControlStateNormal];
  UIImage *icon = NFBTemplateIcon(iconName);
  [button setImage:icon forState:UIControlStateNormal];
  button.tintColor = tint;
  button.accessibilityIdentifier = action;
  [button addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
  [button.heightAnchor constraintEqualToConstant:44.0].active = YES;
  return button;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  _backdropButton.frame = self.view.bounds;
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);
  CGFloat safeTop = self.view.safeAreaInsets.top + 10.0;
  CGFloat safeBottom = height - self.view.safeAreaInsets.bottom - 10.0;
  CGFloat trayWidth = MIN(356.0, width - 28.0);
  CGFloat trayHeight = 56.0;
  CGFloat sourceMidX = CGRectGetMidX(_sourceRect);
  if (sourceMidX != sourceMidX || sourceMidX <= 0.0) sourceMidX = width * 0.5;
  CGFloat trayX = floor(MIN(MAX(14.0, sourceMidX - trayWidth * 0.5), width - trayWidth - 14.0));
  CGFloat rows = _canDelete ? 3.0 : 2.0;
  CGFloat panelWidth = MIN(286.0, width - 48.0);
  CGFloat panelHeight = rows * 44.0 + (rows - 1.0) / UIScreen.mainScreen.scale;
  CGFloat panelX = floor(MIN(MAX(24.0, sourceMidX - panelWidth * 0.5), width - panelWidth - 24.0));
  CGFloat stackHeight = trayHeight + 8.0 + panelHeight;
  CGFloat stackY = CGRectGetMinY(_sourceRect) - stackHeight - 12.0;
  if (stackY < safeTop) stackY = CGRectGetMaxY(_sourceRect) + 12.0;
  if (stackY + stackHeight > safeBottom) stackY = safeBottom - stackHeight;
  stackY = MAX(safeTop, stackY);
  CGFloat trayY = floor(stackY);
  _reactionTray.frame = CGRectMake(trayX, trayY, trayWidth, trayHeight);
  _actionPanel.frame = CGRectMake(panelX, CGRectGetMaxY(_reactionTray.frame) + 8.0, panelWidth, panelHeight);
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  _reactionTray.alpha = 0.0;
  _reactionTray.transform = CGAffineTransformMakeScale(0.82, 0.82);
  _actionPanel.alpha = 0.0;
  _actionPanel.transform = CGAffineTransformMakeScale(0.92, 0.92);
  [UIView animateWithDuration:0.24 delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.35 options:UIViewAnimationOptionCurveEaseOut animations:^{
    self->_reactionTray.alpha = 1.0;
    self->_reactionTray.transform = CGAffineTransformIdentity;
    self->_actionPanel.alpha = 1.0;
    self->_actionPanel.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)reactionTapped:(UIButton *)sender {
  [self finishWithAction:@"reaction" value:sender.currentTitle ?: sender.accessibilityLabel ?: @""];
}

- (void)actionTapped:(UIButton *)sender {
  NSString *action = sender.accessibilityIdentifier ?: @"";
  if ([action isEqualToString:@"cancel"]) {
    [self cancelTapped];
    return;
  }
  [self finishWithAction:action value:@""];
}

- (void)finishWithAction:(NSString *)action value:(NSString *)value {
  NFBPlaySound(@"pop.aac");
  NFBMessageReactionMenuHandler handler = [_handler copy];
  [self dismissViewControllerAnimated:YES completion:^{
    if (handler) handler(action ?: @"", value ?: @"");
  }];
}

- (void)cancelTapped {
  [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface NFBActorResultCell : UITableViewCell
- (void)configureWithProfile:(NSDictionary *)profile;
@end

@implementation NFBActorResultCell {
  UIImageView *_avatarView;
  UILabel *_nameLabel;
  UIImageView *_verifiedView;
  UILabel *_handleLabel;
  UILabel *_followsYouLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleDefault);

    _avatarView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.layer.cornerRadius = 22.0;
    _avatarView.clipsToBounds = YES;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.textColor = NFBColorText();
    _nameLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _verifiedView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
    _verifiedView.translatesAutoresizingMaskIntoConstraints = NO;
    _verifiedView.tintColor = NFBColorBlue();
    _verifiedView.contentMode = UIViewContentModeScaleAspectFit;

    _handleLabel = [[UILabel alloc] init];
    _handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _handleLabel.textColor = NFBColorSecondaryText();
    _handleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    _handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _followsYouLabel = [[UILabel alloc] init];
    _followsYouLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _followsYouLabel.hidden = YES;
    NFBIPAApplyFollowsYouBadgeAppearance(_followsYouLabel);

    UIStackView *nameStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _verifiedView]];
    nameStack.translatesAutoresizingMaskIntoConstraints = NO;
    nameStack.axis = UILayoutConstraintAxisHorizontal;
    nameStack.alignment = UIStackViewAlignmentCenter;
    nameStack.spacing = 4.0;

    UIStackView *handleStack = [[UIStackView alloc] initWithArrangedSubviews:@[_handleLabel, _followsYouLabel]];
    handleStack.translatesAutoresizingMaskIntoConstraints = NO;
    handleStack.axis = UILayoutConstraintAxisHorizontal;
    handleStack.alignment = UIStackViewAlignmentCenter;
    handleStack.spacing = 6.0;

    [self.contentView addSubview:_avatarView];
    [self.contentView addSubview:nameStack];
    [self.contentView addSubview:handleStack];

    [NSLayoutConstraint activateConstraints:@[
      [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
      [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
      [_avatarView.widthAnchor constraintEqualToConstant:44.0],
      [_avatarView.heightAnchor constraintEqualToConstant:44.0],
      [nameStack.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12.0],
      [nameStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
      [nameStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11.0],
      [_verifiedView.widthAnchor constraintEqualToConstant:16.0],
      [_verifiedView.heightAnchor constraintEqualToConstant:16.0],
      [handleStack.leadingAnchor constraintEqualToAnchor:nameStack.leadingAnchor],
      [handleStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
      [handleStack.topAnchor constraintEqualToAnchor:nameStack.bottomAnchor constant:2.0],
      [handleStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],
      [_followsYouLabel.heightAnchor constraintEqualToConstant:18.0],
      [_followsYouLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],
      [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:64.0]
    ]];
  }
  return self;
}

- (void)configureWithProfile:(NSDictionary *)profile {
  _nameLabel.text = [NFBAtprotoClient displayNameForProfile:profile ?: @{}];
  _verifiedView.hidden = ![NFBAtprotoClient isProfileVerified:profile ?: @{}];
  _handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:profile ?: @{}]];
  NFBIPAApplyFollowsYouBadgeAppearance(_followsYouLabel);
  _followsYouLabel.hidden = !NFBIPAProfileFollowsViewer(profile ?: @{});
  NFBLoadRemoteImage(_avatarView, [NFBAtprotoClient avatarURLForProfile:profile ?: @{}], NFBDefaultAvatarImage());
}

@end

@class NFBNewMessageViewController;

@protocol NFBNewMessageViewControllerDelegate <NSObject>
- (void)newMessageViewController:(NFBNewMessageViewController *)viewController didChooseProfiles:(NSArray<NSDictionary *> *)profiles;
@end

@interface NFBNewMessageViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, weak) id<NFBNewMessageViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, copy) NSString *searchPlaceholder;
@property (nonatomic, copy) NSArray<NSString *> *excludedDIDs;
@property (nonatomic, assign) NSUInteger maxSelectableProfiles;
@property (nonatomic, assign) BOOL requiresGroupEligibleProfiles;
@property (nonatomic, copy) NSString *selectionLimitMessage;
@end

@implementation NFBNewMessageViewController {
  UITextField *_searchField;
  UITableView *_tableView;
  NSArray<NSDictionary *> *_results;
  NSMutableArray<NSDictionary *> *_selectedProfiles;
  UILabel *_selectionLabel;
  UIBarButtonItem *_createButton;
  UIImageView *_loadingView;
  NSUInteger _searchGeneration;
}

- (instancetype)init {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _results = @[];
    _selectedProfiles = [NSMutableArray array];
    _excludedDIDs = @[];
    _maxSelectableProfiles = NFBChatGroupMaxInvitedMembers;
    _selectionLimitMessage = @"Bluesky group chats can include up to 49 invited people.";
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  NSString *title = self.pickerTitle.length > 0 ? self.pickerTitle : NFBTweetieLocalizedString(@"DM_NEW_CONVERSATION_NAVIGATION_BAR_NEW_MESSAGE_TITLE", @"New message");
  self.title = title;
  self.view.backgroundColor = NFBColorBackground();
  self.navigationItem.titleView = NFBTitleView(title, nil);
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  _createButton = [[UIBarButtonItem alloc] initWithTitle:[self currentActionTitle]
                                                   style:UIBarButtonItemStyleDone
                                                  target:self
                                                  action:@selector(createTapped)];
  _createButton.enabled = NO;
  self.navigationItem.rightBarButtonItem = _createButton;

  UIView *searchContainer = [[UIView alloc] init];
  searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
  searchContainer.backgroundColor = NFBColorBackground();

  UILabel *toLabel = [[UILabel alloc] init];
  toLabel.translatesAutoresizingMaskIntoConstraints = NO;
  toLabel.text = @"To:";
  toLabel.textColor = NFBColorText();
  toLabel.font = NFBFont(17.0, NFBFontWeightRegular);

  _searchField = [[UITextField alloc] init];
  _searchField.translatesAutoresizingMaskIntoConstraints = NO;
  NSString *placeholder = self.searchPlaceholder.length > 0 ? self.searchPlaceholder : @"Search people";
  NFBIPAApplySearchTextFieldAppearance(_searchField, placeholder);
  _searchField.returnKeyType = UIReturnKeySearch;
  _searchField.delegate = self;
  [_searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];

  _selectionLabel = [[UILabel alloc] init];
  _selectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _selectionLabel.textColor = NFBColorSecondaryText();
  _selectionLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  _selectionLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIView *divider = [[UIView alloc] init];
  divider.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(divider);

  [searchContainer addSubview:toLabel];
  [searchContainer addSubview:_searchField];
  [searchContainer addSubview:_selectionLabel];
  [searchContainer addSubview:divider];

  _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  _tableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(_tableView);
  _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  _tableView.dataSource = self;
  _tableView.delegate = self;
  [_tableView registerClass:NFBActorResultCell.class forCellReuseIdentifier:NFBActorResultCellIdentifier];

  _loadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  _loadingView.translatesAutoresizingMaskIntoConstraints = NO;
  _loadingView.tintColor = NFBColorSecondaryText();
  _loadingView.hidden = YES;

  [self.view addSubview:searchContainer];
  [self.view addSubview:_tableView];
  [self.view addSubview:_loadingView];
	  [NSLayoutConstraint activateConstraints:@[
	    [searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
	    [searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	    [searchContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
	    [searchContainer.heightAnchor constraintEqualToConstant:88.0],
	    [toLabel.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor constant:16.0],
	    [toLabel.topAnchor constraintEqualToAnchor:searchContainer.topAnchor constant:14.0],
	    [_searchField.leadingAnchor constraintEqualToAnchor:toLabel.trailingAnchor constant:10.0],
	    [_searchField.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor constant:-16.0],
	    [_searchField.centerYAnchor constraintEqualToAnchor:toLabel.centerYAnchor],
	    [_selectionLabel.leadingAnchor constraintEqualToAnchor:_searchField.leadingAnchor],
	    [_selectionLabel.trailingAnchor constraintEqualToAnchor:_searchField.trailingAnchor],
	    [_selectionLabel.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:6.0],
	    [_selectionLabel.heightAnchor constraintEqualToConstant:20.0],
	    [divider.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor],
	    [divider.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor],
	    [divider.bottomAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
    [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_tableView.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [_loadingView.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:18.0],
    [_loadingView.widthAnchor constraintEqualToConstant:28.0],
	    [_loadingView.heightAnchor constraintEqualToConstant:28.0]
	  ]];
  [self updateSelectionSummary];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [_searchField becomeFirstResponder];
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)createTapped {
  if (_selectedProfiles.count == 0) return;
  if (self.maxSelectableProfiles > 0 && _selectedProfiles.count > self.maxSelectableProfiles) {
    [self presentSelectionLimitAlert];
    return;
  }
  [self.delegate newMessageViewController:self didChooseProfiles:[_selectedProfiles copy]];
}

- (BOOL)isDIDExcluded:(NSString *)did {
  if (did.length == 0) return YES;
  if ([did isEqualToString:[NFBAtprotoSession sharedSession].did ?: @""]) return YES;
  for (NSString *excluded in self.excludedDIDs ?: @[]) {
    if ([excluded isKindOfClass:NSString.class] && [excluded isEqualToString:did]) return YES;
  }
  return NO;
}

- (NSArray<NSDictionary *> *)filteredMessageableActors:(NSArray<NSDictionary *> *)items {
  NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
  for (NSDictionary *profile in items ?: @[]) {
    if (![profile isKindOfClass:NSDictionary.class]) continue;
    if ([self isDIDExcluded:NFBStringValue(profile[@"did"])]) continue;
    [filtered addObject:profile];
  }
  return filtered;
}

- (NSUInteger)selectedIndexForProfile:(NSDictionary *)profile {
  NSString *did = NFBStringValue(profile[@"did"]);
  if (did.length == 0) return NSNotFound;
  for (NSUInteger index = 0; index < _selectedProfiles.count; index++) {
    NSDictionary *candidate = _selectedProfiles[index];
    if ([NFBStringValue(candidate[@"did"]) isEqualToString:did]) return index;
  }
  return NSNotFound;
}

- (void)toggleProfile:(NSDictionary *)profile {
  if (![profile isKindOfClass:NSDictionary.class]) return;
  if ([self isDIDExcluded:NFBStringValue(profile[@"did"])]) return;
  NSUInteger selectedIndex = [self selectedIndexForProfile:profile];
  if (selectedIndex == NSNotFound) {
    if (self.maxSelectableProfiles > 0 && _selectedProfiles.count >= self.maxSelectableProfiles) {
      [self presentSelectionLimitAlert];
      return;
    }
    if (![self canAddSelectedProfileToCurrentFlow:profile]) {
      [self presentGroupEligibilityAlert];
      return;
    }
    [_selectedProfiles addObject:profile];
    _searchField.text = @"";
    _results = @[];
    _searchGeneration++;
    _loadingView.hidden = YES;
    NFBStopLoadingAnimation(_loadingView);
  } else {
    [_selectedProfiles removeObjectAtIndex:selectedIndex];
  }
  [self updateSelectionSummary];
  [_tableView reloadData];
}

- (BOOL)profileCanBeAddedToGroup:(NSDictionary *)profile {
  if ([profile[NFBMessageableActorFollowsViewerKey] respondsToSelector:@selector(boolValue)] &&
      [profile[NFBMessageableActorFollowsViewerKey] boolValue]) {
    return YES;
  }
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  return NFBStringValue(viewer[@"followedBy"]).length > 0;
}

- (BOOL)canAddSelectedProfileToCurrentFlow:(NSDictionary *)profile {
  BOOL wouldBeGroup = self.requiresGroupEligibleProfiles || _selectedProfiles.count > 0;
  if (!wouldBeGroup) return YES;
  if (![self profileCanBeAddedToGroup:profile]) return NO;
  for (NSDictionary *selected in _selectedProfiles ?: @[]) {
    if (![self profileCanBeAddedToGroup:selected]) return NO;
  }
  return YES;
}

- (void)presentGroupEligibilityAlert {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_NEW_CONVERSATION_ACTION_SELECT_USER_ERROR_CANNOT_ADD_TO_GROUP", @"Cannot add this user")
                                                                 message:@"Group chats can only include people who follow you."
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentSelectionLimitAlert {
  NSString *message = self.selectionLimitMessage.length > 0 ? self.selectionLimitMessage : NFBTweetieLocalizedString(@"DIRECT_ADD_PEOPLE_MESSAGE_MAXIMUM_PARTICIPANT_COUNT_EXCEEDED", @"You cannot add more people to this conversation");
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"LIMIT_REACHED_LABEL", @"Limit reached")
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)currentActionTitle {
  if (self.actionTitle.length > 0) return self.actionTitle;
  if (_selectedProfiles.count > 1) return NFBTweetieLocalizedString(@"DM_NEW_CONVERSATION_ACTION_CREATE_GROUP", @"Create a group");
  return NFBTweetieLocalizedString(@"NEXT_ACTION_LABEL", @"Next");
}

- (void)updateSelectionSummary {
  _createButton.enabled = _selectedProfiles.count > 0;
  _createButton.title = [self currentActionTitle];
  if (_selectedProfiles.count == 0) {
    _selectionLabel.text = @"Select people to message";
    _selectionLabel.textColor = NFBColorSecondaryText();
    return;
  }
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  for (NSDictionary *profile in _selectedProfiles) {
    NSString *name = [NFBAtprotoClient displayNameForProfile:profile];
    if (name.length == 0) name = [NFBAtprotoClient handleForProfile:profile];
    if (name.length > 0) [names addObject:name];
  }
  _selectionLabel.text = [names componentsJoinedByString:@", "];
  if (self.maxSelectableProfiles > 0 && _selectedProfiles.count > 1) {
    _selectionLabel.text = [NSString stringWithFormat:@"%@ (%lu/%lu)", _selectionLabel.text, (unsigned long)_selectedProfiles.count, (unsigned long)self.maxSelectableProfiles];
  }
  _selectionLabel.textColor = NFBColorText();
}

- (void)searchChanged:(UITextField *)field {
  NSString *query = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  _searchGeneration++;
  NSUInteger generation = _searchGeneration;
  if (query.length == 0) {
    _results = @[];
    [_tableView reloadData];
    _loadingView.hidden = YES;
    NFBStopLoadingAnimation(_loadingView);
    return;
  }

  _loadingView.hidden = NO;
  NFBStartLoadingAnimation(_loadingView);
  [[NFBAtprotoClient sharedClient] searchMessageableActors:query limit:25 completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
	      if (generation != self->_searchGeneration) return;
	      self->_loadingView.hidden = YES;
	      NFBStopLoadingAnimation(self->_loadingView);
	      self->_results = error ? @[] : [self filteredMessageableActors:items ?: @[]];
	      [self->_tableView reloadData];
	    });
	  }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return (NSInteger)_results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NFBActorResultCell *cell = [tableView dequeueReusableCellWithIdentifier:NFBActorResultCellIdentifier forIndexPath:indexPath];
  NSDictionary *profile = _results[(NSUInteger)indexPath.row];
  [cell configureWithProfile:profile];
  cell.accessoryType = [self selectedIndexForProfile:profile] == NSNotFound ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
  cell.tintColor = NFBColorAccent();
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  [self toggleProfile:_results[(NSUInteger)indexPath.row]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  (void)textField;
  if (_results.count == 1) {
    [self toggleProfile:_results.firstObject];
    return NO;
  }
  [self createTapped];
  return NO;
}

@end

@class NFBConversationViewController;

@interface NFBConversationInfoViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, NFBNewMessageViewControllerDelegate>
- (instancetype)initWithConversation:(NSDictionary *)conversation;
@property (nonatomic, copy) void (^conversationChangedHandler)(NSDictionary *conversation);
@property (nonatomic, copy) void (^conversationDeletedHandler)(void);
@end

@implementation NFBConversationInfoViewController {
  UITableView *_tableView;
  NSDictionary *_conversation;
  NSArray<NSDictionary *> *_members;
  BOOL _loadingMembers;
}

- (instancetype)initWithConversation:(NSDictionary *)conversation {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _conversation = [conversation copy] ?: @{};
    _members = NFBChatMembers(_conversation);
    self.hidesBottomBarWhenPushed = YES;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  self.navigationItem.titleView = NFBTitleView(NFBChatConversationInfoTitle(_conversation), nil);
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));

  _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
  _tableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(_tableView);
  _tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
  _tableView.dataSource = self;
  _tableView.delegate = self;
  [self.view addSubview:_tableView];
  [NSLayoutConstraint activateConstraints:@[
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
	    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	  ]];
  [self hydrateGroupMembersIfNeeded];
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)canManageGroup {
  if (!NFBChatConversationIsGroup(_conversation)) return NO;
  if (NFBChatConversationIsLocked(_conversation)) return NO;
  return NFBChatViewerIsGroupOwner(_members ?: @[]);
}

- (NSUInteger)remainingMemberSlots {
  NSUInteger limit = NFBChatConversationMemberLimit(_conversation);
  if (limit == 0) limit = NFBChatGroupMaxTotalMembers;
  NSUInteger count = NFBChatConversationMemberCount(_conversation);
  if (count < _members.count) count = _members.count;
  return count < limit ? limit - count : 0;
}

- (BOOL)canAddMembers {
  return [self canManageGroup] && [self remainingMemberSlots] > 0 && NFBChatConversationHasOpenMemberSlots(_conversation);
}

- (BOOL)indexPathUsesProfileAvatar:(NSIndexPath *)indexPath {
  BOOL group = NFBChatConversationIsGroup(_conversation);
  if (group) {
    if (indexPath.section != 1) return NO;
    return !([self canAddMembers] && indexPath.row == 0);
  }
  return indexPath.section == 0;
}

- (void)resetInfoCellImageStyle:(UITableViewCell *)cell {
  cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
  cell.imageView.clipsToBounds = NO;
  cell.imageView.layer.masksToBounds = NO;
  cell.imageView.layer.cornerRadius = 0.0;
}

- (void)applyProfileAvatarStyleToCell:(UITableViewCell *)cell {
  cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
  cell.imageView.clipsToBounds = YES;
  cell.imageView.layer.masksToBounds = YES;
  CGFloat side = MIN(CGRectGetWidth(cell.imageView.bounds), CGRectGetHeight(cell.imageView.bounds));
  cell.imageView.layer.cornerRadius = side > 0.0 ? side * 0.5 : 18.0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  (void)tableView;
  return NFBChatConversationIsGroup(_conversation) ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  if (NFBChatConversationIsGroup(_conversation)) {
    if (section == 0) return [self canManageGroup] ? 2 : 1;
    if (section == 1) return (NSInteger)_members.count + ([self canAddMembers] ? 1 : 0);
    return 2;
  }
  return section == 0 ? 1 : 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
  (void)tableView;
  return section == 0 ? 16.0 : 24.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  UIView *view = [[UIView alloc] init];
  view.backgroundColor = NFBColorBackground();
  return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *identifier = @"info";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
  NFBIPAApplyTableCellAppearance(cell, UITableViewCellSelectionStyleDefault);
  cell.textLabel.textColor = NFBColorText();
  cell.detailTextLabel.textColor = NFBColorSecondaryText();
  cell.textLabel.font = NFBFont(16.0, NFBFontWeightRegular);
  cell.detailTextLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  cell.accessoryType = UITableViewCellAccessoryNone;
  NFBLoadRemoteImage(cell.imageView, nil, nil);
  cell.imageView.tintColor = NFBColorText();
  [self resetInfoCellImageStyle:cell];
  BOOL group = NFBChatConversationIsGroup(_conversation);
  if (group) {
    if (indexPath.section == 0 && indexPath.row == 0) {
      cell.textLabel.text = NFBChatConversationTitle(_conversation);
      cell.detailTextLabel.text = NFBChatConversationHandle(_conversation);
      NFBLoadRemoteImage(cell.imageView, nil, NFBChatGroupAvatarImage(40.0));
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 0 && indexPath.row == 1) {
      cell.textLabel.text = NFBTweetieLocalizedString(@"DM_EDIT_CONVERSATION_ACTION_EDIT_GROUP_NAME_TITLE", @"Edit group name");
      cell.detailTextLabel.text = @"";
      cell.imageView.image = NFBTemplateIcon(@"nfb_compose_square");
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && [self canAddMembers] && indexPath.row == 0) {
      cell.textLabel.text = NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_ADD_PEOPLE_LABEL", @"Add people");
      cell.detailTextLabel.text = @"";
      cell.imageView.image = NFBTemplateIcon(@"nfb_account_add");
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
      NSUInteger memberIndex = (NSUInteger)indexPath.row - ([self canAddMembers] ? 1 : 0);
      NSDictionary *profile = memberIndex < _members.count ? _members[memberIndex] : @{};
      cell.textLabel.text = [NFBAtprotoClient displayNameForProfile:profile];
      NSString *handle = [NFBAtprotoClient handleForProfile:profile];
      NSMutableArray<NSString *> *detailParts = [NSMutableArray array];
      if (handle.length > 0) [detailParts addObject:[@"@" stringByAppendingString:handle]];
      if (NFBChatProfileIsGroupOwner(profile)) [detailParts addObject:NFBTweetieLocalizedString(@"DIRECT_MESSAGES_GROUP_ADMIN_LABEL", @"Admin")];
      cell.detailTextLabel.text = [detailParts componentsJoinedByString:@"  "];
      cell.imageView.tintColor = nil;
      cell.imageView.image = NFBDefaultAvatarImage();
      [self applyProfileAvatarStyleToCell:cell];
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
      NFBLoadRemoteImage(cell.imageView, [NFBAtprotoClient avatarURLForProfile:profile], NFBDefaultAvatarImage());
    } else if (indexPath.row == 0) {
      BOOL muted = [_conversation[@"muted"] respondsToSelector:@selector(boolValue)] ? [_conversation[@"muted"] boolValue] : NO;
      cell.textLabel.text = NFBChatMuteConversationTitle(muted);
      cell.detailTextLabel.text = @"";
      cell.imageView.image = NFBTemplateIcon(@"nfb_notifications");
    } else {
      cell.textLabel.text = NFBChatDeleteConversationActionTitle(_conversation);
      cell.textLabel.textColor = UIColor.systemRedColor;
      cell.detailTextLabel.text = @"";
      cell.imageView.image = NFBTemplateIcon(@"nfb_trash");
      cell.imageView.tintColor = UIColor.systemRedColor;
    }
    return cell;
  }

  NSDictionary *profile = NFBChatPrimaryMember(_conversation);
  if (indexPath.section == 0) {
    cell.textLabel.text = [NFBAtprotoClient displayNameForProfile:profile];
    cell.detailTextLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:profile]];
    cell.imageView.tintColor = nil;
    cell.imageView.image = NFBDefaultAvatarImage();
    [self applyProfileAvatarStyleToCell:cell];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NFBLoadRemoteImage(cell.imageView, [NFBAtprotoClient avatarURLForProfile:profile], NFBDefaultAvatarImage());
  } else if (indexPath.row == 0) {
    BOOL muted = [_conversation[@"muted"] respondsToSelector:@selector(boolValue)] ? [_conversation[@"muted"] boolValue] : NO;
    cell.textLabel.text = NFBChatMuteConversationTitle(muted);
    cell.detailTextLabel.text = @"";
    cell.imageView.image = NFBTemplateIcon(@"nfb_notifications");
  } else {
    cell.textLabel.text = NFBChatDeleteConversationActionTitle(_conversation);
    cell.textLabel.textColor = UIColor.systemRedColor;
    cell.detailTextLabel.text = @"";
    cell.imageView.image = NFBTemplateIcon(@"nfb_trash");
    cell.imageView.tintColor = UIColor.systemRedColor;
  }
  return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  if ([self indexPathUsesProfileAvatar:indexPath]) {
    [self applyProfileAvatarStyleToCell:cell];
  } else {
    [self resetInfoCellImageStyle:cell];
  }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  BOOL group = NFBChatConversationIsGroup(_conversation);
  if (group && indexPath.section == 0 && indexPath.row == 1) {
    [self presentRenameGroupAlert];
    return;
  }
  if (group && indexPath.section == 1 && [self canAddMembers] && indexPath.row == 0) {
    [self addPeopleTapped];
    return;
  }
  if (group && indexPath.section == 1) {
    NSUInteger memberIndex = (NSUInteger)indexPath.row - ([self canAddMembers] ? 1 : 0);
    NSDictionary *profile = memberIndex < _members.count ? _members[memberIndex] : @{};
    if ([self canRemoveMember:profile]) {
      [self presentActionsForMember:profile];
    } else {
      [self openProfile:profile];
    }
    return;
  }
  if (!group && indexPath.section == 0) {
    NSDictionary *profile = NFBChatPrimaryMember(_conversation);
    [self openProfile:profile];
    return;
  }

  NSString *conversationID = NFBChatConversationID(_conversation);
  if (indexPath.row == 0) {
    BOOL muted = [_conversation[@"muted"] respondsToSelector:@selector(boolValue)] ? [_conversation[@"muted"] boolValue] : NO;
    [[NFBAtprotoClient sharedClient] setChatConversationMuted:conversationID muted:!muted completion:^(NSDictionary *value, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (error || !value) return;
        self->_conversation = value;
        if (self.conversationChangedHandler) self.conversationChangedHandler(value);
        [self->_tableView reloadData];
      });
    }];
    return;
  }

  __weak typeof(self) weakSelf = self;
  NFBPresentNeoFreeBirdMenuSheet(self, NFBChatDeleteConversationAlertTitle(_conversation), NFBChatDeleteConversationMessage(), @[
    @{
      @"id": @"delete",
      @"title": NFBChatDeleteConversationActionTitle(_conversation),
      @"subtitle": NFBChatDeleteConversationMessage(),
      @"icon": @"nfb_trash",
      @"destructive": @YES,
      @"handler": [^{
        [[NFBAtprotoClient sharedClient] leaveChatConversation:conversationID completion:^(NSDictionary *value, NSError *error) {
          (void)value;
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error) return;
            if (weakSelf.conversationDeletedHandler) weakSelf.conversationDeletedHandler();
          });
        }];
      } copy]
    }
  ], NFBTweetieCancelTitle());
}

- (void)openProfile:(NSDictionary *)profile {
  NSString *actor = NFBStringValue(profile[@"did"]);
  if (actor.length == 0) actor = NFBStringValue(profile[@"handle"]);
  if (actor.length == 0) return;
  NFBTimelineViewController *profileVC = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
  [self.navigationController pushViewController:profileVC animated:YES];
}

- (BOOL)canRemoveMember:(NSDictionary *)profile {
  if (![self canManageGroup]) return NO;
  if (NFBChatProfileIsViewer(profile)) return NO;
  if (NFBChatProfileIsGroupOwner(profile)) return NO;
  return NFBStringValue(profile[@"did"]).length > 0;
}

- (void)presentActionsForMember:(NSDictionary *)profile {
  NSString *title = [NFBAtprotoClient displayNameForProfile:profile ?: @{}];
  NSString *handle = [NFBAtprotoClient handleForProfile:profile ?: @{}];
  NSString *subtitle = handle.length > 0 ? [@"@" stringByAppendingString:handle] : nil;
  __weak typeof(self) weakSelf = self;
  NFBPresentNeoFreeBirdMenuSheet(self, title.length > 0 ? title : @"Group member", subtitle, @[
    @{
      @"id": @"profile",
      @"title": NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_VIEW_PROFILE_ACTION", @"View profile"),
      @"subtitle": NFBTweetieLocalizedString(@"GO_TO_PROFILE_LABEL", @"Go to profile"),
      @"icon": @"nfb_profile",
      @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf openProfile:profile];
      } copy]
    },
    @{
      @"id": @"remove",
      @"title": NFBTweetieLocalizedString(@"DM_MANAGE_CONVERSATION_ACTION_REMOVE_FROM_GROUP_TITLE", @"Remove from group"),
      @"subtitle": @"Remove this person from the conversation",
      @"icon": @"nfb_trash",
      @"destructive": @YES,
      @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf removeMember:profile];
      } copy]
    }
  ], NFBTweetieCancelTitle());
}

- (void)removeMember:(NSDictionary *)profile {
  NSString *conversationID = NFBChatConversationID(_conversation);
  NSString *did = NFBStringValue(profile[@"did"]);
  if (conversationID.length == 0 || did.length == 0 || ![self canRemoveMember:profile]) return;
  [[NFBAtprotoClient sharedClient] removeChatMembersFromConversationID:conversationID members:@[did] completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error || !value) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_MANAGE_CONVERSATION_ACTION_REMOVE_FROM_GROUP_ERROR_TITLE", @"Unable to remove from conversation")
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }
      self->_conversation = value;
      NSMutableArray<NSDictionary *> *nextMembers = [NSMutableArray array];
      for (NSDictionary *member in self->_members ?: @[]) {
        if (![NFBStringValue(member[@"did"]) isEqualToString:did]) [nextMembers addObject:member];
      }
      NSArray *valueMembers = [value[@"members"] isKindOfClass:NSArray.class] ? value[@"members"] : nil;
      self->_members = valueMembers.count > 0 ? NFBChatMembers(value) : nextMembers;
      if (self.conversationChangedHandler) self.conversationChangedHandler(value);
      [self->_tableView reloadData];
      [self hydrateGroupMembersIfNeeded];
    });
  }];
}

- (void)hydrateGroupMembersIfNeeded {
  if (_loadingMembers || !NFBChatConversationIsGroup(_conversation)) return;
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) return;
  _loadingMembers = YES;
  [[NFBAtprotoClient sharedClient] fetchChatMembersForConversationID:conversationID cursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_loadingMembers = NO;
      if (error || items.count == 0) return;
      self->_members = items;
      NSMutableDictionary *nextConversation = [self->_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
      nextConversation[@"members"] = items;
      self->_conversation = nextConversation;
      if (self.conversationChangedHandler) self.conversationChangedHandler(self->_conversation);
      [self->_tableView reloadData];
    });
  }];
}

- (void)presentRenameGroupAlert {
  if (![self canManageGroup]) return;
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) return;
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_EDIT_CONVERSATION_ACTION_EDIT_GROUP_NAME_TITLE", @"Edit group name")
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.text = NFBChatConversationTitle(self->_conversation);
    textField.placeholder = NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_NAME_GROUP_LABEL", @"Name your group");
  }];
  [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieCancelTitle() style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieSaveTitle() style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    (void)action;
    NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) return;
    [[NFBAtprotoClient sharedClient] editChatGroupWithConversationID:conversationID name:name completion:^(NSDictionary *value, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (error || !value) return;
        self->_conversation = value;
        self->_members = NFBChatMembers(value);
        self.navigationItem.titleView = NFBTitleView(NFBChatConversationInfoTitle(self->_conversation), nil);
        if (self.conversationChangedHandler) self.conversationChangedHandler(value);
        [self->_tableView reloadData];
        [self hydrateGroupMembersIfNeeded];
      });
    }];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<NSString *> *)currentMemberDIDs {
  NSMutableArray<NSString *> *dids = [NSMutableArray array];
  for (NSDictionary *member in _members ?: @[]) {
    NSString *did = NFBStringValue(member[@"did"]);
    if (did.length > 0) [dids addObject:did];
  }
  return dids;
}

- (void)addPeopleTapped {
  if (![self canAddMembers]) return;
  NSUInteger remaining = [self remainingMemberSlots];
  if (remaining == 0) return;
  NFBNewMessageViewController *picker = [[NFBNewMessageViewController alloc] init];
  picker.pickerTitle = NFBTweetieLocalizedString(@"DM_NEW_CONVERSATION_NAVIGATION_BAR_ADD_PEOPLE_TITLE", @"Add people");
  picker.actionTitle = NFBTweetieLocalizedString(@"ADD_ACTION_LABEL", @"Add");
  picker.searchPlaceholder = NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_ADD_PEOPLE_SEARCH_INPUT_PLACEHOLDER_TEXT", @"Find a person");
  picker.excludedDIDs = [self currentMemberDIDs];
  picker.maxSelectableProfiles = remaining;
  picker.requiresGroupEligibleProfiles = YES;
  picker.selectionLimitMessage = remaining == 1 ? @"This group has room for 1 more person." : [NSString stringWithFormat:@"This group has room for %lu more people.", (unsigned long)remaining];
  picker.delegate = self;
  [self.navigationController pushViewController:picker animated:YES];
}

- (void)newMessageViewController:(NFBNewMessageViewController *)viewController didChooseProfiles:(NSArray<NSDictionary *> *)profiles {
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0 || profiles.count == 0) return;
  NSMutableArray<NSString *> *dids = [NSMutableArray array];
  NSSet<NSString *> *currentDIDs = [NSSet setWithArray:[self currentMemberDIDs]];
  for (NSDictionary *profile in profiles ?: @[]) {
    NSString *did = NFBStringValue(profile[@"did"]);
    if (did.length > 0 && ![currentDIDs containsObject:did] && ![dids containsObject:did]) [dids addObject:did];
  }
  if (dids.count == 0) return;
  NSUInteger remaining = [self remainingMemberSlots];
  if (remaining > 0 && dids.count > remaining) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"LIMIT_REACHED_LABEL", @"Limit reached")
                                                                   message:remaining == 1 ? @"This group has room for 1 more person." : [NSString stringWithFormat:@"This group has room for %lu more people.", (unsigned long)remaining]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
    [viewController presentViewController:alert animated:YES completion:nil];
    return;
  }
  [[NFBAtprotoClient sharedClient] addChatMembersToConversationID:conversationID members:dids completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error || !value) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DIRECT_MESSAGE_ADD_PEOPLE_ERROR_TITLE", @"Could not add people")
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [viewController presentViewController:alert animated:YES completion:nil];
        return;
      }
      [viewController.navigationController popViewControllerAnimated:YES];
      self->_conversation = value;
      self->_members = NFBChatMembers(value);
      if (self.conversationChangedHandler) self.conversationChangedHandler(value);
      [self->_tableView reloadData];
      [self hydrateGroupMembersIfNeeded];
    });
  }];
}

@end

@class NFBMessageComposerView;

@protocol NFBMessageComposerViewDelegate <NSObject>
- (void)messageComposerViewDidTapMedia:(NFBMessageComposerView *)composerView;
- (void)messageComposerViewDidTapGIF:(NFBMessageComposerView *)composerView;
@end

@interface NFBMessageComposerView : UIView <UITextViewDelegate, NFBEmojiInputViewDelegate>
@property (nonatomic, weak) id<NFBMessageComposerViewDelegate> delegate;
@property (nonatomic, copy) void (^sendHandler)(NSString *text);
@property (nonatomic, assign) BOOL sending;
- (void)clearText;
@end

@implementation NFBMessageComposerView {
  UITextView *_textView;
  UILabel *_placeholderLabel;
  UIButton *_sendButton;
  NFBEmojiInputView *_emojiInputView;
  BOOL _usingEmojiPicker;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = NFBColorBackground();

    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    NFBIPAApplyTableSeparatorAppearance(divider);

    UIButton *mediaButton = [self iconButton:@"nfb_media"];
    [mediaButton addTarget:self action:@selector(mediaTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *gifButton = [self iconButton:@"nfb_gif"];
    [gifButton addTarget:self action:@selector(gifTapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *inputContainer = [[UIView alloc] init];
    inputContainer.translatesAutoresizingMaskIntoConstraints = NO;
    NFBIPAApplyMessageInputContainerAppearance(inputContainer);

    _textView = [[UITextView alloc] init];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.backgroundColor = UIColor.clearColor;
    _textView.textColor = NFBColorText();
    _textView.tintColor = NFBColorAccent();
    _textView.font = NFBFont(17.0, NFBFontWeightRegular);
    _textView.textContainerInset = UIEdgeInsetsMake(8.0, 0.0, 8.0, 0.0);
    _textView.textContainer.lineFragmentPadding = 0.0;
    _textView.scrollEnabled = NO;
    _textView.delegate = self;

    _placeholderLabel = [[UILabel alloc] init];
    _placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholderLabel.text = @"Start your message";
    _placeholderLabel.textColor = NFBColorSecondaryText();
    _placeholderLabel.font = NFBFont(17.0, NFBFontWeightRegular);

    UIButton *emojiButton = [self iconButton:@"nfb_emoji"];
    [emojiButton addTarget:self action:@selector(emojiTapped) forControlEvents:UIControlEventTouchUpInside];

    _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_sendButton setImage:NFBTemplateIcon(@"nfb_send") forState:UIControlStateNormal];
    _sendButton.enabled = NO;
    NFBIPAApplyMessageSendButtonAppearance(_sendButton, NO);
    [_sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];

    [inputContainer addSubview:_textView];
    [inputContainer addSubview:_placeholderLabel];
    [inputContainer addSubview:emojiButton];
    [self addSubview:divider];
    [self addSubview:mediaButton];
    [self addSubview:gifButton];
    [self addSubview:inputContainer];
    [self addSubview:_sendButton];

    [NSLayoutConstraint activateConstraints:@[
      [divider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [divider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [divider.topAnchor constraintEqualToAnchor:self.topAnchor],
      [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
      [mediaButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
      [mediaButton.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
      [mediaButton.widthAnchor constraintEqualToConstant:40.0],
      [mediaButton.heightAnchor constraintEqualToConstant:40.0],
      [gifButton.leadingAnchor constraintEqualToAnchor:mediaButton.trailingAnchor constant:2.0],
      [gifButton.centerYAnchor constraintEqualToAnchor:mediaButton.centerYAnchor],
      [gifButton.widthAnchor constraintEqualToConstant:40.0],
      [gifButton.heightAnchor constraintEqualToConstant:40.0],
      [inputContainer.leadingAnchor constraintEqualToAnchor:gifButton.trailingAnchor constant:4.0],
      [inputContainer.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-6.0],
      [inputContainer.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
      [inputContainer.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
      [_sendButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
      [_sendButton.centerYAnchor constraintEqualToAnchor:inputContainer.centerYAnchor],
      [_sendButton.widthAnchor constraintEqualToConstant:40.0],
      [_sendButton.heightAnchor constraintEqualToConstant:40.0],
      [_textView.leadingAnchor constraintEqualToAnchor:inputContainer.leadingAnchor constant:16.0],
      [_textView.trailingAnchor constraintEqualToAnchor:emojiButton.leadingAnchor constant:-8.0],
      [_textView.topAnchor constraintEqualToAnchor:inputContainer.topAnchor],
      [_textView.bottomAnchor constraintEqualToAnchor:inputContainer.bottomAnchor],
      [_placeholderLabel.leadingAnchor constraintEqualToAnchor:_textView.leadingAnchor],
      [_placeholderLabel.centerYAnchor constraintEqualToAnchor:inputContainer.centerYAnchor],
      [emojiButton.trailingAnchor constraintEqualToAnchor:inputContainer.trailingAnchor constant:-4.0],
      [emojiButton.centerYAnchor constraintEqualToAnchor:inputContainer.centerYAnchor],
      [emojiButton.widthAnchor constraintEqualToConstant:36.0],
      [emojiButton.heightAnchor constraintEqualToConstant:36.0],
      [self.heightAnchor constraintGreaterThanOrEqualToConstant:61.0]
    ]];
  }
  return self;
}

- (UIButton *)iconButton:(NSString *)iconName {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setImage:NFBTemplateIcon(iconName) forState:UIControlStateNormal];
  button.tintColor = NFBColorAccent();
  button.backgroundColor = UIColor.clearColor;
  return button;
}

- (void)mediaTapped {
  [self.delegate messageComposerViewDidTapMedia:self];
}

- (void)gifTapped {
  [self.delegate messageComposerViewDidTapGIF:self];
}

- (void)emojiTapped {
  if (_usingEmojiPicker) {
    [self emojiInputViewDidRequestKeyboard:_emojiInputView];
    return;
  }
  if (!_emojiInputView) {
    _emojiInputView = [[NFBEmojiInputView alloc] initWithFrame:CGRectZero];
    _emojiInputView.delegate = self;
  }
  _usingEmojiPicker = YES;
  _textView.inputView = _emojiInputView;
  [_emojiInputView applyTheme];
  [_textView reloadInputViews];
  [_textView becomeFirstResponder];
}

- (void)setSending:(BOOL)sending {
  _sending = sending;
  _sendButton.enabled = !sending && _textView.text.length > 0;
  NFBIPAApplyMessageSendButtonAppearance(_sendButton, _sendButton.enabled);
}

- (void)textViewDidChange:(UITextView *)textView {
  _placeholderLabel.hidden = textView.text.length > 0;
  _sendButton.enabled = !_sending && textView.text.length > 0;
  NFBIPAApplyMessageSendButtonAppearance(_sendButton, _sendButton.enabled);
}

- (void)sendTapped {
  NSString *text = [_textView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0 || self.sending) return;
  if (self.sendHandler) self.sendHandler(text);
}

- (void)clearText {
  _textView.text = @"";
  [self textViewDidChange:_textView];
}

- (void)emojiInputView:(NFBEmojiInputView *)inputView didSelectEmoji:(NSString *)emoji {
  (void)inputView;
  if (emoji.length == 0) return;
  NSRange range = _textView.selectedRange;
  NSString *text = _textView.text ?: @"";
  if (range.location == NSNotFound || NSMaxRange(range) > text.length) range = NSMakeRange(text.length, 0);
  _textView.text = [text stringByReplacingCharactersInRange:range withString:emoji];
  _textView.selectedRange = NSMakeRange(range.location + emoji.length, 0);
  [self textViewDidChange:_textView];
}

- (void)emojiInputViewDidRequestKeyboard:(NFBEmojiInputView *)inputView {
  (void)inputView;
  _usingEmojiPicker = NO;
  _textView.inputView = nil;
  [_textView reloadInputViews];
  [_textView becomeFirstResponder];
}

@end

@interface NFBConversationViewController () <UITableViewDataSource, UITableViewDelegate, NFBMessageBubbleCellDelegate, NFBMessageComposerViewDelegate, NFBQuotedPostViewDelegate>
@end

@implementation NFBConversationViewController {
  NSUInteger _owningAccountGeneration;
  UITableView *_tableView;
  UIScrollView *_messageScrollView;
  UIView *_messageContentView;
  NFBMessageComposerView *_composerView;
  UIView *_requestFooterView;
  UITextView *_readOnlyFooterView;
  BOOL _directMessageUnavailable;
  NSUInteger _messagePermissionGeneration;
  UILabel *_requestFooterLabel;
  UIButton *_requestAcceptButton;
  UIButton *_requestDeleteButton;
  UIButton *_requestBlockButton;
  NSLayoutConstraint *_composerHeightConstraint;
  NSLayoutConstraint *_composerBottomConstraint;
  UIImageView *_loadingView;
  UILabel *_statusLabel;
  NSArray<NSDictionary *> *_messages;
  NSDictionary *_conversation;
  NSString *_cursor;
  BOOL _loading;
  BOOL _loadingMoreMessages;
  BOOL _olderMessagesFailed;
  NSUInteger _messageLoadGeneration;
  NSMutableSet<NSString *> *_consumedMessageCursors;
  NSMutableDictionary<NSString *, NSValue *> *_messageRowFrames;
  BOOL _usedLogFallback;
  BOOL _didReloadAfterInitialLayout;
  BOOL _pendingScrollToBottom;
  BOOL _scrollingProgrammatically;
  CGFloat _lastRenderedMessageWidth;
  CGFloat _lastRenderedMessageHeight;
  NSMutableDictionary<NSString *, NSDictionary *> *_sharedPostsByURI;
  NSMutableSet<NSString *> *_resolvingSharedPostURIs;
  NSMutableSet<NSString *> *_failedSharedPostURIs;
}

- (BOOL)ownsCurrentAccount {
  return _owningAccountGeneration == [NFBAtprotoSession sharedSession].accountGeneration;
}

- (instancetype)initWithConversation:(NSDictionary *)conversation {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _owningAccountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
    _conversation = [conversation copy] ?: @{};
    _messages = @[];
    _consumedMessageCursors = [NSMutableSet set];
    _messageRowFrames = [NSMutableDictionary dictionary];
    _sharedPostsByURI = [NSMutableDictionary dictionary];
    _resolvingSharedPostURIs = [NSMutableSet set];
    _failedSharedPostURIs = [NSMutableSet set];
    self.hidesBottomBarWhenPushed = YES;
  }
  return self;
}

- (UIButton *)requestFooterButtonWithTitle:(NSString *)title style:(NFBIPAButtonStyle)style action:(SEL)action {
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeSystem];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setTitle:title forState:UIControlStateNormal];
  NFBIPAApplyButtonAppearance(button, style, NFBIPAButtonSizeMedium);
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [button.heightAnchor constraintEqualToConstant:38.0].active = YES;
  return button;
}

- (UIView *)createRequestFooterView {
  UIView *footer = [[UIView alloc] initWithFrame:CGRectZero];
  footer.translatesAutoresizingMaskIntoConstraints = NO;
  footer.backgroundColor = NFBColorBackground();
  footer.hidden = YES;

  UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
  separator.translatesAutoresizingMaskIntoConstraints = NO;
  separator.backgroundColor = NFBColorBorder();
  [footer addSubview:separator];

  _requestFooterLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  _requestFooterLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _requestFooterLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  _requestFooterLabel.textColor = NFBColorSecondaryText();
  _requestFooterLabel.textAlignment = NSTextAlignmentCenter;
  _requestFooterLabel.numberOfLines = 2;
  [footer addSubview:_requestFooterLabel];

  _requestDeleteButton = [self requestFooterButtonWithTitle:NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_DELETE_TITLE", @"Delete")
                                                      style:NFBIPAButtonStyleNeutralOutline
                                                     action:@selector(requestDeleteTapped)];
  _requestBlockButton = [self requestFooterButtonWithTitle:NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_BLOCK_TITLE", @"Block")
                                                     style:NFBIPAButtonStyleDestructive
                                                    action:@selector(requestBlockTapped)];
  _requestAcceptButton = [self requestFooterButtonWithTitle:NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_ACCEPT_TITLE", @"Accept")
                                                      style:NFBIPAButtonStylePrimary
                                                     action:@selector(requestAcceptTapped)];

  UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[_requestDeleteButton, _requestBlockButton, _requestAcceptButton]];
  buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
  buttonStack.axis = UILayoutConstraintAxisHorizontal;
  buttonStack.alignment = UIStackViewAlignmentFill;
  buttonStack.distribution = UIStackViewDistributionFillEqually;
  buttonStack.spacing = 10.0;
  [footer addSubview:buttonStack];

  [NSLayoutConstraint activateConstraints:@[
    [separator.topAnchor constraintEqualToAnchor:footer.topAnchor],
    [separator.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor],
    [separator.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
    [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [_requestFooterLabel.topAnchor constraintEqualToAnchor:footer.topAnchor constant:12.0],
    [_requestFooterLabel.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:18.0],
    [_requestFooterLabel.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-18.0],
    [buttonStack.topAnchor constraintEqualToAnchor:_requestFooterLabel.bottomAnchor constant:10.0],
    [buttonStack.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:18.0],
    [buttonStack.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-18.0]
  ]];
  return footer;
}


- (void)themeChanged:(NSNotification *)notification {
  [self configureNavigation];
  NFBApplyNavigationAppearance(self.navigationController);
  [_tableView reloadData];
  CGPoint offset = _messageScrollView.contentOffset;
  [self reloadRenderedMessages];
  _messageScrollView.contentOffset = offset;
  [self updateReadOnlyFooter];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  self.edgesForExtendedLayout = UIRectEdgeNone;
  self.view.backgroundColor = NFBColorBackground();
  [self configureNavigation];

  _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  _tableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(_tableView);
  _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  _tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 8.0, 0.0);
  _tableView.scrollIndicatorInsets = _tableView.contentInset;
  _tableView.hidden = YES;
  _tableView.userInteractionEnabled = NO;
  _tableView.dataSource = self;
  _tableView.delegate = self;
  _tableView.rowHeight = UITableViewAutomaticDimension;
  _tableView.estimatedRowHeight = 68.0;
  [_tableView registerClass:NFBMessageBubbleCell.class forCellReuseIdentifier:NFBMessageBubbleCellIdentifier];

  _messageScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
  _messageScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  _messageScrollView.backgroundColor = NFBColorBackground();
  _messageScrollView.alwaysBounceVertical = YES;
  _messageScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  _messageScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  _messageScrollView.scrollIndicatorInsets = UIEdgeInsetsMake(8.0, 0.0, 8.0, 0.0);
  _messageScrollView.delegate = self;

  _messageContentView = [[UIView alloc] initWithFrame:CGRectZero];
  _messageContentView.translatesAutoresizingMaskIntoConstraints = YES;
  _messageContentView.backgroundColor = NFBColorBackground();
  _messageContentView.clipsToBounds = NO;

  _composerView = [[NFBMessageComposerView alloc] initWithFrame:CGRectZero];
  _composerView.delegate = self;
  __weak typeof(self) weakSelf = self;
  _composerView.sendHandler = ^(NSString *text) {
    [weakSelf sendText:text];
  };
  _requestFooterView = [self createRequestFooterView];
  _readOnlyFooterView = [[UITextView alloc] init];
  _readOnlyFooterView.translatesAutoresizingMaskIntoConstraints = NO;
  _readOnlyFooterView.editable = NO;
  _readOnlyFooterView.scrollEnabled = NO;
  _readOnlyFooterView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 12.0, 16.0);
  _readOnlyFooterView.hidden = YES;
  [self updateReadOnlyFooter];

  _loadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  _loadingView.translatesAutoresizingMaskIntoConstraints = NO;
  _loadingView.tintColor = NFBColorSecondaryText();
  _loadingView.hidden = YES;

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _statusLabel.textColor = NFBColorSecondaryText();
  _statusLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  _statusLabel.textAlignment = NSTextAlignmentCenter;
  _statusLabel.numberOfLines = 0;
  _statusLabel.hidden = YES;

  [self.view addSubview:_tableView];
  [self.view addSubview:_messageScrollView];
  [_messageScrollView addSubview:_messageContentView];
  [self.view addSubview:_composerView];
  [self.view addSubview:_requestFooterView];
  [self.view addSubview:_readOnlyFooterView];
  [self.view addSubview:_loadingView];
  [self.view addSubview:_statusLabel];
  _composerHeightConstraint = [_composerView.heightAnchor constraintEqualToConstant:61.0];
  _composerBottomConstraint = [_composerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
  [NSLayoutConstraint activateConstraints:@[
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [_tableView.bottomAnchor constraintEqualToAnchor:_composerView.topAnchor],
    [_messageScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_messageScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_messageScrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_messageScrollView.bottomAnchor constraintEqualToAnchor:_composerView.topAnchor],
    [_composerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_composerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    _composerHeightConstraint,
    _composerBottomConstraint,
    [_readOnlyFooterView.leadingAnchor constraintEqualToAnchor:_composerView.leadingAnchor],
    [_readOnlyFooterView.trailingAnchor constraintEqualToAnchor:_composerView.trailingAnchor],
    [_readOnlyFooterView.topAnchor constraintEqualToAnchor:_composerView.topAnchor],
    [_readOnlyFooterView.bottomAnchor constraintEqualToAnchor:_composerView.bottomAnchor],
    [_requestFooterView.leadingAnchor constraintEqualToAnchor:_composerView.leadingAnchor],
    [_requestFooterView.trailingAnchor constraintEqualToAnchor:_composerView.trailingAnchor],
    [_requestFooterView.topAnchor constraintEqualToAnchor:_composerView.topAnchor],
    [_requestFooterView.bottomAnchor constraintEqualToAnchor:_composerView.bottomAnchor],
    [_loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [_loadingView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:18.0],
    [_loadingView.widthAnchor constraintEqualToConstant:28.0],
    [_loadingView.heightAnchor constraintEqualToConstant:28.0],
    [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32.0],
    [_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32.0],
    [_statusLabel.centerYAnchor constraintEqualToAnchor:_messageScrollView.centerYAnchor]
  ]];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillHideNotification object:nil];

  [self applyConversationPermissionState];
  [self loadCachedMessagesIfAvailable];
  [self applyConversationPermissionState];
  [self hydrateConversationMembersIfNeeded];
  [self seedMessagesFromConversationIfNeeded];
  [self loadMessages];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self refreshDirectMessagePermission];
}

- (void)updateReadOnlyFooter {
  NSString *html = NFBTweetieLocalizedString(@"DIRECT_MESSAGES_READ_ONLY_FOOTER_MESSAGE", @"You can no longer send Direct Messages to this person. <a href=\"#\">Learn more</a>");
  NSRange start = [html rangeOfString:@"<a "], end = [html rangeOfString:@"</a>"];
  NSMutableAttributedString *text = nil;
  if (start.location != NSNotFound && end.location != NSNotFound && end.location > start.location) {
    NSRange close = [html rangeOfString:@">" options:0 range:NSMakeRange(start.location, end.location - start.location)];
    if (close.location != NSNotFound) {
      NSString *prefix = [html substringToIndex:start.location];
      NSString *link = [html substringWithRange:NSMakeRange(NSMaxRange(close), end.location - NSMaxRange(close))];
      text = [[NSMutableAttributedString alloc] initWithString:[prefix stringByAppendingString:link]];
      [text addAttribute:NSLinkAttributeName value:@"https://bsky.social/about/blog/05-22-2024-direct-messages" range:NSMakeRange(prefix.length, link.length)];
    }
  }
  if (!text) text = [[NSMutableAttributedString alloc] initWithString:html];
  NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
  paragraph.alignment = NSTextAlignmentCenter;
  [text addAttributes:@{NSFontAttributeName: NFBFont(14.0, NFBFontWeightRegular), NSForegroundColorAttributeName: NFBColorSecondaryText(), NSParagraphStyleAttributeName: paragraph} range:NSMakeRange(0, text.length)];
  _readOnlyFooterView.attributedText = text;
  _readOnlyFooterView.backgroundColor = NFBColorBackground();
  _readOnlyFooterView.linkTextAttributes = @{NSForegroundColorAttributeName: NFBColorAccent()};
}

- (void)refreshDirectMessagePermission {
  if (![self ownsCurrentAccount] || NFBChatConversationIsGroup(_conversation)) return;
  NSArray *members = NFBChatNonViewerMembers(_conversation);
  if (members.count != 1) return;
  NSString *did = NFBStringValue(members.firstObject[@"did"]);
  if (did.length == 0) return;
  NSUInteger generation = ++_messagePermissionGeneration;
  [[NFBAtprotoClient sharedClient] fetchChatConversationAvailabilityForMembers:@[did] completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount] || generation != self->_messagePermissionGeneration || error) return;
      self->_directMessageUnavailable = !NFBChatAvailabilityAllowsMessaging(value);
      if (self->_directMessageUnavailable) [self->_composerView endEditing:YES];
      [self applyConversationPermissionState];
      [self.view setNeedsLayout];
    });
  }];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self updateComposerHeightForCurrentSafeArea];
  [self layoutMessageScrollViewFrame];
  [self updateTableInsetsForCurrentContent];
  CGFloat renderWidth = _messageScrollView.bounds.size.width;
  CGFloat renderHeight = _messageScrollView.bounds.size.height;
  BOOL renderSizeChanged = fabs(renderWidth - _lastRenderedMessageWidth) > 0.5 || fabs(renderHeight - _lastRenderedMessageHeight) > 0.5;
  if (_messages.count > 0 && renderWidth > 0.0 && renderHeight > 0.0 && renderSizeChanged) {
    BOOL wasNearBottom = [self isScrolledNearBottom];
    CGFloat oldContentHeight = _messageScrollView.contentSize.height;
    CGFloat oldOffsetY = _messageScrollView.contentOffset.y;
    [self reloadRenderedMessages];
    if (_pendingScrollToBottom || wasNearBottom) {
      [self scrollToBottomAnimated:NO];
    } else if (oldContentHeight > 0.0) {
      CGFloat delta = _messageScrollView.contentSize.height - oldContentHeight;
      CGFloat maxOffsetY = MAX(0.0, _messageScrollView.contentSize.height - CGRectGetHeight(_messageScrollView.bounds));
      [self setMessageScrollOffsetY:MIN(MAX(0.0, oldOffsetY + delta), maxOffsetY) animated:NO];
    }
  }
  if (!_didReloadAfterInitialLayout && _tableView.bounds.size.height > 0.0) {
    _didReloadAfterInitialLayout = YES;
    if (_messages.count > 0) {
      [_tableView reloadData];
      [_tableView layoutIfNeeded];
      [self reloadRenderedMessages];
      [self scrollToBottomAnimated:NO];
    }
  }
}

- (void)viewSafeAreaInsetsDidChange {
  [super viewSafeAreaInsetsDidChange];
  [self updateComposerHeightForCurrentSafeArea];
}

- (BOOL)shouldShowRequestFooter {
  return NFBChatConversationIsRequest(_conversation ?: @{});
}

- (void)updateRequestFooter {
  if (!_requestFooterView) return;
  _requestFooterLabel.text = NFBChatConversationRequestMessage(_conversation ?: @{});
  _requestBlockButton.hidden = NFBChatRequestBlockProfile(_conversation ?: @{}).count == 0;
}

- (void)updateComposerHeightForCurrentSafeArea {
  CGFloat bottomInset = MAX(0.0, self.view.safeAreaInsets.bottom);
  CGFloat height = 0.0;
  if ([self canSendMessagesInCurrentConversation]) {
    height = 61.0 + bottomInset;
  } else if ([self shouldShowRequestFooter]) {
    height = 112.0 + bottomInset;
  } else if (_directMessageUnavailable) {
    height = MAX(76.0, [_readOnlyFooterView sizeThatFits:CGSizeMake(CGRectGetWidth(self.view.bounds), CGFLOAT_MAX)].height) + bottomInset;
  }
  if (fabs(_composerHeightConstraint.constant - height) > 0.5) {
    _composerHeightConstraint.constant = height;
  }
}

- (BOOL)canSendMessagesInCurrentConversation {
  return !_directMessageUnavailable && NFBChatConversationCanSendMessages(_conversation ?: @{});
}

- (void)applyConversationPermissionState {
  BOOL canSend = [self canSendMessagesInCurrentConversation];
  BOOL showRequestFooter = !canSend && [self shouldShowRequestFooter];
  _composerView.hidden = !canSend;
  _composerView.userInteractionEnabled = canSend;
  _readOnlyFooterView.hidden = !_directMessageUnavailable || showRequestFooter;
  _requestFooterView.hidden = !showRequestFooter;
  _requestFooterView.userInteractionEnabled = showRequestFooter;
  if (showRequestFooter) {
    [self updateRequestFooter];
    _statusLabel.hidden = YES;
  }
  [self updateComposerHeightForCurrentSafeArea];
  if (!canSend && !showRequestFooter && !_directMessageUnavailable && _messages.count == 0) {
    [self showStatusText:NFBChatConversationReadOnlyMessage(_conversation ?: @{})];
  } else if (_messages.count > 0 && [_statusLabel.text isEqualToString:NFBChatConversationReadOnlyMessage(_conversation ?: @{})]) {
    _statusLabel.hidden = YES;
  }
}

- (void)layoutMessageScrollViewFrame {
  if (!_messageScrollView) return;
  CGFloat width = CGRectGetWidth(_messageScrollView.bounds);
  CGFloat height = CGRectGetHeight(_messageScrollView.bounds);
  if (width <= 0.0) width = CGRectGetWidth(self.view.bounds);
  if (height <= 0.0) height = MAX(0.0, CGRectGetMinY(_composerView.frame));
  if (width <= 0.0 || height <= 0.0) return;

  CGFloat contentHeight = MAX(height + 1.0, _messageScrollView.contentSize.height);
  _messageContentView.frame = CGRectMake(0.0, 0.0, width, contentHeight);
  UIEdgeInsets inset = UIEdgeInsetsZero;
  _messageScrollView.contentInset = inset;
  _messageScrollView.scrollIndicatorInsets = inset;
  [self.view bringSubviewToFront:_messageScrollView];
  [self.view bringSubviewToFront:_composerView];
  [self.view bringSubviewToFront:_requestFooterView];
  [self.view bringSubviewToFront:_readOnlyFooterView];
  [self.view bringSubviewToFront:_loadingView];
  [self.view bringSubviewToFront:_statusLabel];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
  NSDictionary *userInfo = notification.userInfo ?: @{};
  CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect keyboardInView = [self.view convertRect:keyboardFrame fromView:nil];
  CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - keyboardInView.origin.y);
  _composerBottomConstraint.constant = -overlap;

  NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] respondsToSelector:@selector(doubleValue)] ? [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] : 0.25;
  UIViewAnimationOptions options = UIViewAnimationOptionCurveEaseInOut;
  NSNumber *curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] isKindOfClass:NSNumber.class] ? userInfo[UIKeyboardAnimationCurveUserInfoKey] : nil;
  if (curve) options = (UIViewAnimationOptions)(curve.unsignedIntegerValue << 16);
  [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
    [self.view layoutIfNeeded];
    [self updateTableInsetsForCurrentContent];
  } completion:^(BOOL finished) {
    (void)finished;
    [self scrollToBottomAnimated:NO];
  }];
}

- (void)configureNavigation {
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  self.navigationItem.titleView = NFBTitleView(NFBChatConversationTitle(_conversation), NFBChatConversationHandle(_conversation));
  UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeCustom];
  infoButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
  [infoButton setImage:NFBTemplateIcon(@"nfb_conversation_info") forState:UIControlStateNormal];
  infoButton.accessibilityLabel = NFBTweetieLocalizedString(@"DM_CONVERSATION_INFO_TITLE", @"Conversation info");
  infoButton.tintColor = NFBColorText();
  [infoButton addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:infoButton];
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)setRequestFooterActionsEnabled:(BOOL)enabled {
  _requestAcceptButton.enabled = enabled;
  _requestDeleteButton.enabled = enabled;
  _requestBlockButton.enabled = enabled;
  _requestFooterView.userInteractionEnabled = enabled;
}

- (void)requestAcceptTapped {
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) return;
  [self setRequestFooterActionsEnabled:NO];
  [[NFBAtprotoClient sharedClient] acceptChatConversation:conversationID completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self setRequestFooterActionsEnabled:YES];
      if (error || !value) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_MESSAGE_SEND_ERROR_FAILED_TO_SEND", @"Message failed to send")
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }
      NSMutableDictionary *nextConversation = [self->_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
      [nextConversation addEntriesFromDictionary:value];
      self->_conversation = nextConversation;
      [self configureNavigation];
      [self applyConversationPermissionState];
      [self hydrateConversationMembersIfNeeded];
      [self saveMessageCache];
      if (self.conversationChangedHandler) self.conversationChangedHandler(self->_conversation);
      [self->_tableView reloadData];
      [self reloadRenderedMessages];
      [self scrollToBottomAnimated:NO];
    });
  }];
}

- (void)requestDeleteTapped {
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) return;
  [self setRequestFooterActionsEnabled:NO];
  [[NFBAtprotoClient sharedClient] leaveChatConversation:conversationID completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self setRequestFooterActionsEnabled:YES];
      if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBChatDeleteConversationActionTitle(self->_conversation ?: @{})
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }
      NFBChatRemoveCacheNamed([self messageCacheName]);
      if (self.conversationDeletedHandler) self.conversationDeletedHandler();
      [self.navigationController popViewControllerAnimated:YES];
    });
  }];
}

- (void)requestBlockTapped {
  NSString *conversationID = NFBChatConversationID(_conversation);
  NSDictionary *profile = NFBChatRequestBlockProfile(_conversation ?: @{});
  if (conversationID.length == 0 || profile.count == 0) return;
  [self setRequestFooterActionsEnabled:NO];
  [[NFBAtprotoClient sharedClient] blockProfileIfNeeded:profile completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        [self setRequestFooterActionsEnabled:YES];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_BLOCK_TITLE", @"Block")
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }
      [[NFBAtprotoClient sharedClient] leaveChatConversation:conversationID completion:^(NSDictionary *leaveValue, NSError *leaveError) {
        (void)leaveValue;
        dispatch_async(dispatch_get_main_queue(), ^{
          [self setRequestFooterActionsEnabled:YES];
          if (leaveError) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBChatDeleteConversationActionTitle(self->_conversation ?: @{})
                                                                           message:leaveError.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
          }
          NFBChatRemoveCacheNamed([self messageCacheName]);
          if (self.conversationDeletedHandler) self.conversationDeletedHandler();
          [self.navigationController popViewControllerAnimated:YES];
        });
      }];
    });
  }];
}

- (NSString *)messageCacheName {
  NSString *conversationID = NFBChatConversationID(_conversation);
  return conversationID.length > 0 ? NFBChatConversationCacheName(conversationID) : nil;
}

- (void)loadCachedMessagesIfAvailable {
  if (![self ownsCurrentAccount]) return;
  NSString *cacheName = [self messageCacheName];
  if (cacheName.length == 0) return;
  NSDictionary *cache = NFBChatLoadCacheNamed(cacheName);
  if (cache.count == 0) return;

  NSDictionary *cachedConversation = [cache[@"conversation"] isKindOfClass:NSDictionary.class] ? cache[@"conversation"] : nil;
  if (cachedConversation.count > 0) {
    NSMutableDictionary *nextConversation = [_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
    [nextConversation addEntriesFromDictionary:cachedConversation];
    _conversation = nextConversation;
    [self configureNavigation];
    [self applyConversationPermissionState];
  }

  NSArray *cachedMessages = [cache[@"messages"] isKindOfClass:NSArray.class] ? cache[@"messages"] : @[];
  if (cachedMessages.count == 0) return;
  _messages = NFBMergedChatMessages(@[], cachedMessages);
  _cursor = NFBStringValue(cache[@"cursor"]);
  _statusLabel.hidden = YES;
  [self hydrateSharedPostsForCurrentMessages];
  [_tableView reloadData];
  [_tableView layoutIfNeeded];
  [self updateTableInsetsForCurrentContent];
  [self reloadRenderedMessages];
  _pendingScrollToBottom = YES;
  NSLog(@"NotTwitter chat cache loaded convo=%@ count=%lu", NFBChatConversationID(_conversation), (unsigned long)_messages.count);
}

- (void)saveMessageCache {
  if (![self ownsCurrentAccount]) return;
  NSString *cacheName = [self messageCacheName];
  if (cacheName.length == 0) return;
  NSMutableDictionary *payload = [@{
    @"conversation": _conversation ?: @{},
    @"messages": NFBChatCacheSlice(_messages, 500, YES)
  } mutableCopy];
  if (_messages.count <= 500 && _cursor.length > 0) payload[@"cursor"] = _cursor;
  NFBChatSaveCacheNamed(cacheName, payload);
}

- (void)hydrateConversationMembersIfNeeded {
  if (![self ownsCurrentAccount]) return;
  if (!NFBChatConversationIsGroup(_conversation)) return;
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) return;
  NSUInteger memberCount = NFBChatConversationMemberCount(_conversation);
  if (memberCount > 0 && NFBChatMembers(_conversation).count >= memberCount) return;
  [[NFBAtprotoClient sharedClient] fetchChatMembersForConversationID:conversationID cursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount]) return;
      if (error || items.count == 0) return;
      NSMutableDictionary *nextConversation = [self->_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
      nextConversation[@"members"] = items;
      self->_conversation = nextConversation;
      [self configureNavigation];
      [self applyConversationPermissionState];
      [self saveMessageCache];
      [self->_tableView reloadData];
      [self reloadRenderedMessages];
      if (self.conversationChangedHandler) self.conversationChangedHandler(self->_conversation);
    });
  }];
}

- (void)rememberSharedPostsFromMessages:(NSArray<NSDictionary *> *)messages {
  for (NSDictionary *message in messages ?: @[]) {
    NSDictionary *sharedPost = NFBChatSharedPostForMessage(message);
    if (sharedPost.count == 0) continue;
    NSString *uri = NFBChatSharedPostURIFromMessage(message);
    if (uri.length == 0) uri = NFBStringValue(sharedPost[@"uri"]);
    if (uri.length > 0) _sharedPostsByURI[uri] = sharedPost;
  }
}

- (NSArray<NSDictionary *> *)messagesByApplyingSharedPostCache:(NSArray<NSDictionary *> *)messages {
  NSMutableArray<NSDictionary *> *next = [NSMutableArray arrayWithCapacity:messages.count];
  for (NSDictionary *message in messages ?: @[]) {
    if (![message isKindOfClass:NSDictionary.class]) continue;
    NSString *uri = NFBChatSharedPostURIFromMessage(message);
    NSDictionary *cachedPost = uri.length > 0 ? _sharedPostsByURI[uri] : nil;
    if (cachedPost.count == 0 && NFBChatSharedPostForMessage(message).count == 0) {
      [next addObject:message];
      continue;
    }
    NSMutableDictionary *item = [message mutableCopy];
    NSMutableDictionary *target = item;
    if ([item[@"message"] isKindOfClass:NSDictionary.class] && ![item[@"id"] isKindOfClass:NSString.class]) {
      target = [item[@"message"] mutableCopy];
      item[@"message"] = target;
    }
    if (uri.length > 0) {
      item[NFBChatSharedPostURIKey] = uri;
      target[NFBChatSharedPostURIKey] = uri;
    }
    if (cachedPost.count > 0) {
      item[NFBChatSharedPostKey] = cachedPost;
      target[NFBChatSharedPostKey] = cachedPost;
    }
    [next addObject:item];
  }
  return next;
}

- (void)applySharedPostCacheToConversation {
  NSDictionary *lastMessage = NFBChatLastMessage(_conversation);
  if (!lastMessage) return;
  NSArray<NSDictionary *> *updated = [self messagesByApplyingSharedPostCache:@[lastMessage]];
  NSDictionary *nextLastMessage = updated.firstObject;
  if (!nextLastMessage || [nextLastMessage isEqual:lastMessage]) return;
  NSMutableDictionary *nextConversation = [_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
  nextConversation[@"lastMessage"] = nextLastMessage;
  _conversation = nextConversation;
}

- (void)fetchSharedPostForURI:(NSString *)uri completion:(void (^)(NSDictionary *post, NSError *error))completion {
  NSString *actor = NFBChatPostActorFromURI(uri);
  NSString *rkey = NFBChatPostRkeyFromURI(uri);
  if (actor.length == 0 || rkey.length == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"NFBMessagesViewController" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Shared post link was not available."}]);
    return;
  }

  void (^fetchPostWithActor)(NSString *) = ^(NSString *resolvedActor) {
    NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", resolvedActor, rkey];
    [[NFBAtprotoClient sharedClient] fetchPostForURI:postURI completion:^(NSDictionary *post, NSError *error) {
      if (completion) completion(post, error);
    }];
  };

  if ([actor hasPrefix:@"did:"]) {
    fetchPostWithActor(actor);
    return;
  }

  [[NFBAtprotoClient sharedClient] fetchProfileForActor:actor completion:^(NSDictionary *profile, NSError *error) {
    NSString *did = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
    if (did.length == 0) {
      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"NFBMessagesViewController" code:13 userInfo:@{NSLocalizedDescriptionKey: @"Shared post author could not be resolved."}]);
      return;
    }
    fetchPostWithActor(did);
  }];
}

- (void)hydrateSharedPostsForCurrentMessages {
  if (![self ownsCurrentAccount]) return;
  [self rememberSharedPostsFromMessages:_messages];
  NSArray<NSDictionary *> *cachedMessages = [self messagesByApplyingSharedPostCache:_messages];
  if (![cachedMessages isEqualToArray:_messages]) {
    _messages = cachedMessages;
    [self applySharedPostCacheToConversation];
  }

  NSMutableArray<NSString *> *urisToFetch = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (NSDictionary *message in _messages ?: @[]) {
    NSString *uri = NFBChatSharedPostURIFromMessage(message);
    if (uri.length == 0 || [seen containsObject:uri]) continue;
    [seen addObject:uri];
    if (_sharedPostsByURI[uri] || [_resolvingSharedPostURIs containsObject:uri] || [_failedSharedPostURIs containsObject:uri]) continue;
    [_resolvingSharedPostURIs addObject:uri];
    [urisToFetch addObject:uri];
  }
  if (urisToFetch.count == 0) return;

  for (NSString *uri in urisToFetch) {
    [self fetchSharedPostForURI:uri completion:^(NSDictionary *post, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (![self ownsCurrentAccount]) return;
        [self->_resolvingSharedPostURIs removeObject:uri];
        if (error || post.count == 0) {
          [self->_failedSharedPostURIs addObject:uri];
          return;
        }
        self->_sharedPostsByURI[uri] = post;
        NSString *canonicalURI = NFBStringValue(post[@"uri"]);
        if (canonicalURI.length > 0) self->_sharedPostsByURI[canonicalURI] = post;
        BOOL wasNearBottom = [self isScrolledNearBottom];
        NSDictionary *anchor = [self visibleMessageAnchor];
        self->_messages = [self messagesByApplyingSharedPostCache:self->_messages];
        [self applySharedPostCacheToConversation];
        [self saveMessageCache];
        [self->_tableView reloadData];
        [self->_tableView layoutIfNeeded];
        [self updateTableInsetsForCurrentContent];
        [self reloadRenderedMessages];
        if (wasNearBottom) {
          [self scrollToBottomAnimated:NO];
        } else {
          [self restoreVisibleMessageAnchor:anchor];
        }
        if (self.conversationChangedHandler) self.conversationChangedHandler(self->_conversation);
      });
    }];
  }
}

- (void)infoTapped {
  NFBConversationInfoViewController *info = [[NFBConversationInfoViewController alloc] initWithConversation:_conversation];
  __weak typeof(self) weakSelf = self;
  info.conversationChangedHandler = ^(NSDictionary *conversation) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    strongSelf->_conversation = conversation ?: strongSelf->_conversation;
    [strongSelf configureNavigation];
    [strongSelf applyConversationPermissionState];
    [strongSelf saveMessageCache];
    if (strongSelf.conversationChangedHandler) strongSelf.conversationChangedHandler(strongSelf->_conversation);
  };
  info.conversationDeletedHandler = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    NFBChatRemoveCacheNamed([strongSelf messageCacheName]);
    if (strongSelf.conversationDeletedHandler) strongSelf.conversationDeletedHandler();
    [strongSelf.navigationController popToRootViewControllerAnimated:YES];
  };
  [self.navigationController pushViewController:info animated:YES];
}

- (void)loadMessages {
  if (![self ownsCurrentAccount]) return;
  if (_loading) return;
  NSUInteger generation = ++_messageLoadGeneration;
  _loadingMoreMessages = NO;
  _olderMessagesFailed = NO;
  [_consumedMessageCursors removeAllObjects];
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) {
    [self showStatusText:@"This conversation is not available."];
    return;
  }
  _loading = YES;
  _statusLabel.hidden = YES;
  _loadingView.hidden = NO;
  NFBStartLoadingAnimation(_loadingView);
  [[NFBAtprotoClient sharedClient] fetchChatMessagesForConversationID:conversationID cursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount] || generation != self->_messageLoadGeneration) return;

      self->_loadingView.hidden = YES;
      NFBStopLoadingAnimation(self->_loadingView);
      if (error) {
        NSLog(@"NotTwitter chat thread load failed convo=%@ error=%@", conversationID, error.localizedDescription ?: @"unknown");
        [self seedMessagesFromConversationIfNeeded];
        self->_loading = NO;
        [self loadMessagesFromLogFallbackForConversationID:conversationID emptyStatus:error.localizedDescription ?: @"Could not load this conversation."];
        return;
      }
      BOOL followBottom = self->_messages.count == 0 || self->_pendingScrollToBottom || [self isScrolledNearBottom];
      NSDictionary *anchor = [self visibleMessageAnchor];
      if (items.count > 0) {
        self->_messages = NFBMergedChatMessages(self->_messages, items ?: @[]);
        NSMutableDictionary *nextConversation = [self->_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
        NSDictionary *lastMessage = self->_messages.lastObject;
        if (lastMessage) nextConversation[@"lastMessage"] = lastMessage;
        self->_conversation = nextConversation;
        [self hydrateSharedPostsForCurrentMessages];
      } else {
        [self seedMessagesFromConversationIfNeeded];
        self->_loading = NO;
        [self loadMessagesFromLogFallbackForConversationID:conversationID emptyStatus:@"No messages yet."];
        return;
      }
      self->_cursor = cursor;
      [self saveMessageCache];
      [self->_tableView reloadData];
      [self->_tableView layoutIfNeeded];
      [self updateTableInsetsForCurrentContent];
      [self reloadRenderedMessages];
      if (followBottom) {
        self->_pendingScrollToBottom = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
          if (![self ownsCurrentAccount] || generation != self->_messageLoadGeneration) return;
          [self scrollToBottomAnimated:NO];
        });
      } else {
        [self restoreVisibleMessageAnchor:anchor];
      }
      self->_loading = NO;
      [self markReadIfPossible];
      [self scheduleOlderMessagePrefetch];
    });
  }];
}

- (void)loadMessagesFromLogFallbackForConversationID:(NSString *)conversationID emptyStatus:(NSString *)emptyStatus {
  if (![self ownsCurrentAccount]) return;
  if (_usedLogFallback) {
    if (_messages.count == 0) [self hydrateConversationThenLoadMessagesWithStatus:emptyStatus];
    return;
  }
  _usedLogFallback = YES;
  _loading = YES;
  NSUInteger generation = _messageLoadGeneration;
  _statusLabel.hidden = YES;
  [[NFBAtprotoClient sharedClient] fetchChatLogMessagesForConversationID:conversationID completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount] || generation != self->_messageLoadGeneration) return;
      self->_loading = NO;
      if (items.count > 0) {
        self->_messages = NFBMergedChatMessages(self->_messages, items ?: @[]);
        (void)cursor; // getLog and getMessages have independent cursor namespaces.
        [self hydrateSharedPostsForCurrentMessages];
        [self saveMessageCache];
        [self->_tableView reloadData];
        [self->_tableView layoutIfNeeded];
        [self updateTableInsetsForCurrentContent];
        [self reloadRenderedMessages];
        self->_pendingScrollToBottom = YES;
        [self scrollToBottomAnimated:NO];
        [self markReadIfPossible];
        return;
      }
      if (self->_messages.count == 0) {
        [self hydrateConversationThenLoadMessagesWithStatus:emptyStatus];
      } else {
        [self hydrateSharedPostsForCurrentMessages];
        [self saveMessageCache];
        [self->_tableView reloadData];
        [self->_tableView layoutIfNeeded];
        [self updateTableInsetsForCurrentContent];
        [self reloadRenderedMessages];
        self->_pendingScrollToBottom = YES;
        [self scrollToBottomAnimated:NO];
        [self markReadIfPossible];
      }
    });
  }];
}

- (void)hydrateConversationThenLoadMessages {
  [self hydrateConversationThenLoadMessagesWithStatus:@"No messages yet."];
}

- (void)hydrateConversationThenLoadMessagesWithStatus:(NSString *)emptyStatus {
  if (![self ownsCurrentAccount]) return;
  NSString *conversationID = NFBChatConversationID(_conversation);
  if (conversationID.length == 0) {
    [self showStatusText:emptyStatus ?: @"No messages yet."];
    return;
  }
  [[NFBAtprotoClient sharedClient] fetchChatConversationWithID:conversationID completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount]) return;
      if (error || !value) {
        if (self->_messages.count == 0) [self showStatusText:error.localizedDescription ?: @"No messages yet."];
        return;
      }
      NSMutableDictionary *nextConversation = [self->_conversation mutableCopy] ?: [NSMutableDictionary dictionary];
      [nextConversation addEntriesFromDictionary:value];
      self->_conversation = nextConversation;
      [self configureNavigation];
      [self applyConversationPermissionState];
      if (!self->_directMessageUnavailable) [self refreshDirectMessagePermission];
      [self seedMessagesFromConversationIfNeeded];
      [self hydrateSharedPostsForCurrentMessages];
      if (self.conversationChangedHandler) self.conversationChangedHandler(self->_conversation);
      if (self->_messages.count == 0) [self showStatusText:emptyStatus ?: @"No messages yet."];
      [self saveMessageCache];
      [self->_tableView reloadData];
      [self->_tableView layoutIfNeeded];
      [self updateTableInsetsForCurrentContent];
      [self reloadRenderedMessages];
      self->_pendingScrollToBottom = YES;
      [self scrollToBottomAnimated:NO];
    });
  }];
}

- (void)seedMessagesFromConversationIfNeeded {
  if (_messages.count > 0) return;
  NSDictionary *lastMessage = NFBChatLastMessage(_conversation);
  if (!lastMessage) return;
  _messages = @[lastMessage];
  [self hydrateSharedPostsForCurrentMessages];
  [self saveMessageCache];
  NSLog(@"NotTwitter chat seeded thread convo=%@ message=%@ textLength=%lu",
        NFBChatConversationID(_conversation),
        NFBChatMessageID(lastMessage),
        (unsigned long)NFBChatMessageText(lastMessage).length);
  [_tableView reloadData];
  [_tableView layoutIfNeeded];
  [self updateTableInsetsForCurrentContent];
  [self reloadRenderedMessages];
  _pendingScrollToBottom = YES;
}

- (void)showStatusText:(NSString *)text {
  if ([self shouldShowRequestFooter]) {
    _statusLabel.text = @"";
    _statusLabel.hidden = YES;
    return;
  }
  NSString *statusText = (![self canSendMessagesInCurrentConversation] && _messages.count == 0) ? NFBChatConversationReadOnlyMessage(_conversation ?: @{}) : (text ?: @"");
  _statusLabel.text = statusText ?: @"";
  _statusLabel.hidden = _statusLabel.text.length == 0;
}

- (void)markReadIfPossible {
  if (![self ownsCurrentAccount]) return;
  NSDictionary *last = _messages.lastObject ?: NFBChatLastMessage(_conversation);
  NSString *messageID = NFBChatMessageID(last ?: @{});
  if (messageID.length == 0) return;
  [[NFBAtprotoClient sharedClient] markChatConversationRead:NFBChatConversationID(_conversation) messageID:messageID completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    if (!error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NFBNotificationCoordinator sharedCoordinator] refreshMessageBadge];
      });
    }
  }];
}

- (void)reloadRenderedMessages {
  if (!_messageContentView || !_messageScrollView) return;
  [self layoutMessageScrollViewFrame];
  CGFloat width = _messageScrollView.bounds.size.width;
  if (width <= 0.0) width = self.view.bounds.size.width;
  if (width <= 0.0) return;
  _lastRenderedMessageWidth = width;
  _lastRenderedMessageHeight = _messageScrollView.bounds.size.height;
  _messageContentView.frame = CGRectMake(0.0, 0.0, width, MAX(_messageScrollView.bounds.size.height + 1.0, _messageContentView.bounds.size.height));

  for (UIView *subview in [_messageContentView.subviews copy]) {
    [subview removeFromSuperview];
  }

  [_messageRowFrames removeAllObjects];
  NSMutableArray<NSNumber *> *rowHeights = [NSMutableArray arrayWithCapacity:_messages.count];
  CGFloat messagesHeight = 0.0;
  for (NSUInteger index = 0; index < _messages.count; index++) {
    NSDictionary *message = _messages[index];
    NSString *sender = NFBChatMessageSenderDID(message);
    NSDictionary *previous = index > 0 ? _messages[index - 1] : nil;
    NSDictionary *next = index + 1 < _messages.count ? _messages[index + 1] : nil;
    BOOL groupedWithPrevious = previous && [NFBChatMessageSenderDID(previous) isEqualToString:sender];
    BOOL groupedWithNext = next && [NFBChatMessageSenderDID(next) isEqualToString:sender];
    BOOL showTimestamp = !groupedWithNext;
    NSString *senderName = !groupedWithPrevious ? NFBChatSenderDisplayNameForMessageInConversation(message, _conversation ?: @{}) : @"";
    CGFloat rowHeight = NFBMessageBubbleHeightForWidth(message, width, showTimestamp, senderName);
    [rowHeights addObject:@(rowHeight)];
    messagesHeight += rowHeight;
  }

  CGFloat viewportHeight = MAX(0.0, CGRectGetHeight(_messageScrollView.bounds));
  CGFloat topPadding = _cursor.length > 0 ? 38.0 : 8.0;
  CGFloat bottomPadding = 8.0;
  CGFloat y = messagesHeight + topPadding + bottomPadding < viewportHeight ? MAX(topPadding, viewportHeight - bottomPadding - messagesHeight) : topPadding;

  if (_cursor.length > 0) {
    UIImageView *olderSpinner = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    olderSpinner.tintColor = NFBColorSecondaryText();
    olderSpinner.frame = CGRectMake((width - 22.0) / 2.0, 9.0, 22.0, 22.0);
    olderSpinner.hidden = !_loadingMoreMessages;
    [_messageContentView addSubview:olderSpinner];
    if (_loadingMoreMessages) NFBStartLoadingAnimation(olderSpinner);
    if (!_loadingMoreMessages) {
      UIButton *olderButton = [UIButton buttonWithType:UIButtonTypeSystem];
      olderButton.frame = CGRectMake(16.0, 0.0, width - 32.0, 38.0);
      olderButton.titleLabel.font = NFBFont(13.0, NFBFontWeightRegular);
      [olderButton setTitle:_olderMessagesFailed ? @"Couldn't load older messages. Tap to retry." : @"Load earlier messages" forState:UIControlStateNormal];
      [olderButton addTarget:self action:@selector(retryOlderMessages) forControlEvents:UIControlEventTouchUpInside];
      [_messageContentView addSubview:olderButton];
    }
  }

  for (NSUInteger index = 0; index < _messages.count; index++) {
    NSDictionary *message = _messages[index];
    NSString *sender = NFBChatMessageSenderDID(message);
    NSDictionary *previous = index > 0 ? _messages[index - 1] : nil;
    NSDictionary *next = index + 1 < _messages.count ? _messages[index + 1] : nil;
    BOOL groupedWithPrevious = previous && [NFBChatMessageSenderDID(previous) isEqualToString:sender];
    BOOL groupedWithNext = next && [NFBChatMessageSenderDID(next) isEqualToString:sender];
    BOOL mine = NFBChatMessageIsMine(message);
    BOOL showAvatar = !mine && !groupedWithPrevious;
    BOOL showTimestamp = !groupedWithNext;
    NSString *senderName = !groupedWithPrevious ? NFBChatSenderDisplayNameForMessageInConversation(message, _conversation ?: @{}) : @"";

    CGFloat rowTop = y;
    CGFloat rowHeight = [rowHeights[index] doubleValue];
    NSString *messageID = NFBChatMessageID(message);
    if (messageID.length > 0) _messageRowFrames[messageID] = [NSValue valueWithCGRect:CGRectMake(0, rowTop, width, rowHeight)];
    CGFloat maxBubbleWidth = MAX(180.0, width * 0.72);
    CGFloat textWidth = MAX(120.0, maxBubbleWidth - 32.0);
    NSString *text = NFBChatMessageDisplayText(message);
    NSDictionary *sharedPost = NFBChatSharedPostForMessage(message);
    BOOL hasTextBubble = text.length > 0 || sharedPost.count == 0;
    CGFloat contentTop = rowTop;
    if (senderName.length > 0) {
      UILabel *senderLabel = [[UILabel alloc] initWithFrame:CGRectMake(60.0, rowTop, maxBubbleWidth, 18.0)];
      senderLabel.text = senderName;
      senderLabel.textColor = NFBColorSecondaryText();
      senderLabel.font = NFBFont(12.0, NFBFontWeightMedium);
      senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
      [_messageContentView addSubview:senderLabel];
      contentTop = CGRectGetMaxY(senderLabel.frame) + 2.0;
    }
    CGFloat contentBottom = contentTop;

    if (hasTextBubble) {
      CGRect textRect = [text boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                       attributes:@{NSFontAttributeName: NFBFont(NFBIPAMetricValue(NFBIPAMetricMessageBodyFontSize), NFBFontWeightRegular)}
                                          context:nil];
      CGFloat bubbleWidth = MIN(maxBubbleWidth, MAX(44.0, ceil(textRect.size.width) + 32.0));
      CGFloat bubbleHeight = MAX(44.0, ceil(textRect.size.height) + 20.0);
      CGFloat bubbleX = mine ? width - 16.0 - bubbleWidth : 60.0;
      UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(bubbleX, contentTop, bubbleWidth, bubbleHeight)];
      NFBIPAApplyMessageBubbleAppearance(bubble, mine);
      NFBApplyMessageBubbleShape(bubble, mine, groupedWithPrevious, groupedWithNext);
      bubble.clipsToBounds = NO;
      bubble.tag = (NSInteger)index + 1;
      [_messageContentView addSubview:bubble];

      NFBInteractiveTextLabel *body = [[NFBInteractiveTextLabel alloc] initWithFrame:CGRectInset(bubble.bounds, 16.0, 10.0)];
      body.numberOfLines = 0;
      body.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricMessageBodyFontSize), NFBFontWeightRegular);
      body.textColor = mine ? UIColor.whiteColor : NFBColorText();
      body.text = text;
      if (NFBChatURLTokensInText(text).count > 0) {
        NSMutableAttributedString *linkedText = [NFBTweetBodyAttributedString(text, body.font) mutableCopy];
        if (mine) [linkedText addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:NSMakeRange(0, linkedText.length)];
        [linkedText enumerateAttribute:NFBTextLinkURLAttributeName inRange:NSMakeRange(0, linkedText.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
          if (value) [linkedText addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
        }];
        body.attributedText = linkedText;
        __weak typeof(self) weakSelf = self;
        body.linkTapHandler = ^(NSURL *url) { NFBOpenTweetTextURL(url, weakSelf); };
      }
      [bubble addSubview:body];

      UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(manualMessageLongPressed:)];
      [bubble addGestureRecognizer:longPress];
      contentBottom = CGRectGetMaxY(bubble.frame);
    }

    if (sharedPost.count > 0) {
      CGFloat cardWidth = MIN(maxBubbleWidth, width - 76.0);
      CGFloat cardHeight = NFBSharedPostCardHeightForWidth(sharedPost, cardWidth);
      CGFloat cardX = mine ? width - 16.0 - cardWidth : 60.0;
      CGFloat cardY = contentBottom + (hasTextBubble ? 6.0 : 0.0);
      NFBQuotedPostView *cardView = [[NFBQuotedPostView alloc] initWithFrame:CGRectMake(cardX, cardY, cardWidth, cardHeight)];
      cardView.delegate = self;
      cardView.tag = (NSInteger)index + 1;
      [cardView configureWithPost:sharedPost];
      [_messageContentView addSubview:cardView];

      UILongPressGestureRecognizer *cardLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(manualMessageLongPressed:)];
      [cardView addGestureRecognizer:cardLongPress];
      contentBottom = CGRectGetMaxY(cardView.frame);

      NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:sharedPost];
      if (quotedPost.count > 0) {
        CGFloat quotedY = contentBottom + 6.0;
        CGFloat quotedHeight = NFBSharedPostCardHeightForWidth(quotedPost, cardWidth);
        NFBQuotedPostView *quotedView = [[NFBQuotedPostView alloc] initWithFrame:CGRectMake(cardX, quotedY, cardWidth, quotedHeight)];
        quotedView.delegate = self;
        quotedView.tag = (NSInteger)index + 1;
        [quotedView configureWithPost:quotedPost];
        [_messageContentView addSubview:quotedView];

        UILongPressGestureRecognizer *quotedLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(manualMessageLongPressed:)];
        [quotedView addGestureRecognizer:quotedLongPress];
        contentBottom = CGRectGetMaxY(quotedView.frame);
      }
    }

    if (showAvatar) {
      NSDictionary *senderProfile = [self profileForSenderDID:sender];
      UIImageView *avatar = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
      avatar.frame = CGRectMake(16.0, MAX(contentTop + 36.0, contentBottom) - 36.0, 36.0, 36.0);
      avatar.contentMode = UIViewContentModeScaleAspectFill;
      avatar.clipsToBounds = YES;
      avatar.layer.cornerRadius = 18.0;
      [_messageContentView addSubview:avatar];
      NFBLoadRemoteImage(avatar, [NFBAtprotoClient avatarURLForProfile:senderProfile], NFBDefaultAvatarImage());

      UIButton *avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
      avatarButton.frame = avatar.frame;
      avatarButton.tag = (NSInteger)index + 1;
      [avatarButton addTarget:self action:@selector(manualMessageAvatarTapped:) forControlEvents:UIControlEventTouchUpInside];
      [_messageContentView addSubview:avatarButton];
    }

    CGFloat detailY = contentBottom + 2.0;
    NSArray *reactions = [message[@"reactions"] isKindOfClass:NSArray.class] ? message[@"reactions"] : @[];
    if (reactions.count > 0) {
      NSMutableArray<NSString *> *values = [NSMutableArray array];
      for (NSDictionary *reaction in reactions) {
        NSString *value = [reaction isKindOfClass:NSDictionary.class] ? NFBStringValue(reaction[@"value"]) : @"";
        if (value.length > 0 && ![values containsObject:value]) [values addObject:value];
        if (values.count >= 3) break;
      }
      if (values.count > 0) {
        UILabel *reactionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        reactionLabel.text = [NSString stringWithFormat:@"  %@  ", [values componentsJoinedByString:@" "]];
        reactionLabel.font = NFBFont(14.0, NFBFontWeightRegular);
        reactionLabel.userInteractionEnabled = YES;
        reactionLabel.accessibilityLabel = @"Message reactions";
        reactionLabel.tag = (NSInteger)index + 1;
        NFBIPAApplyMessageReactionPillAppearance(reactionLabel);
        UITapGestureRecognizer *reactionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(manualMessageLongPressed:)];
        [reactionLabel addGestureRecognizer:reactionTap];
        UILongPressGestureRecognizer *reactionLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(manualMessageLongPressed:)];
        [reactionLabel addGestureRecognizer:reactionLongPress];
        CGSize reactionSize = [reactionLabel sizeThatFits:CGSizeMake(180.0, 22.0)];
        reactionSize.width = MIN(180.0, MAX(36.0, ceil(reactionSize.width)));
        CGFloat reactionX = mine ? width - 16.0 - reactionSize.width - 4.0 : 64.0;
        reactionLabel.frame = CGRectMake(reactionX, detailY, reactionSize.width, 22.0);
        [_messageContentView addSubview:reactionLabel];
        detailY = CGRectGetMaxY(reactionLabel.frame) + 2.0;
      }
    }

    if (showTimestamp) {
      UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
      timeLabel.text = NFBFullTimeForISOString(NFBChatMessageSentAt(message));
      timeLabel.font = NFBFont(12.0, NFBFontWeightRegular);
      timeLabel.textColor = NFBColorSecondaryText();
      CGSize timeSize = [timeLabel sizeThatFits:CGSizeMake(maxBubbleWidth, 16.0)];
      timeSize.width = MIN(maxBubbleWidth, ceil(timeSize.width));
      CGFloat timeX = mine ? width - 16.0 - timeSize.width - 8.0 : 68.0;
      timeLabel.frame = CGRectMake(timeX, detailY, timeSize.width, 16.0);
      [_messageContentView addSubview:timeLabel];
    }

    y = rowTop + rowHeight;
  }

  CGFloat contentHeight = MAX(y + bottomPadding, _messageScrollView.bounds.size.height + 1.0);
  _messageContentView.frame = CGRectMake(0.0, 0.0, width, contentHeight);
  _messageScrollView.contentSize = CGSizeMake(width, contentHeight);
  [self.view bringSubviewToFront:_messageScrollView];
  [self.view bringSubviewToFront:_composerView];
  [self.view bringSubviewToFront:_requestFooterView];
  [self.view bringSubviewToFront:_loadingView];
  [self.view bringSubviewToFront:_statusLabel];
  [_messageContentView setNeedsLayout];
  [_messageContentView layoutIfNeeded];
}

- (void)manualMessageLongPressed:(UIGestureRecognizer *)gesture {
  if ([gesture isKindOfClass:UILongPressGestureRecognizer.class] && gesture.state != UIGestureRecognizerStateBegan) return;
  if ([gesture isKindOfClass:UITapGestureRecognizer.class] && gesture.state != UIGestureRecognizerStateEnded) return;
  NSInteger index = gesture.view.tag - 1;
  if (index < 0 || (NSUInteger)index >= _messages.count) return;
  [self presentActionsForMessage:_messages[(NSUInteger)index] sourceView:gesture.view];
}

- (void)manualMessageAvatarTapped:(UIButton *)button {
  NSInteger index = button.tag - 1;
  if (index < 0 || (NSUInteger)index >= _messages.count) return;
  NSString *sender = NFBChatMessageSenderDID(_messages[(NSUInteger)index]);
  [self openProfileForSenderProfile:[self profileForSenderDID:sender]];
}

- (void)quotedPostViewDidTapPost:(NFBQuotedPostView *)view {
  NSDictionary *post = view.post ?: @{};
  if (post.count == 0) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  [self.navigationController pushViewController:detail animated:YES];
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapLinkURL:(NSURL *)url {
  (void)view;
  NFBOpenTweetTextURL(url, self);
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapMediaAtIndex:(NSUInteger)index transitionSource:(NFBMediaTransitionSource *)transitionSource {
  NSDictionary *post = view.post ?: @{};
  NSArray<NSDictionary *> *mediaItems = [NFBAtprotoClient mediaItemsForPost:post];
  if (index >= mediaItems.count) return;
  NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithMediaItems:mediaItems initialIndex:index post:post];
  viewer.transitionSource = transitionSource;
  [self presentViewController:viewer animated:YES completion:nil];
}

- (void)quotedPostViewDidTapExternalCard:(NFBQuotedPostView *)view {
  NSDictionary *card = [NFBAtprotoClient externalCardForPost:view.post ?: @{}];
  NSString *urlString = NFBStringValue(card[@"url"]);
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (url) NFBOpenTweetTextURL(url, self);
}

- (void)quotedPostViewDidTapExternalCardWebsite:(NFBQuotedPostView *)view {
  [self quotedPostViewDidTapExternalCard:view];
}

- (BOOL)isScrolledNearBottom {
  if (!_messageScrollView) return YES;
  CGFloat maxOffsetY = MAX(0.0, _messageScrollView.contentSize.height - CGRectGetHeight(_messageScrollView.bounds));
  return maxOffsetY - _messageScrollView.contentOffset.y < 36.0;
}

- (void)setMessageScrollOffsetY:(CGFloat)offsetY animated:(BOOL)animated {
  if (!_messageScrollView) return;
  CGFloat maxOffsetY = MAX(0.0, _messageScrollView.contentSize.height - CGRectGetHeight(_messageScrollView.bounds));
  CGPoint target = CGPointMake(0.0, MIN(MAX(0.0, offsetY), maxOffsetY));
  BOOL shouldAnimate = animated && fabs(_messageScrollView.contentOffset.y - target.y) > 0.5;
  _scrollingProgrammatically = YES;
  [_messageScrollView setContentOffset:target animated:shouldAnimate];
  if (!shouldAnimate) {
    _scrollingProgrammatically = NO;
  } else {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      self->_scrollingProgrammatically = NO;
    });
  }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
  if (_messages.count == 0) return;
  if (_messageScrollView) {
    [self reloadRenderedMessages];
    CGFloat maxOffsetY = MAX(0.0, _messageScrollView.contentSize.height - CGRectGetHeight(_messageScrollView.bounds));
    [self setMessageScrollOffsetY:maxOffsetY animated:animated];
    _pendingScrollToBottom = NO;
    return;
  }
  [self updateTableInsetsForCurrentContent];
  [_tableView layoutIfNeeded];
  CGFloat totalContentHeight = _tableView.contentSize.height + _tableView.contentInset.top + _tableView.contentInset.bottom;
  if (totalContentHeight <= _tableView.bounds.size.height) {
    [_tableView setContentOffset:CGPointMake(0.0, -_tableView.contentInset.top) animated:NO];
    return;
  }
  NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)_messages.count - 1 inSection:0];
  [_tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (void)updateTableInsetsForCurrentContent {
  if (!_tableView) return;
  UIEdgeInsets inset = UIEdgeInsetsMake(8.0, 0.0, 8.0, 0.0);
  if (UIEdgeInsetsEqualToEdgeInsets(_tableView.contentInset, inset)) return;
  _tableView.contentInset = inset;
  _tableView.scrollIndicatorInsets = inset;
}

// Capture at response time: the reader may keep scrolling while the request runs.
- (NSDictionary *)visibleMessageAnchor {
  CGFloat offset = _messageScrollView.contentOffset.y;
  for (NSDictionary *message in _messages) {
    NSString *messageID = NFBChatMessageID(message);
    NSValue *value = _messageRowFrames[messageID];
    if (!value) continue;
    CGRect frame = value.CGRectValue;
    if (CGRectGetMaxY(frame) > offset) {
      return @{@"id": messageID, @"distance": @(offset - frame.origin.y)};
    }
  }
  return nil;
}

- (void)restoreVisibleMessageAnchor:(NSDictionary *)anchor {
  NSValue *value = _messageRowFrames[NFBStringValue(anchor[@"id"])];
  if (value) [self setMessageScrollOffsetY:value.CGRectValue.origin.y + [anchor[@"distance"] doubleValue] animated:NO];
}

- (void)retryOlderMessages {
  _olderMessagesFailed = NO;
  [self loadOlderMessagesIfNeeded];
}

- (void)scheduleOlderMessagePrefetch {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.viewIfLoaded.window || self->_pendingScrollToBottom || self->_scrollingProgrammatically) return;
    CGFloat threshold = NFBChatPaginationPrefetchDistance(CGRectGetHeight(self->_messageScrollView.bounds));
    if (self->_messageScrollView.contentOffset.y < threshold) [self loadOlderMessagesIfNeeded];
  });
}

- (void)loadOlderMessagesIfNeeded {
  if (![self ownsCurrentAccount]) return;
  if (_loading || _loadingMoreMessages || _olderMessagesFailed || _cursor.length == 0) return;
  NSString *conversationID = NFBChatConversationID(_conversation);
  NSString *cursor = [_cursor copy];
  if (conversationID.length == 0) return;
  NSUInteger generation = _messageLoadGeneration;
  _loadingMoreMessages = YES;
  [self reloadRenderedMessages];
  [[NFBAtprotoClient sharedClient] fetchChatMessagesForConversationID:conversationID cursor:cursor completion:^(NSArray<NSDictionary *> *items, NSString *nextCursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount] || generation != self->_messageLoadGeneration) return;
      if (error) {
        self->_olderMessagesFailed = YES;
        self->_loadingMoreMessages = NO;
        [self reloadRenderedMessages];
        return;
      }
      NSDictionary *anchor = [self visibleMessageAnchor];
      self->_messages = NFBMergedChatMessages(self->_messages, items ?: @[]);
      self->_cursor = NFBChatNextPageCursor(cursor, nextCursor, self->_consumedMessageCursors);
      [self hydrateSharedPostsForCurrentMessages];
      [self->_tableView reloadData];
      self->_loadingMoreMessages = NO;
      [self reloadRenderedMessages];
      [self restoreVisibleMessageAnchor:anchor];
      [self saveMessageCache];
      [self scheduleOlderMessagePrefetch];
    });
  }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (scrollView != _messageScrollView || _scrollingProgrammatically || _pendingScrollToBottom) return;
  if (scrollView.isDragging || scrollView.isDecelerating) [self scheduleOlderMessagePrefetch];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
  if (scrollView == _messageScrollView) _scrollingProgrammatically = NO;
}

- (void)sendText:(NSString *)text {
  if (![self canSendMessagesInCurrentConversation]) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_MESSAGE_SEND_ERROR_FAILED_TO_SEND", @"Message failed to send")
                                                                   message:_directMessageUnavailable ? NFBChatPresentedErrorMessage(NFBChatPermissionDeniedError()) : NFBChatConversationReadOnlyMessage(_conversation ?: @{})
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return;
  }
  _composerView.sending = YES;
  [[NFBAtprotoClient sharedClient] sendChatMessageToConversationID:NFBChatConversationID(_conversation) text:text completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount]) return;
      self->_composerView.sending = NO;
      if (error || !value) {
        if (NFBChatErrorIsPermissionDenied(error) && !NFBChatConversationIsGroup(self->_conversation)) {
          self->_messagePermissionGeneration++;
          self->_directMessageUnavailable = YES;
          [self->_composerView endEditing:YES];
          [self applyConversationPermissionState];
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_MESSAGE_SEND_ERROR_FAILED_TO_SEND", @"Message failed to send")
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self hydrateConversationThenLoadMessagesWithStatus:nil];
        return;
      }
      [self->_composerView clearText];
      NFBPlaySound(@"pop.aac");
      self->_messages = NFBMergedChatMessages(self->_messages, @[value]);
      NSMutableDictionary *convo = [self->_conversation mutableCopy];
      convo[@"lastMessage"] = value;
      convo[@"unreadCount"] = @0;
      self->_conversation = convo;
      [self hydrateSharedPostsForCurrentMessages];
      [self saveMessageCache];
      if (self.conversationChangedHandler) self.conversationChangedHandler(self->_conversation);
      [self->_tableView reloadData];
      [self->_tableView layoutIfNeeded];
      [self updateTableInsetsForCurrentContent];
      [self reloadRenderedMessages];
      self->_pendingScrollToBottom = YES;
      [self scrollToBottomAnimated:YES];
    });
  }];
}

- (void)messageComposerViewDidTapMedia:(NFBMessageComposerView *)composerView {
  (void)composerView;
  [self presentMediaSharingUnavailableAlert];
}

- (void)messageComposerViewDidTapGIF:(NFBMessageComposerView *)composerView {
  (void)composerView;
  [self presentMediaSharingUnavailableAlert];
}

- (void)presentMediaSharingUnavailableAlert {
  NFBPlaySound(@"pop.aac");
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Media sharing isn't available in Direct Messages yet."
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return (NSInteger)_messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSDictionary *message = _messages[(NSUInteger)indexPath.row];
  NSString *sender = NFBChatMessageSenderDID(message);
  NSDictionary *previous = indexPath.row > 0 ? _messages[(NSUInteger)indexPath.row - 1] : nil;
  NSDictionary *next = (NSUInteger)indexPath.row + 1 < _messages.count ? _messages[(NSUInteger)indexPath.row + 1] : nil;
  BOOL groupedWithPrevious = previous && [NFBChatMessageSenderDID(previous) isEqualToString:sender];
  BOOL groupedWithNext = next && [NFBChatMessageSenderDID(next) isEqualToString:sender];
  BOOL showTimestamp = !groupedWithNext;
  NSString *senderName = !groupedWithPrevious ? NFBChatSenderDisplayNameForMessageInConversation(message, _conversation ?: @{}) : @"";
  return NFBMessageBubbleHeightForWidth(message, tableView.bounds.size.width, showTimestamp, senderName);
}

- (NSDictionary *)profileForSenderDID:(NSString *)did {
  for (NSDictionary *member in NFBChatMembers(_conversation)) {
    if ([NFBStringValue(member[@"did"]) isEqualToString:did]) return member;
  }
  for (NSDictionary *message in _messages) {
    NSArray *relatedProfiles = [message[@"__relatedProfiles"] isKindOfClass:NSArray.class] ? message[@"__relatedProfiles"] : @[];
    for (NSDictionary *profile in relatedProfiles) {
      if ([profile isKindOfClass:NSDictionary.class] && [NFBStringValue(profile[@"did"]) isEqualToString:did]) return profile;
    }
  }
  return @{};
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NFBMessageBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:NFBMessageBubbleCellIdentifier forIndexPath:indexPath];
  NSDictionary *message = _messages[(NSUInteger)indexPath.row];
  NSString *sender = NFBChatMessageSenderDID(message);
  NSDictionary *previous = indexPath.row > 0 ? _messages[(NSUInteger)indexPath.row - 1] : nil;
  NSDictionary *next = (NSUInteger)indexPath.row + 1 < _messages.count ? _messages[(NSUInteger)indexPath.row + 1] : nil;
  BOOL groupedWithPrevious = previous && [NFBChatMessageSenderDID(previous) isEqualToString:sender];
  BOOL groupedWithNext = next && [NFBChatMessageSenderDID(next) isEqualToString:sender];
  BOOL showAvatar = !groupedWithPrevious;
  BOOL showTimestamp = !groupedWithNext;
  NSString *senderName = !groupedWithPrevious ? NFBChatSenderDisplayNameForMessageInConversation(message, _conversation ?: @{}) : @"";
  [cell configureWithMessage:message senderProfile:[self profileForSenderDID:sender] showAvatar:showAvatar showTimestamp:showTimestamp senderName:senderName];
  cell.delegate = self;
  return cell;
}

- (void)messageBubbleCellDidLongPress:(NFBMessageBubbleCell *)cell sourceView:(UIView *)sourceView {
  [self presentActionsForMessage:cell.message ?: @{} sourceView:sourceView];
}

- (void)presentActionsForMessage:(NSDictionary *)message sourceView:(UIView *)sourceView {
  NSString *messageID = NFBChatMessageID(message);
  CGRect sourceRect = sourceView ? [sourceView convertRect:sourceView.bounds toView:nil] : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
  NSSet<NSString *> *selectedReactions = NFBChatMessageViewerReactionValues(message);
  __weak typeof(self) weakSelf = self;
  NFBMessageReactionMenuViewController *menu = [[NFBMessageReactionMenuViewController alloc] initWithSourceRect:sourceRect canDelete:messageID.length > 0 selectedReactions:selectedReactions handler:^(NSString *action, NSString *value) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if ([action isEqualToString:@"copy"]) {
      UIPasteboard.generalPasteboard.string = NFBChatMessageText(message);
      return;
    }
    if ([action isEqualToString:@"reaction"]) {
      if (messageID.length == 0 || value.length == 0) return;
      BOOL removing = [selectedReactions containsObject:value];
      NFBAtprotoDictionaryCompletion completion = ^(NSDictionary *updated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (error || !updated) return;
          [strongSelf replaceMessage:updated];
        });
      };
      if (removing) {
        [[NFBAtprotoClient sharedClient] removeChatReactionFromConversationID:NFBChatConversationID(strongSelf->_conversation) messageID:messageID value:value completion:completion];
      } else {
        [[NFBAtprotoClient sharedClient] addChatReactionToConversationID:NFBChatConversationID(strongSelf->_conversation) messageID:messageID value:value completion:completion];
      }
      return;
    }
    if ([action isEqualToString:@"delete"]) {
      [strongSelf deleteMessageForSelf:messageID];
    }
  }];
  [self presentViewController:menu animated:NO completion:nil];
}

- (void)deleteMessageForSelf:(NSString *)messageID {
  if (messageID.length == 0) return;
  [[NFBAtprotoClient sharedClient] deleteChatMessageForSelfInConversationID:NFBChatConversationID(_conversation) messageID:messageID completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) return;
      NSMutableArray *next = [NSMutableArray array];
      for (NSDictionary *candidate in self->_messages) {
        if (![NFBChatMessageID(candidate) isEqualToString:messageID]) [next addObject:candidate];
      }
      self->_messages = next;
      [self saveMessageCache];
      [self->_tableView reloadData];
      [self reloadRenderedMessages];
      [self scrollToBottomAnimated:NO];
    });
  }];
}

- (void)replaceMessage:(NSDictionary *)message {
  NSString *messageID = NFBChatMessageID(message);
  if (messageID.length == 0) return;
  NSMutableArray *next = [_messages mutableCopy] ?: [NSMutableArray array];
  for (NSUInteger index = 0; index < next.count; index++) {
    if ([NFBChatMessageID(next[index]) isEqualToString:messageID]) {
      next[index] = message;
      break;
    }
  }
  _messages = next;
  [self hydrateSharedPostsForCurrentMessages];
  [self saveMessageCache];
  [_tableView reloadData];
  [self reloadRenderedMessages];
}

- (void)messageBubbleCellDidTapAvatar:(NFBMessageBubbleCell *)cell {
  [self openProfileForSenderProfile:cell.senderProfile ?: @{}];
}

- (void)openProfileForSenderProfile:(NSDictionary *)profile {
  NSString *actor = NFBStringValue(profile[@"did"]);
  if (actor.length == 0) actor = NFBStringValue(profile[@"handle"]);
  if (actor.length == 0) return;
  NFBTimelineViewController *profileViewController = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
  [self.navigationController pushViewController:profileViewController animated:YES];
}

@end

@interface NFBMessagesViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, NFBConversationCellDelegate, NFBNewMessageViewControllerDelegate>
@end

@implementation NFBMessagesViewController {
  NSUInteger _owningAccountGeneration;
  NSUInteger _conversationListGeneration;
  UITableView *_tableView;
  UIRefreshControl *_refreshControl;
  UITextField *_searchField;
  UIImageView *_loadingView;
  UILabel *_emptyTitleLabel;
  UILabel *_emptySubtitleLabel;
  NSArray<NSDictionary *> *_conversations;
  NSArray<NSDictionary *> *_filteredConversations;
  NSString *_cursor;
  NSString *_cacheAccountKey;
  NSString *_cacheListName;
  UIImageView *_headerAvatarImageView;
  BOOL _loading;
  BOOL _loadingMoreConversations;
  BOOL _moreConversationsFailed;
  NSMutableSet<NSString *> *_consumedConversationCursors;
  BOOL _showingRequests;
  BOOL _refreshSuccessSoundPending;
}


- (BOOL)ownsCurrentAccount {
  return _owningAccountGeneration == [NFBAtprotoSession sharedSession].accountGeneration;
}

- (instancetype)init {
  self = [super initWithNibName:nil bundle:nil];
  if (self) _owningAccountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  return self;
}

- (void)themeChanged:(NSNotification *)notification {
  [self configureNavigation];
  NFBApplyNavigationAppearance(self.navigationController);
  NFBUpdateRefreshControlAppearance(_refreshControl);
  [_tableView reloadData];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  self.view.backgroundColor = NFBColorBackground();
  [self configureNavigation];
  [self buildViews];
  [self loadCachedConversationsIfAvailable];
  [self loadConversations];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self resetConversationListForAccountChangeIfNeeded];
  if (!_showingRequests) [self loadHeaderAvatar];
  if (!_loading && !_showingRequests) [self loadConversations];
}

- (void)refreshConversations {
  if (_refreshControl.isRefreshing) {
    _refreshSuccessSoundPending = YES;
    NFBPlaySound(@"pull.aac");
  }
  [self loadConversations];
}

- (void)configureNavigation {
  self.navigationItem.titleView = NFBTitleView(_showingRequests ? NFBTweetieLocalizedString(@"DIRECT_MESSAGE_MESSAGE_REQUESTS_INBOX_TIMELINE_TITLE", @"Requests") : @"Messages", nil);
  if (_showingRequests) {
    self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backFromRequests));
  } else {
    [self configureHeaderAvatarButton];
  }
  if (_showingRequests) {
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = nil;
  } else {
    UIButton *compose = [UIButton buttonWithType:UIButtonTypeCustom];
    compose.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    compose.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    compose.contentEdgeInsets = UIEdgeInsetsMake(8.0, 16.0, 8.0, 0.0);
    [compose setImage:NFBTemplateIcon(@"nfb_new_message") forState:UIControlStateNormal];
    compose.tintColor = NFBColorText();
    compose.accessibilityLabel = @"New message";
    [compose addTarget:self action:@selector(newMessageTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:compose];
  }
}

- (void)configureHeaderAvatarButton {
  UIView *avatarContainer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];
  UIButton *avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
  avatarButton.frame = CGRectMake(0.0, 6.0, 32.0, 32.0);
  avatarButton.clipsToBounds = YES;
  avatarButton.layer.cornerRadius = 16.0;
  avatarButton.accessibilityLabel = @"Account menu";

  _headerAvatarImageView = [[UIImageView alloc] initWithImage:NFBBrandIconImage() ?: NFBDefaultAvatarImage()];
  _headerAvatarImageView.frame = avatarButton.bounds;
  _headerAvatarImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _headerAvatarImageView.contentMode = UIViewContentModeScaleAspectFill;
  _headerAvatarImageView.clipsToBounds = YES;
  _headerAvatarImageView.layer.cornerRadius = 16.0;
  [avatarButton addSubview:_headerAvatarImageView];

  [avatarButton addTarget:self action:@selector(accountMenuTapped) forControlEvents:UIControlEventTouchUpInside];
  [avatarContainer addSubview:avatarButton];
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:avatarContainer];
  [self loadHeaderAvatar];
}

- (void)loadHeaderAvatar {
  if (!_headerAvatarImageView || ![self ownsCurrentAccount]) return;
  NSDictionary *account = [NFBAtprotoSession sharedSession].currentAccountDictionary ?: @{};
  NSString *avatarURL = [account[@"avatar"] isKindOfClass:NSString.class] ? account[@"avatar"] : @"";
  NFBLoadAccountAvatar(_headerAvatarImageView, avatarURL);
  NSString *actor = [NFBAtprotoSession sharedSession].did;
  if (!actor.length) return;
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchProfileForActor:actor completion:^(NSDictionary *profile, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || error || ![strongSelf ownsCurrentAccount]) return;
      NFBLoadAccountAvatar(strongSelf->_headerAvatarImageView, [NFBAtprotoClient avatarURLForProfile:profile]);
    });
  }];
}

- (void)accountMenuTapped {
  NFBSideMenuViewController *menu = [[NFBSideMenuViewController alloc] init];
  menu.modalPresentationStyle = UIModalPresentationOverFullScreen;
  menu.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  [self presentViewController:menu animated:NO completion:nil];
}

- (void)buildViews {
  UIView *searchContainer = [[UIView alloc] init];
  searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
  searchContainer.backgroundColor = NFBColorBackground();

  UIView *searchPill = [[UIView alloc] init];
  searchPill.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplySearchContainerAppearance(searchPill);

  UIImageView *searchIcon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_search")];
  searchIcon.translatesAutoresizingMaskIntoConstraints = NO;
  searchIcon.tintColor = NFBColorSecondaryText();
  searchIcon.contentMode = UIViewContentModeScaleAspectFit;

  _searchField = [[UITextField alloc] init];
  _searchField.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplySearchTextFieldAppearance(_searchField, @"Search Direct Messages");
  _searchField.returnKeyType = UIReturnKeySearch;
  _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
  [_searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];

  UIView *searchDivider = [[UIView alloc] init];
  searchDivider.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(searchDivider);

  [searchPill addSubview:searchIcon];
  [searchPill addSubview:_searchField];
  [searchContainer addSubview:searchPill];
  [searchContainer addSubview:searchDivider];

  _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  _tableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(_tableView);
  _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  _tableView.dataSource = self;
  _tableView.delegate = self;
  _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  _tableView.rowHeight = UITableViewAutomaticDimension;
  _tableView.estimatedRowHeight = 80.0;
  [_tableView registerClass:NFBConversationCell.class forCellReuseIdentifier:NFBConversationCellIdentifier];
  [_tableView registerClass:NFBMessageRequestCell.class forCellReuseIdentifier:NFBMessageRequestCellIdentifier];
  _refreshControl = NFBCreateRefreshControl(self, @selector(refreshConversations));
  _tableView.refreshControl = _refreshControl;

  _loadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  _loadingView.translatesAutoresizingMaskIntoConstraints = NO;
  _loadingView.tintColor = NFBColorSecondaryText();
  _loadingView.hidden = YES;

  _emptyTitleLabel = [[UILabel alloc] init];
  _emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _emptyTitleLabel.text = @"No messages yet";
  _emptyTitleLabel.textColor = NFBColorText();
  _emptyTitleLabel.font = NFBFont(26.0, NFBFontWeightHeavy);
  _emptyTitleLabel.hidden = YES;

  _emptySubtitleLabel = [[UILabel alloc] init];
  _emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _emptySubtitleLabel.text = @"Your Bluesky conversations will show up here.";
  _emptySubtitleLabel.textColor = NFBColorSecondaryText();
  _emptySubtitleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  _emptySubtitleLabel.numberOfLines = 0;
  _emptySubtitleLabel.hidden = YES;

  [self.view addSubview:searchContainer];
  [self.view addSubview:_tableView];
  [self.view addSubview:_loadingView];
  [self.view addSubview:_emptyTitleLabel];
  [self.view addSubview:_emptySubtitleLabel];

  [NSLayoutConstraint activateConstraints:@[
    [searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [searchContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [searchContainer.heightAnchor constraintEqualToConstant:62.0],
    [searchPill.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor constant:20.0],
    [searchPill.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor constant:-20.0],
    [searchPill.centerYAnchor constraintEqualToAnchor:searchContainer.centerYAnchor],
    [searchPill.heightAnchor constraintEqualToConstant:40.0],
    [searchIcon.leadingAnchor constraintEqualToAnchor:searchPill.leadingAnchor constant:12.0],
    [searchIcon.centerYAnchor constraintEqualToAnchor:searchPill.centerYAnchor],
    [searchIcon.widthAnchor constraintEqualToConstant:20.0],
    [searchIcon.heightAnchor constraintEqualToConstant:20.0],
    [_searchField.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:10.0],
    [_searchField.trailingAnchor constraintEqualToAnchor:searchPill.trailingAnchor constant:-14.0],
    [_searchField.centerYAnchor constraintEqualToAnchor:searchPill.centerYAnchor],
    [searchDivider.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor],
    [searchDivider.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor],
    [searchDivider.bottomAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
    [searchDivider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_tableView.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
    [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [_loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [_loadingView.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:18.0],
    [_loadingView.widthAnchor constraintEqualToConstant:28.0],
    [_loadingView.heightAnchor constraintEqualToConstant:28.0],
    [_emptyTitleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32.0],
    [_emptyTitleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32.0],
    [_emptyTitleLabel.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:72.0],
    [_emptySubtitleLabel.leadingAnchor constraintEqualToAnchor:_emptyTitleLabel.leadingAnchor],
    [_emptySubtitleLabel.trailingAnchor constraintEqualToAnchor:_emptyTitleLabel.trailingAnchor],
    [_emptySubtitleLabel.topAnchor constraintEqualToAnchor:_emptyTitleLabel.bottomAnchor constant:8.0]
  ]];
}

- (NSString *)conversationListCacheName {
  return _showingRequests ? @"requests" : @"inbox";
}

- (void)resetConversationListForAccountChangeIfNeeded {
  NSString *accountKey = NFBChatCacheAccountKey();
  if ([_cacheAccountKey isEqualToString:accountKey]) return;
  _cacheAccountKey = accountKey;
  _cacheListName = nil;
  _conversations = @[];
  _filteredConversations = @[];
  _cursor = nil;
  _searchField.text = @"";
  [self loadCachedConversationsIfAvailable];
}

- (void)loadCachedConversationsIfAvailable {
  if (![self ownsCurrentAccount]) return;
  NSString *accountKey = NFBChatCacheAccountKey();
  if (![_cacheAccountKey isEqualToString:accountKey]) _cacheAccountKey = accountKey;
  NSString *listName = [self conversationListCacheName];
  BOOL listChanged = ![_cacheListName isEqualToString:listName];
  _cacheListName = listName;
  if (listChanged) {
    _conversationListGeneration++;
    _loading = NO;
    _loadingMoreConversations = NO;
    _moreConversationsFailed = NO;
    _consumedConversationCursors = [NSMutableSet set];
    _refreshSuccessSoundPending = NO;
    [_refreshControl endRefreshing];
  }
  NSDictionary *cache = NFBChatLoadCacheNamed(listName);
  NSArray *cachedConversations = [cache[@"conversations"] isKindOfClass:NSArray.class] ? cache[@"conversations"] : @[];
  if (cachedConversations.count == 0) {
    if (listChanged) {
      _conversations = @[];
      _cursor = nil;
    }
    [self applySearchFilter];
    return;
  }
  _conversations = NFBMergedChatConversations(@[], NFBChatConversationsForList(cachedConversations, _showingRequests));
  _cursor = NFBStringValue(cache[@"cursor"]);
  [self applySearchFilter];
  NSLog(@"NotTwitter chat inbox cache loaded account=%@ requests=%d count=%lu", _cacheAccountKey, _showingRequests, (unsigned long)_conversations.count);
}

- (void)saveConversationListCache {
  if (![self ownsCurrentAccount]) return;
  NSMutableDictionary *payload = [@{
    @"conversations": NFBChatLimitedDictionaries(_conversations ?: @[], 120)
  } mutableCopy];
  if (_conversations.count <= 120 && _cursor.length > 0) payload[@"cursor"] = _cursor;
  NFBChatSaveCacheNamed([self conversationListCacheName], payload);
}

- (NSDictionary *)visibleConversationAnchor {
  if (_tableView.contentOffset.y <= -_tableView.adjustedContentInset.top + 1.0) return nil;
  NSIndexPath *path = _tableView.indexPathsForVisibleRows.firstObject;
  NSInteger index = path.row - (_showingRequests ? 0 : 1);
  if (!path || index < 0 || (NSUInteger)index >= _filteredConversations.count) return nil;
  NSString *conversationID = NFBChatConversationID(_filteredConversations[(NSUInteger)index]);
  return @{@"id": conversationID, @"distance": @(_tableView.contentOffset.y - [_tableView rectForRowAtIndexPath:path].origin.y)};
}

- (void)restoreVisibleConversationAnchor:(NSDictionary *)anchor {
  if (!anchor) return;
  NSUInteger index = [_filteredConversations indexOfObjectPassingTest:^BOOL(NSDictionary *conversation, NSUInteger idx, BOOL *stop) {
    return [NFBChatConversationID(conversation) isEqualToString:anchor[@"id"]];
  }];
  if (index == NSNotFound) return;
  [_tableView layoutIfNeeded];
  NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)index + (_showingRequests ? 0 : 1) inSection:0];
  CGFloat y = [_tableView rectForRowAtIndexPath:path].origin.y + [anchor[@"distance"] doubleValue];
  CGFloat minimum = -_tableView.adjustedContentInset.top;
  CGFloat maximum = MAX(minimum, _tableView.contentSize.height - CGRectGetHeight(_tableView.bounds) + _tableView.adjustedContentInset.bottom);
  [_tableView setContentOffset:CGPointMake(0, MIN(maximum, MAX(minimum, y))) animated:NO];
}

- (void)loadConversations {
  if (![self ownsCurrentAccount]) return;
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    _refreshSuccessSoundPending = NO;
    [_refreshControl endRefreshing];
    return;
  }
  if (_loading) {
    _refreshSuccessSoundPending = NO;
    [_refreshControl endRefreshing];
    return;
  }
  _conversationListGeneration++;
  _loadingMoreConversations = NO;
  _moreConversationsFailed = NO;
  _consumedConversationCursors = [NSMutableSet set];
  _loading = YES;
  BOOL hasCachedRows = _conversations.count > 0;
  _loadingView.hidden = hasCachedRows;
  _emptyTitleLabel.hidden = YES;
  _emptySubtitleLabel.hidden = YES;
  if (!hasCachedRows) NFBStartLoadingAnimation(_loadingView);
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  BOOL requests = _showingRequests;
  NSUInteger listGeneration = _conversationListGeneration;
  NFBAtprotoArrayCompletion completion = ^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration || requests != self->_showingRequests || listGeneration != self->_conversationListGeneration) return;
      NSDictionary *anchor = [self visibleConversationAnchor];
      self->_loading = NO;
      self->_loadingView.hidden = YES;
      NFBStopLoadingAnimation(self->_loadingView);
      BOOL shouldPlayRefreshSound = self->_refreshSuccessSoundPending;
      self->_refreshSuccessSoundPending = NO;
      [self->_refreshControl endRefreshing];
      if (error) {
        if (self->_conversations.count == 0) [self loadCachedConversationsIfAvailable];
      } else {
        NSArray<NSDictionary *> *listItems = NFBChatConversationsForList(items ?: @[], self->_showingRequests);
        self->_conversations = NFBMergedChatConversations(self->_conversations, listItems);
        self->_cursor = cursor;
        [self saveConversationListCache];
        [[NFBNotificationCoordinator sharedCoordinator] refreshMessageBadge];
        if (shouldPlayRefreshSound) NFBPlaySound(@"refresh.aac");
      }
      [self applySearchFilter];
      [self restoreVisibleConversationAnchor:anchor];
      if (!error) [self scheduleConversationPrefetch];
    });
  };
  if (_showingRequests) {
    [[NFBAtprotoClient sharedClient] fetchChatConversationRequestsWithCursor:nil completion:completion];
  } else {
    [[NFBAtprotoClient sharedClient] fetchChatConversationsWithCursor:nil completion:completion];
  }
}

- (void)loadMoreConversationsIfNeeded {
  if (![self ownsCurrentAccount]) return;
  if (_loading || _loadingMoreConversations || _moreConversationsFailed || _cursor.length == 0) return;
  NSString *cursor = [_cursor copy];
  _loadingMoreConversations = YES;
  [self updateConversationPagingFooter];
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  BOOL requests = _showingRequests;
  NSUInteger listGeneration = _conversationListGeneration;
  NFBAtprotoArrayCompletion completion = ^(NSArray<NSDictionary *> *items, NSString *nextCursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration || requests != self->_showingRequests || listGeneration != self->_conversationListGeneration) return;
      NSDictionary *anchor = [self visibleConversationAnchor];
      self->_moreConversationsFailed = error != nil;
      if (!error) {
        NSArray<NSDictionary *> *previous = self->_conversations ?: @[];
        NSArray<NSDictionary *> *listItems = NFBChatConversationsForList(items ?: @[], self->_showingRequests);
        self->_conversations = NFBMergedChatConversations(previous, listItems);
        self->_cursor = NFBChatNextPageCursor(cursor, nextCursor, self->_consumedConversationCursors);
        [self saveConversationListCache];
      }
      self->_loadingMoreConversations = NO;
      [self applySearchFilter];
      [self restoreVisibleConversationAnchor:anchor];
      if (!error) [self scheduleConversationPrefetch];
    });
  };
  if (_showingRequests) {
    [[NFBAtprotoClient sharedClient] fetchChatConversationRequestsWithCursor:cursor completion:completion];
  } else {
    [[NFBAtprotoClient sharedClient] fetchChatConversationsWithCursor:cursor completion:completion];
  }
}

- (void)updateConversationPagingFooter {
  if (!_loadingMoreConversations && _cursor.length == 0) {
    _tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    return;
  }
  UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(_tableView.bounds), 48)];
  if (_loadingMoreConversations) {
    UIImageView *spinner = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    spinner.frame = CGRectMake((CGRectGetWidth(footer.bounds) - 22) / 2, 13, 22, 22);
    spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    spinner.tintColor = NFBColorSecondaryText();
    [footer addSubview:spinner];
    NFBStartLoadingAnimation(spinner);
  } else {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = footer.bounds;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    button.titleLabel.font = NFBFont(14, NFBFontWeightRegular);
    [button setTitle:_moreConversationsFailed ? @"Couldn't load more messages. Tap to retry." : @"Load more conversations" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(retryMoreConversations) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:button];
  }
  _tableView.tableFooterView = footer;
}

- (void)retryMoreConversations {
  _moreConversationsFailed = NO;
  [self loadMoreConversationsIfNeeded];
}

- (void)scheduleConversationPrefetch {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.viewIfLoaded.window) return;
    [self->_tableView layoutIfNeeded];
    CGFloat distance = self->_tableView.contentSize.height - self->_tableView.contentOffset.y - CGRectGetHeight(self->_tableView.bounds) + self->_tableView.adjustedContentInset.bottom;
    if (distance < NFBChatPaginationPrefetchDistance(CGRectGetHeight(self->_tableView.bounds))) [self loadMoreConversationsIfNeeded];
  });
}

- (void)applySearchFilter {
  NSString *query = [_searchField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
  if (query.length == 0) {
    _filteredConversations = _conversations ?: @[];
  } else {
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *conversation in _conversations) {
      NSString *haystack = NFBChatConversationSearchText(conversation);
      if ([haystack containsString:query]) [matches addObject:conversation];
    }
    _filteredConversations = matches;
  }
  BOOL searchingOlder = query.length > 0 && _cursor.length > 0 && !_moreConversationsFailed;
  BOOL empty = !_loading && !searchingOlder && _filteredConversations.count == 0;
  _emptyTitleLabel.hidden = !empty;
  _emptySubtitleLabel.hidden = !empty;
  _emptyTitleLabel.text = _showingRequests ? NFBTweetieLocalizedString(@"DIRECT_MESSAGE_INBOX_UNTRUSTED_EMPTY_STATE_TITLE", @"Your message requests are empty") : @"No messages yet";
  _emptySubtitleLabel.text = _showingRequests ? NFBTweetieLocalizedString(@"DM_INBOX_REQUESTS_EMPTY_MESSAGE", @"Incoming messages from people you don't follow will show up here, and you'll be able to accept or ignore them") : @"Your Bluesky conversations will show up here.";
  if (query.length > 0) {
    _emptyTitleLabel.text = @"No results";
    _emptySubtitleLabel.text = @"Try another name or message.";
  }
  [_tableView reloadData];
  [self updateConversationPagingFooter];
}

- (void)searchChanged:(UITextField *)field {
  (void)field;
  [self applySearchFilter];
  [self scheduleConversationPrefetch];
}

- (void)newMessageTapped {
  NFBNewMessageViewController *newMessage = [[NFBNewMessageViewController alloc] init];
  newMessage.delegate = self;
  [self.navigationController pushViewController:newMessage animated:YES];
}

- (void)messageSettingsTapped {
  NFBSettingsViewController *settings = [[NFBSettingsViewController alloc] init];
  UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settings];
  NFBApplyNavigationAppearance(navigationController);
  navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)backFromRequests {
  _showingRequests = NO;
  _searchField.text = @"";
  [self configureNavigation];
  [self loadCachedConversationsIfAvailable];
  [self loadConversations];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return (NSInteger)_filteredConversations.count + (_showingRequests ? 0 : 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if (!_showingRequests && indexPath.row == 0) {
    NFBMessageRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:NFBMessageRequestCellIdentifier forIndexPath:indexPath];
    [cell configure];
    return cell;
  }
  NSUInteger conversationIndex = (NSUInteger)indexPath.row - (_showingRequests ? 0 : 1);
  NFBConversationCell *cell = [tableView dequeueReusableCellWithIdentifier:NFBConversationCellIdentifier forIndexPath:indexPath];
  [cell configureWithConversation:_filteredConversations[conversationIndex]];
  cell.delegate = self;
  return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (scrollView == _tableView && (scrollView.isDragging || scrollView.isDecelerating)) [self scheduleConversationPrefetch];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (!_showingRequests && indexPath.row == 0) {
    _showingRequests = YES;
    _searchField.text = @"";
    [self configureNavigation];
    [self loadCachedConversationsIfAvailable];
    [self loadConversations];
    return;
  }
  NSUInteger conversationIndex = (NSUInteger)indexPath.row - (_showingRequests ? 0 : 1);
  NSDictionary *conversation = _filteredConversations[conversationIndex];
  if (_showingRequests) {
    [self presentRequestActionsForConversation:conversation];
    return;
  }
  [self openConversation:conversation];
}

- (void)presentRequestActionsForConversation:(NSDictionary *)conversation {
  NSString *title = NFBChatConversationTitle(conversation);
  NSString *subtitle = NFBChatConversationHandle(conversation);
  __weak typeof(self) weakSelf = self;
  NSMutableArray<NSDictionary<NSString *, id> *> *actions = [NSMutableArray array];
  [actions addObject:@{
    @"id": @"accept",
    @"title": NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_ACCEPT_TITLE", @"Accept"),
    @"subtitle": NFBChatConversationRequestMessage(conversation),
    @"icon": @"nfb_check",
    @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[NFBAtprotoClient sharedClient] acceptChatConversation:NFBChatConversationID(conversation) completion:^(NSDictionary *value, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !value) return;
            [strongSelf removeConversationFromCurrentList:conversation];
            strongSelf->_showingRequests = NO;
            [strongSelf configureNavigation];
            [strongSelf loadCachedConversationsIfAvailable];
            [strongSelf replaceConversation:value];
            [strongSelf openConversation:value];
          });
        }];
    } copy]
  }];
  NSDictionary *blockProfile = NFBChatRequestBlockProfile(conversation);
  if (blockProfile.count > 0) {
    [actions addObject:@{
      @"id": @"block",
      @"title": NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_BLOCK_TITLE", @"Block"),
      @"subtitle": NFBChatConversationRequestMessage(conversation),
      @"icon": @"nfb_close",
      @"destructive": @YES,
      @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[NFBAtprotoClient sharedClient] blockProfileIfNeeded:blockProfile completion:^(NSDictionary *value, NSError *error) {
          (void)value;
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error) return;
            [[NFBAtprotoClient sharedClient] leaveChatConversation:NFBChatConversationID(conversation) completion:^(NSDictionary *leaveValue, NSError *leaveError) {
              (void)leaveValue;
              dispatch_async(dispatch_get_main_queue(), ^{
                if (leaveError) return;
                [strongSelf removeConversationFromCurrentList:conversation];
                [strongSelf loadConversations];
              });
            }];
          });
        }];
      } copy]
    }];
  }
  [actions addObject:@{
    @"id": @"delete",
    @"title": NFBTweetieLocalizedString(@"DM_CONVERSATION_FOOTER_MESSAGE_REQUESTS_ACTION_DELETE_TITLE", @"Delete"),
    @"subtitle": NFBChatDeleteConversationMessage(),
    @"icon": @"nfb_trash",
    @"destructive": @YES,
    @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[NFBAtprotoClient sharedClient] leaveChatConversation:NFBChatConversationID(conversation) completion:^(NSDictionary *value, NSError *error) {
          (void)value;
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error) return;
            [strongSelf removeConversationFromCurrentList:conversation];
            [strongSelf loadConversations];
          });
        }];
    } copy]
  }];
  NFBPresentNeoFreeBirdMenuSheet(self, NFBTweetieLocalizedString(@"DM_INBOX_PILL_REQUESTS_TITLE", @"Message request"), title.length > 0 ? title : subtitle, actions, NFBTweetieCancelTitle());
}

- (void)presentConversationActionsForConversation:(NSDictionary *)conversation sourceView:(UIView *)sourceView {
  if (![conversation isKindOfClass:NSDictionary.class]) return;
  NSString *title = NFBChatConversationTitle(conversation);
  NSString *subtitle = NFBChatConversationHandle(conversation);
  BOOL muted = [conversation[@"muted"] respondsToSelector:@selector(boolValue)] ? [conversation[@"muted"] boolValue] : NO;
  BOOL group = NFBChatConversationIsGroup(conversation);
  __weak typeof(self) weakSelf = self;
  NSMutableArray<NSDictionary<NSString *, id> *> *actions = [NSMutableArray array];
  if (NFBChatUnreadCount(conversation) > 0) {
    [actions addObject:@{
      @"id": @"mark-read",
      @"title": @"Mark as read",
      @"subtitle": @"Clear the unread badge for this conversation",
      @"icon": @"nfb_check",
      @"handler": [^{
      NSString *messageID = NFBChatMessageID(NFBChatLastMessage(conversation) ?: @{});
      [[NFBAtprotoClient sharedClient] markChatConversationRead:NFBChatConversationID(conversation) messageID:messageID completion:^(NSDictionary *value, NSError *error) {
        (void)value;
        dispatch_async(dispatch_get_main_queue(), ^{
          if (!error) [weakSelf loadConversations];
        });
      }];
    } copy]
    }];
  }
  if (group) {
    [actions addObject:@{
      @"id": @"group-info",
      @"title": NFBTweetieLocalizedString(@"DM_MANAGE_CONVERSATION_NAVIGATION_BAR_GROUP_INFO_TITLE", @"Group info"),
      @"subtitle": NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_SETTINGS_PEOPLE_LABEL", @"People"),
      @"icon": @"nfb_people_group",
      @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf openConversationInfo:conversation];
      } copy]
    }];
  } else {
    [actions addObject:@{
      @"id": @"profile",
      @"title": NFBTweetieLocalizedString(@"DIRECT_MESSAGE_CONVERSATION_VIEW_PROFILE_ACTION", @"View profile"),
      @"subtitle": NFBTweetieLocalizedString(@"GO_TO_PROFILE_LABEL", @"Go to profile"),
      @"icon": @"nfb_profile",
      @"handler": [^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      NSDictionary *profile = NFBChatPrimaryMember(conversation);
      NSString *actor = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
      if (actor.length == 0) actor = [profile[@"handle"] isKindOfClass:NSString.class] ? profile[@"handle"] : @"";
      if (actor.length == 0) return;
      NFBTimelineViewController *profileController = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
      [strongSelf.navigationController pushViewController:profileController animated:YES];
    } copy]
    }];
  }
  [actions addObject:@{
    @"id": @"mute",
    @"title": NFBChatMuteConversationTitle(muted),
    @"subtitle": muted ? @"Resume message notifications" : @"Stop notifications from this conversation",
    @"icon": @"nfb_notifications",
    @"selected": @(muted),
    @"handler": [^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      [[NFBAtprotoClient sharedClient] setChatConversationMuted:NFBChatConversationID(conversation) muted:!muted completion:^(NSDictionary *value, NSError *error) {
        (void)value;
        dispatch_async(dispatch_get_main_queue(), ^{
          if (!error) [strongSelf loadConversations];
        });
      }];
    } copy]
  }];
  [actions addObject:@{
    @"id": @"settings",
    @"title": @"Messages settings",
    @"subtitle": @"Open message preferences",
    @"icon": @"nfb_messages",
    @"handler": [^{
    [weakSelf messageSettingsTapped];
  } copy]
  }];
  [actions addObject:@{
    @"id": @"delete",
    @"title": NFBChatDeleteConversationActionTitle(conversation),
    @"subtitle": NFBChatDeleteConversationMessage(),
    @"icon": @"nfb_trash",
    @"destructive": @YES,
    @"handler": [^{
    [[NFBAtprotoClient sharedClient] leaveChatConversation:NFBChatConversationID(conversation) completion:^(NSDictionary *value, NSError *error) {
      (void)value;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!error) {
          [weakSelf removeConversationFromCurrentList:conversation];
          [weakSelf loadConversations];
        }
      });
    }];
  } copy]
  }];
  (void)sourceView;
  NFBPresentNeoFreeBirdMenuSheet(self, title.length > 0 ? title : @"Conversation", subtitle, actions, nil);
}

- (void)openConversation:(NSDictionary *)conversation {
  NFBConversationViewController *thread = [[NFBConversationViewController alloc] initWithConversation:conversation];
  __weak typeof(self) weakSelf = self;
  thread.conversationDeletedHandler = ^{
    [weakSelf removeConversationFromCurrentList:conversation];
    [weakSelf loadConversations];
  };
  thread.conversationChangedHandler = ^(NSDictionary *updated) {
    [weakSelf replaceConversation:updated];
    [[NFBNotificationCoordinator sharedCoordinator] refreshMessageBadge];
  };
  [self.navigationController pushViewController:thread animated:YES];
}

- (void)openConversationInfo:(NSDictionary *)conversation {
  NFBConversationInfoViewController *info = [[NFBConversationInfoViewController alloc] initWithConversation:conversation];
  __weak typeof(self) weakSelf = self;
  info.conversationChangedHandler = ^(NSDictionary *updated) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf replaceConversation:updated];
    [[NFBNotificationCoordinator sharedCoordinator] refreshMessageBadge];
  };
  info.conversationDeletedHandler = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf removeConversationFromCurrentList:conversation];
    [strongSelf loadConversations];
    [strongSelf.navigationController popToViewController:strongSelf animated:YES];
  };
  [self.navigationController pushViewController:info animated:YES];
}

- (void)removeConversationFromCurrentList:(NSDictionary *)conversation {
  NSString *conversationID = NFBChatConversationID(conversation);
  if (conversationID.length == 0) return;
  NSMutableArray *next = [NSMutableArray array];
  for (NSDictionary *candidate in _conversations ?: @[]) {
    if (![NFBChatConversationID(candidate) isEqualToString:conversationID]) [next addObject:candidate];
  }
  _conversations = next;
  NFBChatRemoveCacheNamed(NFBChatConversationCacheName(conversationID));
  [self saveConversationListCache];
  [self applySearchFilter];
}

- (void)replaceConversation:(NSDictionary *)conversation {
  NSString *conversationID = NFBChatConversationID(conversation);
  if (conversationID.length == 0) return;
  BOOL request = NFBChatConversationIsRequest(conversation);
  if ((_showingRequests && !request && NFBStringValue(conversation[@"status"]).length > 0) ||
      (!_showingRequests && request)) {
    [self removeConversationFromCurrentList:conversation];
    return;
  }
  NSMutableArray *next = [_conversations mutableCopy] ?: [NSMutableArray array];
  BOOL replaced = NO;
  for (NSUInteger index = 0; index < next.count; index++) {
    if ([NFBChatConversationID(next[index]) isEqualToString:conversationID]) {
      next[index] = conversation;
      replaced = YES;
      break;
    }
  }
  if (!replaced) [next insertObject:conversation atIndex:0];
  _conversations = next;
  [self saveConversationListCache];
  [self applySearchFilter];
}

- (void)conversationCellDidTapAvatar:(NFBConversationCell *)cell {
  if (NFBChatConversationIsGroup(cell.conversation)) {
    [self openConversationInfo:cell.conversation ?: @{}];
    return;
  }
  NSDictionary *profile = cell.profile ?: @{};
  NSString *actor = NFBStringValue(profile[@"did"]);
  if (actor.length == 0) actor = NFBStringValue(profile[@"handle"]);
  if (actor.length == 0) return;
  NFBTimelineViewController *profileVC = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
  [self.navigationController pushViewController:profileVC animated:YES];
}

- (void)conversationCellDidLongPress:(NFBConversationCell *)cell sourceView:(UIView *)sourceView {
  [self presentConversationActionsForConversation:cell.conversation sourceView:sourceView];
}

- (void)newMessageViewController:(NFBNewMessageViewController *)viewController didChooseProfiles:(NSArray<NSDictionary *> *)profiles {
  NSMutableArray<NSDictionary *> *selectedProfiles = [NSMutableArray array];
  NSMutableArray<NSString *> *dids = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  NSString *viewerDID = [NFBAtprotoSession sharedSession].did ?: @"";
  for (NSDictionary *profile in profiles ?: @[]) {
    NSString *did = NFBStringValue(profile[@"did"]);
    if (did.length == 0 || [did isEqualToString:viewerDID] || [seen containsObject:did]) continue;
    [seen addObject:did];
    [dids addObject:did];
    [selectedProfiles addObject:profile];
  }
  if (dids.count == 0) return;
  if (dids.count > NFBChatGroupMaxInvitedMembers) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBTweetieLocalizedString(@"DM_CONVERSATION_TOO_MANY_PARTICIPANTS_ERROR_TITLE", @"Too many members")
                                                                   message:@"Bluesky group chats can include up to 49 invited people."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
    [viewController presentViewController:alert animated:YES completion:nil];
    return;
  }

  void (^finishWithConversation)(NSDictionary *, NSError *) = ^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error || !value) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NFBChatErrorIsPermissionDenied(error) ? @"Messages" : NFBTweetieLocalizedString(@"DM_NETWORK_ERROR_TITLE", @"Something went wrong. Check your connection and try again.")
                                                                       message:NFBChatPresentedErrorMessage(error)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NFBTweetieOKTitle() style:UIAlertActionStyleCancel handler:nil]];
        [viewController presentViewController:alert animated:YES completion:nil];
        return;
      }
      NSMutableDictionary *conversation = [value mutableCopy];
      NSArray *members = [conversation[@"members"] isKindOfClass:NSArray.class] ? conversation[@"members"] : @[];
      if (members.count == 0) conversation[@"members"] = selectedProfiles;
      [viewController.navigationController popViewControllerAnimated:NO];
      [self replaceConversation:conversation];
      [self openConversation:conversation];
    });
  };

  if (dids.count == 1) {
    [[NFBAtprotoClient sharedClient] fetchChatConversationForMembers:@[dids.firstObject] completion:finishWithConversation];
  } else {
    [[NFBAtprotoClient sharedClient] createChatGroupWithMembers:dids
                                                           name:NFBChatDefaultGroupNameForProfiles(selectedProfiles)
                                                     completion:finishWithConversation];
  }
}

@end
