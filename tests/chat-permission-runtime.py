"""Execute production DM permission/opening methods with a controlled chat proxy.

Requires the GNUstep prefix used by account-switch-runtime.py. No requests or
messages are sent. This checks control flow and Foundation data, not UIKit.
"""
from pathlib import Path
import os
import re
import subprocess

root = Path(__file__).resolve().parents[1]
runtime = Path(os.environ.get('NFB_OBJC_TEST_RUNTIME', '/tmp/nfb-objc-test-runtime'))
source = (root / 'NFBAtprotoClient.m').read_text()
def method(prefix):
    start = source.index(prefix, source.index('@implementation'))
    return source[start:source.index('\n}', start) + 2]
body = '\n'.join(method(prefix) for prefix in [
    '- (void)messagePermissionForProfile:',
    '- (void)fetchChatConversationAvailabilityForMembers:',
    '- (void)fetchChatConversationForMembers:',
])
# Legacy GNU Objective-C needs message syntax for dictionary subscripting.
body = re.sub(r'(\w+)\[(@"[^"]+")\]', r'[\1 objectForKey:\2]', body)
policy = (root / 'NFBProfilePresentation.h').read_text()
policy = re.sub(r'(\w+)\[(@"[^"]+")\]', r'[\1 objectForKey:\2]', policy)
head = r'''
#import <Foundation/Foundation.h>
#import "NFBChatPermission.h"
#import "NFBRepostContext.h"
typedef void (^NFBAtprotoDictionaryCompletion)(NSDictionary *, NSError *);
typedef void (^Response)(id, NSHTTPURLResponse *, NSError *);
static NSString *NFBClientStringValue(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }
static NSArray *NFBClientUniqueNonEmptyStrings(NSArray *v) {return v;}
static NSMutableArray *calls;
static Response pending;
@interface NFBAtprotoSession:NSObject {NSString *_did; NSUInteger _accountGeneration;}
@property(copy) NSString *did;
@property NSUInteger accountGeneration;
+ (instancetype)sharedSession;
- (void)xrpcGETViaChatProxy:(NSString *)method params:(NSDictionary *)params completion:(Response)completion;
@end
@implementation NFBAtprotoSession
@synthesize did=_did, accountGeneration=_accountGeneration;
+ (instancetype)sharedSession {static id s; if(!s)s=[self new];return s;}
- (void)xrpcGETViaChatProxy:(NSString *)method params:(NSDictionary *)params completion:(Response)completion {
 [calls addObject:@{@"method":method,@"params":params}];
 NSCAssert(pending==nil,@"overlapping request");pending=Block_copy(completion);
}
@end
static void Finish(id value,NSError *error) {Response p=pending;pending=nil;p(value,nil,error);Block_release(p);}
@interface NFBAtprotoClient:NSObject
- (void)messagePermissionForProfile:(NSDictionary *)profile completion:(void (^)(BOOL,BOOL))completion;
- (void)fetchChatConversationAvailabilityForMembers:(NSArray *)members completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)fetchChatConversationForMembers:(NSArray *)members completion:(NFBAtprotoDictionaryCompletion)completion;
@end
'''
tail = r'''
@end
#define CHECK(x) do {if(!(x)){fprintf(stderr,"FAIL at line %d\n",__LINE__);return 1;}}while(0)
int main(void) {@autoreleasepool {
 calls=[NSMutableArray new];NFBAtprotoSession *session=[NFBAtprotoSession sharedSession];session.did=@"did:plc:me";session.accountGeneration=1;
 NFBAtprotoClient *client=[NFBAtprotoClient new];__block BOOL allowed=NO;__block NSDictionary *result=nil;__block NSError *failure=nil;
 NFBAtprotoDictionaryCompletion completion=^(NSDictionary *v,NSError *e){result=v;failure=e;};
 for(NSString *setting in @[@"all",@"following",@"none",@"unknown"]) {
   NSDictionary *profile=@{@"did":@"did:plc:other",@"associated":@{@"chat":@{@"allowIncoming":setting}},@"viewer":@{@"following":@"viewer-follows-recipient"}};
   allowed=YES;[calls removeAllObjects];
   [client messagePermissionForProfile:profile completion:^(BOOL a,BOOL follows){allowed=a;}];
   CHECK(calls.count==1 && [[[calls lastObject] objectForKey:@"method"] isEqual:@"chat.bsky.convo.getConvoAvailability"]);
   CHECK([[[[calls lastObject] objectForKey:@"params"] objectForKey:@"members"] isEqual:@[@"did:plc:other"]]);
   Finish(@{@"canChat":@(NO)},nil);CHECK(!allowed);
   [client messagePermissionForProfile:profile completion:^(BOOL a,BOOL follows){allowed=a;}];
   Finish(@{@"canChat":@(YES),@"convo":@{@"id":@"existing"}},nil);CHECK(allowed);
 }
 for(NSString *key in @[@"blocking",@"blockedBy",@"blockingByList",@"blockedByList"]) {
   [calls removeAllObjects];allowed=YES;
   [client messagePermissionForProfile:@{@"did":@"did:plc:other",@"viewer":@{key:@(YES)}} completion:^(BOOL a,BOOL f){allowed=a;}];
   CHECK(!allowed && calls.count==0);
 }
 [client messagePermissionForProfile:@{@"did":@"did:plc:me"} completion:^(BOOL a,BOOL f){allowed=a;}];CHECK(!allowed && pending==nil);
 [client messagePermissionForProfile:@{@"did":@"did:plc:other"} completion:^(BOOL a,BOOL f){allowed=a;}];
 Finish(nil,[NSError errorWithDomain:NSURLErrorDomain code:-1009 userInfo:nil]);CHECK(!allowed);
 [client fetchChatConversationAvailabilityForMembers:@[@"did:plc:other"] completion:completion];
 Finish(@{@"canChat":@"true"},nil);CHECK(failure && !result);
 [calls removeAllObjects];
 [client fetchChatConversationForMembers:@[@"did:plc:other"] completion:completion];
 Finish(@{@"canChat":@(NO),@"convo":@{@"id":@"existing"}},nil);CHECK(!result && NFBChatErrorIsPermissionDenied(failure) && calls.count==1);
 [calls removeAllObjects];
 [client fetchChatConversationForMembers:@[@"did:plc:other"] completion:completion];
 Finish(@{@"canChat":@(YES),@"convo":@{@"id":@"existing"}},nil);CHECK([[result objectForKey:@"id"] isEqual:@"existing"] && !failure && calls.count==1);
 [calls removeAllObjects];
 [client fetchChatConversationForMembers:@[@"did:plc:other"] completion:completion];
 Finish(@{@"canChat":@(YES)},nil);CHECK(calls.count==2 && [[[calls lastObject] objectForKey:@"method"] isEqual:@"chat.bsky.convo.getConvoForMembers"]);
 NSError *closed=[NSError errorWithDomain:@"NFBAtprotoSession" code:400 userInfo:@{NFBChatErrorNameKey:@"MessagesDisabled",NSLocalizedDescriptionKey:@"any server wording"}];
 Finish(nil,closed);CHECK(!result && NFBChatErrorIsPermissionDenied(failure));
 [calls removeAllObjects];
 [client fetchChatConversationForMembers:@[@"did:plc:other"] completion:completion];session.accountGeneration++;
 Finish(@{@"canChat":@(YES)},nil);CHECK(failure.code==NSURLErrorCancelled && calls.count==1 && !pending);
 for(NSString *name in @[@"MessagesDisabled",@"NotFollowedBySender",@"BlockedActor",@"BlockedSubject",@"AccountSuspended",@"RecipientNotFound",@"ConvoLocked"]) {
   CHECK(NFBChatErrorIsPermissionDenied([NSError errorWithDomain:@"server" code:400 userInfo:@{NFBChatErrorNameKey:name}]));
 }
 CHECK(!NFBChatErrorIsPermissionDenied([NSError errorWithDomain:NSURLErrorDomain code:-1009 userInfo:nil]));
 CHECK(!NFBChatErrorIsPermissionDenied([NSError errorWithDomain:@"server" code:403 userInfo:@{NFBChatErrorNameKey:@"Forbidden"}]));
 NSDictionary *repost=@{@"reason":@{@"$type":@"app.bsky.feed.defs#reasonRepost",@"by":@{@"did":@"did:plc:other",@"displayName":@"Alice",@"handle":@"alice.example"}}};
 CHECK([NFBRepostContextText(repost,@"did:plc:me") isEqual:@"Alice Retweeted"]);
 CHECK([NFBRepostContextText(repost,@"did:plc:other") isEqual:@"You Retweeted"]);
 CHECK(NFBFeedReposter(@{@"reason":@"repost"})==nil);
 CHECK(NFBFeedReposter(@{@"reason":@{@"$type":@"app.bsky.feed.defs#reasonPin"}})==nil);
 CHECK([NFBRepostContextText(@{},session.did) isEqual:@""]);
 CHECK([NFBRepostContextText(@{@"reason":@{@"$type":@"app.bsky.feed.defs#reasonRepost",@"by":@{@"displayName":[NSNull null],@"handle":@"alice.example"}}},session.did) isEqual:@"alice.example Retweeted"]);
 puts("PASS: authoritative permissions, closed/blocked/self/unknown states, existing chat, no creation on denial, permission races, account switch, protocol errors, repost labels");
}return 0;}
'''
output = runtime / 'chat-permission.m'
output.write_text(head + policy + '\n@implementation NFBAtprotoClient\n' + body + tail)
subprocess.run(['clang', '-fblocks', '-fobjc-exceptions', '-fconstant-string-class=NSConstantString', '-I'+str(root), '-I'+str(runtime/'usr/include'), str(output), '-L'+str(runtime/'usr/lib'), '-Wl,-rpath,'+str(runtime/'usr/lib'), '-L/usr/lib/swift/lib/swift/linux', '-Wl,-rpath,/usr/lib/swift/lib/swift/linux', '-lBlocksRuntime', '-lgnustep-base', '-lobjc', '-o', str(runtime/'chat-permission')], check=True)
subprocess.run([str(runtime/'chat-permission')], check=True)
