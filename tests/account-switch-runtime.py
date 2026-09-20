"""Execute production account-transition methods with Foundation and UIKit/network stubs.

NFB_OBJC_TEST_RUNTIME=/path/to/gnustep-prefix python3 tests/account-switch-runtime.py
The prefix contains usr/include/{Foundation,GNUstepBase,objc} and usr/lib/libgnustep-base.so.
This checks Objective-C control flow, not on-device layout or animation rendering.
"""
import os
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
s=(root/'NFBMainTabBarController.m').read_text()
def method(signature):
 a=s.index(signature); b=s.index('\n}',a)+2
 return s[a:b]
body=method('- (void)sessionChanged:(NSNotification *)notification')
client=(root/'NFBAtprotoClient.m').read_text()
a=client.index('- (void)fetchAppViewGET:',client.index('@implementation'))
client_method=client[a:client.index('\n}',a)+2]
session=(root/'NFBAtprotoSession.m').read_text()
a=session.index('- (void)updateProfileFromDictionary:')
profile_method=session[a:session.index('\n}',a)+2]
# Clang's legacy GNU runtime uses message syntax for NSDictionary subscripting.
import re
profile_method=re.sub(r'profile\[(@"[^"]+")\]',r'[profile objectForKey:\1]',profile_method)

head=r'''

#import <Foundation/Foundation.h>
typedef void (^dispatch_block_t)(void);
static void *dispatch_get_main_queue(void) { return NULL; }
static void dispatch_async(void *q, dispatch_block_t b) { b(); }
static void dispatch_sync(void *q, dispatch_block_t b) { b(); }
typedef void (^NFBAtprotoValueCompletion)(id, NSHTTPURLResponse *, NSError *);
static NFBAtprotoValueCompletion pendingResponse;
static NSUInteger networkCalls;
static NSString *NFBAtprotoPublicAppViewURL=@"public", *NFBAtprotoAppViewURL=@"appview";
static double transitionDuration;
@interface UIView : NSObject
@property BOOL userInteractionEnabled;
- (id)snapshotViewAfterScreenUpdates:(BOOL)b;
- (void)addSubview:(id)v;
- (void)removeFromSuperview;
- (void)layoutIfNeeded;
@property double alpha;
+ (void)animateWithDuration:(double)d animations:(dispatch_block_t)a completion:(void (^)(BOOL))c;
@end
@implementation UIView
- (id)snapshotViewAfterScreenUpdates:(BOOL)b { return [UIView new]; }
- (void)addSubview:(id)v {}
- (void)removeFromSuperview {}
- (void)layoutIfNeeded {}
- (void)setAlpha:(double)a {}
- (double)alpha { return 1; }
- (BOOL)userInteractionEnabled {return YES;}
- (void)setUserInteractionEnabled:(BOOL)b {}
+ (void)animateWithDuration:(double)d animations:(dispatch_block_t)a completion:(void (^)(BOOL))c {transitionDuration=d; a(); if(c)c(YES);}
@end
@interface NFBAtprotoSession : NSObject { NSString *_did,*_handle; NSDictionary *_profile; NSUInteger _accountGeneration; }
@property(copy) NSString *handle;
@property(retain) NSDictionary *profile;
@property NSUInteger accountGeneration;
@property(readonly) void *stateQueue;
- (void)saveStoredSessionLocked;
- (void)updateProfileFromDictionary:(NSDictionary *)profile;
- (void)xrpcGETViaAppViewProxy:(NSString *)method params:(NSDictionary *)params completion:(NFBAtprotoValueCompletion)completion;
- (void)xrpcGET:(NSString *)method service:(NSString *)service params:(NSDictionary *)params authenticated:(BOOL)authenticated completion:(NFBAtprotoValueCompletion)completion;
@property(copy) NSString *did;
+ (instancetype)sharedSession;
- (BOOL)hasSession;
@end
@implementation NFBAtprotoSession
@synthesize did=_did,profile=_profile,handle=_handle,accountGeneration=_accountGeneration;
- (void *)stateQueue {return NULL;}
- (void)saveStoredSessionLocked {}
- (void)xrpcGETViaAppViewProxy:(NSString *)method params:(NSDictionary *)params completion:(NFBAtprotoValueCompletion)completion {networkCalls++;pendingResponse=Block_copy(completion);}
- (void)xrpcGET:(NSString *)method service:(NSString *)service params:(NSDictionary *)params authenticated:(BOOL)authenticated completion:(NFBAtprotoValueCompletion)completion {networkCalls++;pendingResponse=Block_copy(completion);}
+ (instancetype)sharedSession {static id s; if(!s)s=[self new]; return s;}
- (BOOL)hasSession {return _did.length>0;}
'''+profile_method+r'''
@end
@interface NFBAtprotoClient : NSObject
- (void)fetchAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)auth completion:(NFBAtprotoValueCompletion)completion;
@end
@implementation NFBAtprotoClient
'''+client_method+r'''
@end
@interface NFBNotificationCoordinator : NSObject
+ (id)sharedCoordinator;
- (void)refreshBadgeCounts;
@end
@implementation NFBNotificationCoordinator
+ (id)sharedCoordinator {static id s; if(!s)s=[self new]; return s;}
- (void)refreshBadgeCounts {}
@end
@interface NFBMainTabBarController : NSObject {
 NSString *_displayedAccountDID;
 NSArray *_viewControllers;
 NSUInteger _displayedAccountGeneration,_selectedIndex,_currentHomeBadgeCount,_currentNotificationBadgeCount,_currentMessageBadgeCount;
 UIView *_view;
}
@property(copy) NSString *displayedAccountDID;
@property(retain) NSArray *viewControllers;
@property NSUInteger displayedAccountGeneration,selectedIndex,currentHomeBadgeCount,currentNotificationBadgeCount,currentMessageBadgeCount;
@property(retain) UIView *view;
@property(readonly) BOOL isViewLoaded;
- (void)sessionChanged:(NSNotification *)n;
- (void)rebuildTabControllers;
- (void)applyCurrentTabBadges;
- (void)updateLeftEdgeMenuGestureEnabled;
@end
@implementation NFBMainTabBarController
@synthesize displayedAccountGeneration=_displayedAccountGeneration,displayedAccountDID=_displayedAccountDID,viewControllers=_viewControllers,selectedIndex=_selectedIndex,currentHomeBadgeCount=_currentHomeBadgeCount,currentNotificationBadgeCount=_currentNotificationBadgeCount,currentMessageBadgeCount=_currentMessageBadgeCount,view=_view;
- (BOOL)isViewLoaded {return YES;}
- (void)rebuildTabControllers {self.viewControllers=[NSArray arrayWithObjects:[NSMutableDictionary dictionaryWithObjectsAndKeys:[NFBAtprotoSession sharedSession].did,@"owner",@"loading",@"content",nil],@"Explore",@"Notifications",@"Messages",nil];}
- (void)applyCurrentTabBadges {}
- (void)updateLeftEdgeMenuGestureEnabled {}
'''
tail=r'''
@end
int main(void) { @autoreleasepool {
 NFBAtprotoSession *s=[NFBAtprotoSession sharedSession]; s.did=@"A";
 NFBMainTabBarController *host=[NFBMainTabBarController new]; host.view=[UIView new]; host.displayedAccountDID=s.did;
 [host rebuildTabControllers]; host.selectedIndex=3; host.currentMessageBadgeCount=8;
 NSMutableDictionary *inFlightA=[host.viewControllers objectAtIndex:0];
 [inFlightA setObject:@"A content" forKey:@"content"];
 s.did=@"B"; [host sessionChanged:nil];
 NSMutableDictionary *visible=[host.viewControllers objectAtIndex:0];
 if(![[visible objectForKey:@"owner"] isEqual:@"B"]) {puts("FAIL: switching A to B leaves A's content/controller visible while loading");return 1;}
 [inFlightA setObject:@"late A response" forKey:@"content"];
 if([[visible objectForKey:@"content"] isEqual:@"late A response"]) {puts("FAIL: old response replaced B content");return 2;}
 if(host.selectedIndex!=3 || host.currentMessageBadgeCount!=0) {puts("FAIL: selected tab/badge transition");return 3;}
 NSArray *same=host.viewControllers; [host sessionChanged:nil];
 if(host.viewControllers!=same) {puts("FAIL: token refresh resets the current account screen");return 4;}
 if(fabs(transitionDuration-0.35)>0.001) {puts("FAIL: reference account transition duration");return 5;}
 s.did=@"A";[host sessionChanged:nil];
 if(![[[host.viewControllers objectAtIndex:0] objectForKey:@"owner"] isEqual:@"A"])return 6;
 same=host.viewControllers;
 s.did=@"B";s.accountGeneration++;s.did=@"A";s.accountGeneration++;
 [host sessionChanged:nil];
 if(host.viewControllers==same) {puts("FAIL: coalesced A-B-A kept expired controllers");return 12;}
 puts("PASS: account screen replacement, late response isolation, tab preservation, badge clearing, token refresh, return switch, 0.35s fade");
 s.did=@"B";s.profile=[NSDictionary dictionaryWithObjectsAndKeys:@"B",@"did",@"B photo",@"avatar",nil];
 [s updateProfileFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:@"A",@"did",@"A photo",@"avatar",nil]];
 if(![s.did isEqual:@"B"] || ![[s.profile objectForKey:@"avatar"] isEqual:@"B photo"]) {puts("FAIL: late profile response changed the active account/photo");return 7;}
 [s updateProfileFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:@"B",@"did",@"new B photo",@"avatar",nil]];
 if(![[s.profile objectForKey:@"avatar"] isEqual:@"new B photo"])return 8;
 puts("PASS: stale profile cannot replace identity/photo; current profile still updates");
 NFBAtprotoClient *client=[NFBAtprotoClient new];
 __block BOOL canceled=NO; __block BOOL succeeded=NO;
 s.accountGeneration=1;
 [client fetchAppViewGET:@"profile" params:nil requiresAuth:NO completion:^(id v,NSHTTPURLResponse *r,NSError *e) {canceled=e.code==NSURLErrorCancelled;succeeded=v!=nil;}];
 s.did=@"A";s.accountGeneration=2;
 pendingResponse(@"B content",nil,nil);
 if(!canceled || succeeded || networkCalls!=1) {puts("FAIL: stale AppView success escaped");return 9;}
 canceled=NO;succeeded=NO;
 [client fetchAppViewGET:@"profile" params:nil requiresAuth:NO completion:^(id v,NSHTTPURLResponse *r,NSError *e) {canceled=e.code==NSURLErrorCancelled;succeeded=v!=nil;}];
 s.did=@"B";s.accountGeneration=3;s.did=@"A";s.accountGeneration=4;
 pendingResponse(nil,nil,[NSError errorWithDomain:@"test" code:500 userInfo:nil]);
 if(!canceled || succeeded || networkCalls!=2) {puts("FAIL: old request retried through the switched account");return 10;}
 [client fetchAppViewGET:@"profile" params:nil requiresAuth:NO completion:^(id v,NSHTTPURLResponse *r,NSError *e) {canceled=e.code==NSURLErrorCancelled;succeeded=v!=nil;}];
 pendingResponse(@"A content",nil,nil);
 if(canceled || !succeeded)return 11;
 puts("PASS: stale AppView responses/fallbacks rejected, including A-B-A; current response delivered");
}return 0;}
'''
r=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
p=r/'account-switch.m';p.write_text(head+body+tail)
subprocess.run(['clang','-Wno-objc-property-implementation','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(r/'usr/include'),str(p),'-L'+str(r/'usr/lib'),'-Wl,-rpath,'+str(r/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(r/'account-switch')],check=True)
subprocess.run([str(r/'account-switch')],check=True)
