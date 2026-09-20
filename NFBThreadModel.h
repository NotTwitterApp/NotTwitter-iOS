#import <Foundation/Foundation.h>

// Session-scoped screen state; merged branches preserve already displayed posts.
@interface NFBThreadModel : NSObject
@property (nonatomic, copy) NSString *anchorURI;
- (void)mergeNodes:(NSArray<NSDictionary *> *)nodes;
- (NSArray<NSDictionary *> *)displayItems;
- (void)markRepliesExhaustedForURI:(NSString *)uri;
- (NSUInteger)postCount;
- (void)markAdditionalRepliesLoadedForURI:(NSString *)uri;
@end
