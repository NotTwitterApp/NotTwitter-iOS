"""Exercise shared detection and production text/link display without UIKit/network."""
from pathlib import Path
import os,re,subprocess
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
theme=(root/'NFBTheme.m').read_text()
a=theme.index('static NSURL *NFBInternalTextLinkURL');b=theme.index('static void NFBApplyTweetLink',a)
helpers=re.sub(r'(\w+)\[(@"[^"\n]+")\]',r'[\1 objectForKey:\2]',theme[a:b])
compose=(root/'NFBComposeViewController.m').read_text()
a=compose.index('- (NSString *)normalizedHashtagFromText:');b=compose.index('\n}',a)+2
normalizer=compose[a:b].replace('- (NSString *)normalizedHashtagFromText:(NSString *)text','static NSString *Normalize(NSString *text)')
normalizer=normalizer.replace('span[@"feature"][@"tag"]','[[span objectForKey:@"feature"] objectForKey:@"tag"]')
normalizer=re.sub(r'(\w+)\[(@"[^"\n]+")\]',r'[\1 objectForKey:\2]',normalizer)
source=r'''
#import <Foundation/Foundation.h>
#import "NFBRichText.h"
#import "NFBPostLinkResolver.h"
#include <assert.h>
'''+helpers+normalizer+r'''
static NSDictionary *Facet(NSString *text,NSString *token,NSDictionary *feature) {
 NSRange r=[text rangeOfString:token];NSUInteger start=[[text substringToIndex:r.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
 return @{@"index":@{@"byteStart":@(start),@"byteEnd":@(start+[token lengthOfBytesUsingEncoding:NSUTF8StringEncoding])},@"features":@[feature]};
}
static NSArray *Tokens(NSString *text) {
 NSMutableArray *result=[NSMutableArray array];
 for(NSDictionary *span in NFBRichTextSpans(text,nil))[result addObject:[text substringWithRange:[[span objectForKey:@"range"] rangeValue]]];
 return result;
}
int main(void){@autoreleasepool{
 assert([Normalize(@"＃日本語") isEqual:@"#日本語"]);
 assert([Normalize(@"foo-bar") isEqual:@"#foo-bar"]);
 assert([Normalize(@"123") isEqual:@""] && [Normalize(@"two words") isEqual:@""]);

 assert(([Tokens(@"😀 @alice.example. #日本語 example.com/path?q=one") isEqual:@[@"@alice.example",@"#日本語",@"example.com/path?q=one"]]));
 assert(([Tokens(@"foo@www.example.com v1.2 readme.md invalid.notarealtld foo#tag #123 @short") isEqual:@[@"readme.md"]]));
 assert(([Tokens(@"#example.com https://example.com/#topic www.example.com") isEqual:@[@"#example.com",@"https://example.com/#topic",@"www.example.com"]]));
 assert(([Tokens(@"(@alice.example) @bad..example @-bad.example") isEqual:@[@"@alice.example"]]));
 NSString *text=@"😀 read this @old.example #wrong example.com";
 NSDictionary *link=@{@"$type":@"app.bsky.richtext.facet#link",@"uri":@"https://example.org/actual"};
 NSDictionary *mention=@{@"$type":@"app.bsky.richtext.facet#mention",@"did":@"did:plc:stable"};
 NSDictionary *tag=@{@"$type":@"app.bsky.richtext.facet#tag",@"tag":@"actual"};
 NSArray *facets=@[Facet(text,@"read this",link),Facet(text,@"@old.example",mention),Facet(text,@"#wrong",tag)];
 NSDictionary *record=@{@"text":text,@"facets":facets};
 for(int shorten=0;shorten<2;shorten++) {
  NSDictionary *display=NFBDisplayTextAndLinksForRecord(record,shorten);NSArray *links=[display objectForKey:@"links"];
  assert([[display objectForKey:@"text"] isEqual:text] && links.count==4);
  assert([[[[links objectAtIndex:0] objectForKey:@"url"] absoluteString] isEqual:@"https://example.org/actual"]);
  assert([[[[links objectAtIndex:1] objectForKey:@"url"] absoluteString] containsString:@"did:plc:stable"]);
  assert([[[[links objectAtIndex:2] objectForKey:@"url"] absoluteString] containsString:@"actual"]);
  assert([[[display objectForKey:@"text"] substringWithRange:[[[links objectAtIndex:0] objectForKey:@"range"] rangeValue]] isEqual:@"read this"]);
 }
 // A facet's destination wins over the URL-like label; no fallback overlap.
 NSString *label=@"example.com";
 NSDictionary *misleading=@{@"text":label,@"facets":@[Facet(label,label,link)]};
 NSDictionary *display=NFBDisplayTextAndLinksForRecord(misleading,YES);
 assert([[display objectForKey:@"text"] isEqual:label] && [[display objectForKey:@"links"] count]==1);
 // Shortened URLs shift later links; DMs retain the exact string for bubble sizing.
 NSString *longText=@"https://example.com/a-very-long-path-that-is-longer-than-thirty-four-chars @alice.example";
 display=NFBDisplayTextAndLinksForRecord(@{@"text":longText},YES);
 NSDictionary *last=[[display objectForKey:@"links"] lastObject];
 assert([[[display objectForKey:@"text"] substringWithRange:[[last objectForKey:@"range"] rangeValue]] isEqual:@"@alice.example"]);
 assert([[NFBDisplayTextAndLinksForRecord(@{@"text":longText},NO) objectForKey:@"text"] isEqual:longText]);
 // Invalid types/ranges/scalar boundaries and overlapping facets don't corrupt text.
 NSArray *bad=@[[NSNull null],@{},@{@"index":@{@"byteStart":@1,@"byteEnd":@3},@"features":@[link]},@{@"index":@{@"byteStart":@(-1),@"byteEnd":@8},@"features":@[link]},@{@"index":@{@"byteStart":@0.5,@"byteEnd":@4},@"features":@[link]},@{@"index":@{@"byteStart":@0,@"byteEnd":@99999},@"features":@[link]}];
 assert(NFBRichTextSpans(@"😀 plain",bad).count==0);
 NSMutableArray *overlap=[facets mutableCopy];[overlap addObjectsFromArray:facets];
 assert(NFBRichTextSpans(text,overlap).count==4);
 // Hiding a shared-post custom label remaps remaining DID/tag/link facets.
 NSString *shared=@"https://bsky.app/profile/did:plc:other/post/abc";
 NSDictionary *postLink=@{@"$type":@"app.bsky.richtext.facet#link",@"uri":shared};
 record=@{@"text":text,@"facets":@[Facet(text,@"read this",postLink),Facet(text,@"@old.example",mention),Facet(text,@"#wrong",tag)]};
 NSDictionary *hidden=NFBRecordByHidingLinkedURL(record,@"at://did:plc:other/app.bsky.feed.post/abc");
 display=NFBDisplayTextAndLinksForRecord(hidden,NO);
 assert([[display objectForKey:@"text"] isEqual:@"😀  @old.example #wrong example.com"]);
 NSArray *links=[display objectForKey:@"links"];assert(links.count==3);
 assert([[[display objectForKey:@"text"] substringWithRange:[[[links firstObject] objectForKey:@"range"] rangeValue]] isEqual:@"@old.example"]);
 assert([[[[links firstObject] objectForKey:@"url"] absoluteString] containsString:@"did:plc:stable"]);
 assert([[record objectForKey:@"text"] isEqual:text]);
 puts("PASS: shared detection, bare domains/email boundaries, mentions/Unicode tags, authoritative facet destinations, custom labels, URL shortening, exact DM text, malformed/overlapping ranges, shared-post facet remapping");
}return 0;}
'''
p=runtime/'rich-text-runtime.m';p.write_text(source)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(p),str(root/'NFBRichText.m'),str(root/'NFBPostLinkResolver.m'),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(runtime/'rich-text-runtime')],check=True)
subprocess.run([str(runtime/'rich-text-runtime')],check=True)
