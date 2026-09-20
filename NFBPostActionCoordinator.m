#import "NFBPostActionCoordinator.h"

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBComposeViewController.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBNotificationCoordinator.h"
#import "NFBTheme.h"
#import "NFBTimelineViewController.h"
#import "NFBProfilePresentation.h"

static UIColor *NFBActionLikeColor(void) {
  return [UIColor colorWithRed:0.976 green:0.094 blue:0.502 alpha:1.0];
}

static UIColor *NFBActionRepostColor(void) {
  return [UIColor colorWithRed:0.0 green:0.729 blue:0.486 alpha:1.0];
}

static UIView *NFBActionAnimationHostForView(UIView *view) {
  UIView *host = view.superview;
  while (host && CGRectGetWidth(host.bounds) < 36.0 && host.superview) host = host.superview;
  return host ?: view.superview;
}

static CGPoint NFBActionCenterInHost(UIView *view, UIView *host) {
  return [view.superview convertPoint:view.center toView:host];
}

@implementation NFBPostActionCoordinator

- (instancetype)initWithPresentingViewController:(UIViewController *)presentingViewController {
  self = [super init];
  if (self) {
    _presentingViewController = presentingViewController;
  }
  return self;
}

- (BOOL)ensureSession {
  if ([[NFBAtprotoSession sharedSession] hasSession]) return YES;
  NFBPresentBlueskyLoginIfNeeded();
  return NO;
}

- (UIViewController *)presenter {
  return self.presentingViewController ?: UIApplication.sharedApplication.keyWindow.rootViewController;
}

- (void)showActionError:(NSError *)error {
  UIViewController *presenter = [self presenter];
  if (!presenter || !error) return;
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't update Tweet"
                                                                 message:error.localizedDescription ?: @"Please try again."
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)performReplyForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  if (![self ensureSession]) return;
  [self.class animateActionView:sourceView kind:NFBPostActionKindReply activating:YES];
  [self.class playActionFeedbackForKind:NFBPostActionKindReply activating:YES];
  NFBComposeViewController *compose = [[NFBComposeViewController alloc] initWithReplyToPost:post ?: @{}];
  __weak typeof(self) weakSelf = self;
  compose.completionHandler = ^(BOOL posted) {
    if (posted && weakSelf.reloadHandler) weakSelf.reloadHandler();
  };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [[self presenter] presentViewController:nav animated:YES completion:nil];
}

- (void)performRepostForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  if (![self ensureSession]) return;
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  __weak typeof(self) weakSelf = self;
  NFBPresentNeoFreeBirdRetweetSheet([self presenter], reposted, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf.class animateActionView:sourceView kind:NFBPostActionKindRepost activating:!reposted];
    [strongSelf.class playActionFeedbackForKind:NFBPostActionKindRepost activating:!reposted];
    NSDictionary *optimistic = [NFBAtprotoClient post:post applyingToggleForViewerKey:@"repost" countKey:@"repostCount" response:nil];
    if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(optimistic, post ?: @{});
    [[NFBAtprotoClient sharedClient] toggleRepostForPost:post completion:^(NSDictionary *value, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
          if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(post ?: @{}, post ?: @{});
          [strongSelf showActionError:error];
          return;
        }
        NSDictionary *updatedPost = [NFBAtprotoClient post:post applyingToggleForViewerKey:@"repost" countKey:@"repostCount" response:value];
        if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(updatedPost, post ?: @{});
      });
    }];
  }, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf.class animateActionView:sourceView kind:NFBPostActionKindRepost activating:YES];
    [strongSelf.class playActionFeedbackForKind:NFBPostActionKindRepost activating:YES];
    NFBComposeViewController *compose = [[NFBComposeViewController alloc] initWithQuotePost:post ?: @{}];
    compose.completionHandler = ^(BOOL posted) {
      if (posted && strongSelf.reloadHandler) strongSelf.reloadHandler();
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
    NFBApplyNavigationAppearance(nav);
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [[strongSelf presenter] presentViewController:nav animated:YES completion:nil];
  });
}

