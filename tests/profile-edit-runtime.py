"""Run the production profile record logic and save transaction with a fake PDS.

The fake session captures real XRPC method/body/account arguments, holds replies,
and injects upload, CAS, malformed-response and identity-transition failures.
No requests are sent to a real account. UIKit rendering is not covered.
"""
from pathlib import Path
import os, re, subprocess
root = Path(__file__).resolve().parents[1]
r = Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
record = (root/'NFBProfileRecord.m').read_text().replace('#import "NFBProfileRecord.h"','')
service = (root/'NFBProfileEditorService.m').read_text()
service = '\n'.join(x for x in service.splitlines() if not x.startswith('#import'))
a = service.index('@interface'); b = service.index('@implementation',a)
service = service[:a]+service[b:]
service = service.replace('@implementation NFBProfileEditorService','@implementation NFBProfileEditorService\n@synthesize accountDID=_accountDID, accountGeneration=_accountGeneration, saving=_saving;')
service = service.replace('patch[key] = blob;', '[patch setObject:blob forKey:key];').replace('keys[index]','[keys objectAtIndex:index]')
service = re.sub(r'\b(snapshot|result|value|images)\[(@"[^"]+"|key)\]',r'[\1 objectForKey:\2]',service)
head = r'''
#import <Foundation/Foundation.h>
typedef void (^NFBAtprotoDictionaryCompletion)(NSDictionary *,NSError *);
typedef void (^NFBAtprotoValueCompletion)(id,NSHTTPURLResponse *,NSError *);
@interface Request : NSObject { @public NFBAtprotoValueCompletion reply; }
@property(copy) NSString *method;
@property(copy) NSString *did;
@property(retain) NSDictionary *body;
@end
@implementation Request { NSString *_method,*_did; NSDictionary *_body; }
@synthesize method=_method,did=_did,body=_body;
@end
static NSMutableArray *requests;
@interface NFBAtprotoSession : NSObject {
 NSString *_did,*_serviceEndpoint; NSUInteger _accountGeneration;
}
@property(copy) NSString *did;
@property(copy) NSString *serviceEndpoint;
@property NSUInteger accountGeneration;
@property(readonly) BOOL hasSession;
+ (instancetype)sharedSession;
- (void)xrpcGET:(NSString *)method service:(NSString *)endpoint params:(NSDictionary *)params authenticated:(BOOL)auth completion:(NFBAtprotoValueCompletion)completion;
- (void)xrpcPOST:(NSString *)method forAccountDID:(NSString *)did body:(NSDictionary *)body completion:(NFBAtprotoValueCompletion)completion;
- (void)xrpcPOSTData:(NSString *)method forAccountDID:(NSString *)did data:(NSData *)data contentType:(NSString *)type completion:(NFBAtprotoValueCompletion)completion;
@end
@implementation NFBAtprotoSession
@synthesize did=_did,serviceEndpoint=_serviceEndpoint,accountGeneration=_accountGeneration;
+ (instancetype)sharedSession {static id s; if(!s)s=[self new]; return s;}
- (BOOL)hasSession {return self.did.length>0;}
- (void)capture:(NSString *)method did:(NSString *)did body:(NSDictionary *)body completion:(NFBAtprotoValueCompletion)completion {
 Request *q=[Request new];q.method=method;q.did=did;q.body=body;q->reply=Block_copy(completion);[requests addObject:q];
}
- (void)xrpcGET:(NSString *)method service:(NSString *)endpoint params:(NSDictionary *)params authenticated:(BOOL)auth completion:(NFBAtprotoValueCompletion)completion {
 NSCAssert(auth && [endpoint isEqual:self.serviceEndpoint],@"Must read authenticated account PDS");
 [self capture:method did:self.did body:params completion:completion];
}
- (void)xrpcPOST:(NSString *)method forAccountDID:(NSString *)did body:(NSDictionary *)body completion:(NFBAtprotoValueCompletion)completion {[self capture:method did:did body:body completion:completion];}
- (void)xrpcPOSTData:(NSString *)method forAccountDID:(NSString *)did data:(NSData *)data contentType:(NSString *)type completion:(NFBAtprotoValueCompletion)completion {
 NSCAssert([type isEqual:@"image/jpeg"],@"Must send the encoded JPEG type");
 [self capture:method did:did body:@{@"data":data} completion:completion];
}
@end
@interface NFBProfileEditorService : NSObject { NSString *_accountDID; NSUInteger _accountGeneration; BOOL _saving; }
@property(copy) NSString *accountDID;
@property NSUInteger accountGeneration;
@property BOOL saving;
- (instancetype)initWithAccountDID:(NSString *)did;
- (void)loadWithCompletion:(NFBAtprotoDictionaryCompletion)completion;
- (void)savePatch:(NSDictionary *)patch images:(NSDictionary *)images snapshot:(NSDictionary *)snapshot completion:(NFBAtprotoDictionaryCompletion)completion;
- (void)uploadImages:(NSDictionary *)images keys:(NSArray *)keys index:(NSUInteger)index patch:(NSMutableDictionary *)patch snapshot:(NSDictionary *)snapshot completion:(NFBAtprotoDictionaryCompletion)completion;
@end
static void respond(NSDictionary *value,NSError *error) {Request *q=[requests objectAtIndex:0];[requests removeObjectAtIndex:0];q->reply(value,nil,error);}
#define CHECK(c,m) if(!(c)){puts("FAIL: " m);return 1;}
'''
# Legacy GNU ABI requires ivars in the interface, not implementation.
head=head.replace('@interface Request : NSObject { @public NFBAtprotoValueCompletion reply; }','@interface Request : NSObject { NSString *_method,*_did; NSDictionary *_body; @public NFBAtprotoValueCompletion reply; }').replace('@implementation Request { NSString *_method,*_did; NSDictionary *_body; }','@implementation Request')
tail = r'''
int main(void) { @autoreleasepool {
 requests=[NSMutableArray new]; NFBAtprotoSession *session=NFBAtprotoSession.sharedSession;session.did=@"did:plc:alice";session.serviceEndpoint=@"https://alice.test";session.accountGeneration=1;
 NSDictionary *blob=@{@"$type":@"blob",@"ref":@{@"$link":@"bafk-photo"},@"mimeType":@"image/jpeg",@"size":@5};
 NSDictionary *base=@{@"$type":@"app.bsky.actor.profile",@"displayName":@"Old",@"description":@"Bio",@"avatar":blob,@"labels":@{@"values":@[]},@"pinnedPost":@{@"uri":@"at://post",@"cid":@"pin"},@"example.other":@{@"untouched":@1},@"pronouns":@"they/them"};
 NSDictionary *patch=@{@"displayName":@"New",@"description":NSNull.null,@"com.nottwitter.location":@"New York",@"website":NFBProfileNormalizedWebsite(@"example.com")};
 NSDictionary *merged=NFBProfileRecordApplyingPatch(base,patch);
 CHECK([[merged objectForKey:@"displayName"] isEqual:@"New"] && ![merged objectForKey:@"description"],"edit and removal");
 for(NSString *key in @[@"labels",@"pinnedPost",@"example.other",@"pronouns",@"avatar"]) {CHECK([[merged objectForKey:key] isEqual:[base objectForKey:key]],"unrelated record field lost");}
 CHECK(!NFBProfilePatchError(patch),"valid profile rejected");
 CHECK(NFBProfilePatchError(@{@"displayName":[@"x" stringByPaddingToLength:65 withString:@"x" startingAtIndex:0]}),"name limit");
 CHECK(NFBProfilePatchError(@{@"description":[@"x" stringByPaddingToLength:257 withString:@"x" startingAtIndex:0]}),"bio limit");
 CHECK(NFBProfileCharacterCount(@"e\u0301")==1,"composed character count");
 NSMutableString *longCluster=[NSMutableString stringWithString:@"a"];for(int i=0;i<400;i++)[longCluster appendString:@"\u0301"];
 CHECK(NFBProfilePatchError(@{@"displayName":longCluster}),"UTF-8 byte limit independent of grapheme limit");
 CHECK(!NFBProfilePatchError(@{@"pronouns":[@"p" stringByPaddingToLength:20 withString:@"p" startingAtIndex:0]}),"20-character pronouns rejected");
 CHECK(NFBProfilePatchError(@{@"pronouns":[@"p" stringByPaddingToLength:21 withString:@"p" startingAtIndex:0]}),"pronouns character limit");
 CHECK(NFBProfilePatchError(@{@"pronouns":longCluster}),"pronouns UTF-8 byte limit");
 CHECK(!NFBProfilePatchError(@{@"pronouns":NSNull.null}),"optional pronouns cannot be cleared");
 CHECK(NFBProfilePatchError(@{@"website":@"javascript:alert(1)"}),"unsafe website");
 CHECK(NFBProfilePatchError(@{@"website":@"https://"}),"missing website host");
 CHECK(!NFBProfilePatchError(@{@"com.nottwitter.birthDate":@"2000-02-29"}),"valid leap day");
 CHECK(NFBProfilePatchError(@{@"com.nottwitter.birthDate":@"2001-02-29"}),"invalid leap day");
 CHECK(NFBProfilePatchError(@{@"com.nottwitter.birthDate":@"2999-01-01"}),"future birthday");
 CHECK(NFBProfilePatchError(@{@"labels":NSNull.null}),"unrecognized edit allowed");
 NSDictionary *view=NFBProfileViewApplyingRecord(@{@"did":session.did,@"avatar":@"https://old.test/old-photo",@"banner":@"https://old.test/banner",@"_nfbLoadedAvatar":@"stale image",@"followersCount":@42},merged,session.serviceEndpoint);
 CHECK([[view objectForKey:@"avatar"] containsString:@"alice.test/xrpc/com.atproto.sync.getBlob"] && ![view objectForKey:@"banner"] && ![view objectForKey:@"_nfbLoadedAvatar"] && [[view objectForKey:@"followersCount"] isEqual:@42],"saved profile projection retains stale media or loses counts");
 NFBProfileEditorService *service=[[NFBProfileEditorService alloc] initWithAccountDID:session.did];
 __block NSDictionary *snapshot=nil,*saved=nil; __block NSError *failure=nil;
 NFBAtprotoDictionaryCompletion done=^(NSDictionary *value,NSError *error){saved=value;failure=error;};
 [service loadWithCompletion:^(NSDictionary *value,NSError *error){snapshot=value;failure=error;}];
 CHECK([[(Request *)requests.firstObject method] isEqual:@"com.atproto.repo.getRecord"],"profile read method");
 NSString *uri=@"at://did:plc:alice/app.bsky.actor.profile/self";
 respond(@{@"uri":uri,@"cid":@"old-cid",@"value":base},nil);
 CHECK(!failure && [[snapshot objectForKey:@"cid"] isEqual:@"old-cid"],"snapshot lost revision");
 [service savePatch:patch images:@{@"banner":[@"image" dataUsingEncoding:NSUTF8StringEncoding]} snapshot:snapshot completion:done];
 CHECK([[(Request *)requests.firstObject method] isEqual:@"com.atproto.repo.uploadBlob"] && requests.count==1,"put before upload");
 [service savePatch:patch images:@{} snapshot:snapshot completion:done]; CHECK(failure.code==5 && requests.count==1,"duplicate save");
 respond(@{@"blob":blob},nil);
 Request *put=requests.firstObject;CHECK([put.method isEqual:@"com.atproto.repo.putRecord"] && [put.did isEqual:@"did:plc:alice"],"wrong mutation/account");
 CHECK([[put.body objectForKey:@"swapRecord"] isEqual:@"old-cid"] && [[put.body objectForKey:@"rkey"] isEqual:@"self"] && [[put.body objectForKey:@"collection"] isEqual:@"app.bsky.actor.profile"],"CAS/repo parameters");
 CHECK([[[put.body objectForKey:@"record"] objectForKey:@"banner"] isEqual:blob] && [[[put.body objectForKey:@"record"] objectForKey:@"example.other"] isEqual:[base objectForKey:@"example.other"]],"uploaded blob or extension lost");
 respond(@{@"uri":uri,@"cid":@"new-cid"},nil); CHECK(saved && !failure && !service.saving,"save success");
 NSDictionary *afterSave=saved;
 [service savePatch:@{@"pronouns":@"she/they"} images:@{} snapshot:afterSave completion:done];
 NSDictionary *pronounRecord=[[(Request *)requests.firstObject body] objectForKey:@"record"];
 CHECK([[pronounRecord objectForKey:@"pronouns"] isEqual:@"she/they"] && [[pronounRecord objectForKey:@"displayName"] isEqual:@"New"],"pronouns update damaged other profile fields");
 respond(@{@"uri":uri,@"cid":@"pronoun-cid"},nil); CHECK(!failure && saved,"pronouns save failed");
 NSDictionary *pronounView=NFBProfileViewApplyingRecord(@{@"did":session.did},[saved objectForKey:@"value"],session.serviceEndpoint);
 CHECK([[pronounView objectForKey:@"pronouns"] isEqual:@"she/they"],"saved pronouns not displayed");
 [service savePatch:@{@"pronouns":NSNull.null} images:@{} snapshot:saved completion:done];
 CHECK(![[[(Request *)requests.firstObject body] objectForKey:@"record"] objectForKey:@"pronouns"],"clearing pronouns did not remove the record field");
 respond(@{@"uri":uri,@"cid":@"cleared-cid"},nil);
 pronounView=NFBProfileViewApplyingRecord(pronounView,[saved objectForKey:@"value"],session.serviceEndpoint);
 CHECK(!failure && [[pronounView objectForKey:@"pronouns"] isEqual:@""],"cleared pronouns stayed visible");
 NSError *network=[NSError errorWithDomain:@"Network" code:500 userInfo:nil];
 [service savePatch:patch images:@{} snapshot:snapshot completion:done]; respond(@{@"error":@"InvalidSwap"},network); CHECK(!saved && failure.code==6 && !service.saving,"conflict not surfaced");
 [service savePatch:patch images:@{@"avatar":[@"image" dataUsingEncoding:NSUTF8StringEncoding]} snapshot:snapshot completion:done]; respond(nil,network); CHECK(failure && !requests.count && !service.saving,"upload failure still wrote record");
 [service savePatch:patch images:@{@"avatar":[@"image" dataUsingEncoding:NSUTF8StringEncoding]} snapshot:snapshot completion:done]; respond(@{@"blob":@{@"bad":@1}},nil); CHECK(failure && !requests.count,"malformed blob accepted");
 [service savePatch:patch images:@{} snapshot:snapshot completion:done]; respond(@{},nil); CHECK(failure && !saved,"malformed success accepted");
 [service loadWithCompletion:done]; respond(nil,network); CHECK(failure && !saved,"load failure became empty writable profile");
 [service loadWithCompletion:done]; respond(@{@"error":@"RecordNotFound"},network); NSDictionary *empty=saved; CHECK([empty objectForKey:@"cid"]==NSNull.null && !failure,"missing record not handled");
 [service savePatch:patch images:@{} snapshot:empty completion:done]; CHECK([[(Request *)requests.firstObject body] objectForKey:@"swapRecord"]==NSNull.null,"record creation must compare against absence"); respond(@{@"uri":uri,@"cid":@"created"},nil);
 [service savePatch:patch images:@{@"avatar":[@"image" dataUsingEncoding:NSUTF8StringEncoding]} snapshot:snapshot completion:done]; session.did=@"did:plc:bob";session.accountGeneration++;
 respond(@{@"blob":blob},nil); CHECK(failure.code==2 && requests.count==0,"account switch during upload wrote profile");
 session.did=@"did:plc:alice";session.accountGeneration++;
 [service savePatch:patch images:@{} snapshot:snapshot completion:done]; CHECK(failure.code==2 && !requests.count,"A-B-A identity transition accepted stale editor");
 puts("PASS: record preservation, validation, profile projection, fresh PDS snapshot, blob upload, CAS, missing records, duplicate saves, network/malformed responses, and account-switch isolation");
 } return 0;
}
'''
source=(head+record+service+tail).replace('@YES','@(YES)').replace('@NO','@(NO)')
p=r/'profile-edit.m';p.write_text(source)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(r/'usr/include'),str(p),'-L'+str(r/'usr/lib'),'-Wl,-rpath,'+str(r/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(r/'profile-edit')],check=True)
subprocess.run([str(r/'profile-edit')],check=True)
