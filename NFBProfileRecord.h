#import <Foundation/Foundation.h>

// Only explicit edits enter the patch. NSNull removes a field; all other record
// fields (including labels, pinned posts, and other clients' extensions) survive.
NSString *NFBProfileString(id value);
NSUInteger NFBProfileCharacterCount(NSString *text);
NSString *NFBProfileNormalizedWebsite(NSString *text);
NSError *NFBProfilePatchError(NSDictionary *patch);
NSDictionary *NFBProfileRecordApplyingPatch(NSDictionary *record, NSDictionary *patch);
NSDictionary *NFBProfileViewApplyingRecord(NSDictionary *profile, NSDictionary *record, NSString *endpoint);