- (void)performLikeForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  if (![self ensureSession]) return;
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL liked = [viewer[@"like"] isKindOfClass:NSString.class] && [viewer[@"like"] length] > 0;
  [self.class animateActionView:sourceView kind:NFBPostActionKindLike activating:!liked];
  [self.class playActionFeedbackForKind:NFBPostActionKindLike activating:!liked];
  NSDictionary *optimistic = [NFBAtprotoClient post:post applyingToggleForViewerKey:@"like" countKey:@"likeCount" response:nil];
  if (self.postUpdateHandler) self.postUpdateHandler(optimistic, post ?: @{});
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] toggleLikeForPost:post completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (error) {
        if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(post ?: @{}, post ?: @{});
        [strongSelf showActionError:error];
        return;
      }
      NSDictionary *updatedPost = [NFBAtprotoClient post:post applyingToggleForViewerKey:@"like" countKey:@"likeCount" response:value];
      if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(updatedPost, post ?: @{});
    });
  }];
}

- (void)performBookmarkForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  if (![self ensureSession]) return;
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  [self.class animateActionView:sourceView kind:NFBPostActionKindBookmark activating:!bookmarked];
  [self.class playActionFeedbackForKind:NFBPostActionKindBookmark activating:!bookmarked];
  NSDictionary *optimistic = [NFBAtprotoClient postByApplyingBookmarkToggleForPost:post response:nil];
  if (self.postUpdateHandler) self.postUpdateHandler(optimistic, post ?: @{});
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] toggleBookmarkForPost:post completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (error) {
        if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(post ?: @{}, post ?: @{});
        [strongSelf showActionError:error];
        return;
      }
      NSDictionary *updatedPost = [NFBAtprotoClient postByApplyingBookmarkToggleForPost:post response:value];
      if (strongSelf.postUpdateHandler) strongSelf.postUpdateHandler(updatedPost, post ?: @{});
    });
  }];
}

- (void)performShareForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  [self.class animateActionView:sourceView kind:NFBPostActionKindShare activating:YES];
  [self.class playActionFeedbackForKind:NFBPostActionKindShare activating:YES];
  NSString *urlString = [NFBAtprotoClient webURLStringForPost:post ?: @{}];
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  id shareItem = url ?: (uri ?: @"");
  if ([shareItem isKindOfClass:NSString.class] && [(NSString *)shareItem length] == 0) return;
  UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[shareItem] applicationActivities:nil];
  [[self presenter] presentViewController:activity animated:YES completion:nil];
}

- (void)performCopyLinkForPost:(NSDictionary *)post {
  NSString *urlString = [NFBAtprotoClient webURLStringForPost:post ?: @{}];
  if (urlString.length == 0) urlString = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  if (urlString.length == 0) return;
  UIPasteboard.generalPasteboard.string = urlString;
  [self showTransientActionMessage:@"Copied link to Tweet"];
}

- (void)showTransientActionMessage:(NSString *)message {
  UIViewController *presenter = [self presenter];
  if (!presenter || message.length == 0) return;
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [presenter presentViewController:alert animated:YES completion:^{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [alert dismissViewControllerAnimated:YES completion:nil];
    });
  }];
}

- (void)showUnavailableActionNamed:(NSString *)name {
  UIViewController *presenter = [self presenter];
  if (!presenter) return;
  NSString *title = name.length > 0 ? name : @"Action unavailable";
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:@"Reporting isn’t available yet."
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)performDeleteForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  [self.class animateActionView:sourceView kind:NFBPostActionKindDelete activating:YES];
  [self confirmDeletePost:post];
}

