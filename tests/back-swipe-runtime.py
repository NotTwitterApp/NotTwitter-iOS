"""Run production back gesture methods with UIKit doubles; no device physics claimed."""
from pathlib import Path
import ast, os, subprocess
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
# Reuse the exact minimal UIKit geometry/scroll doubles from the paging checks.
tree=ast.parse((root/'tests/search-paging-runtime.py').read_text())
head=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='head' for t in n.targets))
head=head.replace('UIGestureRecognizerStateEnded };','UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed };')
head=head.replace('CGPoint _velocity;','CGPoint _velocity; CGPoint _translation;')
head=head.replace('@property CGPoint velocity;','@property CGPoint velocity; @property CGPoint translation;\n- (CGPoint)translationInView:(UIView *)view;')
head=head.replace('@synthesize velocity=_velocity;','@synthesize velocity=_velocity,translation=_translation;\n- (CGPoint)translationInView:(UIView *)view {return _translation;}')
head=head.replace('CGRect _bounds;UIView *_superview;','CGRect _bounds;UIView *_superview;NSInteger _effectiveUserInterfaceLayoutDirection;')
head=head.replace('@property CGRect bounds;', '@property NSInteger effectiveUserInterfaceLayoutDirection;\n@property CGRect bounds;')
head=head.replace('@synthesize bounds=_bounds,superview=_superview;','@synthesize bounds=_bounds,superview=_superview,effectiveUserInterfaceLayoutDirection=_effectiveUserInterfaceLayoutDirection;')
policy=(root/'NFBGesturePolicy.h').read_text().replace('#import <UIKit/UIKit.h>','').replace('#pragma once','')
source=(root/'NFBMainTabBarController.m').read_text()
def method(prefix):
 a=source.index(prefix);return source[a:source.index('\n}',a)+2]
