#import "NFBProfileEditorService.h"
#import "NFBProfileRecord.h"
#import "NFBAtprotoSession.h"

static NSError *NFBProfileServiceError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:@"NFBProfileEditor" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
@interface NFBProfileEditorService ()
@property (nonatomic, copy) NSString *accountDID;
@property (nonatomic) NSUInteger accountGeneration;
@property (atomic) BOOL saving;
@end
@implementation NFBProfileEditorService
- (instancetype)initWithAccountDID:(NSString *)did {
  if ((self = [super init])) { _accountDID = [did copy]; _accountGeneration = NFBAtprotoSession.sharedSession.accountGeneration; }
  return self;
}
- (BOOL)ownsCurrentAccount {
  NFBAtprotoSession *session = NFBAtprotoSession.sharedSession;
  return self.accountDID.length && session.hasSession && [session.did isEqual:self.accountDID] && session.accountGeneration == self.accountGeneration;
}
- (NSError *)accountError { return NFBProfileServiceError(2, @"The active account changed. Reopen Edit profile for the account you want to edit."); }
- (void)loadWithCompletion:(NFBAtprotoDictionaryCompletion)completion {
  if (![self ownsCurrentAccount]) { completion(nil, [self accountError]); return; }
  NSString *endpoint = [NFBAtprotoSession.sharedSession.serviceEndpoint copy];
  [NFBAtprotoSession.sharedSession xrpcGET:@"com.atproto.repo.getRecord" service:endpoint params:@{@"repo":self.accountDID,@"collection":@"app.bsky.actor.profile",@"rkey":@"self"} authenticated:YES completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    if (![self ownsCurrentAccount]) { completion(nil, [self accountError]); return; }
    NSDictionary *result = [value isKindOfClass:NSDictionary.class] ? value : @{};
    if (error && [result[@"error"] isEqual:@"RecordNotFound"]) {
      completion(@{@"value":@{@"$type":@"app.bsky.actor.profile"},@"cid":NSNull.null,@"endpoint":endpoint,@"did":self.accountDID},nil); return;
    }
    if (error) { completion(nil,error); return; }
    if (![result[@"value"] isKindOfClass:NSDictionary.class] || !NFBProfileString(result[@"cid"]).length || ![result[@"uri"] isEqual:[NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self",self.accountDID]]) {
      completion(nil,NFBProfileServiceError(3,@"The server returned an incomplete profile. Your profile has not been changed.")); return;
    }
    completion(@{@"value":result[@"value"],@"cid":result[@"cid"],@"endpoint":endpoint,@"did":self.accountDID},nil);
  }];
}
- (void)savePatch:(NSDictionary *)patch images:(NSDictionary<NSString *,NSData *> *)images snapshot:(NSDictionary *)snapshot completion:(NFBAtprotoDictionaryCompletion)completion {
  if (![self ownsCurrentAccount]) { completion(nil,[self accountError]); return; }
  NSError *validation = NFBProfilePatchError(patch);
  if (validation) { completion(nil,validation); return; }
  if (![snapshot[@"did"] isEqual:self.accountDID] || ![snapshot[@"value"] isKindOfClass:NSDictionary.class] || !(snapshot[@"cid"] == NSNull.null || NFBProfileString(snapshot[@"cid"]).length)) { completion(nil,NFBProfileServiceError(3,@"Load your profile before saving.")); return; }
  for (NSString *key in images) {
    NSData *data = images[key];
    if (![@[@"avatar",@"banner"] containsObject:key] || ![data isKindOfClass:NSData.class] || data.length == 0 || data.length > 1000000) { completion(nil,NFBProfileServiceError(4,@"Profile photos must be smaller than 1 MB.")); return; }
  }
  @synchronized(self) {
    if (self.saving) { completion(nil,NFBProfileServiceError(5,@"Your profile is already being saved.")); return; }
    self.saving = YES;
  }
  [self uploadImages:images keys:images.allKeys index:0 patch:[patch mutableCopy] snapshot:snapshot completion:^(NSDictionary *value, NSError *error) { self.saving = NO; completion(value,error); }];
}
- (void)uploadImages:(NSDictionary *)images keys:(NSArray *)keys index:(NSUInteger)index patch:(NSMutableDictionary *)patch snapshot:(NSDictionary *)snapshot completion:(NFBAtprotoDictionaryCompletion)completion {
  if (![self ownsCurrentAccount]) { completion(nil,[self accountError]); return; }
  if (index < keys.count) {
    NSString *key = keys[index];
    [NFBAtprotoSession.sharedSession xrpcPOSTData:@"com.atproto.repo.uploadBlob" forAccountDID:self.accountDID data:images[key] contentType:@"image/jpeg" completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      NSDictionary *blob = [value isKindOfClass:NSDictionary.class] && [value[@"blob"] isKindOfClass:NSDictionary.class] ? value[@"blob"] : nil;
      NSError *invalid = blob ? NFBProfilePatchError(@{key:blob}) : NFBProfileServiceError(4,@"The photo could not be uploaded. Try again.");
      if (error || invalid) { completion(nil,error ?: invalid); return; }
      patch[key] = blob;
      [self uploadImages:images keys:keys index:index+1 patch:patch snapshot:snapshot completion:completion];
    }];
    return;
  }
  NSDictionary *record = NFBProfileRecordApplyingPatch(snapshot[@"value"],patch);
  NSDictionary *body = @{@"repo":self.accountDID,@"collection":@"app.bsky.actor.profile",@"rkey":@"self",@"record":record,@"swapRecord":snapshot[@"cid"],@"validate":@YES};
  [NFBAtprotoSession.sharedSession xrpcPOST:@"com.atproto.repo.putRecord" forAccountDID:self.accountDID body:body completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    NSDictionary *result = [value isKindOfClass:NSDictionary.class] ? value : @{};
    if (error) {
      if ([result[@"error"] isEqual:@"InvalidSwap"]) error = NFBProfileServiceError(6,@"Your profile changed in another app. Reload the latest profile before saving again. Your current edits are still here.");
      completion(nil,error); return;
    }
    if (!NFBProfileString(result[@"cid"]).length || ![result[@"uri"] isEqual:[NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self",self.accountDID]]) { completion(nil,NFBProfileServiceError(3,@"The server did not confirm the save. Reload your profile to check whether it was saved before trying again.")); return; }
    completion(@{@"value":record,@"cid":result[@"cid"],@"endpoint":snapshot[@"endpoint"],@"did":self.accountDID},nil);
  }];
}
@end