- (void)presentMoreMenuForPost:(NSDictionary *)post sourceView:(UIView *)sourceView {
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *displayHandle = [NFBAtprotoClient displayHandleForProfile:author];
  BOOL isCurrentUser = [self.class isPostAuthoredByCurrentUser:post];
  NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
  BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
  BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
  BOOL conversationMuted = [NFBNotificationCoordinator isConversationMutedForPost:post];
  __weak typeof(self) weakSelf = self;
  NSMutableArray<NSDictionary<NSString *, id> *> *actions = [NSMutableArray array];
  if (!isCurrentUser) {
    [actions addObject:@{
      @"id": @"mute",
      @"title": displayHandle.length > 0 ? [NSString stringWithFormat:@"Mute %@", displayHandle] : @"Mute",
      @"icon": @"nfb_close",
      @"handler": [^{
        [weakSelf showUnavailableActionNamed:@"Mute account"];
      } copy]
    }];
  }
  [actions addObject:@{
    @"id": @"mute-conversation",
    @"title": conversationMuted ? @"Unmute Conversation" : @"Mute Conversation",
    @"icon": @"nfb_notifications",
    @"selected": @(conversationMuted),
    @"handler": [^{
      BOOL nextMuted = ![NFBNotificationCoordinator isConversationMutedForPost:post];
      [NFBNotificationCoordinator setConversationMuted:nextMuted forPost:post];
      [weakSelf showTransientActionMessage:nextMuted ? @"Muted conversation" : @"Unmuted conversation"];
    } copy]
  }];
  if (!isCurrentUser) {
    if (!blockingByList) {
      [actions addObject:@{
        @"id": @"block",
        @"title": displayHandle.length > 0 ? [NSString stringWithFormat:@"%@ %@", blocking ? @"Unblock" : @"Block", displayHandle] : (blocking ? @"Unblock" : @"Block"),
        @"icon": @"nfb_close",
        @"selected": @(blocking),
        @"destructive": blocking ? @NO : @YES,
        @"handler": [^{
          [weakSelf performBlockForProfile:author sourceView:sourceView completion:nil];
        } copy]
      }];
    }
    [actions addObject:@{
      @"id": @"report",
      @"title": @"Report Tweet",
      @"icon": @"nfb_info",
      @"destructive": @YES,
      @"handler": [^{
        [weakSelf showUnavailableActionNamed:@"Report Tweet"];
      } copy]
    }];
  }
  [actions addObject:@{
    @"id": @"share",
    @"title": @"Share Tweet",
    @"icon": @"nfb_share",
    @"handler": [^{
      [weakSelf performShareForPost:post sourceView:sourceView];
    } copy]
  }];
  [actions addObject:@{
    @"id": @"copy-link",
    @"title": @"Copy link to Tweet",
    @"icon": @"nfb_link",
    @"handler": [^{
      [weakSelf performCopyLinkForPost:post];
    } copy]
  }];
  if ([self.class isPostAuthoredByCurrentUser:post]) {
    [actions addObject:@{
      @"id": @"delete",
      @"title": @"Delete Tweet",
      @"icon": @"nfb_trash",
      @"destructive": @YES,
      @"handler": [^{
        [weakSelf confirmDeletePost:post];
      } copy]
    }];
  }
  NFBPresentNeoFreeBirdMenuSheet([self presenter], nil, nil, actions, nil);
}

