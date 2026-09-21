"""Exercise production search query translation, result membership, and API methods.

Uses the same GNUstep prefix as chat-permission-runtime.py; no account or network
requests. This validates Foundation logic, not UIKit rendering.
"""
from pathlib import Path
import os, re, subprocess
root = Path(__file__).resolve().parents[1]
runtime = Path(os.environ.get('NFB_OBJC_TEST_RUNTIME', '/tmp/nfb-objc-test-runtime'))

def portable(s):
    s = re.sub(r'(\w+)\[(@"[^"\n]+"|\w+)\] = ([^;]+);', r'[\1 setObject:\3 forKey:\2];', s)
    s = re.sub(r'(\w+)\[(@"[^"\n]+"|\w+)\]', r'[\1 objectForKey:\2]', s)
    return s.replace('@YES', '@(YES)').replace('@NO', '@(NO)')
policy = portable('\n'.join((root / f).read_text() for f in ['NFBSearchQuery.h', 'NFBSearchResultFilter.h']))
source = (root / 'NFBAtprotoClient.m').read_text()
def method(signature):
    start = source.index(signature, source.index('@implementation'))
    return source[start:source.index('\n}', start)+2]
body = portable('\n'.join(method(s) for s in [
    '- (void)searchPosts:(NSString *)query sort:(NSString *)sort followingOnly:',
    '- (void)searchActors:(NSString *)query limit:(NSUInteger)limit cursor:'
]))
head = r'''
#import <Foundation/Foundation.h>
typedef void (^NFBAtprotoArrayCompletion)(NSArray *, NSString *, NSError *);
typedef void (^Response)(id, NSHTTPURLResponse *, NSError *);
static NSString *requestMethod;
static NSDictionary *requestParams;
static Response pending;
@interface NFBAtprotoSession:NSObject
+ (instancetype)sharedSession;
- (NSString *)did;
- (BOOL)hasSession;
@end
@implementation NFBAtprotoSession
+ (instancetype)sharedSession {static id session; if(!session)session=[self new]; return session;}
- (NSString *)did {return @"did:plc:me";}
- (BOOL)hasSession {return YES;}
@end
@interface NFBAtprotoClient:NSObject
- (void)fetchAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)auth completion:(Response)completion;
@end
'''
tail = r'''
- (void)fetchAppViewGET:(NSString *)method params:(NSDictionary *)params requiresAuth:(BOOL)auth completion:(Response)completion {
 requestMethod=method; requestParams=params; NSCAssert(!pending,@"overlap"); pending=Block_copy(completion);
 NSCAssert(auth,@"viewer relationships must be authenticated");
}
@end
static void Finish(id value,NSError *error) {Response callback=pending;pending=nil;callback(value,nil,error);Block_release(callback);}
#define CHECK(x) do {if(!(x)){fprintf(stderr,"FAIL at line %d\n",__LINE__);return 1;}}while(0)
int main(int argc,char **argv) {@autoreleasepool {
 NSDictionary *params=NFBSearchRequestParameters(@"coffee from:@alice from:bob.example -from:spam.example mentions:me lang:en tag:#tea since:2025-01-01 until:2026-01-01",@"latest",NO,0,@"did:plc:me");
 CHECK([[params objectForKey:@"query"] isEqual:@"coffee"]);
 CHECK(([[params objectForKey:@"authors"] isEqual:@[@"alice.bsky.social",@"bob.example"]]));
 CHECK(([[params objectForKey:@"mentions"] isEqual:@[@"did:plc:me"]]));
 CHECK(([[params objectForKey:@"excludeAuthors"] isEqual:@[@"spam.example"]]));
 CHECK(([[params objectForKey:@"hashtags"] isEqual:@[@"tea"]]));
 CHECK([[params objectForKey:@"since"] isEqual:@"2025-01-01"] && [[params objectForKey:@"until"] isEqual:@"2026-01-01"]);
 CHECK([[params objectForKey:@"sort"] isEqual:@"recent"] && [[params objectForKey:@"allTime"] isEqual:@"true"]);
 params=NFBSearchRequestParameters(@"\"from:alice coffee\" \"two words\"",@"top",YES,4,@"did:plc:me");
 CHECK(![params objectForKey:@"authors"] && [[params objectForKey:@"query"] isEqual:@"\"from:alice coffee\" \"two words\""]);
 CHECK([[params objectForKey:@"following"] isEqual:@"true"] && [[params objectForKey:@"hasVideo"] isEqual:@"true"]);
 params=NFBSearchRequestParameters(@"from:me",@"top",NO,3,@"did:plc:me");
 CHECK(![params objectForKey:@"query"] && [[params objectForKey:@"hasMedia"] isEqual:@"true"]);
 CHECK(([[params objectForKey:@"authors"] isEqual:@[@"did:plc:me"]]));
 params=NFBSearchRequestParameters(@"cat min_faves:5 filter:links filter:replies",@"top",NO,0,@"");
 CHECK([[params objectForKey:@"query"] isEqual:@"cat"] && [[params objectForKey:@"repliesOnly"] isEqual:@"true"]);
 CHECK(!NFBSearchCountsMatch(@{@"likeCount":@4},@"cat min_faves:5"));
 CHECK(NFBSearchCountsMatch(@{@"likeCount":@5,@"repostCount":@2},@"min_faves:5 min_retweets:2"));
 CHECK(NFBSearchCountsMatch(@{@"likeCount":@0},@"\"min_faves:50\""));
 CHECK(!NFBSearchCountsMatch(@{@"record":@{@"text":@"https://example.com"}},@"filter:links"));
 CHECK(NFBSearchCountsMatch(@{@"record":@{@"facets":@[@{@"features":@[@{@"$type":@"app.bsky.richtext.facet#link"}]}]}},@"filter:links"));
 NSDictionary *actor=@{@"did":@"did:plc:alice",@"viewer":@{@"following":@"at://follow"}};
 NSDictionary *images=@{@"$type":@"app.bsky.embed.images#view",@"images":@[@{}]};
 NSDictionary *video=@{@"$type":@"app.bsky.embed.video#view",@"playlist":@"video.m3u8"};
 NSDictionary *photo=@{@"post":@{@"author":actor,@"embed":images}};
 CHECK(NFBSearchResultMatches(photo,NO,YES,3,YES,YES));
 CHECK(!NFBSearchResultMatches(photo,NO,YES,4,YES,YES));
 CHECK(NFBSearchResultMatches(@{@"post":@{@"author":actor,@"embed":video}},NO,NO,4,YES,YES));
 CHECK(NFBSearchResultMatches(@{@"post":@{@"author":actor,@"embed":@{@"$type":@"app.bsky.embed.recordWithMedia#view",@"media":images}}},NO,NO,3,YES,YES));
 CHECK(!NFBSearchResultMatches(@{@"post":@{@"author":actor,@"embed":@{@"$type":@"app.bsky.embed.record#view",@"record":@{@"embeds":@[images]}}}},NO,NO,3,YES,YES));
 CHECK(!NFBSearchResultMatches(@{@"post":@{@"author":@{@"viewer":@{@"followedBy":@"at://other"}}}},NO,YES,0,YES,YES));
 CHECK(NFBSearchResultMatches(actor,YES,YES,2,YES,YES));
 CHECK(!NFBSearchResultMatches(@{@"viewer":@{@"muted":@(YES)}},YES,NO,2,YES,YES));
 CHECK(NFBSearchResultMatches(@{@"viewer":@{@"muted":@(YES)}},YES,NO,2,YES,NO));
 CHECK(!NFBSearchResultMatches(@{@"post":@{@"labels":@[@{@"val":@"porn"}]}},NO,NO,0,YES,YES));
 CHECK(NFBSearchResultMatches(@{@"post":@{@"labels":@[@{@"val":@"porn",@"neg":@(YES)}]}},NO,NO,0,YES,YES));
 NFBAtprotoClient *client=[NFBAtprotoClient new];__block NSArray *results=nil;__block NSString *cursor=nil;__block NSError *error=nil;
 NFBAtprotoArrayCompletion completion=^(NSArray *items,NSString *next,NSError *failure){results=items;cursor=next;error=failure;};
 [client searchPosts:@"cat from:alice" sort:@"latest" followingOnly:YES mediaTab:4 cursor:@"next-1" completion:completion];
 CHECK([requestMethod isEqual:@"app.bsky.feed.searchPostsV2"] && [[requestParams objectForKey:@"cursor"] isEqual:@"next-1"]);
 CHECK([[requestParams objectForKey:@"sort"] isEqual:@"recent"] && [[requestParams objectForKey:@"following"] isEqual:@"true"]);
 Finish(@{@"posts":@[@{@"uri":@"at://post"},@"bad"],@"cursor":@"next-2"},nil);
 CHECK(results.count==1 && [[[[results firstObject] objectForKey:@"post"] objectForKey:@"uri"] isEqual:@"at://post"] && [cursor isEqual:@"next-2"] && !error);
 [client searchActors:@"alice" limit:25 cursor:@"people-next" completion:completion];
 CHECK([requestMethod isEqual:@"app.bsky.actor.searchActors"] && [[requestParams objectForKey:@"cursor"] isEqual:@"people-next"]);
 Finish(@{@"actors":@[actor],@"cursor":@"people-last"},nil);CHECK(results.count==1 && [cursor isEqual:@"people-last"]);
 [client searchPosts:@"cat" sort:@"top" followingOnly:NO mediaTab:0 cursor:nil completion:completion];
 Finish(nil,[NSError errorWithDomain:NSURLErrorDomain code:-1009 userInfo:nil]);CHECK(error && !results);
 [client searchPosts:@"  " sort:@"top" followingOnly:NO mediaTab:0 cursor:nil completion:completion];CHECK(!pending && results.count==0 && !error);
 if(argc>1) {
  NSDictionary *live=NFBSearchRequestParameters(@"cat",@"latest",NO,4,@"");
  NSData *json=[NSJSONSerialization dataWithJSONObject:live options:0 error:NULL]; [json writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
 }
 puts("PASS: search query operators/phrases, typed API parameters, media/follow relationships, content settings, minimum counts, cursor propagation, response decoding and failures");
}return 0;}
'''
output=runtime/'search-runtime.m'
output.write_text(head+policy+'\n@implementation NFBAtprotoClient\n'+body+tail)
subprocess.run(['clang','-fblocks','-fobjc-exceptions','-fconstant-string-class=NSConstantString','-I'+str(root),'-I'+str(runtime/'usr/include'),str(output),'-L'+str(runtime/'usr/lib'),'-Wl,-rpath,'+str(runtime/'usr/lib'),'-L/usr/lib/swift/lib/swift/linux','-Wl,-rpath,/usr/lib/swift/lib/swift/linux','-lBlocksRuntime','-lgnustep-base','-lobjc','-o',str(runtime/'search-runtime')],check=True)
subprocess.run([str(runtime/'search-runtime'),'/tmp/nfb-search-live-params.json'],check=True)
