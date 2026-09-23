"""Run the production Home chrome setup with navigation-item cleanup doubles."""
from pathlib import Path
import os,subprocess
root=Path(__file__).resolve().parents[1];r=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
s=(root/'NFBTimelineViewController.m').read_text()
a=s.index('    UIImageView *logo =',s.index('- (void)configureNavigation'))
b=s.index('  } else if (self.kind == NFBTimelineKindProfile)',a)
method='- (void)configureHomeForTest {\n'+s[a:b]+'\n}'
head=r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#define CGRectMake NSMakeRect
#define UIEdgeInsetsMake(a,b,c,d) 0
enum {UIViewContentModeScaleAspectFit,UIButtonTypeCustom,UIControlStateNormal,UIControlEventTouchUpInside};
static id NFBTemplateIcon(id name){return name;}
static BOOL NFBNeoFreeBirdColorTopBirdIcon(){return YES;}
static id NFBColorAccent(){return @"blue";}
static id NFBColorText(){return @"text";}
@interface UIView:NSObject {UIView *_superview;NSRect _frame;id _tintColor,_accessibilityLabel;NSInteger _contentMode;}
@property(assign)UIView *superview;@property NSRect frame;@property(nonatomic,retain)id tintColor,accessibilityLabel;@property NSInteger contentMode;
- (void)addSubview:(UIView *)v;- (void)removeFromSuperview;
@end
@implementation UIView
@synthesize superview=_superview,frame=_frame,tintColor=_tintColor,accessibilityLabel=_accessibilityLabel,contentMode=_contentMode;
- (void)addSubview:(UIView *)v{v.superview=self;}- (void)removeFromSuperview{self.superview=nil;}
@end
@interface UIImageView:UIView {id _image;}
@property(nonatomic,retain)id image;
- (id)initWithImage:(id)i;
@end
@implementation UIImageView
@synthesize image=_image;
- (id)initWithImage:(id)i{self=[super init];self.image=i;return self;}
@end
#define UIImage NSObject
@interface UIButton:UIView {NSInteger _imageEdgeInsets;}
@property NSInteger imageEdgeInsets;
+ (id)buttonWithType:(int)t;- (void)setImage:(id)i forState:(int)s;- (void)addTarget:(id)t action:(SEL)a forControlEvents:(int)e;
@end
@implementation UIButton
@synthesize imageEdgeInsets=_imageEdgeInsets;
+ (id)buttonWithType:(int)t{return [self new];}- (void)setImage:(id)i forState:(int)s{}- (void)addTarget:(id)t action:(SEL)a forControlEvents:(int)e{}
@end
@interface UIBarButtonItem:NSObject {UIView *_customView;}
@property(nonatomic,retain)UIView *customView;
- (id)initWithCustomView:(UIView *)v;
@end
@implementation UIBarButtonItem
@synthesize customView=_customView;
- (id)initWithCustomView:(UIView *)v{self=[super init];self.customView=v;return self;}
@end
@interface NavItem:NSObject {UIView *_titleView;UIBarButtonItem *_leftBarButtonItem,*_rightBarButtonItem;}
@property(nonatomic,retain)UIView *titleView;@property(nonatomic,retain)UIBarButtonItem *leftBarButtonItem,*rightBarButtonItem;
@end
@implementation NavItem
@synthesize titleView=_titleView,leftBarButtonItem=_leftBarButtonItem,rightBarButtonItem=_rightBarButtonItem;
// UIKit must remove old navigation content when an item is cleared. A view
// cannot safely be adopted by Home while still registered with that item.
- (void)setTitleView:(UIView *)v{[_titleView removeFromSuperview];_titleView=v;}
- (void)setLeftBarButtonItem:(UIBarButtonItem *)v{[_leftBarButtonItem.customView removeFromSuperview];_leftBarButtonItem=v;}
@end
@interface Timeline:NSObject {NavItem *_navigationItem;UIView *_header,*_left,*_right;UIImageView *_bird;}
@property(nonatomic,retain)NavItem *navigationItem;@property(nonatomic,retain)UIView *header,*left,*right;@property(nonatomic,retain)UIImageView *bird;
@end
@implementation Timeline
@synthesize navigationItem=_navigationItem,header=_header,left=_left,right=_right,bird=_bird;
- (UIView *)makeRootAccountAvatarView{return [UIView new];}
- (void)configureRootAccountAvatarButton{self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithCustomView:[self makeRootAccountAvatarView]];}
- (void)configureHomeHeaderWithLeftView:(UIView *)l titleView:(UIImageView *)b rightView:(UIView *)r {
 self.left=l;self.bird=b;self.right=r;[self.header addSubview:l];[self.header addSubview:b];[self.header addSubview:r];
}
'''
tail=r'''
@end
int main(){@autoreleasepool{
 Timeline *t=[Timeline new];t.header=[UIView new];t.navigationItem=[NavItem new];
 for(int i=0;i<3;i++){
  [t configureHomeForTest];
  assert(t.bird.superview==t.header && "clearing the native title must not remove Home's bird");
  assert(t.left.superview==t.header && t.right.superview==t.header);
  assert([t.bird.image isEqual:@"nfb_twitter_logo"] && [t.bird.tintColor isEqual:@"blue"]);
  assert(t.navigationItem.titleView==nil && t.navigationItem.leftBarButtonItem==nil);
 }
 puts("PASS: Home retains its bird, account and feed controls across initial setup and repeated theme rebuilds");
}return 0;}
'''
p=r/'home-header-ownership.m';p.write_text(head+method+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-Wno-objc-property-implementation','-I'+str(r/'usr/include'),str(p),'-L'+str(r/'usr/lib'),'-Wl,-rpath,'+str(r/'usr/lib'),'-lgnustep-base','-lobjc','-o',str(r/'home-header-ownership')],check=True)
subprocess.run([str(r/'home-header-ownership')],check=True)
