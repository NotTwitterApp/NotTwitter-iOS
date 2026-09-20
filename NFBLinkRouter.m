#import "NFBLinkRouter.h"

#import "NFBTheme.h"
#import "NFBTimelineViewController.h"
#import "NFBFeedRoute.h"

#import <SafariServices/SafariServices.h>

static NSString *NFBQueryValueForURL(NSURL *url, NSString *name) {
  NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
  for (NSURLQueryItem *item in components.queryItems ?: @[]) {
    if ([item.name isEqualToString:name]) return item.value ?: @"";
  }
  return @"";
}

static UIViewController *NFBVisiblePresenter(UIViewController *viewController) {
  UIViewController *presenter = viewController;
  while (presenter.presentedViewController) presenter = presenter.presentedViewController;
  return presenter ?: viewController;
}

static NSURL *NFBAbsoluteURLForTwitterClonePath(NSString *path) {
  if (![path hasPrefix:@"/"]) return nil;
  NSString *absolute = [@"https://nottwitterapp.github.io" stringByAppendingString:path];
  return [NSURL URLWithString:absolute];
}

void NFBOpenTweetTextURL(NSURL *url, UIViewController *presentingViewController) {
  if (!url || !presentingViewController) return;
  NSDictionary *feedRoute = NFBFeedRouteFromString(url.absoluteString);
  if (feedRoute) {
    NFBTimelineViewController *feed = [[NFBTimelineViewController alloc] initWithFeedActor:feedRoute[@"actor"] recordKey:feedRoute[@"rkey"] title:nil];
    [presentingViewController.navigationController pushViewController:feed animated:YES];
    return;
  }
  if ([url.scheme isEqualToString:@"nottwitter"]) {
    if ([url.host isEqualToString:@"profile"]) {
      NSString *actor = NFBQueryValueForURL(url, @"actor");
      if (actor.length == 0) return;
      NFBTimelineViewController *profile = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
      [presentingViewController.navigationController pushViewController:profile animated:YES];
      return;
    }
    if ([url.host isEqualToString:@"search"]) {
      NSString *query = NFBQueryValueForURL(url, @"query");
      if (query.length == 0) return;
      NFBTimelineViewController *search = [[NFBTimelineViewController alloc] initWithSearchQuery:query];
      [presentingViewController.navigationController pushViewController:search animated:YES];
      return;
    }
  }

  NSURL *externalURL = url;
  NSString *absoluteString = externalURL.absoluteString ?: @"";
  if (externalURL.scheme.length == 0 && [absoluteString hasPrefix:@"/"]) {
    externalURL = NFBAbsoluteURLForTwitterClonePath(absoluteString);
  }
  if (externalURL.scheme.length == 0 && [externalURL.absoluteString.lowercaseString hasPrefix:@"www."]) {
    externalURL = [NSURL URLWithString:[@"https://" stringByAppendingString:externalURL.absoluteString]];
  }
  if (!externalURL.scheme.length) return;
  SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:externalURL];
  safari.preferredControlTintColor = NFBColorAccent();
  [NFBVisiblePresenter(presentingViewController) presentViewController:safari animated:YES completion:nil];
}