body='\n'.join(method(p) for p in [
 '- (void)nfbFullWidthBackPanned:', '- (void)nfbStopVerticalScrollingAtPoint:',
 '- (BOOL)gestureRecognizerShouldBegin:',
 '- (void)navigationController:(UINavigationController *)navigationController didShowViewController:',
])
interface=r'''
typedef double CGFloat;
enum {UIUserInterfaceLayoutDirectionRightToLeft=1,UIViewAnimationCurveEaseOut=2,UIViewAnimationCurveEaseInOut=0};
static NSString *NFBNavigationStackDidChangeNotification=@"navigation";
@interface UIPercentDrivenInteractiveTransition:NSObject {double _progress,_completionSpeed;NSInteger _completionCurve,_result;}
@property double progress,completionSpeed;@property NSInteger completionCurve,result;
- (void)updateInteractiveTransition:(CGFloat)progress; - (void)finishInteractiveTransition; - (void)cancelInteractiveTransition;
@end
@implementation UIPercentDrivenInteractiveTransition
@synthesize progress=_progress,completionSpeed=_completionSpeed,completionCurve=_completionCurve,result=_result;
- (void)updateInteractiveTransition:(CGFloat)progress{_progress=progress;}
- (void)finishInteractiveTransition{_result=1;}
- (void)cancelInteractiveTransition{_result=-1;}
@end
@interface UIViewController:NSObject @end
@implementation UIViewController @end
@interface UINavigationController:NSObject @end
@implementation UINavigationController @end
@interface Harness:NSObject {
 UIView *_view;NSArray *_viewControllers;id _transitionCoordinator,_presentedViewController,_topViewController;
 UIPanGestureRecognizer *_nfbFullWidthBackPanGestureRecognizer,*_interactivePopGestureRecognizer;
 UIPercentDrivenInteractiveTransition *_nfbBackInteraction;
 BOOL _nfbBackTransitionInFlight;NSInteger _pops,_configurations;
}
@property(retain) UIView *view;
@property(retain) NSArray *viewControllers;
@property(retain) id transitionCoordinator,presentedViewController,topViewController;
@property(retain) UIPanGestureRecognizer *nfbFullWidthBackPanGestureRecognizer,*interactivePopGestureRecognizer;
@property(retain) UIPercentDrivenInteractiveTransition *nfbBackInteraction;
@property BOOL nfbBackTransitionInFlight;
@property NSInteger pops,configurations;
@end
@implementation Harness
@synthesize view=_view,viewControllers=_viewControllers,transitionCoordinator=_transitionCoordinator,presentedViewController=_presentedViewController,topViewController=_topViewController,nfbFullWidthBackPanGestureRecognizer=_nfbFullWidthBackPanGestureRecognizer,interactivePopGestureRecognizer=_interactivePopGestureRecognizer,nfbBackInteraction=_nfbBackInteraction,nfbBackTransitionInFlight=_nfbBackTransitionInFlight,pops=_pops,configurations=_configurations;
- (void)popViewControllerAnimated:(BOOL)animated{_pops++;}
- (void)configureInteractivePopGesture{_configurations++;}
'''
tail=r'''
@end
int main(void){@autoreleasepool{
 Harness *nav=[Harness new];nav.view=[[UIView alloc] initWithFrame:NSMakeRect(0,0,400,800)];nav.viewControllers=@[@1,@2];nav.topViewController=[UIViewController new];
 UIPanGestureRecognizer *pan=[UIPanGestureRecognizer new];nav.nfbFullWidthBackPanGestureRecognizer=pan;nav.interactivePopGestureRecognizer=[UIScreenEdgePanGestureRecognizer new];
 UIScrollView *list=[[UIScrollView alloc] initWithFrame:NSMakeRect(0,0,400,800)];list.contentSize=NSMakeSize(400,4000);list.superview=nav.view;list.contentOffset=NSMakePoint(0,400);hit=list;
 pan.velocity=NSMakePoint(200,200);assert([nav gestureRecognizerShouldBegin:pan]);
 pan.velocity=NSMakePoint(200,201);assert(![nav gestureRecognizerShouldBegin:pan]);
 pan.velocity=NSMakePoint(0,0);assert(![nav gestureRecognizerShouldBegin:pan]);
 pan.velocity=NSMakePoint(200,0);nav.presentedViewController=[UIViewController new];assert(![nav gestureRecognizerShouldBegin:pan]);nav.presentedViewController=nil;
 list.contentSize=NSMakeSize(1200,800);assert(![nav gestureRecognizerShouldBegin:pan]);list.contentSize=NSMakeSize(400,4000);
 list.zoomScale=2;assert(![nav gestureRecognizerShouldBegin:pan]);list.zoomScale=1;
 UISlider *slider=[UISlider new];slider.superview=list;hit=slider;assert(![nav gestureRecognizerShouldBegin:pan]);hit=list;
 pan.state=UIGestureRecognizerStateBegan;pan.translation=NSMakePoint(12,0);[nav nfbFullWidthBackPanned:pan];
 assert(nav.pops==1 && nav.nfbBackTransitionInFlight && nav.nfbBackInteraction.progress==.03);
 assert(list.stops==1 && list.contentOffset.y==400 && list.panGestureRecognizer.enableChanges==2 && list.panGestureRecognizer.enabled);
 pan.state=UIGestureRecognizerStateChanged;pan.translation=NSMakePoint(180,0);[nav nfbFullWidthBackPanned:pan];assert(nav.nfbBackInteraction.progress==.45);
 pan.state=UIGestureRecognizerStateEnded;pan.velocity=NSMakePoint(0,0);[nav nfbFullWidthBackPanned:pan];
 assert(nav.nfbBackInteraction.result==-1 && nav.nfbBackTransitionInFlight && nav.nfbBackInteraction.completionSpeed==.99);
 assert(![nav gestureRecognizerShouldBegin:pan]);
 pan.state=UIGestureRecognizerStateBegan;[nav nfbFullWidthBackPanned:pan];assert(nav.pops==1);
 [nav navigationController:nil didShowViewController:nil animated:YES];assert(!nav.nfbBackInteraction && !nav.nfbBackTransitionInFlight && nav.configurations==1);
 pan.state=UIGestureRecognizerStateBegan;pan.translation=NSMakePoint(20,0);[nav nfbFullWidthBackPanned:pan];
 pan.state=UIGestureRecognizerStateEnded;pan.velocity=NSMakePoint(200,0);[nav nfbFullWidthBackPanned:pan];assert(nav.nfbBackInteraction.result==1);
 [nav navigationController:nil didShowViewController:nil animated:YES];
 pan.state=UIGestureRecognizerStateBegan;pan.translation=NSMakePoint(350,0);[nav nfbFullWidthBackPanned:pan];
 pan.state=UIGestureRecognizerStateCancelled;pan.velocity=NSMakePoint(900,0);[nav nfbFullWidthBackPanned:pan];assert(nav.nfbBackInteraction.result==-1);
 [nav navigationController:nil didShowViewController:nil animated:YES];
 nav.view.effectiveUserInterfaceLayoutDirection=UIUserInterfaceLayoutDirectionRightToLeft;pan.velocity=NSMakePoint(-200,0);assert([nav gestureRecognizerShouldBegin:pan]);
 pan.state=UIGestureRecognizerStateBegan;pan.translation=NSMakePoint(-240,0);[nav nfbFullWidthBackPanned:pan];assert(nav.nfbBackInteraction.progress==.6);
 pan.state=UIGestureRecognizerStateEnded;pan.velocity=NSMakePoint(0,0);[nav nfbFullWidthBackPanned:pan];assert(nav.nfbBackInteraction.result==1);
 [nav navigationController:nil didShowViewController:nil animated:YES];nav.viewControllers=@[@1];assert(![nav gestureRecognizerShouldBegin:pan]);
 puts("PASS: production back gesture gates, vertical scroll takeover, progress, cancel/finish lifetime, repeat-drag protection, modal/media conflicts and RTL");
 }return 0;}
'''
output=runtime/'back-swipe-runtime.m';output.write_text(head+policy+interface+body+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(runtime/'usr/include'),str(output),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-lgnustep-base','-lobjc','-lm','-o',str(runtime/'back-swipe-runtime')],check=True)
subprocess.run([str(runtime/'back-swipe-runtime')],check=True)
