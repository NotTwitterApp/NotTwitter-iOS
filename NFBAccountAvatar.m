#import "NFBAccountAvatar.h"
#import "NFBTheme.h"
#import <objc/runtime.h>

static char NFBAccountAvatarURLKey;
static char NFBAccountAvatarTaskKey;
static char NFBAccountAvatarRequestKey;

static NSCache<NSString *, UIImage *> *NFBAccountAvatarCache(void) {
  static NSCache *cache;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 64; });
  return cache;
}

void NFBLoadAccountAvatar(UIImageView *imageView, NSString *urlString) {
  if (!imageView) return;
  NSString *urlKey = [urlString isKindOfClass:NSString.class] ? urlString : @"";
  NSURLSessionDataTask *previousTask = objc_getAssociatedObject(imageView, &NFBAccountAvatarTaskKey);
  NSString *previousURL = objc_getAssociatedObject(imageView, &NFBAccountAvatarURLKey);
  UIImage *cached = urlKey.length ? [NFBAccountAvatarCache() objectForKey:urlKey] : nil;
  if ([previousURL isEqualToString:urlKey] && (cached || previousTask)) {
    if (cached) imageView.image = cached;
    return;
  }
  [previousTask cancel];
  NSObject *requestToken = [NSObject new];
  objc_setAssociatedObject(imageView, &NFBAccountAvatarRequestKey, requestToken, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(imageView, &NFBAccountAvatarTaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(imageView, &NFBAccountAvatarURLKey, urlKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
  imageView.image = cached ?: NFBDefaultAvatarImage() ?: NFBBrandIconImage();
  if (cached || urlKey.length == 0) return;
  NSURL *url = [NSURL URLWithString:urlKey];
  if (!url) return;
  __weak UIImageView *weakImageView = imageView;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    UIImage *image = !error && data.length ? [UIImage imageWithData:data] : nil;
    if (image) [NFBAccountAvatarCache() setObject:image forKey:urlKey];
    dispatch_async(dispatch_get_main_queue(), ^{
      UIImageView *target = weakImageView;
      if (!target || objc_getAssociatedObject(target, &NFBAccountAvatarRequestKey) != requestToken) return;
      if (image) target.image = image;
      objc_setAssociatedObject(target, &NFBAccountAvatarTaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
  }];
  objc_setAssociatedObject(imageView, &NFBAccountAvatarTaskKey, task, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [task resume];
}
