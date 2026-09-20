#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface NFBGIFService : NSObject
+ (NSURL *)searchURLForQuery:(NSString *)query limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
+ (NSURLSessionDataTask *)searchQuery:(NSString *)query limit:(NSUInteger)limit cursor:(nullable NSString *)cursor completion:(void (^)(NSArray<NSDictionary *> *items, NSString *nextCursor, NSError *_Nullable error))completion;
+ (NSArray<NSDictionary *> *)itemsFromResponse:(NSDictionary *)response;
@end
NS_ASSUME_NONNULL_END