- (UIMenu *)contextMenuForPost:(NSDictionary *)post {
  if (@available(iOS 13.0, *)) {
    NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
    NSString *displayHandle = [NFBAtprotoClient displayHandleForProfile:author];
    BOOL isCurrentUser = [self.class isPostAuthoredByCurrentUser:post];
    NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
    BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
    BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
    BOOL conversationMuted = [NFBNotificationCoordinator isConversationMutedForPost:post];
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    if (!isCurrentUser) {
      UIAction *mute = [UIAction actionWithTitle:displayHandle.length > 0 ? [NSString stringWithFormat:@"Mute %@", displayHandle] : @"Mute" image:NFBTemplateIcon(@"nfb_close") identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        [weakSelf showUnavailableActionNamed:@"Mute account"];
      }];
      [actions addObject:mute];
    }
    UIAction *muteConversation = [UIAction actionWithTitle:conversationMuted ? @"Unmute Conversation" : @"Mute Conversation" image:NFBTemplateIcon(@"nfb_notifications") identifier:nil handler:^(__kindof UIAction *action) {
      (void)action;
      BOOL nextMuted = ![NFBNotificationCoordinator isConversationMutedForPost:post];
      [NFBNotificationCoordinator setConversationMuted:nextMuted forPost:post];
      [weakSelf showTransientActionMessage:nextMuted ? @"Muted conversation" : @"Unmuted conversation"];
    }];
    muteConversation.state = conversationMuted ? UIMenuElementStateOn : UIMenuElementStateOff;
    [actions addObject:muteConversation];
    if (!isCurrentUser) {
      if (!blockingByList) {
        UIAction *block = [UIAction actionWithTitle:displayHandle.length > 0 ? [NSString stringWithFormat:@"%@ %@", blocking ? @"Unblock" : @"Block", displayHandle] : (blocking ? @"Unblock" : @"Block") image:NFBTemplateIcon(@"nfb_close") identifier:nil handler:^(__kindof UIAction *action) {
          (void)action;
          [weakSelf performBlockForProfile:author sourceView:nil completion:nil];
        }];
        block.state = blocking ? UIMenuElementStateOn : UIMenuElementStateOff;
        block.attributes = blocking ? 0 : UIMenuElementAttributesDestructive;
        [actions addObject:block];
      }
      UIAction *report = [UIAction actionWithTitle:@"Report Tweet" image:NFBTemplateIcon(@"nfb_info") identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        [weakSelf showUnavailableActionNamed:@"Report Tweet"];
      }];
      report.attributes = UIMenuElementAttributesDestructive;
      [actions addObject:report];
    }
    UIAction *share = [UIAction actionWithTitle:@"Share Tweet" image:NFBTemplateIcon(@"nfb_share") identifier:nil handler:^(__kindof UIAction *action) {
      (void)action;
      [weakSelf performShareForPost:post sourceView:nil];
    }];
    [actions addObject:share];
    UIAction *copyLink = [UIAction actionWithTitle:@"Copy link to Tweet" image:NFBTemplateIcon(@"nfb_link") identifier:nil handler:^(__kindof UIAction *action) {
      (void)action;
      [weakSelf performCopyLinkForPost:post];
    }];
    [actions addObject:copyLink];
    if ([self.class isPostAuthoredByCurrentUser:post]) {
	    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete Tweet" image:NFBTemplateIcon(@"nfb_trash") identifier:nil handler:^(__kindof UIAction *action) {
	        (void)action;
	        [weakSelf confirmDeletePost:post];
	      }];
	      deleteAction.attributes = UIMenuElementAttributesDestructive;
	      [actions addObject:deleteAction];
	    }
	    return [UIMenu menuWithTitle:@"" children:actions];
	  }
	  return nil;
	}

- (void)confirmDeletePost:(NSDictionary *)post {
  if (![self ensureSession]) return;
  __weak typeof(self) weakSelf = self;
  NFBPresentNeoFreeBirdMenuSheet([self presenter], @"Delete Tweet?", @"This can’t be undone, and it will be removed from your profile and timelines.", @[
    @{
      @"id": @"delete",
      @"title": @"Delete Tweet",
      @"subtitle": @"Permanently remove this Tweet",
      @"icon": @"nfb_trash",
      @"destructive": @YES,
      @"handler": [^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.class playActionFeedbackForKind:NFBPostActionKindDelete activating:YES];
        [[NFBAtprotoClient sharedClient] deletePost:post completion:^(NSDictionary *value, NSError *error) {
          (void)value;
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
              [strongSelf showActionError:error];
              return;
            }
            if (strongSelf.deleteHandler) strongSelf.deleteHandler(post ?: @{});
          });
        }];
      } copy]
    }
  ], @"Cancel");
}

- (void)performFollowForProfile:(NSDictionary *)profile
                      sourceView:(UIView *)sourceView
                      completion:(void (^)(NSDictionary *updatedProfile, NSError *error))completion {
  if ([self.class shouldHideFollowButtonForProfile:profile]) return;
  if (![self ensureSession]) return;
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
  BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
  if (blocking || blockingByList) {
    [self performBlockForProfile:profile sourceView:sourceView completion:completion];
    return;
  }
  BOOL following = [viewer[@"following"] isKindOfClass:NSString.class] && [viewer[@"following"] length] > 0;
  [self.class animateActionView:sourceView kind:NFBPostActionKindFollow activating:!following];
  [self.class playActionFeedbackForKind:NFBPostActionKindFollow activating:!following];
  NSDictionary *optimisticProfile = [NFBAtprotoClient profile:profile applyingFollowToggleWithResponse:nil];
  if (self.profileUpdateHandler) self.profileUpdateHandler(optimisticProfile, profile ?: @{});
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] toggleFollowForProfile:profile completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (error) {
        if (strongSelf.profileUpdateHandler) strongSelf.profileUpdateHandler(profile ?: @{}, profile ?: @{});
        [strongSelf showActionError:error];
        if (completion) completion(profile ?: @{}, error);
        return;
      }
      NSDictionary *updatedProfile = [NFBAtprotoClient profile:profile applyingFollowToggleWithResponse:value];
      if (strongSelf.profileUpdateHandler) strongSelf.profileUpdateHandler(updatedProfile, profile ?: @{});
      if (completion) completion(updatedProfile, nil);
    });
  }];
}

