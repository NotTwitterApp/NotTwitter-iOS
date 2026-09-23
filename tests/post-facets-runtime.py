"""Run the production post publisher with a captured transport; never posts online.
Requires the same GNUstep prefix as the other *-runtime.py tests.
"""
from pathlib import Path
import os, re, subprocess
root = Path(__file__).resolve().parents[1]
runtime = Path(os.environ.get('NFB_OBJC_TEST_RUNTIME', '/tmp/nfb-objc-test-runtime'))
source = (root / 'NFBAtprotoClient.m').read_text()
def method(signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]
def legacy(code):
    code = re.sub(r'(\w+)\[(@"[^"\n]+")\] = ([^;\n]+);', r'[\1 setObject:\3 forKey:\2];', code)
    return re.sub(r'(\w+)\[(@"[^"\n]+")\]', r'[\1 objectForKey:\2]', code)
helpers = ''
methods = '\n'.join(method(s) for s in ['- (void)prepareFacetsForText:', '- (void)sendChatMessageToConversationID:', '- (void)createPostWithText:(NSString *)text\n', '+ (NSDictionary *)postRefForPost:(NSDictionary *)post {', '+ (NSDictionary *)replyRefForParentPost:'])
head = r'''
#import <Foundation/Foundation.h>
#import "NFBMediaAttachmentPolicy.h"
#import "NFBRichText.h"
#include <assert.h>
typedef void (^NFBAtprotoDictionaryCompletion)(NSDictionary *, NSError *);
static NSString *NFBClientStringValue(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }
static NSString *NFBComposeReplyGateEveryone=@"everyone";
static NSDictionary *sentBody;
static NSString *sentAccount;
static NSString *NFBAtprotoPublicAppViewURL=@"public";
static NSUInteger lookups=0, chatSends=0, generation=1;
static BOOL delayLookup=NO, failLookup=NO;
static void (^pendingLookup)(id,NSHTTPURLResponse *,NSError *);
static NSDictionary *sentMessage;

@interface NFBAtprotoSession:NSObject
@property(readonly) NSString *did;
@property(readonly) NSUInteger accountGeneration;
- (void)xrpcGET:(NSString *)m service:(NSString *)s params:(NSDictionary *)p authenticated:(BOOL)a completion:(void (^)(id,NSHTTPURLResponse *,NSError *))done;
- (void)xrpcPOSTViaChatProxy:(NSString *)m body:(NSDictionary *)b completion:(void (^)(id,NSHTTPURLResponse *,NSError *))done;

+ (instancetype)sharedSession;
- (void)xrpcPOST:(NSString *)m forAccountDID:(NSString *)d body:(NSDictionary *)b completion:(void (^)(id,NSHTTPURLResponse *,NSError *))done;
@end
@implementation NFBAtprotoSession
+ (instancetype)sharedSession {static id s;if(!s)s=[self new];return s;}
- (NSUInteger)accountGeneration {return generation;}
- (void)xrpcGET:(NSString *)m service:(NSString *)s params:(NSDictionary *)p authenticated:(BOOL)a completion:(void (^)(id,NSHTTPURLResponse *,NSError *))done {
 assert([m isEqual:@"com.atproto.identity.resolveHandle"] && !a);lookups++;
 if(delayLookup){pendingLookup=Block_copy(done);return;}
 done(failLookup?@{}:@{@"did":@"did:plc:alice"},nil,failLookup?[NSError errorWithDomain:@"offline" code:1 userInfo:nil]:nil);
}
- (void)xrpcPOSTViaChatProxy:(NSString *)m body:(NSDictionary *)b completion:(void (^)(id,NSHTTPURLResponse *,NSError *))done {
 chatSends++;sentMessage=[b objectForKey:@"message"];done(sentMessage,nil,nil);
}
- (NSString *)did {return @"did:plc:other-active-account";}
- (void)xrpcPOST:(NSString *)m forAccountDID:(NSString *)d body:(NSDictionary *)b completion:(void (^)(id,NSHTTPURLResponse *,NSError *))done {
 assert([m isEqual:@"com.atproto.repo.createRecord"]);sentBody=b;sentAccount=d;
 static NSUInteger sequence=0;sequence++;
 done(@{@"uri":[NSString stringWithFormat:@"at://did:plc:author/app.bsky.feed.post/%lu",(unsigned long)sequence],@"cid":[NSString stringWithFormat:@"cid-%lu",(unsigned long)sequence]},nil,nil);
}
@end
'''
interface = r'''
@interface NFBAtprotoClient:NSObject {NSString *_postingAccountDID;}
@property(copy) NSString *postingAccountDID;
+ (instancetype)sharedClient;
+ (instancetype)postingClientForAccountDID:(NSString *)did;
+ (NSDictionary *)postRefForPost:(NSDictionary *)p;
+ (NSDictionary *)replyRefForParentPost:(NSDictionary *)p;
+ (NSDictionary *)embedForUploadedMediaItems:(NSArray *)items quoteRef:(NSDictionary *)quote;
+ (NSString *)isoDateNow;
+ (NSError *)composeErrorWithMessage:(NSString *)m code:(NSInteger)c;
- (void)prepareFacetsForText:(NSString *)text completion:(void (^)(NSArray *,NSError *))done;
- (void)sendChatMessageToConversationID:(NSString *)c text:(NSString *)text completion:(NFBAtprotoDictionaryCompletion)done;
- (void)uploadMediaItems:(NSArray *)items completion:(void (^)(NSArray *,NSError *))done;
- (void)invalidateThreadPayloadCache;
- (void)createThreadgateForPostURI:(NSString *)u replyGate:(NSString *)g completion:(NFBAtprotoDictionaryCompletion)done;
- (void)createPostWithText:(NSString *)text replyToPost:(NSDictionary *)parent quotePost:(NSDictionary *)quote mediaItems:(NSArray *)items replyGate:(NSString *)gate completion:(NFBAtprotoDictionaryCompletion)done;
@end
@implementation NFBAtprotoClient
@synthesize postingAccountDID=_postingAccountDID;
+ (instancetype)sharedClient {static id s;if(!s)s=[self new];return s;}
+ (instancetype)postingClientForAccountDID:(NSString *)did {NFBAtprotoClient *c=[self new];c.postingAccountDID=did;return c;}
+ (NSDictionary *)embedForUploadedMediaItems:(NSArray *)items quoteRef:(NSDictionary *)quote {return quote ? @{@"record":quote} : (items.count ? @{@"images":items} : nil);}
+ (NSString *)isoDateNow {return @"2026-09-22T12:00:00Z";}
+ (NSError *)composeErrorWithMessage:(NSString *)m code:(NSInteger)c {return [NSError errorWithDomain:@"test" code:c userInfo:nil];}
- (void)uploadMediaItems:(NSArray *)items completion:(void (^)(NSArray *,NSError *))done {done(items,nil);}
- (void)invalidateThreadPayloadCache {}
- (void)createThreadgateForPostURI:(NSString *)u replyGate:(NSString *)g completion:(NFBAtprotoDictionaryCompletion)done {done(@{},nil);}
'''
tail = r'''
@end
static NSDictionary *Publish(NSString *text,NSDictionary *parent,NSDictionary *quote,NSArray *media) {
 __block NSDictionary *result=nil;
 [[NFBAtprotoClient postingClientForAccountDID:@"did:plc:author"] createPostWithText:text replyToPost:parent quotePost:quote mediaItems:media replyGate:nil completion:^(NSDictionary *v,NSError *e){assert(!e);result=v;}];
 assert(result && [sentAccount isEqual:@"did:plc:author"]);
 assert([[sentBody objectForKey:@"record"] isEqual:[result objectForKey:@"record"]]);
 NSDictionary *record=[result objectForKey:@"record"];
 assert([[record objectForKey:@"text"] isEqual:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
 if(quote || media.count)assert([record objectForKey:@"embed"]);
 return result;
}
static void Check(NSDictionary *post,NSArray *tokens,NSArray *values) {
 NSDictionary *record=[post objectForKey:@"record"];
 NSArray *facets=[record objectForKey:@"facets"];
 if(facets.count != tokens.count) {fprintf(stderr,"FAIL: outgoing record has %lu facets; expected %lu\n",(unsigned long)facets.count,(unsigned long)tokens.count);exit(1);}
 NSData *bytes=[[record objectForKey:@"text"] dataUsingEncoding:NSUTF8StringEncoding];NSUInteger previous=0;
 for(NSUInteger i=0;i<tokens.count;i++) {
  NSDictionary *facet=[facets objectAtIndex:i], *range=[facet objectForKey:@"index"], *feature=[[facet objectForKey:@"features"] firstObject];
  NSUInteger start=[[range objectForKey:@"byteStart"] unsignedIntegerValue],end=[[range objectForKey:@"byteEnd"] unsignedIntegerValue];
  assert(start>=previous && end>start && end<=bytes.length);previous=end;
  NSString *token=[[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(start,end-start)] encoding:NSUTF8StringEncoding];
  assert([token isEqual:[tokens objectAtIndex:i]]);
  NSString *key=[token hasPrefix:@"#"] || [token hasPrefix:@"＃"] ? @"tag" : ([token hasPrefix:@"@"] ? @"did" : @"uri");
  assert([[feature objectForKey:key] isEqual:[values objectAtIndex:i]]);
  assert([[feature objectForKey:@"$type"] isEqual:[key isEqual:@"tag"]?@"app.bsky.richtext.facet#tag":([key isEqual:@"did"]?@"app.bsky.richtext.facet#mention":@"app.bsky.richtext.facet#link")]);
 }
}
int main(void) {@autoreleasepool {
 Check(Publish(@"Hi @alice.example",nil,nil,nil),@[@"@alice.example"],@[@"did:plc:alice"]);
 NSString *release=@"https://github.com/NotTwitterApp/NotTwitter-iOS/releases/tag/1.2";
 Check(Publish(release,nil,nil,nil),@[release],@[release]);
 NSDictionary *root=Publish(@"Not Twitter for iOS 1.2 is out! #NotTwitter #iOSDev #atproto #atprotodev",nil,nil,nil);
 Check(root,@[@"#NotTwitter",@"#iOSDev",@"#atproto",@"#atprotodev"],@[@"NotTwitter",@"iOSDev",@"atproto",@"atprotodev"]);
 NSDictionary *reply=Publish(release,root,nil,nil),*next=Publish(@"😀 café #日本語 https://example.org/path",reply,nil,nil);
 Check(reply,@[release],@[release]);Check(next,@[@"#日本語",@"https://example.org/path"],@[@"日本語",@"https://example.org/path"]);
 NSDictionary *replyRefs=[[next objectForKey:@"record"] objectForKey:@"reply"];
 assert([[replyRefs objectForKey:@"root"] isEqual:[NFBAtprotoClient postRefForPost:root]]);
 assert([[replyRefs objectForKey:@"parent"] isEqual:[NFBAtprotoClient postRefForPost:reply]]);
 Check(Publish(@" \n👩🏽‍💻 é #café https://example.org/#section. \n",nil,root,nil),@[@"#café",@"https://example.org/#section"],@[@"café",@"https://example.org/#section"]);
 Check(Publish(@"(https://en.wikipedia.org/wiki/Bluesky_(social_network)). #hello!",nil,nil,nil),@[@"https://en.wikipedia.org/wiki/Bluesky_(social_network)",@"#hello"],@[@"https://en.wikipedia.org/wiki/Bluesky_(social_network)",@"hello"]);
 Check(Publish(@"www.example.org, #hello #hello ＃世界",nil,nil,@[@{@"type":@"image"}]),@[@"www.example.org",@"#hello",@"#hello",@"＃世界"],@[@"https://www.example.org",@"hello",@"hello",@"世界"]);
 Check(Publish(@"plain text, email@example.org, foo#bar, #123, #!",nil,nil,nil),@[],@[]);
 NSString *longTag=[@"#" stringByPaddingToLength:66 withString:@"x" startingAtIndex:0];
 Check(Publish(longTag,nil,nil,nil),@[],@[]);
 NSString *maxTag=[longTag substringToIndex:65];
 Check(Publish(maxTag,nil,nil,nil),@[maxTag],@[[maxTag substringFromIndex:1]]);
 // Local link/tag facets do not require a network lookup.
 NSString *dm=@"😀 (https://example.org/path_(one)).";
 Check(@{@"record":@{@"text":dm,@"facets":NFBRichTextLocalFacets(dm)}},@[@"https://example.org/path_(one)"],@[@"https://example.org/path_(one)"]);
 Check(Publish(@"",nil,root,nil),@[],@[]);
 lookups=0;
 Check(Publish(@"😀 @Alice.Example @alice.example #hello example.com",nil,nil,nil),@[@"@Alice.Example",@"@alice.example",@"#hello",@"example.com"],@[@"did:plc:alice",@"did:plc:alice",@"hello",@"https://example.com"]);assert(lookups==1);
 NFBAtprotoClient *client=[NFBAtprotoClient sharedClient];
 [client sendChatMessageToConversationID:@"conversation" text:@"😀 @alice.example #hello example.com" completion:^(NSDictionary *v,NSError *e){assert(!e);}];
 Check(@{@"record":sentMessage},@[@"@alice.example",@"#hello",@"example.com"],@[@"did:plc:alice",@"hello",@"https://example.com"]);
 NSUInteger sent=chatSends;delayLookup=YES;__block NSError *failure=nil;
 [client sendChatMessageToConversationID:@"conversation" text:@"@alice.example" completion:^(NSDictionary *v,NSError *e){failure=e;}];
 assert(chatSends==sent);generation++;pendingLookup(@{@"did":@"did:plc:alice"},nil,nil);assert(chatSends==sent && failure.code==NSURLErrorCancelled);
 delayLookup=NO;failLookup=YES;sentBody=nil;failure=nil;
 [[NFBAtprotoClient postingClientForAccountDID:@"did:plc:author"] createPostWithText:@"@alice.example" replyToPost:nil quotePost:nil mediaItems:nil replyGate:@"mentioned" completion:^(NSDictionary *v,NSError *e){failure=e;}];
 assert(failure && !sentBody);
 puts("PASS: production post payloads, release URL/hashtags, replies/thread roots, quotes/media, UTF-8 emoji/combining marks, punctuation, URL fragments, sorted non-overlapping facets, plain/invalid tags, deduplicated DID resolution, DM send/account-switch cancellation, lookup failure prevents publishing");
 }return 0;}
'''
p = runtime / 'post-facets-runtime.m'
p.write_text(legacy(head+helpers+interface+methods+tail))
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(p),str(root/'NFBRichText.m'),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(runtime/'post-facets-runtime')],check=True)
subprocess.run([str(runtime/'post-facets-runtime')],check=True)
