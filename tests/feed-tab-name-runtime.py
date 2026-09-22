"""Run the actual feed-tab tap handler with deterministic UIKit layout doubles."""
from pathlib import Path
import os,subprocess
root=Path(__file__).resolve().parents[1];runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
s=(root/'NFBTimelineViewController.m').read_text();a=s.index('- (void)homeFeedTabTapped:');method=s[a:s.index('\n}',a)+2]
a=s.index('- (void)collapseInactiveHomeFeedTabs');method=s[a:s.index('\n}',a)+2]+'\n'+method
assert '[self collapseInactiveHomeFeedTabs];' in s.split('- (void)updateHomeTabsSelection {',1)[1].split('\n}',1)[0]
head=r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <math.h>
typedef NSRect CGRect;
typedef struct {double top,left,bottom,right;} UIEdgeInsets;
#define CGRectGetWidth(r) ((r).size.width)
static NSString *NSFontAttributeName=@"font";
enum {UIControlStateNormal};
@interface NSString(Measure)
- (NSSize)sizeWithAttributes:(id)a;
@end
@implementation NSString(Measure)
- (NSSize)sizeWithAttributes:(id)a{return NSMakeSize(self.length*8,18);}
@end
@interface Label:NSObject
- (id)font;
@end
@implementation Label
- (id)font{return @"font";}
@end
@interface NSLayoutConstraint:NSObject {NSString *_identifier;double _constant;}
@property(copy)NSString *identifier;@property double constant;
@end
@implementation NSLayoutConstraint
@synthesize identifier=_identifier,constant=_constant;
@end
@interface UIButton:NSObject {NSString *_title;NSInteger _tag;double _available;NSArray *_constraints;}
@property(copy)NSString *title;@property NSInteger tag;@property double available;@property(retain)NSArray *constraints;
- (void)layoutIfNeeded;- (id)titleForState:(int)s;- (Label *)titleLabel;- (NSRect)bounds;- (NSRect)contentRectForBounds:(NSRect)b;
- (NSRect)frame;- (UIEdgeInsets)contentEdgeInsets;
@end
@implementation UIButton
@synthesize title=_title,tag=_tag,available=_available,constraints=_constraints;
- (void)layoutIfNeeded{}- (id)titleForState:(int)s{return self.title;}- (Label *)titleLabel{return [Label new];}
- (NSRect)bounds{return NSMakeRect(0,0,176,53);}- (NSRect)contentRectForBounds:(NSRect)b{return NSMakeRect(16,0,self.available,53);}
- (NSRect)frame{return NSMakeRect(200,0,MAX(176,[[self.constraints firstObject] constant]),53);}
- (UIEdgeInsets)contentEdgeInsets{return (UIEdgeInsets){0,16,0,16};}
@end
@interface Strip:NSObject {NSRect _scrolledRect;NSInteger _layouts,_scrolls;}
@property NSRect scrolledRect;@property NSInteger layouts,scrolls;
- (void)layoutIfNeeded;- (NSRect)bounds;- (void)scrollRectToVisible:(NSRect)r animated:(BOOL)a;
@end
@implementation Strip
@synthesize scrolledRect=_scrolledRect,layouts=_layouts,scrolls=_scrolls;
- (void)layoutIfNeeded{_layouts++;}- (NSRect)bounds{return NSMakeRect(0,0,390,53);}
- (void)scrollRectToVisible:(NSRect)r animated:(BOOL)a{_scrolledRect=r;_scrolls++;}
@end
@interface Timeline:NSObject {NSInteger _selectedHomeFeedIndex,_switches;Strip *_homeTabsView,*_homeTabsScrollView;NSArray *_homeTabButtons;}
@property(retain)NSArray *homeTabButtons;
@property NSInteger selectedHomeFeedIndex,switches;@property(retain)Strip *homeTabsView,*homeTabsScrollView;
@end
@implementation Timeline
@synthesize homeTabButtons=_homeTabButtons;
@synthesize selectedHomeFeedIndex=_selectedHomeFeedIndex,switches=_switches,homeTabsView=_homeTabsView,homeTabsScrollView=_homeTabsScrollView;
- (void)switchToHomeFeedIndex:(NSInteger)i direction:(int)d animated:(BOOL)a{self.selectedHomeFeedIndex=i;self.switches++;[self collapseInactiveHomeFeedTabs];}
// Any attempt to show a popup is a regression.
- (void)presentViewController:(id)c animated:(BOOL)a completion:(id)b{assert(0 && "No feed-name popup");}
'''
tail=r'''
@end
int main(void){@autoreleasepool{
 for(int mode=0;mode<4;mode++){
  Timeline *t=[Timeline new];t.homeTabsView=[Strip new];t.homeTabsScrollView=[Strip new];
  UIButton *b=[UIButton new];b.tag=mode==1 || mode==3 ? 1:0;
  b.title=mode<2 ? @"A very long feed name that must remain readable" : @"For you";b.available=144;
  NSLayoutConstraint *min=[NSLayoutConstraint new];min.identifier=@"nfbFeedTabMinimumWidth";min.constant=128;
  NSLayoutConstraint *max=[NSLayoutConstraint new];max.identifier=@"nfbFeedTabMaximumWidth";max.constant=176;
  NSLayoutConstraint *other=[NSLayoutConstraint new];other.identifier=@"unrelated";other.constant=53;b.constraints=@[min,max,other];t.homeTabButtons=@[b];
  [t homeFeedTabTapped:b];
  assert(t.selectedHomeFeedIndex==b.tag);assert(t.switches==(mode==1 || mode==3));assert(other.constant==53);
  if(mode<2){
   assert(min.constant==b.title.length*8+32 && max.constant==min.constant);
   assert(t.homeTabsView.layouts==1 && t.homeTabsScrollView.scrolls==1);
   assert(t.homeTabsScrollView.scrolledRect.origin.x==200 && t.homeTabsScrollView.scrolledRect.size.width<=390);
   b.available=min.constant-32;[t homeFeedTabTapped:b];assert(t.homeTabsView.layouts==1);
   [t collapseInactiveHomeFeedTabs];assert(min.constant>176); // Current feed stays expanded.
   [t switchToHomeFeedIndex:b.tag+1 direction:1 animated:YES];
   assert(min.constant==128 && max.constant==176 && other.constant==53);
   // Returning by swipe/programmatic selection does not re-expand the old title.
   t.selectedHomeFeedIndex=b.tag;[t collapseInactiveHomeFeedTabs];assert(max.constant==176);
   b.available=144;[t homeFeedTabTapped:b];assert(min.constant==b.title.length*8+32);
  }else{assert(min.constant==128 && max.constant==176);assert(t.homeTabsView.layouts==0);}
 }
 puts("PASS: selected/unselected truncated tabs expand in place; switching collapses old titles, returning stays shortened, repeat taps and leading-edge scrolling remain correct");
}return 0;}
'''
p=runtime/'feed-tab-name.m';p.write_text(head+method+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(runtime/'usr/include'),str(p),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-lgnustep-base','-lobjc','-lm','-o',str(runtime/'feed-tab-name')],check=True)
subprocess.run([str(runtime/'feed-tab-name')],check=True)