- (void)performBlockForProfile:(NSDictionary *)profile
                     sourceView:(UIView *)sourceView
                     completion:(void (^)(NSDictionary *updatedProfile, NSError *error))completion {
  if ([self.class isProfileCurrentUser:profile]) return;
  if (![self ensureSession]) return;
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
  if (blockingByList) return;
  BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
  [self.class animateActionView:sourceView kind:NFBPostActionKindFollow activating:!blocking];
  [self.class playActionFeedbackForKind:NFBPostActionKindFollow activating:!blocking];
  NSDictionary *optimisticProfile = [NFBAtprotoClient profile:profile applyingBlockToggleWithResponse:nil];
  if (self.profileUpdateHandler) self.profileUpdateHandler(optimisticProfile, profile ?: @{});
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] toggleBlockForProfile:profile completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (error) {
        if (strongSelf.profileUpdateHandler) strongSelf.profileUpdateHandler(profile ?: @{}, profile ?: @{});
        [strongSelf showActionError:error];
        if (completion) completion(profile ?: @{}, error);
        return;
      }
      NSDictionary *updatedProfile = [NFBAtprotoClient profile:profile applyingBlockToggleWithResponse:value];
      if (strongSelf.profileUpdateHandler) strongSelf.profileUpdateHandler(updatedProfile, profile ?: @{});
      if (completion) completion(updatedProfile, nil);
    });
  }];
}

- (void)performGoToProfile:(NSDictionary *)profile {
  if (![profile isKindOfClass:NSDictionary.class] || profile.count == 0) return;
  UIViewController *presenter = [self presenter];
  UINavigationController *navigationController = presenter.navigationController ?: presenter.presentingViewController.navigationController;
  if (!navigationController) return;

  UIViewController *top = navigationController.topViewController;
  if ([top respondsToSelector:@selector(isViewingProfileForProfile:)] &&
      [(id)top isViewingProfileForProfile:profile]) {
    if ([top isKindOfClass:NFBTimelineViewController.class]) [(NFBTimelineViewController *)top animateCurrentProfileReselection];
    if (presenter.presentingViewController && !presenter.navigationController) {
      [presenter dismissViewControllerAnimated:YES completion:nil];
    }
    return;
  }

  void (^push)(void) = ^{
    UIViewController *visibleTop = navigationController.topViewController;
    if ([visibleTop respondsToSelector:@selector(isViewingProfileForProfile:)] &&
        [(id)visibleTop isViewingProfileForProfile:profile]) {
      if ([visibleTop isKindOfClass:NFBTimelineViewController.class]) [(NFBTimelineViewController *)visibleTop animateCurrentProfileReselection];
      return;
    }
    NSString *actor = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
    if (actor.length == 0) actor = [profile[@"handle"] isKindOfClass:NSString.class] ? profile[@"handle"] : @"";
    if (actor.length == 0) return;
    NFBTimelineViewController *profileController = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
    [navigationController pushViewController:profileController animated:YES];
  };

  if (presenter.presentingViewController && !presenter.navigationController) {
    [presenter dismissViewControllerAnimated:YES completion:push];
  } else {
    push();
  }
}

+ (BOOL)isPostAuthoredByCurrentUser:(NSDictionary *)post {
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  return [self isProfileCurrentUser:author];
}

+ (BOOL)isProfileCurrentUser:(NSDictionary *)profile {
  NSString *profileDID = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  return profileDID.length > 0 && sessionDID.length > 0 && [profileDID isEqualToString:sessionDID];
}

