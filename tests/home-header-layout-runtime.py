"""Run production collapse layout while protecting UIKit's navigation-bar geometry."""
from pathlib import Path
import os, subprocess
root=Path(__file__).resolve().parents[1];r=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
s=(root/'NFBTimelineViewController.m').read_text();a=s.index('- (void)applyHomeHeaderCollapse:');method=s[a:s.index('\n}',a)+2]
a=s.index('  self.homeTabsScrollView =',s.index('- (void)configureHomeTabsView'))
b=s.index('\n\n',a)
strip='- (void)configureFeedStripForTest {\n'+s[a:b]+'\n}'
head=r'''
#import <Foundation/Foundation.h>
#include <assert.h>
typedef double CGFloat;
#define CGAffineTransform NSPoint
static CGAffineTransform CGAffineTransformMakeTranslation(double x,double y){return NSMakePoint(x,y);}
#define CGRectGetHeight(r) ((r).size.height)
enum {NFBTimelineKindHome, UIScrollViewContentInsetAdjustmentNever=2};
static id NFBColorBackground(void){return nil;}
@interface View:NSObject {NSRect _bounds;NSPoint _transform;double _alpha;BOOL _userInteractionEnabled,_accessibilityElementsHidden,_translatesAutoresizingMaskIntoConstraints,_automaticallyAdjustsScrollIndicatorInsets,_showsHorizontalScrollIndicator,_alwaysBounceHorizontal,_scrollsToTop;NSInteger _contentInsetAdjustmentBehavior;id _backgroundColor;}
@property BOOL translatesAutoresizingMaskIntoConstraints,automaticallyAdjustsScrollIndicatorInsets,showsHorizontalScrollIndicator,alwaysBounceHorizontal,scrollsToTop;@property NSInteger contentInsetAdjustmentBehavior;@property(retain)id backgroundColor;
@property NSRect bounds;@property NSPoint transform;@property double alpha;@property BOOL userInteractionEnabled,accessibilityElementsHidden;
@end
@implementation View
@synthesize translatesAutoresizingMaskIntoConstraints=_translatesAutoresizingMaskIntoConstraints,automaticallyAdjustsScrollIndicatorInsets=_automaticallyAdjustsScrollIndicatorInsets,showsHorizontalScrollIndicator=_showsHorizontalScrollIndicator,alwaysBounceHorizontal=_alwaysBounceHorizontal,scrollsToTop=_scrollsToTop,contentInsetAdjustmentBehavior=_contentInsetAdjustmentBehavior,backgroundColor=_backgroundColor;
@synthesize bounds=_bounds,transform=_transform,alpha=_alpha,userInteractionEnabled=_userInteractionEnabled,accessibilityElementsHidden=_accessibilityElementsHidden;
@end
#define UINavigationBar View
#define UIScrollView View
@interface Constraint:NSObject {double _constant;}
@property double constant;
@end
@implementation Constraint
@synthesize constant=_constant;
@end
@interface Nav:NSObject {View *_navigationBar;}
@property(retain)View *navigationBar;
@end
@implementation Nav
@synthesize navigationBar=_navigationBar;
@end
@interface Timeline:NSObject {NSInteger _kind;double _homeHeaderCollapse;Nav *_navigationController;Constraint *_homeTabsTopConstraint,*_homeHeaderHeightConstraint;View *_homeHeaderContentView,*_homeTabsScrollView;}
@property(retain)View *homeTabsScrollView;
@property NSInteger kind;@property double homeHeaderCollapse;@property(retain)Nav *navigationController;
@property(retain)Constraint *homeTabsTopConstraint,*homeHeaderHeightConstraint;@property(retain)View *homeHeaderContentView;
@end
@implementation Timeline
@synthesize homeTabsScrollView=_homeTabsScrollView;
@synthesize kind=_kind,homeHeaderCollapse=_homeHeaderCollapse,navigationController=_navigationController,homeTabsTopConstraint=_homeTabsTopConstraint,homeHeaderHeightConstraint=_homeHeaderHeightConstraint,homeHeaderContentView=_homeHeaderContentView;
- (double)homeNavigationHeight{return 44;}
'''
tail=r'''
@end
int main(){@autoreleasepool{
 Timeline *t=[Timeline new];t.navigationController=[Nav new];View *bar=[View new];bar.bounds=NSMakeRect(0,0,390,44);bar.alpha=1;t.navigationController.navigationBar=bar;
 [t configureFeedStripForTest];
 assert(t.homeTabsScrollView.contentInsetAdjustmentBehavior==UIScrollViewContentInsetAdjustmentNever && "horizontal feed labels must never inherit vertical navigation insets");
 t.homeTabsTopConstraint=[Constraint new];t.homeHeaderHeightConstraint=[Constraint new];t.homeHeaderContentView=[View new];
 // Repeated collapse -> interrupted horizontal swipe -> expand must never move
 // UIKit's bar or subtract collapse a second time from the safe-area guide.
 double offsets[]={44,21,0,44,0,12,0};
 for(int i=0;i<7;i++){
  [t applyHomeHeaderCollapse:offsets[i]];
  assert(bar.transform.y==0 && bar.alpha==1 && "Home collapse must not mutate the navigation controller's bar");
  assert(t.homeTabsTopConstraint.constant==0 && "feed labels must not be moved above the safe-area guide");
  assert(t.homeHeaderHeightConstraint.constant==44-offsets[i]);
  assert(t.homeHeaderContentView.alpha==1-offsets[i]/44);
 }
 puts("PASS: repeated collapse/interruption/reveal uses one header height, preserves native bar geometry and restores content opacity");
}return 0;}
'''
p=r/'home-header-layout.m';p.write_text(head+method+strip+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(r/'usr/include'),str(p),'-L'+str(r/'usr/lib'),'-Wl,-rpath,'+str(r/'usr/lib'),'-lgnustep-base','-lobjc','-lm','-o',str(r/'home-header-layout')],check=True)
subprocess.run([str(r/'home-header-layout')],check=True)
