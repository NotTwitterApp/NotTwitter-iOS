"""Exercise the production scroll callback during horizontal paging/reload callbacks."""
from pathlib import Path
import os, subprocess
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
s=(root/'NFBTimelineViewController.m').read_text()
a=s.index('- (void)scrollViewDidScroll:')
method=s[a:s.index('\n}',a)+2]
a=s.index('  UIView *outgoingSnapshot =',s.index('- (void)finishHomeFeedPanToIndex:'))
b=s.index('\n  [self cacheCurrentHomeFeedState];',a)
snapshot='- (UIScrollView *)outgoingSnapshotForTest {\n'+s[a:b]+'\nreturn outgoingSnapshot;\n}'
head=r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include "NFBChromeGeometry.h"
typedef double CGFloat;
#define UIView UIScrollView
#define CGRectMake NSMakeRect
#define CGRectGetWidth(r) ((r).size.width)
#define CGRectGetHeight(r) ((r).size.height)
enum {NFBTimelineKindHome=0};
static NSInteger NFBSearchPageForOffset(double x,double w,NSInteger n){return 0;}
@interface Pan:NSObject {NSPoint _translation;}
@property NSPoint translation;
- (NSPoint)translationInView:(id)v;
@end
@implementation Pan
@synthesize translation=_translation;
- (NSPoint)translationInView:(id)v{return _translation;}
@end
@interface UIScrollView:NSObject {NSPoint _contentOffset,_center,_transform;NSSize _contentSize;NSRect _bounds;BOOL _dragging;Pan *_panGestureRecognizer;}
@property NSPoint center,transform;@property NSRect frame;
- (UIScrollView *)snapshotViewAfterScreenUpdates:(BOOL)b;
@property NSPoint contentOffset;@property NSSize contentSize;@property NSRect bounds;@property BOOL dragging;@property(retain) Pan *panGestureRecognizer;
@end
@implementation UIScrollView
@synthesize center=_center,transform=_transform;
- (NSRect)frame{return NSMakeRect(_center.x-_bounds.size.width/2+_transform.x,_center.y-_bounds.size.height/2+_transform.y,_bounds.size.width,_bounds.size.height);}
- (void)setFrame:(NSRect)f{_bounds=NSMakeRect(0,0,f.size.width,f.size.height);_center=NSMakePoint(f.origin.x+f.size.width/2,f.origin.y+f.size.height/2);}
- (UIScrollView *)snapshotViewAfterScreenUpdates:(BOOL)b{return [UIScrollView new];}
@synthesize contentOffset=_contentOffset,contentSize=_contentSize,bounds=_bounds,dragging=_dragging,panGestureRecognizer=_panGestureRecognizer;
@end
@interface Nav:NSObject {id _topViewController;UIScrollView *_navigationBar;}
@property(assign)id topViewController;@property(retain)UIScrollView *navigationBar;
@end
@implementation Nav
@synthesize topViewController=_topViewController,navigationBar=_navigationBar;
@end
@interface Refresh:NSObject {BOOL _refreshing;}
@property BOOL refreshing;
@end
@implementation Refresh
@synthesize refreshing=_refreshing;
@end
@interface Timeline:NSObject {
 UIScrollView *_tableView,*_searchPager,*_searchTabsScrollView,*_homeFeedPreviewTableView;
 NSArray *_searchPages;Nav *_navigationController;Refresh *_refreshControl;
 BOOL _homeFeedPanTracking,_homeFeedSwitchAnimating,_homeHeaderDragging;
 CGFloat _homeHeaderCollapse,_homeHeaderLastPanY;NSInteger _kind,_changes;
}
@property(retain)UIScrollView *tableView,*searchPager,*searchTabsScrollView,*homeFeedPreviewTableView;
@property(retain)NSArray *searchPages;@property(retain)Nav *navigationController;@property(retain)Refresh *refreshControl;
@property BOOL homeFeedPanTracking,homeFeedSwitchAnimating,homeHeaderDragging;
@property CGFloat homeHeaderCollapse,homeHeaderLastPanY;@property NSInteger kind,changes;
@end
@implementation Timeline
@synthesize tableView=_tableView,searchPager=_searchPager,searchTabsScrollView=_searchTabsScrollView,homeFeedPreviewTableView=_homeFeedPreviewTableView;
@synthesize searchPages=_searchPages,navigationController=_navigationController,refreshControl=_refreshControl;
@synthesize homeFeedPanTracking=_homeFeedPanTracking,homeFeedSwitchAnimating=_homeFeedSwitchAnimating,homeHeaderDragging=_homeHeaderDragging;
@synthesize homeHeaderCollapse=_homeHeaderCollapse,homeHeaderLastPanY=_homeHeaderLastPanY,kind=_kind,changes=_changes;
- (double)homeNavigationHeight{return 44;}
- (id)view{return self;}
- (void)addSubview:(id)v{}
- (void)loadSearchPagesNearIndex:(NSInteger)i{}
- (void)updateSearchPageIndicator{}
- (void)updateFeedNavigationForScrollOffset{}
- (void)updateProfileNavigationForScrollOffset{}
- (void)applyHomeHeaderCollapse:(CGFloat)c{self.homeHeaderCollapse=c;self.changes++;}
'''
tail=r'''
@end
int main(void){@autoreleasepool{
 Timeline *t=[Timeline new];UIScrollView *v=[UIScrollView new];t.tableView=v;
 v.bounds=NSMakeRect(0,0,390,700);v.contentSize=NSMakeSize(390,2400);v.panGestureRecognizer=[Pan new];
 t.navigationController=[Nav new];t.navigationController.topViewController=t;
 t.navigationController.navigationBar=[UIScrollView new];t.navigationController.navigationBar.bounds=NSMakeRect(0,0,390,44);
 t.refreshControl=[Refresh new];
 // The source is already translated by the drag when the release snapshot is captured.
 v.center=NSMakePoint(195,450);v.transform=NSMakePoint(-120,0);
 UIScrollView *outgoing=[t outgoingSnapshotForTest];
 assert(outgoing.center.x==v.center.x && outgoing.center.y==v.center.y);
 assert(outgoing.frame.origin.x==-120 && "outgoing snapshot must apply the drag transform exactly once");
 // A destination reload clamps offset to zero while the horizontal transition is active.
 for(int phase=0;phase<2;phase++){
  t.homeHeaderCollapse=44;t.homeFeedPanTracking=phase==0;t.homeFeedSwitchAnimating=phase==1;
  v.contentOffset=NSMakePoint(0,0);[t scrollViewDidScroll:v];
  assert(t.homeHeaderCollapse==44 && "horizontal feed reload must not pop the hidden header open");
  t.refreshControl.refreshing=YES;[t scrollViewDidScroll:v];
  assert(t.homeHeaderCollapse==44 && "destination loading must not move shared chrome mid-swipe");
  t.refreshControl.refreshing=NO;
 }
 t.homeFeedPanTracking=NO;t.homeFeedSwitchAnimating=NO;
 // After paging has settled, the new feed at the top expands normally.
 [t scrollViewDidScroll:v];assert(t.homeHeaderCollapse==0);
 // Direction reversal continues to work during a genuine vertical drag.
 t.homeHeaderCollapse=44;t.homeHeaderDragging=YES;v.dragging=YES;v.contentOffset=NSMakePoint(0,100);
 v.panGestureRecognizer.translation=NSMakePoint(0,10);t.homeHeaderLastPanY=0;
 [t scrollViewDidScroll:v];assert(t.homeHeaderCollapse==34);
 puts("PASS: hidden header stays fixed during horizontal drag/settle reloads and refresh, then vertical scrolling resumes; outgoing snapshot applies the horizontal transform once");
}return 0;}
'''
p=runtime/'home-header-paging.m';p.write_text(head+method+snapshot+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(p),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-lgnustep-base','-lobjc','-lm','-o',str(runtime/'home-header-paging')],check=True)
subprocess.run([str(runtime/'home-header-paging')],check=True)