+ (NSString *)followTitleForProfile:(NSDictionary *)profile {
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
  BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
  if (blocking) return @"Unblock";
  if (blockingByList) return @"Blocked";
  BOOL following = [viewer[@"following"] isKindOfClass:NSString.class] && [viewer[@"following"] length] > 0;
  BOOL followedBy = [viewer[@"followedBy"] isKindOfClass:NSString.class] && [viewer[@"followedBy"] length] > 0;
  if (following) return @"Following";
  if (followedBy) return @"Follow back";
  return @"Follow";
}

+ (BOOL)shouldHideFollowButtonForProfile:(NSDictionary *)profile {
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  BOOL blockedBy = NFBProfileViewerIsBlockedBy(viewer);
  return [self isProfileCurrentUser:profile] || blockedBy;
}

+ (void)configureFollowButton:(UIButton *)button profile:(NSDictionary *)profile overDarkBackground:(BOOL)overDarkBackground {
  if (!button) return;
  BOOL hidden = [self shouldHideFollowButtonForProfile:profile];
  button.hidden = hidden;
  button.userInteractionEnabled = !hidden;
  if (hidden) return;

  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  BOOL following = [viewer[@"following"] isKindOfClass:NSString.class] && [viewer[@"following"] length] > 0;
  BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
  BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
  NSString *title = [self followTitleForProfile:profile];
  [button setTitle:title forState:UIControlStateNormal];
  button.userInteractionEnabled = !blockingByList;
  NFBIPAApplyFollowButtonAppearance(button, following || blockingByList, blocking, overDarkBackground);
}

