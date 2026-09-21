"""Execute production chat pagination callbacks against a delayed transport.
No network or UIKit rendering: verifies request races, cursors, and reading anchors.
"""
from pathlib import Path
import os, re, subprocess
root=Path(__file__).resolve().parents[1]
runtime=Path(os.environ.get('NFB_OBJC_TEST_RUNTIME','/tmp/nfb-objc-test-runtime'))
source=(root/'NFBMessagesViewController.m').read_text()
def method(name):
    a=source.index(name)
    return source[a:source.index('\n}',a)+2]
def legacy(s):
    # The GNU runtime supports Foundation, but not modern subscripting syntax.
    s=re.sub(r'(\w+)\[([^\]\n]+)\] = ([^;\n]+);',r'[\1 setObject:\3 forKey:\2];',s)
    s=re.sub(r'(\w+)\[(@"[^"\n]+"|messageID|fallbackKey|conversationID)\]',r'[\1 objectForKey:\2]',s)
    s=s.replace('_messageRowFrames[NFBStringValue(anchor[@"id"])]','[_messageRowFrames objectForKey:NFBStringValue([anchor objectForKey:@"id"])]')
    # Inner literal-key conversion may already have happened.
    s=s.replace('_messageRowFrames[NFBStringValue([anchor objectForKey:@"id"])]','[_messageRowFrames objectForKey:NFBStringValue([anchor objectForKey:@"id"]) ]')
    return s
