#import "NFBGIFService.h"
#import <math.h>

static NSString *NFBGIFString(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}
static NSDictionary *NFBGIFDictionary(id value) {
  return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static NSString *NFBGIFMediaURL(id value) {
  NSString *string = NFBGIFString(value);
  NSURL *url = [NSURL URLWithString:string];
  return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length ? string : @"";
}

@implementation NFBGIFService
+ (NSURL *)searchURLForQuery:(NSString *)query limit:(NSUInteger)limit cursor:(NSString *)cursor {
  // Same Bluesky KLIPY proxy and filters as the web compose picker.
  NSURLComponents *url = [NSURLComponents componentsWithString:@"https://gifs.bsky.app/klipy/v2/search"];
  NSMutableArray *parameters = [@[
    [NSURLQueryItem queryItemWithName:@"q" value:query ?: @""],
    [NSURLQueryItem queryItemWithName:@"limit" value:@(MIN(50, MAX(1, limit))).stringValue],
    [NSURLQueryItem queryItemWithName:@"media_filter" value:@"gif,tinygif,mp4,tinymp4"],
    [NSURLQueryItem queryItemWithName:@"contentfilter" value:@"high"]
  ] mutableCopy];
  if (cursor.length) [parameters addObject:[NSURLQueryItem queryItemWithName:@"pos" value:cursor]];
  url.queryItems = parameters;
  return url.URL;
}

+ (NSURLSession *)session {
  static NSURLSession *session;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.HTTPMaximumConnectionsPerHost = 4;
    configuration.timeoutIntervalForRequest = 20.0;
    session = [NSURLSession sessionWithConfiguration:configuration];
  });
  return session;
}

+ (NSURLSessionDataTask *)searchQuery:(NSString *)query limit:(NSUInteger)limit cursor:(NSString *)cursor completion:(void (^)(NSArray<NSDictionary *> *, NSString *, NSError *))completion {
  NSURLSessionDataTask *task = [[self session] dataTaskWithURL:[self searchURLForQuery:query limit:limit cursor:cursor] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    NSError *failure = error;
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    id json = data.length && !failure ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&failure] : nil;
    if (!failure && (status < 200 || status >= 300 || ![json isKindOfClass:NSDictionary.class] || ![json[@"results"] isKindOfClass:NSArray.class])) {
      failure = [NSError errorWithDomain:@"NFBGIFService" code:status userInfo:@{NSLocalizedDescriptionKey: @"GIFs couldn't load. Try again."}];
    }
    NSArray *items = failure ? @[] : [self itemsFromResponse:json];
    NSString *next = failure ? @"" : NFBGIFString(json[@"next"]);
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(items, next, failure); });
  }];
  [task resume];
  return task;
}

+ (NSArray<NSDictionary *> *)itemsFromResponse:(NSDictionary *)response {
  NSArray *results = [response[@"results"] isKindOfClass:NSArray.class] ? response[@"results"] : @[];
  NSMutableArray *items = [NSMutableArray array];
  for (id value in results) {
    NSDictionary *result = NFBGIFDictionary(value);
    NSDictionary *formats = NFBGIFDictionary(result[@"media_formats"]);
    NSDictionary *gif = NFBGIFDictionary(formats[@"gif"]);
    NSDictionary *preview = NFBGIFDictionary(formats[@"tinygif"]);
    if (!NFBGIFMediaURL(gif[@"url"]).length) gif = preview;
    if (!NFBGIFMediaURL(preview[@"url"]).length) preview = gif;
    if (!NFBGIFMediaURL(gif[@"url"]).length) continue;
    NSDictionary *video = NFBGIFDictionary(formats[@"mp4"]);
    if (!NFBGIFMediaURL(video[@"url"]).length) video = NFBGIFDictionary(formats[@"tinymp4"]);
    BOOL hasVideo = NFBGIFMediaURL(video[@"url"]).length > 0;
    NSDictionary *asset = hasVideo ? video : gif;
    NSArray *dims = [asset[@"dims"] isKindOfClass:NSArray.class] ? asset[@"dims"] : @[];
    double width = dims.count > 0 && [dims[0] respondsToSelector:@selector(doubleValue)] ? [dims[0] doubleValue] : 320;
    double height = dims.count > 1 && [dims[1] respondsToSelector:@selector(doubleValue)] ? [dims[1] doubleValue] : 240;
    NSString *title = [NFBGIFString(result[@"content_description"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) title = NFBGIFString(result[@"title"]);
    [items addObject:@{
      @"id": NFBGIFString(result[@"id"]), @"title": title.length ? title : @"GIF",
      @"previewURL": NFBGIFMediaURL(preview[@"url"]), @"gifURL": NFBGIFMediaURL(gif[@"url"]),
      // UIKit previews use tinygif; the existing native upload path uses MP4
      // when supplied so animations aren't limited by the image blob ceiling.
      @"assetURL": NFBGIFMediaURL(asset[@"url"]), @"mimeType": hasVideo ? @"video/mp4" : @"image/gif",
      @"width": @(isfinite(width) && width > 0 ? width : 320),
      @"height": @(isfinite(height) && height > 0 ? height : 240),
      @"duration": [asset[@"duration"] isKindOfClass:NSNumber.class] ? asset[@"duration"] : @0
    }];
  }
  return items;
}
@end
