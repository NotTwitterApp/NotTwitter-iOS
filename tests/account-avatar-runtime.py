"""Run the production avatar loader against controllable UIKit/network doubles.

Uses the same GNUstep prefix as account-switch-runtime.py. Checks cached-image
handoff and delayed completions; it does not validate UIKit rendering or ARC.
"""
from pathlib import Path
import os, subprocess
root=Path(__file__).resolve().parents[1]
r=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
source=(root/'NFBAccountAvatar.m').read_text().replace('__weak ', '')
source='\n'.join(line for line in source.splitlines() if not line.startswith('#import'))
head=r'''
#import <Foundation/Foundation.h>
#define NSURLSession FakeSession
#define NSURLSessionDataTask FakeTask
#define OBJC_ASSOCIATION_RETAIN_NONATOMIC 1
#define OBJC_ASSOCIATION_COPY_NONATOMIC 2
static NSMutableDictionary *associated;
id objc_getAssociatedObject(id object,const void *key) {return [associated objectForKey:[NSString stringWithFormat:@"%p:%p",object,key]];}
void objc_setAssociatedObject(id object,const void *key,id value,NSUInteger policy) {
 if(!associated)associated=[NSMutableDictionary new];
 NSString *k=[NSString stringWithFormat:@"%p:%p",object,key];
 if(value)[associated setObject:value forKey:k];else [associated removeObjectForKey:k];
}
typedef void (^dispatch_block_t)(void);
typedef NSUInteger dispatch_once_t;
static void dispatch_once(dispatch_once_t *t,dispatch_block_t b){if(!*t){*t=1;b();}}
static void *dispatch_get_main_queue(void){return NULL;}
static void dispatch_async(void *q,dispatch_block_t b){b();}
@interface UIImage:NSObject
+ (instancetype)imageWithData:(NSData *)data;
@end
@implementation UIImage
+ (instancetype)imageWithData:(NSData *)data {return [self new];}
@end
@interface UIImageView:NSObject {UIImage *_image;}
@property(retain) UIImage *image;
@end
@implementation UIImageView
@synthesize image=_image;
@end
static UIImage *defaultImage;
static UIImage *NFBDefaultAvatarImage(void){if(!defaultImage)defaultImage=[UIImage new];return defaultImage;}
static UIImage *NFBBrandIconImage(void){return nil;}
static NSMutableArray *requests;
@interface FakeTask:NSObject { @public void (^completion)(NSData *,NSURLResponse *,NSError *); BOOL canceled; }
- (void)cancel;
- (void)resume;
- (void)finish;
@end
@implementation FakeTask
- (void)cancel {canceled=YES;}
- (void)resume {if(!requests)requests=[NSMutableArray new];[requests addObject:self];}
- (void)finish {completion([@"photo" dataUsingEncoding:NSUTF8StringEncoding],nil,nil);}
@end
@interface FakeSession:NSObject
+ (instancetype)sharedSession;
- (FakeTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion;
@end
@implementation FakeSession
+ (instancetype)sharedSession {static id s;if(!s)s=[self new];return s;}
- (FakeTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))b {FakeTask *t=[FakeTask new];t->completion=Block_copy(b);return t;}
@end
'''
tail=r'''
#define CHECK(c,m) if(!(c)){puts("FAIL: " m);return 1;}
int main(void){@autoreleasepool {
 UIImageView *picker=[UIImageView new],*header=[UIImageView new];
 NFBLoadAccountAvatar(picker,@"https://example.test/B");[[requests lastObject] finish];
 UIImage *b=picker.image;NSUInteger count=requests.count;
 NFBLoadAccountAvatar(header,@"https://example.test/B");
 CHECK(header.image==b && requests.count==count,"selected photo did not transfer synchronously from picker to header");
 NFBLoadAccountAvatar(header,@"https://example.test/A");FakeTask *a=[requests lastObject];
 NFBLoadAccountAvatar(header,@"https://example.test/B");[a finish];
 CHECK(a->canceled && header.image==b,"late A image replaced B");
 NFBLoadAccountAvatar(header,@"https://example.test/A");
 CHECK(header.image!=defaultImage && header.image!=b,"return switch did not reuse A cache");
 NFBLoadAccountAvatar(header,@"https://example.test/C");FakeTask *oldC=[requests lastObject];
 count=requests.count;NFBLoadAccountAvatar(header,@"https://example.test/C");
 CHECK(requests.count==count,"same pending URL restarted its request");
 NFBLoadAccountAvatar(header,nil);[oldC finish];
 CHECK(header.image==defaultImage,"missing photo retained/restored previous account photo");
 NFBLoadAccountAvatar(header,@"https://example.test/D");FakeTask *oldD=[requests lastObject];
 NFBLoadAccountAvatar(header,@"https://example.test/E");
 NFBLoadAccountAvatar(header,@"https://example.test/D");FakeTask *newD=[requests lastObject];
 [oldD finish];CHECK(header.image==defaultImage,"A-B-A accepted the canceled first image request");
 [newD finish];CHECK(header.image!=defaultImage,"current image request was discarded");
 puts("PASS: immediate cached picker/header handoff, cancellation, missing photo, request deduplication, late A-B-A images");
}return 0;}
'''
p=r/'account-avatar.m';p.write_text(head+source+tail)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(r/'usr/include'),str(p),'-L'+str(r/'usr/lib'),'-Wl,-rpath,'+str(r/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(r/'account-avatar')],check=True)
subprocess.run([str(r/'account-avatar')],check=True)
