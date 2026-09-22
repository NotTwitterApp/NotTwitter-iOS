"""Run the production cell reply-context method for ordinary timeline feed items."""
from pathlib import Path
import os,re,subprocess
root=Path(__file__).resolve().parents[1];runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
s=(root/'NFBPostCell.m').read_text();a=s.index('- (NSAttributedString *)replyContextAttributedStringForFeedItem:');method=s[a:s.index('\n}',a)+2]
method=re.sub(r'(\w+)\[(@"[^"\n]+")\]',r'[\1 objectForKey:\2]',method)
head=r'''
#import <Foundation/Foundation.h>
static NSString *NSForegroundColorAttributeName=@"color",*NSFontAttributeName=@"font";
static id NFBColorSecondaryText(void){return @"gray";} static id NFBColorAccent(void){return @"blue";}
static int NFBIPAMetricTimelineMetaFontSize=15,NFBFontWeightRegular=0;
static double NFBIPAMetricValue(int x){return x;}static id NFBFont(double s,int w){return @"font";}
@interface Label:NSObject
- (id)font;
@end
@implementation Label
- (id)font{return @"font";}
@end
@interface NFBAtprotoClient:NSObject
+ (NSDictionary *)replyParentPostFromFeedItem:(NSDictionary *)item;
+ (NSString *)handleForProfile:(NSDictionary *)p;
@end
@implementation NFBAtprotoClient
+ (NSDictionary *)replyParentPostFromFeedItem:(NSDictionary *)item{return [item objectForKey:@"replyParentPost"] ?: [[item objectForKey:@"reply"] objectForKey:@"parent"] ?: @{};}
+ (NSString *)handleForProfile:(NSDictionary *)p{return [p objectForKey:@"handle"] ?: @"";}
@end
@interface Cell:NSObject
- (Label *)replyContextLabel;
@end
@implementation Cell
- (Label *)replyContextLabel{return [Label new];}
'''
tail=r'''
@end
int main(void){@autoreleasepool {
 Cell *cell=[Cell new];NSDictionary *post=@{@"record":@{@"text":@"this did it for me",@"reply":@{@"parent":@{@"uri":@"at://did:plc:parent/app.bsky.feed.post/one"}}}};
 NSDictionary *item=@{@"post":post,@"reply":@{@"parent":@{@"author":@{@"handle":@"vamospeat.bsky.social"}}}};
 NSString *display=[[cell replyContextAttributedStringForFeedItem:item post:post] string];
 if(![display isEqual:@"Replying to @vamospeat.bsky.social"]){fprintf(stderr,"FAIL: ordinary timeline reply displays %s, expected Replying to @vamospeat.bsky.social\n",[display UTF8String] ?: "nothing");return 1;}
 NSMutableDictionary *thread=[item mutableCopy];[thread setObject:@(NO) forKey:@"_nfbShowReplyContext"];
 if([cell replyContextAttributedStringForFeedItem:thread post:post])return 2;
 if([cell replyContextAttributedStringForFeedItem:@{} post:@{@"record":@{@"text":@"not a reply"}}])return 3;
 if(![[[cell replyContextAttributedStringForFeedItem:@{} post:post] string] isEqual:@"Replying to a post"])return 4;
 [thread setObject:@(YES) forKey:@"_nfbShowReplyContext"];
 if(![[[cell replyContextAttributedStringForFeedItem:thread post:post] string] isEqual:display])return 5;
 NSDictionary *hydrated=@{@"replyParentPost":@{@"author":@{@"handle":@"parent.example"}}};
 if(![[[cell replyContextAttributedStringForFeedItem:hydrated post:post] string] isEqual:@"Replying to @parent.example"])return 6;
 puts("PASS: ordinary timeline replies show parent context, explicit thread suppression and non-replies remain hidden");
}return 0;}
'''
p=runtime/'timeline-reply-context.m';p.write_text(head+method+tail)
subprocess.run(['clang','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(runtime/'usr/include'),str(p),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-lgnustep-base','-lobjc','-o',str(runtime/'timeline-reply-context')],check=True)
subprocess.run([str(runtime/'timeline-reply-context')],check=True)
