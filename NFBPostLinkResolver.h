#import <Foundation/Foundation.h>

typedef void (^NFBPostLinkFetch)(NSString *method, NSDictionary *params, void (^completion)(NSDictionary *value, NSError *error));

// One quote card per post, matching the existing tweet component. Resolution is
// batched, preserves native quotes, and never follows links inside fetched cards.
@interface NFBPostLinkResolver : NSObject
+ (void)resolveValue:(id)value fetch:(NFBPostLinkFetch)fetch completion:(void (^)(id value))completion;
@end

// Presentation-only text and facets; the original record remains unchanged.
NSDictionary *NFBPostDisplayRecord(NSDictionary *post);

NSDictionary *NFBRecordByHidingLinkedURL(NSDictionary *record, NSString *target);
