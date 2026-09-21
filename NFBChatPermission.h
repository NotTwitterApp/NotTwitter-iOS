#import <Foundation/Foundation.h>

// Keep protocol error names separate from human-readable server messages.
static NSString * const NFBChatErrorNameKey = @"NFBATProtoErrorName";

static inline BOOL NFBChatErrorIsPermissionDenied(NSError *error) {
  NSString *name = [error.userInfo objectForKey:NFBChatErrorNameKey];
  return [@[@"MessagesDisabled", @"NotFollowedBySender", @"BlockedActor", @"BlockedSubject",
            @"AccountSuspended", @"RecipientNotFound", @"ConvoLocked"] containsObject:name ?: @""];
}

static inline NSError *NFBChatPermissionDeniedError(void) {
  return [NSError errorWithDomain:@"NFBAtprotoClient" code:403 userInfo:@{
    NFBChatErrorNameKey: @"MessagesDisabled",
    NSLocalizedDescriptionKey: @"Sorry! You cannot message this account."
  }];
}

static inline BOOL NFBChatAvailabilityAllowsMessaging(NSDictionary *availability) {
  id canChat = [availability objectForKey:@"canChat"];
  return [canChat isKindOfClass:NSNumber.class] && [canChat boolValue];
}