+ (void)animateActionView:(UIView *)view kind:(NFBPostActionKind)kind activating:(BOOL)activating {
  if (!view) return;
  if (kind == NFBPostActionKindLike) {
    [self animateLikeView:view activating:activating];
    return;
  }
  if (kind == NFBPostActionKindRepost) {
    [self animateRepostView:view activating:activating];
    return;
  }

  CGFloat overshoot = activating ? 1.34 : 1.18;
  if (kind == NFBPostActionKindReply || kind == NFBPostActionKindShare) overshoot = 1.16;
  view.transform = CGAffineTransformIdentity;
  [UIView animateKeyframesWithDuration:0.42 delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
    [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.26 animations:^{
      view.transform = CGAffineTransformMakeScale(0.86, 0.86);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.26 relativeDuration:0.34 animations:^{
      view.transform = CGAffineTransformMakeScale(overshoot, overshoot);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.60 relativeDuration:0.22 animations:^{
      view.transform = CGAffineTransformMakeScale(0.96, 0.96);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.82 relativeDuration:0.18 animations:^{
      view.transform = CGAffineTransformIdentity;
    }];
  } completion:^(BOOL finished) {
    (void)finished;
    view.transform = CGAffineTransformIdentity;
  }];
}

+ (void)animateLikeView:(UIView *)view activating:(BOOL)activating {
  if ([view isKindOfClass:UIImageView.class]) {
    UIImageView *imageView = (UIImageView *)view;
    if (activating) {
      imageView.image = NFBTemplateIcon(@"nfb_like_filled");
      imageView.tintColor = NFBActionLikeColor();
    } else {
      imageView.image = NFBTemplateIcon(@"nfb_like");
    }
  }

  if (!activating) {
    [self animateReactionSettleForView:view overshoot:1.10];
    return;
  }

  UIView *host = NFBActionAnimationHostForView(view);
  CGPoint center = host ? NFBActionCenterInHost(view, host) : CGPointZero;
  UIView *burst = nil;
  if (host) {
    burst = [[UIView alloc] initWithFrame:CGRectMake(center.x - 34.0, center.y - 34.0, 68.0, 68.0)];
    burst.userInteractionEnabled = NO;
    burst.backgroundColor = UIColor.clearColor;
    burst.clipsToBounds = NO;
    [host addSubview:burst];

    UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(18.0, 18.0, 32.0, 32.0)];
    ring.userInteractionEnabled = NO;
    ring.layer.cornerRadius = 16.0;
    ring.layer.borderWidth = 2.5;
    ring.layer.borderColor = NFBActionLikeColor().CGColor;
    ring.alpha = 0.0;
    ring.transform = CGAffineTransformMakeScale(0.20, 0.20);
    [burst addSubview:ring];

    [UIView animateKeyframesWithDuration:0.58 delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
      [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.18 animations:^{
        ring.alpha = 0.95;
        ring.transform = CGAffineTransformMakeScale(0.55, 0.55);
      }];
      [UIView addKeyframeWithRelativeStartTime:0.18 relativeDuration:0.48 animations:^{
        ring.alpha = 0.22;
        ring.transform = CGAffineTransformMakeScale(1.42, 1.42);
      }];
      [UIView addKeyframeWithRelativeStartTime:0.66 relativeDuration:0.34 animations:^{
        ring.alpha = 0.0;
        ring.transform = CGAffineTransformMakeScale(1.72, 1.72);
      }];
    } completion:nil];

    NSArray<UIColor *> *colors = @[
      [UIColor colorWithRed:0.98 green:0.24 blue:0.47 alpha:1.0],
      [UIColor colorWithRed:0.99 green:0.72 blue:0.20 alpha:1.0],
      [UIColor colorWithRed:0.40 green:0.85 blue:0.76 alpha:1.0],
      [UIColor colorWithRed:0.45 green:0.45 blue:1.00 alpha:1.0],
      [UIColor colorWithRed:0.74 green:0.34 blue:0.94 alpha:1.0],
      [UIColor colorWithRed:0.99 green:0.45 blue:0.73 alpha:1.0],
      [UIColor colorWithRed:0.60 green:0.91 blue:0.55 alpha:1.0],
      [UIColor colorWithRed:0.91 green:0.55 blue:0.77 alpha:1.0]
    ];
    CGFloat centerInBurst = CGRectGetMidX(burst.bounds);
    for (NSUInteger index = 0; index < colors.count; index++) {
      CGFloat angle = ((CGFloat)index / (CGFloat)colors.count) * (CGFloat)(M_PI * 2.0) - (CGFloat)(M_PI_2);
      CGFloat distance = index % 2 == 0 ? 30.0 : 25.0;
      CGFloat dotSize = index % 3 == 0 ? 5.0 : 4.0;
      UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(centerInBurst - dotSize * 0.5, centerInBurst - dotSize * 0.5, dotSize, dotSize)];
      dot.backgroundColor = colors[index];
      dot.layer.cornerRadius = dotSize * 0.5;
      dot.alpha = 0.0;
      dot.transform = CGAffineTransformMakeScale(0.15, 0.15);
      [burst addSubview:dot];
      CGPoint endCenter = CGPointMake(centerInBurst + cos(angle) * distance, centerInBurst + sin(angle) * distance);
      [UIView animateKeyframesWithDuration:0.62 delay:0.03 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.16 animations:^{
          dot.alpha = 1.0;
          dot.transform = CGAffineTransformMakeScale(1.08, 1.08);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.16 relativeDuration:0.54 animations:^{
          dot.center = endCenter;
          dot.transform = CGAffineTransformMakeScale(0.86, 0.86);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.70 relativeDuration:0.30 animations:^{
          dot.alpha = 0.0;
          dot.transform = CGAffineTransformMakeScale(0.12, 0.12);
        }];
      } completion:nil];
    }
  }

  view.transform = CGAffineTransformMakeScale(0.18, 0.18);
  [UIView animateKeyframesWithDuration:0.62 delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
    [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.18 animations:^{
      view.transform = CGAffineTransformMakeScale(0.18, 0.18);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.18 relativeDuration:0.25 animations:^{
      view.transform = CGAffineTransformMakeScale(1.34, 1.34);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.43 relativeDuration:0.20 animations:^{
      view.transform = CGAffineTransformMakeScale(0.88, 0.88);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.63 relativeDuration:0.20 animations:^{
      view.transform = CGAffineTransformMakeScale(1.08, 1.08);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.83 relativeDuration:0.17 animations:^{
      view.transform = CGAffineTransformIdentity;
    }];
  } completion:^(BOOL finished) {
    (void)finished;
    view.transform = CGAffineTransformIdentity;
    [burst removeFromSuperview];
  }];
}

+ (void)animateRepostView:(UIView *)view activating:(BOOL)activating {
  if ([view isKindOfClass:UIImageView.class] && activating) {
    ((UIImageView *)view).tintColor = NFBActionRepostColor();
  }

  if (!activating) {
    [self animateReactionSettleForView:view overshoot:1.08];
    return;
  }

  UIView *host = NFBActionAnimationHostForView(view);
  CGPoint center = host ? NFBActionCenterInHost(view, host) : CGPointZero;
  UIView *pulse = nil;
  if (host) {
    pulse = [[UIView alloc] initWithFrame:CGRectMake(center.x - 22.0, center.y - 22.0, 44.0, 44.0)];
    pulse.userInteractionEnabled = NO;
    pulse.layer.cornerRadius = 22.0;
    pulse.backgroundColor = [NFBActionRepostColor() colorWithAlphaComponent:0.14];
    pulse.alpha = 0.0;
    pulse.transform = CGAffineTransformMakeScale(0.38, 0.38);
    if (view.superview == host) {
      [host insertSubview:pulse belowSubview:view];
    } else {
      [host addSubview:pulse];
      [host sendSubviewToBack:pulse];
    }
    [UIView animateKeyframesWithDuration:0.46 delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
      [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.24 animations:^{
        pulse.alpha = 1.0;
        pulse.transform = CGAffineTransformMakeScale(0.86, 0.86);
      }];
      [UIView addKeyframeWithRelativeStartTime:0.24 relativeDuration:0.76 animations:^{
        pulse.alpha = 0.0;
        pulse.transform = CGAffineTransformMakeScale(1.24, 1.24);
      }];
    } completion:nil];
  }

  view.transform = CGAffineTransformIdentity;
  [UIView animateKeyframesWithDuration:0.46 delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
    [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.22 animations:^{
      view.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.82, 0.82), CGAffineTransformMakeRotation((CGFloat)(-M_PI / 16.0)));
    }];
    [UIView addKeyframeWithRelativeStartTime:0.22 relativeDuration:0.36 animations:^{
      view.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.22, 1.22), CGAffineTransformMakeRotation((CGFloat)(M_PI / 18.0)));
    }];
    [UIView addKeyframeWithRelativeStartTime:0.58 relativeDuration:0.24 animations:^{
      view.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.96, 0.96), CGAffineTransformMakeRotation((CGFloat)(-M_PI / 40.0)));
    }];
    [UIView addKeyframeWithRelativeStartTime:0.82 relativeDuration:0.18 animations:^{
      view.transform = CGAffineTransformIdentity;
    }];
  } completion:^(BOOL finished) {
    (void)finished;
    view.transform = CGAffineTransformIdentity;
    [pulse removeFromSuperview];
  }];
}

