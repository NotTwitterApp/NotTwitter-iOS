#import <Foundation/Foundation.h>
#import "NFBAtprotoClient.h"

@interface NFBProfileEditorService : NSObject
@property (nonatomic, readonly, copy) NSString *accountDID;
- (instancetype)initWithAccountDID:(NSString *)did;
// Snapshot contains the full record, its CID (NSNull for a missing record), and PDS.
- (void)loadWithCompletion:(NFBAtprotoDictionaryCompletion)completion;
- (void)savePatch:(NSDictionary *)patch images:(NSDictionary<NSString *, NSData *> *)images snapshot:(NSDictionary *)snapshot completion:(NFBAtprotoDictionaryCompletion)completion;
@end