methods='\n'.join(method(n) for n in [
 '- (void)loadOlderMessagesIfNeeded {','- (NSDictionary *)visibleMessageAnchor {','- (void)restoreVisibleMessageAnchor:',
 '- (void)retryOlderMessages {','- (void)loadConversations {','- (void)loadMoreConversationsIfNeeded {','- (void)retryMoreConversations {',
 '- (void)saveMessageCache {','- (void)saveConversationListCache {',
])
helpers='\n'.join(method(n) for n in ['static NSArray<NSDictionary *> *NFBSortedChatMessages(', 'static NSArray<NSDictionary *> *NFBMergedChatMessages(', 'static NSArray<NSDictionary *> *NFBMergedChatConversations('])
head=r'''
#import <Foundation/Foundation.h>
#import "NFBChatPagination.h"
#include <assert.h>
typedef NSRect CGRect; typedef NSPoint CGPoint; typedef double CGFloat;
#define CGRectGetMaxY NSMaxY
#define CGRectValue rectValue
#define CGPointMake NSMakePoint
static void dispatch_async(int queue, void (^block)(void)) {block();}
static int dispatch_get_main_queue(void){return 0;}
typedef void (^NFBAtprotoArrayCompletion)(NSArray *,NSString *,NSError *);
@interface View:NSObject {BOOL _hidden;CGPoint _contentOffset;}
@property BOOL hidden;@property CGPoint contentOffset;
- (void)reloadData; - (void)layoutIfNeeded; - (void)endRefreshing;
@end
@implementation View
@synthesize hidden=_hidden,contentOffset=_contentOffset;
- (void)reloadData{} - (void)layoutIfNeeded{} - (void)endRefreshing{}
@end
static void NFBStartLoadingAnimation(id v){} static void NFBStopLoadingAnimation(id v){} static void NFBPlaySound(id v){}
static NSString *NFBStringValue(id v){return [v isKindOfClass:NSString.class]?v:@"";}
static NSString *NFBChatMessageID(NSDictionary *v){return NFBStringValue([v objectForKey:@"id"]);}
static NSString *NFBChatConversationID(NSDictionary *v){return NFBChatMessageID(v);}
static NSString *NFBChatMessageSentAt(NSDictionary *v){return NFBStringValue([v objectForKey:@"sentAt"]);}
static NSString *NFBChatMessageSenderDID(NSDictionary *v){return NFBStringValue([v objectForKey:@"sender"]);}
static NSString *NFBChatMessageText(NSDictionary *v){return NFBStringValue([v objectForKey:@"text"]);}
static NSDictionary *NFBChatLastMessage(NSDictionary *v){return [v objectForKey:@"lastMessage"];}
static NSArray *NFBChatConversationsForList(NSArray *v,BOOL requests){return v;}
static NSArray *NFBChatLimitedDictionaries(NSArray *v,NSUInteger limit){return NFBChatCacheSlice(v,limit,NO);}
static NSDictionary *savedCache;
static void NFBChatSaveCacheNamed(NSString *name,NSDictionary *v){savedCache=v;}
@interface NFBAtprotoSession:NSObject {NSUInteger _accountGeneration;}
@property NSUInteger accountGeneration;
+ (instancetype)sharedSession; - (BOOL)hasSession;
@end
@implementation NFBAtprotoSession
@synthesize accountGeneration=_accountGeneration;
+ (instancetype)sharedSession {static id s;if(!s)s=[self new];return s;}
- (BOOL)hasSession{return YES;}
@end
@interface NFBNotificationCoordinator:NSObject
+ (instancetype)sharedCoordinator; - (void)refreshMessageBadge;
@end
@implementation NFBNotificationCoordinator
+ (instancetype)sharedCoordinator {return [self new];} - (void)refreshMessageBadge{}
@end
static NSMutableArray *requests;
@interface NFBAtprotoClient:NSObject
+ (instancetype)sharedClient;
- (void)fetchChatMessagesForConversationID:(NSString *)cid cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchChatConversationsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
- (void)fetchChatConversationRequestsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion;
@end
static void Enqueue(NSString *kind,NSString *cursor,NFBAtprotoArrayCompletion completion) {
 [requests addObject:@{@"kind":kind,@"cursor":cursor?:@"",@"callback":[NSValue valueWithPointer:Block_copy(completion)]}];
}
static void Finish(NSUInteger index,NSArray *items,NSString *cursor,NSError *error) {
 NFBAtprotoArrayCompletion callback=[[[requests objectAtIndex:index] objectForKey:@"callback"] pointerValue];
 [requests removeObjectAtIndex:index];callback(items,cursor,error);Block_release(callback);
}
@implementation NFBAtprotoClient
+ (instancetype)sharedClient {static id s;if(!s)s=[self new];return s;}
- (void)fetchChatMessagesForConversationID:(NSString *)cid cursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)c {Enqueue(@"history",cursor,c);}
- (void)fetchChatConversationsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)c {Enqueue(@"inbox",cursor,c);}
- (void)fetchChatConversationRequestsWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)c {Enqueue(@"requests",cursor,c);}
@end
'''
interface=r'''
@interface Harness:NSObject { @public
 BOOL _loading,_loadingMoreMessages,_olderMessagesFailed,_loadingMoreConversations,_moreConversationsFailed,_showingRequests,_refreshSuccessSoundPending;
 NSUInteger _messageLoadGeneration,_conversationListGeneration,_owner,scheduledHistory,scheduledInbox;
 NSString *_cursor;NSDictionary *_conversation;
 NSArray *_messages,*_conversations;
 NSMutableSet *_consumedMessageCursors,*_consumedConversationCursors;
 NSMutableDictionary *_messageRowFrames;
 View *_messageScrollView,*_tableView,*_loadingView,*_emptyTitleLabel,*_emptySubtitleLabel,*_refreshControl;
}
- (void)loadOlderMessagesIfNeeded; - (void)loadMoreConversationsIfNeeded; - (void)loadConversations;
- (NSDictionary *)visibleMessageAnchor; - (void)restoreVisibleMessageAnchor:(NSDictionary *)anchor;
@end
@implementation Harness
- (instancetype)init {self=[super init];if(self){
 _owner=[NFBAtprotoSession sharedSession].accountGeneration;_conversation=@{@"id":@"chat"};_messages=@[];_conversations=@[];
 _consumedMessageCursors=[NSMutableSet new];_consumedConversationCursors=[NSMutableSet new];_messageRowFrames=[NSMutableDictionary new];
 _messageScrollView=[View new];_tableView=[View new];_loadingView=[View new];_emptyTitleLabel=[View new];_emptySubtitleLabel=[View new];_refreshControl=[View new];
 }return self;}
- (BOOL)ownsCurrentAccount{return _owner==[NFBAtprotoSession sharedSession].accountGeneration;}
- (void)hydrateSharedPostsForCurrentMessages{}
- (void)scheduleOlderMessagePrefetch{scheduledHistory++;}
- (void)scheduleConversationPrefetch{scheduledInbox++;}
- (void)updateConversationPagingFooter{}
- (void)applySearchFilter{}
- (void)loadCachedConversationsIfAvailable{}
- (NSDictionary *)visibleConversationAnchor{return nil;}
- (void)restoreVisibleConversationAnchor:(NSDictionary *)anchor{}
- (NSString *)messageCacheName{return @"history";}
- (NSString *)conversationListCacheName{return @"inbox";}
- (void)setMessageScrollOffsetY:(CGFloat)y animated:(BOOL)animated{_messageScrollView.contentOffset=NSMakePoint(0,y);}
- (void)reloadRenderedMessages {
 [_messageRowFrames removeAllObjects];double y=_cursor.length?38:8;
 for(NSDictionary *message in _messages){
  double height=[[message objectForKey:@"height"] doubleValue];if(!height)height=100;
  [_messageRowFrames setObject:[NSValue valueWithRect:NSMakeRect(0,y,300,height)] forKey:NFBChatMessageID(message)];y+=height;
 }
}
'''
tail=r'''
@end
static NSDictionary *Message(NSString *i){return @{@"id":i,@"sentAt":i,@"height":@100};}
static NSDictionary *Convo(NSString *i){return @{@"id":i,@"lastMessage":Message(i)};}
int main(void) {@autoreleasepool {
 requests=[NSMutableArray new];[NFBAtprotoSession sharedSession].accountGeneration=1;
 Harness *h=[Harness new];h->_cursor=@"A";h->_messages=@[Message(@"20"),Message(@"30"),Message(@"40")];[h reloadRenderedMessages];h->_messageScrollView.contentOffset=NSMakePoint(0,80);
 [h loadOlderMessagesIfNeeded];[h loadOlderMessagesIfNeeded];assert(requests.count==1);
 // Scroll while waiting; append a new message before the older-page response.
 h->_messages=@[Message(@"20"),Message(@"30"),Message(@"40"),Message(@"50")];[h reloadRenderedMessages];h->_messageScrollView.contentOffset=NSMakePoint(0,180);
 Finish(0,@[Message(@"00"),Message(@"10"),Message(@"20")],@"B",nil);
 assert(h->_messages.count==6 && h->_messageScrollView.contentOffset.y==380);
 assert([[[h visibleMessageAnchor] objectForKey:@"id"] isEqual:@"30"]);
 [h loadOlderMessagesIfNeeded];Finish(0,@[],@"C",nil);assert([h->_cursor isEqual:@"C"]);
 [h loadOlderMessagesIfNeeded];Finish(0,@[Message(@"00")],@"A",nil);assert(h->_cursor==nil);[h loadOlderMessagesIfNeeded];assert(requests.count==0);
 assert(h->_messageScrollView.contentOffset.y==350);
 h->_cursor=@"retry";[h reloadRenderedMessages];h->_messageScrollView.contentOffset=NSMakePoint(0,380);[h loadOlderMessagesIfNeeded];NSError *offline=[NSError errorWithDomain:@"network" code:-1009 userInfo:nil];Finish(0,nil,nil,offline);
 assert(h->_olderMessagesFailed && [h->_cursor isEqual:@"retry"]);[h loadOlderMessagesIfNeeded];assert(requests.count==0);
 [h retryOlderMessages];assert(requests.count==1);Finish(0,@[],nil,nil);assert(!h->_loadingMoreMessages && !h->_olderMessagesFailed && h->_cursor==nil);
 // Removing the 30pt paging header retains the same visible message and offset within it.
 assert(h->_messageScrollView.contentOffset.y==350);
 h->_cursor=@"stale";[h loadOlderMessagesIfNeeded];h->_messageLoadGeneration++;h->_loadingMoreMessages=NO;h->_cursor=@"fresh";Finish(0,@[Message(@"-1")],@"bad",nil);assert([h->_cursor isEqual:@"fresh"] && h->_messages.count==6);
 // Refresh supersedes an in-flight older inbox page, in either completion order.
 for(int olderFirst=0;olderFirst<2;olderFirst++){
  Harness *list=[Harness new];list->_cursor=@"old";list->_conversations=@[Convo(@"10")];[list loadMoreConversationsIfNeeded];[list loadConversations];assert(requests.count==2);
  if(olderFirst) {Finish(0,@[Convo(@"01")],@"bad",nil);assert(list->_loading);Finish(0,@[Convo(@"20")],@"new",nil);}
  else {Finish(1,@[Convo(@"20")],@"new",nil);Finish(0,@[Convo(@"01")],@"bad",nil);}
  assert([list->_cursor isEqual:@"new"] && list->_conversations.count==2 && !list->_loadingMoreConversations);
  [list loadMoreConversationsIfNeeded];[list loadMoreConversationsIfNeeded];assert(requests.count==1);Finish(0,@[],@"next",nil);assert([list->_cursor isEqual:@"next"]);
  [list loadMoreConversationsIfNeeded];Finish(0,@[Convo(@"10")],@"new",nil);assert(list->_cursor==nil);
  list->_cursor=@"retry-list";[list loadMoreConversationsIfNeeded];Finish(0,nil,nil,offline);[list loadMoreConversationsIfNeeded];assert(requests.count==0 && list->_moreConversationsFailed);
  [list retryMoreConversations];assert(requests.count==1);Finish(0,@[],nil,nil);assert(!list->_moreConversationsFailed);
 }
 // Switching inbox/request generations and accounts ignores outstanding callbacks.
 Harness *list=[Harness new];list->_cursor=@"old";[list loadMoreConversationsIfNeeded];list->_showingRequests=YES;list->_conversationListGeneration++;list->_loadingMoreConversations=NO;list->_cursor=@"request-page";Finish(0,@[Convo(@"bad")],@"bad",nil);assert([list->_cursor isEqual:@"request-page"] && list->_conversations.count==0);
 [list loadMoreConversationsIfNeeded];assert([[[requests lastObject] objectForKey:@"kind"] isEqual:@"requests"]);[NFBAtprotoSession sharedSession].accountGeneration++;Finish(0,@[Convo(@"wrong-account")],nil,nil);assert(list->_conversations.count==0);
 [NFBAtprotoSession sharedSession].accountGeneration=1;
 // Bounded caches preserve newest messages and never save a cursor below omitted rows.
 NSMutableArray *many=[NSMutableArray new];for(int i=0;i<501;i++)[many addObject:Message([NSString stringWithFormat:@"%03d",i])];h->_messages=many;h->_cursor=@"too-far";[h saveMessageCache];
 NSArray *cached=[savedCache objectForKey:@"messages"];assert(cached.count==500 && [NFBChatMessageID(cached.firstObject) isEqual:@"001"] && [NFBChatMessageID(cached.lastObject) isEqual:@"500"] && ![savedCache objectForKey:@"cursor"]);
 h->_messages=@[Message(@"latest")];[h saveMessageCache];assert([[savedCache objectForKey:@"cursor"] isEqual:@"too-far"]);
 list->_conversations=many;list->_cursor=@"too-far";[list saveConversationListCache];assert([[savedCache objectForKey:@"conversations"] count]==120 && ![savedCache objectForKey:@"cursor"]);
 assert(NFBChatPaginationPrefetchDistance(100)==240 && NFBChatPaginationPrefetchDistance(600)==450 && NFBChatPaginationPrefetchDistance(1000)==480);
 puts("PASS: production chat callbacks, scroll-during-load anchors, overlap/empty/cyclic pages, explicit retries, refresh races, request/account isolation, bounded cache cursor safety");
 }return 0;}
'''
body=legacy(head+helpers+interface+methods+tail)
output=runtime/'chat-pagination-runtime.m';output.write_text(body)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(output),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-lm','-o',str(runtime/'chat-pagination-runtime')],check=True)
subprocess.run([str(runtime/'chat-pagination-runtime')],check=True)