+ (void)animateReactionSettleForView:(UIView *)view overshoot:(CGFloat)overshoot {
  view.transform = CGAffineTransformIdentity;
  [UIView animateKeyframesWithDuration:0.30 delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
    [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.34 animations:^{
      view.transform = CGAffineTransformMakeScale(0.84, 0.84);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.34 relativeDuration:0.36 animations:^{
      view.transform = CGAffineTransformMakeScale(overshoot, overshoot);
    }];
    [UIView addKeyframeWithRelativeStartTime:0.70 relativeDuration:0.30 animations:^{
      view.transform = CGAffineTransformIdentity;
    }];
  } completion:^(BOOL finished) {
    (void)finished;
    view.transform = CGAffineTransformIdentity;
  }];
}

+ (void)playActionFeedbackForKind:(NFBPostActionKind)kind activating:(BOOL)activating {
  if (kind == NFBPostActionKindLike && activating) {
    NFBPlaySound(@"pop.aac");
  }
  if (@available(iOS 10.0, *)) {
    if (kind == NFBPostActionKindDelete) {
      UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
      [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
      return;
    }
    UIImpactFeedbackStyle style = activating ? UIImpactFeedbackStyleLight : UIImpactFeedbackStyleSoft;
    if (kind == NFBPostActionKindLike || kind == NFBPostActionKindRepost) style = activating ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleLight;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    [feedback impactOccurred];
  }
}

@end
