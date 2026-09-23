#import <Foundation/Foundation.h>

// UI spans use UTF-16 ranges. Unresolved mentions have a local-only handle key.
NSArray<NSDictionary *> *NFBRichTextSpans(NSString *text, NSArray *facets);
NSRange NFBRichTextRange(NSString *text, NSDictionary *index);
NSArray<NSDictionary *> *NFBRichTextLocalFacets(NSString *text);
typedef void (^NFBResolveMention)(NSString *handle, void (^completion)(NSString *did, NSError *error));
void NFBRichTextResolve(NSString *text, NFBResolveMention resolve, void (^completion)(NSArray *facets, NSError *error));
