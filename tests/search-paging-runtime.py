"""Run the production paging recognizer methods against deterministic UIKit doubles.
This checks arbitration and cancellation; UIKit's native physics need a device.
"""
from pathlib import Path
import os, subprocess
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
head=r'''
#import <Foundation/Foundation.h>
#include <assert.h>
typedef NSPoint CGPoint; typedef NSRect CGRect;
#define CGRectZero NSZeroRect
#define CGPointMake NSMakePoint
#define CGRectGetWidth(r) ((r).size.width)
enum { UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded };
enum { UIScrollViewContentInsetAdjustmentNever = 2 };
@class UIView;
@protocol UIGestureRecognizerDelegate @end
@interface UIGestureRecognizer:NSObject {NSInteger _state;UIView *_view;BOOL _enabled;NSInteger _enableChanges;}
@property NSInteger state; @property(assign) UIView *view; @property(nonatomic) BOOL enabled; @property NSInteger enableChanges;
- (CGPoint)locationInView:(UIView *)view;
@end
@implementation UIGestureRecognizer
@synthesize state=_state,view=_view,enabled=_enabled,enableChanges=_enableChanges;
- (void)setEnabled:(BOOL)value {_enabled=value;_enableChanges++;}
- (CGPoint)locationInView:(UIView *)view {return CGPointMake(100,100);}
@end
@interface UIPanGestureRecognizer:UIGestureRecognizer {CGPoint _velocity;}
@property CGPoint velocity;
- (CGPoint)velocityInView:(UIView *)view;
@end
@implementation UIPanGestureRecognizer
@synthesize velocity=_velocity;
- (CGPoint)velocityInView:(UIView *)view {return _velocity;}
@end
@interface UIScreenEdgePanGestureRecognizer:UIPanGestureRecognizer @end
@implementation UIScreenEdgePanGestureRecognizer @end
static UIView *hit;
@interface UIView:NSObject {CGRect _bounds;UIView *_superview;}
@property CGRect bounds;@property(assign) UIView *superview;
- (instancetype)initWithFrame:(CGRect)frame;
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event;
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture;
@end
@implementation UIView
@synthesize bounds=_bounds,superview=_superview;
- (instancetype)initWithFrame:(CGRect)frame {self=[super init];if(self)_bounds=frame;return self;}
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event {return hit;}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {return YES;}
@end
@interface UISlider:UIView @end
@implementation UISlider @end
@interface UIScrollView:UIView {
 BOOL _pagingEnabled,_directionalLockEnabled,_showsHorizontalScrollIndicator,_showsVerticalScrollIndicator,_scrollsToTop,_scrollEnabled;
 NSInteger _contentInsetAdjustmentBehavior,_stops;
 NSSize _contentSize;CGPoint _contentOffset;double _zoomScale,_minimumZoomScale;
 UIPanGestureRecognizer *_panGestureRecognizer;
}
@property BOOL pagingEnabled,directionalLockEnabled,showsHorizontalScrollIndicator,showsVerticalScrollIndicator,scrollsToTop,scrollEnabled;
@property NSInteger contentInsetAdjustmentBehavior,stops;
@property NSSize contentSize;@property CGPoint contentOffset;@property double zoomScale,minimumZoomScale;
@property(retain) UIPanGestureRecognizer *panGestureRecognizer;
- (void)setContentOffset:(CGPoint)point animated:(BOOL)animated;
@end
@implementation UIScrollView
@synthesize pagingEnabled=_pagingEnabled,directionalLockEnabled=_directionalLockEnabled,showsHorizontalScrollIndicator=_showsHorizontalScrollIndicator,showsVerticalScrollIndicator=_showsVerticalScrollIndicator,scrollsToTop=_scrollsToTop,scrollEnabled=_scrollEnabled,contentInsetAdjustmentBehavior=_contentInsetAdjustmentBehavior,stops=_stops,contentSize=_contentSize,contentOffset=_contentOffset,zoomScale=_zoomScale,minimumZoomScale=_minimumZoomScale,panGestureRecognizer=_panGestureRecognizer;
- (instancetype)initWithFrame:(CGRect)frame {self=[super initWithFrame:frame];if(self){_panGestureRecognizer=[UIPanGestureRecognizer new];_panGestureRecognizer.view=self;_scrollEnabled=YES;_zoomScale=1;_minimumZoomScale=1;}return self;}
- (void)setContentOffset:(CGPoint)point animated:(BOOL)animated {_contentOffset=point;_stops++;}
@end
'''
policy=(root/'NFBGesturePolicy.h').read_text().replace('#import <UIKit/UIKit.h>','').replace('#pragma once','')
source=(root/'NFBSearchPagingScrollView.m').read_text()
source='\n'.join(line for line in source.splitlines() if not line.startswith('#import'))
source=source.replace('@implementation NFBSearchPagingScrollView','@implementation NFBSearchPagingScrollView\n@synthesize pageCount=_pageCount;')
interface='@interface NFBSearchPagingScrollView:UIScrollView <UIGestureRecognizerDelegate,NFBHorizontalPagingSurface> {NSInteger _pageCount;}\n@property NSInteger pageCount;\n@end\n'
tail=r'''
int main(void) {@autoreleasepool {
 NFBSearchPagingScrollView *pager=[[NFBSearchPagingScrollView alloc] initWithFrame:NSMakeRect(0,0,300,600)];pager.pageCount=5;pager.contentSize=NSMakeSize(1500,600);pager.contentOffset=CGPointMake(600,0);
 assert(pager.pagingEnabled && pager.directionalLockEnabled && !pager.scrollsToTop);
 UIScrollView *list=[[UIScrollView alloc] initWithFrame:NSMakeRect(0,0,300,600)];list.superview=pager;list.contentSize=NSMakeSize(300,3000);list.contentOffset=CGPointMake(0,750);
 UIView *row=[UIView new];row.superview=list;hit=row;
 pager.panGestureRecognizer.velocity=CGPointMake(400,200);
 assert(![pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);assert(list.stops==0);
 pager.panGestureRecognizer.velocity=CGPointMake(-401,200);
 assert([pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);
 assert(list.stops==1 && list.contentOffset.y==750 && list.panGestureRecognizer.enabled && list.panGestureRecognizer.enableChanges==2);
 UIScrollView *media=[[UIScrollView alloc] initWithFrame:NSMakeRect(0,0,250,200)];media.superview=list;media.contentSize=NSMakeSize(1000,200);hit=media;
 assert(![pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);assert(list.stops==1);
 media.contentSize=NSMakeSize(250,200);media.zoomScale=2;
 assert(![pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);
 UISlider *slider=[UISlider new];slider.superview=list;hit=slider;
 assert(![pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);
 hit=row;pager.contentOffset=CGPointMake(0,0);pager.panGestureRecognizer.velocity=CGPointMake(900,0);
 assert(![pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);
 UIView *rootView=[UIView new];pager.superview=rootView;
 // The outer pager yields full-width back at Top, while media still owns a drag.
 assert(!NFBTouchIsInHorizontalScrollerForVelocity(rootView,CGPointMake(100,100),CGPointMake(900,0)));
 assert(NFBTouchIsInHorizontalScrollerForVelocity(rootView,CGPointMake(100,100),CGPointMake(-900,0)));
 hit=media;assert(NFBTouchIsInHorizontalScrollerForVelocity(rootView,CGPointMake(100,100),CGPointMake(900,0)));
 hit=row;pager.contentOffset=CGPointMake(1200,0);pager.panGestureRecognizer.velocity=CGPointMake(-900,0);
 assert(![pager gestureRecognizerShouldBegin:pager.panGestureRecognizer]);
 assert([pager gestureRecognizer:pager.panGestureRecognizer shouldRequireFailureOfGestureRecognizer:[UIScreenEdgePanGestureRecognizer new]]);
 assert(![pager gestureRecognizer:pager.panGestureRecognizer shouldRequireFailureOfGestureRecognizer:[UIPanGestureRecognizer new]]);
 pager.panGestureRecognizer.state=UIGestureRecognizerStatePossible;
 assert([pager gestureRecognizer:pager.panGestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:list.panGestureRecognizer]);
 media.contentSize=NSMakeSize(1000,200);
 assert(![pager gestureRecognizer:pager.panGestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:media.panGestureRecognizer]);
 pager.panGestureRecognizer.state=UIGestureRecognizerStateBegan;
 assert(![pager gestureRecognizer:pager.panGestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:list.panGestureRecognizer]);
 puts("PASS: production pager gates, vertical-fling cancellation, nested media/zoom/slider priority, edge-back precedence and directional full-width back");
}return 0;}
'''
output=runtime/'search-paging-runtime.m';output.write_text(head+policy+(root/'NFBSearchPagingPolicy.h').read_text().replace('#pragma once','')+interface+source+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(runtime/'usr/include'),str(output),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-lgnustep-base','-lobjc','-lm','-o',str(runtime/'search-paging-runtime')],check=True)
subprocess.run([str(runtime/'search-paging-runtime')],check=True)
