"""Execute the production opening animator with deterministic UIKit doubles.
Checks routing, geometry and cleanup, not UIKit rendering or AVPlayer decoding.
"""
from pathlib import Path
import os,subprocess,re
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
s=(root/'NFBMediaViewerViewController.m').read_text()
a=s.index('@interface NFBMediaOpeningAnimator');b=s.index('\n@implementation NFBMediaViewerViewController',a)
animator=s[a:b].replace('(nonatomic, weak)','(nonatomic, assign)')
animator=animator.replace(': NSObject <UIViewControllerAnimatedTransitioning>',': NSObject <UIViewControllerAnimatedTransitioning> { NFBMediaViewerViewController *_viewer; }')
animator=animator.replace('@implementation NFBMediaOpeningAnimator','@implementation NFBMediaOpeningAnimator\n@synthesize viewer=_viewer;')
animator=animator.replace('viewer.pages[index]','[viewer.pages objectAtIndex:index]')
head=r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#import "NFBMediaTransitionGeometry.h"
typedef NSRect CGRect;typedef NSPoint CGPoint;typedef NSSize CGSize;
#define CGRectZero NSZeroRect
#define CGRectMake NSMakeRect
#define CGRectIntersection NSIntersectionRect
#define CGRectIsEmpty NSIsEmptyRect
#define CGRectIsNull NSIsEmptyRect
static BOOL reduceMotion;static BOOL UIAccessibilityIsReduceMotionEnabled(void){return reduceMotion;}
enum {UIViewAnimationOptionLayoutSubviews=1,UIViewAnimationOptionCurveEaseOut=2<<16};
static NSString *kCAMediaTimingFunctionEaseOut=@"easeOut",*AVLayerVideoGravityResizeAspect=@"fit";
static double duration;static NSUInteger options;static CGRect startingClip,startingImage,endingClip;static BOOL hadClip,hadVideo;
@interface Layer:NSObject {CGFloat _cornerRadius;CGRect _frame;id _player;NSMutableArray *_sublayers;}
@property CGFloat cornerRadius;@property CGRect frame;@property(retain)id player;@property(retain)NSMutableArray *sublayers;
- (void)addSublayer:(Layer *)layer;- (void)addAnimation:(id)a forKey:(id)key;
@end
@implementation Layer
@synthesize cornerRadius=_cornerRadius,frame=_frame,player=_player,sublayers=_sublayers;
- (instancetype)init{if((self=[super init]))_sublayers=[NSMutableArray new];return self;}
- (void)addSublayer:(Layer *)l{[_sublayers addObject:l];}
- (void)addAnimation:(id)a forKey:(id)key{}
@end
@interface CABasicAnimation:NSObject {id _fromValue,_toValue,_timingFunction;double _duration;}
@property(retain)id fromValue,toValue,timingFunction;@property double duration;
+ (instancetype)animationWithKeyPath:(id)key;
@end
@implementation CABasicAnimation
@synthesize fromValue=_fromValue,toValue=_toValue,timingFunction=_timingFunction,duration=_duration;
+ (instancetype)animationWithKeyPath:(id)key{return [self new];}
@end
@interface CAMediaTimingFunction:NSObject
+ (id)functionWithName:(id)name;
@end
@implementation CAMediaTimingFunction
+ (id)functionWithName:(id)name{return name;}
@end
@interface AVPlayerLayer:Layer {id _videoGravity;}
@property(retain)id videoGravity;
+ (instancetype)playerLayerWithPlayer:(id)p;
@end
@implementation AVPlayerLayer
@synthesize videoGravity=_videoGravity;
+ (instancetype)playerLayerWithPlayer:(id)p{AVPlayerLayer *l=[self new];l.player=p;return l;}
@end
@class UIView;static UIView *transitionContainer;
@interface UIView:NSObject {CGRect _frame;BOOL _hidden,_clipsToBounds;CGFloat _alpha;UIView *_superview;id _window;Layer *_layer;NSMutableArray *_subviews;}
@property CGRect frame;@property(readonly)CGRect bounds;@property BOOL hidden,clipsToBounds;@property CGFloat alpha;
@property(assign)UIView *superview;@property(retain)id window;@property(retain)Layer *layer;@property(retain)NSMutableArray *subviews;
- (instancetype)initWithFrame:(CGRect)frame;- (void)addSubview:(UIView *)view;- (void)removeFromSuperview;
- (void)setNeedsLayout;- (void)layoutIfNeeded;- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
+ (void)animateWithDuration:(double)d delay:(double)delay options:(NSUInteger)o animations:(void(^)(void))a completion:(void(^)(BOOL))c;
@end
@implementation UIView
@synthesize frame=_frame,hidden=_hidden,clipsToBounds=_clipsToBounds,alpha=_alpha,superview=_superview,window=_window,layer=_layer,subviews=_subviews;
- (instancetype)initWithFrame:(CGRect)f{if((self=[super init])){_frame=f;_alpha=1;_layer=[Layer new];_subviews=[NSMutableArray new];}return self;}
- (CGRect)bounds{return NSMakeRect(0,0,_frame.size.width,_frame.size.height);}
- (void)addSubview:(UIView *)v{[_subviews addObject:v];v.superview=self;}
- (void)removeFromSuperview{[_superview.subviews removeObjectIdenticalTo:self];_superview=nil;}
- (void)setNeedsLayout{}- (void)layoutIfNeeded{}
- (CGRect)convertRect:(CGRect)r toView:(UIView *)v{for(UIView *p=self;p && p!=v;p=p.superview){r.origin.x+=p.frame.origin.x;r.origin.y+=p.frame.origin.y;}return r;}
+ (void)animateWithDuration:(double)d delay:(double)delay options:(NSUInteger)o animations:(void(^)(void))a completion:(void(^)(BOOL))c{
 duration=d;options=o;hadClip=transitionContainer.subviews.count==2;
 UIView *clip=hadClip?[transitionContainer.subviews lastObject]:nil;UIView *image=[clip.subviews firstObject];
 startingClip=clip.frame;startingImage=image.frame;hadVideo=image.layer.sublayers.count>0;
 a();endingClip=clip.frame;c(YES);
}
@end
@interface UIImageView:UIView {id _image;NSInteger _contentMode;}
@property(retain)id image;@property NSInteger contentMode;- (instancetype)initWithImage:(id)i;
@end
@implementation UIImageView
@synthesize image=_image,contentMode=_contentMode;
- (instancetype)initWithImage:(id)i{if((self=[super initWithFrame:CGRectZero]))_image=i;return self;}
@end
enum {UIViewContentModeScaleToFill};
@interface NFBMediaTransitionSource:NSObject {UIView *_view;id _image,_player;CGFloat _cornerRadius;BOOL(^_isStillValid)(void);}
@property(assign)UIView *view;@property(retain)id image,player;@property CGFloat cornerRadius;@property(copy)BOOL(^isStillValid)(void);
@end
@implementation NFBMediaTransitionSource
@synthesize view=_view,image=_image,player=_player,cornerRadius=_cornerRadius;
// GNUstep's legacy runtime needs explicit BlocksRuntime ownership.
- (BOOL(^)(void))isStillValid{return _isStillValid;}
- (void)setIsStillValid:(BOOL(^)(void))b{if(_isStillValid)Block_release(_isStillValid);_isStillValid=Block_copy(b);}
@end
@interface NFBMediaViewerPage:UIView {UIView *_mediaContentView;}
@property(retain)UIView *mediaContentView;
@end
@implementation NFBMediaViewerPage
@synthesize mediaContentView=_mediaContentView;
@end
@interface NFBMediaViewerViewController:NSObject {UIView *_view;NFBMediaTransitionSource *_transitionSource;NSUInteger _initialIndex;NSArray *_pages;}
@property(retain)UIView *view;@property(retain)NFBMediaTransitionSource *transitionSource;@property NSUInteger initialIndex;@property(retain)NSArray *pages;
@end
@implementation NFBMediaViewerViewController
@synthesize view=_view,transitionSource=_transitionSource,initialIndex=_initialIndex,pages=_pages;
@end
@protocol UIViewControllerContextTransitioning
@property(readonly)UIView *containerView;@property(readonly)BOOL transitionWasCancelled;
- (CGRect)finalFrameForViewController:(id)v;- (void)completeTransition:(BOOL)b;
@end
@protocol UIViewControllerAnimatedTransitioning @end
@interface Context:NSObject <UIViewControllerContextTransitioning> {BOOL _transitionWasCancelled,_completed;UIView *_containerView;}
@property BOOL transitionWasCancelled,completed;@property(retain)UIView *containerView;
@end
@implementation Context
@synthesize transitionWasCancelled=_transitionWasCancelled,completed=_completed,containerView=_containerView;
- (CGRect)finalFrameForViewController:(id)v{return self.containerView.bounds;}
- (void)completeTransition:(BOOL)b{self.completed=b;}
@end
'''
tail=r'''
int main(void){@autoreleasepool{
 for(int mode=0;mode<7;mode++){
  reduceMotion=mode==3;Context *context=[Context new];context.containerView=[[UIView alloc] initWithFrame:NSMakeRect(0,0,390,844)];transitionContainer=context.containerView;
  NFBMediaViewerViewController *viewer=[NFBMediaViewerViewController new];viewer.view=[[UIView alloc] initWithFrame:context.containerView.bounds];
  NFBMediaViewerPage *first=[[NFBMediaViewerPage alloc] initWithFrame:CGRectZero];first.mediaContentView=[[UIView alloc] initWithFrame:NSMakeRect(0,0,20,20)];
  NFBMediaViewerPage *page=[[NFBMediaViewerPage alloc] initWithFrame:CGRectZero];page.mediaContentView=[[UIView alloc] initWithFrame:NSMakeRect(0,312,390,220)];
  viewer.pages=@[first,page];viewer.initialIndex=1;
  UIView *origin=[[UIView alloc] initWithFrame:NSMakeRect(30,120,120,120)];origin.window=@"window";
  NFBMediaTransitionSource *source=[NFBMediaTransitionSource new];source.view=origin;source.image=mode==6?nil:@"image";source.cornerRadius=12;
  source.isStillValid=^BOOL{return mode!=4;};if(mode==1 || mode==6)source.player=@"current video player";
  if(mode==5)origin.frame=NSMakeRect(30,-30,120,120);
  viewer.transitionSource=source;context.transitionWasCancelled=mode==2;
  NFBMediaOpeningAnimator *animator=[NFBMediaOpeningAnimator new];animator.viewer=viewer;[animator animateTransition:context];
  assert(context.completed==(mode!=2));assert(!origin.hidden && !page.mediaContentView.hidden);assert(viewer.view.alpha==1);assert(viewer.transitionSource==nil);assert(source.player==nil);assert(transitionContainer.subviews.count==1);
  assert(hadClip==(mode!=3 && mode!=4));assert(fabs(duration-(mode==3?.15:.25))<.001);assert(options==0x20001);
  if(hadClip){assert(NSEqualRects(endingClip,page.mediaContentView.frame));assert(startingClip.size.width==120);assert(hadVideo==(mode==1 || mode==6));}
  if(mode==5){assert(startingClip.origin.y==0 && startingClip.size.height==90);assert(startingImage.origin.y<=-30);}
 }
 puts("PASS: production opening animator uses selected page, image/video source, clipping, reference timing, reduced-motion fallback and cancellation cleanup");
}return 0;}
'''
p=runtime/'media-opening.m';p.write_text(head+animator+tail)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(p),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-lm','-o',str(runtime/'media-opening')],check=True)
subprocess.run([str(runtime/'media-opening')],check=True)
