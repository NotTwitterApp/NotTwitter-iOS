"""Execute the production link parser/resolver with a controlled transport.
No network: routes, batched hydration, display facets and failures are real code.
"""
from pathlib import Path
import os, re, subprocess
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
chat=(root/'NFBMessagesViewController.m').read_text()
def function(prefix):
    a=chat.index(prefix);return chat[a:chat.index('\n}',a)+2]
chat_helpers='\n'.join(function(p) for p in [
 'static NSString *NFBStringValue(', 'static NSDictionary *NFBChatRawMessage(',
 'static NSString *NFBChatTrimTrailingURLPunctuation(', 'static NSString *NFBChatPostURIFromURLString(',
 'static NSArray<NSString *> *NFBChatURLTokensInText(', 'static NSString *NFBChatSharedPostURIFromMessage(',
 'static NSDictionary *NFBChatSharedPostForMessage(NSDictionary *message) {', 'static NSDictionary *NFBChatMessageDisplayRecord(NSDictionary *message) {', 'static NSString *NFBChatMessageDisplayText(NSDictionary *message) {',
])
chat_helpers=chat_helpers.replace('NFBPostLink(candidate)[@"uri"]','[NFBPostLink(candidate) objectForKey:@"uri"]')
chat_helpers=chat_helpers.replace('NFBChatMessageDisplayRecord(message)[@"text"]','[NFBChatMessageDisplayRecord(message) objectForKey:@"text"]')
chat_helpers=re.sub(r'(\w+)\[(@"[^"\n]+"|NFBChatSharedPostKey|NFBChatSharedPostURIKey)\]',r'[\1 objectForKey:\2]',chat_helpers)
chat_helpers='static NSString *NFBChatSharedPostKey=@"__sharedPost", *NFBChatSharedPostURIKey=@"__sharedPostURI";\nstatic NSString *NFBChatMessageText(NSDictionary *message);\n'+chat_helpers+'\nstatic NSString *NFBChatMessageText(NSDictionary *message){return NFBStringValue([NFBChatRawMessage(message) objectForKey:@"text"]);}'
source=r'''
#import <Foundation/Foundation.h>
#import "NFBPostLink.h"
#import "NFBPostLinkResolver.h"
#include <assert.h>
'''+chat_helpers+r'''
static NSString *const targetURI=@"at://did:plc:alice/app.bsky.feed.post/abc";
static NSDictionary *Post(NSString *uri,NSString *text) {return @{@"uri":uri,@"cid":@"cid",@"author":@{@"did":@"did:plc:alice",@"handle":@"alice.bsky.social",@"displayName":@"Alice"},@"record":@{@"text":text}};}
static NSDictionary *Facet(NSString *text,NSString *token,NSDictionary *feature) {
 NSRange r=[text rangeOfString:token];assert(r.location!=NSNotFound);
 NSUInteger start=[[text substringToIndex:r.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
 return @{@"index":@{@"byteStart":@(start),@"byteEnd":@(start+[token lengthOfBytesUsingEncoding:NSUTF8StringEncoding])},@"features":@[feature]};
}
int main(void) {@autoreleasepool {
 NSString *encoded=[[targetURI dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];encoded=[encoded stringByReplacingOccurrencesOfString:@"=" withString:@""];
 NSArray *urls=@[@"https://bsky.app/profile/alice.bsky.social/post/abc", @"https://bsky.app/profile/did:plc:alice/post/abc?ref=share", [@"https://nottwitterapp.github.io/alice/status/" stringByAppendingString:encoded], [@"https://erickrouss.github.io/not-twitter/tweet/" stringByAppendingString:encoded],targetURI];
 for(NSString *url in urls) {NSDictionary *link=NFBPostLink(url);assert(link && [[link objectForKey:@"rkey"] isEqual:@"abc"]);}
 assert(NFBPostLink(@"HTTPS://WWW.BSKY.APP/profile/ALICE.BSKY.SOCIAL/post/abc/"));
 for(NSString *url in @[@"https://bsky.app.evil.test/profile/a/post/b",@"https://evil.bsky.app/profile/a/post/b",@"https://bsky.app/profile/a",@"https://bsky.app/profile/a/post/b/more",@"https://nottwitterapp.github.io/a/status/garbage",@"https://nottwitterapp.github.io/a/status/Ym9ndXM",@"https://bsky.app/profile/a/post/..",@"https://bsky.app/profile/a%2Fb/post/c",@"https://u:p@bsky.app/profile/a/post/b",@"at://did:plc:a/app.bsky.feed.like/b"]) assert(!NFBPostLink(url));
 __block NSUInteger profiles=0,postCalls=0;__block id result=nil;
 NSDictionary *target=Post(targetURI,@"A real tweet with a link https://bsky.app/profile/did:plc:alice/post/recursive");
 NFBPostLinkFetch fetch=^(NSString *method,NSDictionary *params,void (^done)(NSDictionary *,NSError *)) {
  if([method isEqual:@"app.bsky.actor.getProfiles"]){profiles++;assert([[params objectForKey:@"actors"] count]==1);done(@{@"profiles":@[@{@"handle":@"alice.bsky.social",@"did":@"did:plc:alice"}]},nil);}
  else {postCalls++;assert([method isEqual:@"app.bsky.feed.getPosts"]);assert([[params objectForKey:@"uris"] count]==1);done(@{@"posts":@[target]},nil);}
 };
 NSMutableArray *feed=[NSMutableArray new];int index=0;
 for(NSString *url in urls) [feed addObject:@{@"post":Post([NSString stringWithFormat:@"at://did:plc:me/app.bsky.feed.post/%d",index++],url)}];
 NSDictionary *input=@{@"feed":feed,@"cursor":@"keep-page"};
 [NFBPostLinkResolver resolveValue:input fetch:fetch completion:^(id v){result=v;}];
 assert(profiles==1 && postCalls==1 && [[result objectForKey:@"cursor"] isEqual:@"keep-page"]);
 for(NSDictionary *item in [result objectForKey:@"feed"]){NSDictionary *p=[item objectForKey:@"post"];assert([[p objectForKey:@"__nfbLinkedPost"] isEqual:target]);assert([[NFBPostDisplayRecord(p) objectForKey:@"text"] length]==0);assert([[p objectForKey:@"record"] objectForKey:@"text"]);}
 assert(![[[feed objectAtIndex:0] objectForKey:@"post"] objectForKey:@"__nfbLinkedPost"]);
 // Native quotes and unrelated links are retained. A resolved self-link is not a quote.
 profiles=postCalls=0;NSMutableDictionary *native=[Post(@"parent",[urls firstObject]) mutableCopy];[native setObject:@{@"record":@{@"notFound":@(YES)}} forKey:@"embed"];
 [NFBPostLinkResolver resolveValue:@[native,Post(@"other",@"https://example.com/blog")] fetch:fetch completion:^(id v){result=v;}];assert(profiles==0 && postCalls==0 && [[result objectAtIndex:0] isEqual:native]);
 [NFBPostLinkResolver resolveValue:Post(targetURI,[urls firstObject]) fetch:fetch completion:^(id v){result=v;}];assert(![result objectForKey:@"__nfbLinkedPost"]);
 // Preserve Unicode and remap mention/link facets after replacing a shortened facet link.
 NSString *text=@"😀 https://bsky.app/profile/alice.bsky.social/post/abc @bob https://example.org";
 NSMutableDictionary *record=[@{@"text":text,@"facets":@[Facet(text,[urls firstObject],@{@"$type":@"app.bsky.richtext.facet#link",@"uri":[urls firstObject]}),Facet(text,@"@bob",@{@"$type":@"app.bsky.richtext.facet#mention",@"did":@"did:plc:bob"}),Facet(text,@"https://example.org",@{@"$type":@"app.bsky.richtext.facet#link",@"uri":@"https://example.org"})]} mutableCopy];
 NSMutableDictionary *withFacets=[Post(@"parent",text) mutableCopy];[withFacets setObject:record forKey:@"record"];
 [NFBPostLinkResolver resolveValue:withFacets fetch:fetch completion:^(id v){result=v;}];NSDictionary *display=NFBPostDisplayRecord(result);assert([[display objectForKey:@"text"] isEqual:@"😀  @bob https://example.org"]);assert([[display objectForKey:@"facets"] count]==2);
 NSData *displayBytes=[[display objectForKey:@"text"] dataUsingEncoding:NSUTF8StringEncoding];NSDictionary *mention=[[[display objectForKey:@"facets"] firstObject] objectForKey:@"index"];NSUInteger start=[[mention objectForKey:@"byteStart"] unsignedIntegerValue],end=[[mention objectForKey:@"byteEnd"] unsignedIntegerValue];assert([[[NSString alloc] initWithData:[displayBytes subdataWithRange:NSMakeRange(start,end-start)] encoding:NSUTF8StringEncoding] isEqual:@"@bob"]);assert([[result objectForKey:@"record"] isEqual:record]);
 // A second, different post link must not disappear when the first becomes a card.
 NSString *both=[[urls firstObject] stringByAppendingString:@" https://bsky.app/profile/did:plc:bob/post/second"];
 [NFBPostLinkResolver resolveValue:Post(@"two",both) fetch:fetch completion:^(id v){result=v;}];assert([[NFBPostDisplayRecord(result) objectForKey:@"text"] isEqual:@"https://bsky.app/profile/did:plc:bob/post/second"]);
 // Production DM discovery includes Not Twitter routes, wrapped records and facets.
 NSString *notTwitter=[urls objectAtIndex:2];
 NSDictionary *dm=@{@"text":[notTwitter stringByAppendingString:@" https://bsky.app/profile/did:plc:bob/post/second"],@"__sharedPost":target};
 assert([NFBChatSharedPostURIFromMessage(dm) isEqual:targetURI]);
 assert([NFBChatMessageDisplayText(dm) isEqual:@"https://bsky.app/profile/did:plc:bob/post/second"]);
 assert([NFBChatSharedPostURIFromMessage(@{@"message":dm}) isEqual:targetURI]);
 assert([NFBChatMessageDisplayText(@{@"text":notTwitter}) isEqual:notTwitter]);
 assert([NFBChatSharedPostURIFromMessage(@{@"text":@"a shared tweet",@"facets":@[@{@"features":@[@{@"uri":notTwitter}]}]}) isEqual:targetURI]);
 // API failure or unavailable/blocked target leaves the source link untouched.
 for(int failure=0;failure<3;failure++){
  NSDictionary *original=Post(@"parent",[urls objectAtIndex:1]);
  [NFBPostLinkResolver resolveValue:original fetch:^(NSString *m,NSDictionary *p,void (^done)(NSDictionary *,NSError *)) {
   NSMutableDictionary *blocked=[target mutableCopy];[blocked setObject:@{@"did":@"did:plc:alice",@"viewer":@{@"blockedBy":@(YES)}} forKey:@"author"];
   done(@{@"posts":failure==2?@[blocked]:@[]},failure==0?[NSError errorWithDomain:@"offline" code:1 userInfo:nil]:nil);
  } completion:^(id v){result=v;}];assert(![result objectForKey:@"__nfbLinkedPost"] && [[result objectForKey:@"record"] isEqual:[original objectForKey:@"record"]]);
 }
 // Batches never exceed endpoint limits, including more than one page of cards.
 NSMutableArray *many=[NSMutableArray new];for(int i=0;i<61;i++) [many addObject:Post([NSString stringWithFormat:@"source%d",i],[NSString stringWithFormat:@"https://bsky.app/profile/did:plc:alice/post/key%d",i])];
 postCalls=0;
 [NFBPostLinkResolver resolveValue:many fetch:^(NSString *m,NSDictionary *params,void (^done)(NSDictionary *,NSError *)){
  assert([m isEqual:@"app.bsky.feed.getPosts"]);NSArray *uris=[params objectForKey:@"uris"];assert(uris.count<=25);postCalls++;
  NSMutableArray *posts=[NSMutableArray new];for(NSString *uri in uris)[posts addObject:Post(uri,@"card")];done(@{@"posts":posts},nil);
 } completion:^(id v){result=v;}];assert(postCalls==3 && [result count]==61);for(NSDictionary *p in result)assert([p objectForKey:@"__nfbLinkedPost"]);
 puts("PASS: Bluesky/Not Twitter/AT routes, malformed and spoofed URLs, batched unique hydration, native quotes, self/cyclic links, Unicode facets, multiple links, immutable records, unavailable/blocked/error fallbacks");
 }return 0;}
'''
output=runtime/'post-link-resolver-runtime.m';output.write_text(source)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(output),str(root/'NFBPostLinkResolver.m'),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(runtime/'post-link-resolver-runtime')],check=True)
subprocess.run([str(runtime/'post-link-resolver-runtime')],check=True)
