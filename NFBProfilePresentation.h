#ifndef NFB_PROFILE_PRESENTATION_H
#define NFB_PROFILE_PRESENTATION_H

#include <stdbool.h>

typedef struct {
  bool hasProfile, signedIn, ownProfile;
  bool blocking, blockedBy, following, followsViewer;
  bool canMessage;
} NFBProfileState;

typedef struct {
  bool edit, follow, message, notifications, followsYou, mutuals, counts;
} NFBProfileElements;

static inline NFBProfileElements NFBProfileElementsForState(NFBProfileState state) {
  bool other = state.hasProfile && !state.ownProfile;
  bool interacting = other && state.signedIn && !state.blocking && !state.blockedBy;
  return (NFBProfileElements){
    .edit = state.hasProfile && state.signedIn && state.ownProfile,
    .follow = other && !state.blockedBy,
    .message = interacting && state.canMessage,
    .notifications = interacting && state.following,
    .followsYou = interacting && state.followsViewer,
    .mutuals = interacting,
    .counts = state.hasProfile && !state.blockedBy
  };
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>

// ATProto uses record URIs for follows/blocks, a boolean for blockedBy, and
// objects for list-based relationships. Do not interpret them all as strings.
static inline BOOL NFBProfileRelationshipPresent(id value) {
  if ([value isKindOfClass:NSString.class]) return [value length] > 0;
  if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
  return [value isKindOfClass:NSDictionary.class] && [value count] > 0;
}

static inline BOOL NFBProfileViewerIsBlocking(NSDictionary *viewer) {
  return NFBProfileRelationshipPresent(viewer[@"blocking"]) || NFBProfileRelationshipPresent(viewer[@"blockingByList"]);
}

static inline BOOL NFBProfileViewerIsBlockedBy(NSDictionary *viewer) {
  return NFBProfileRelationshipPresent(viewer[@"blockedBy"]) || NFBProfileRelationshipPresent(viewer[@"blockedByList"]);
}
#endif
#endif
