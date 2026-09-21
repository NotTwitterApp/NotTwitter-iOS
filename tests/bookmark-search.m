// Run with Foundation on macOS or the GNUstep prefix used by the runtime tests.
#import <Foundation/Foundation.h>
#ifdef GNUSTEP
// GNUstep does not implement this NSString option. These tests cover parsing,
// author identity, and case-insensitive text matching, not accent folding.
#define NSDiacriticInsensitiveSearch 0
#endif
#import "../NFBBookmarkSearch.h"

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "FAIL line %d\n", __LINE__); return 1; } } while (0)

static NSDictionary *Post(NSString *handle, NSString *text) {
  return @{@"author": @{@"handle": handle, @"did": @"did:plc:alice"}, @"record": @{@"text": text}};
}

int main(void) {
  @autoreleasepool {
    NSDictionary *alice = Post(@"alice.bsky.social", @"Coffee at the park");
    NSDictionary *bob = Post(@"bob.bsky.social", @"Coffee at the park");
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"from:alice")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"FROM:@ALICE.BSKY.SOCIAL")));
    CHECK(!NFBBookmarkPostMatchesSearch(bob, NFBParseBookmarkSearch(@"from:alice")));
    CHECK(!NFBBookmarkPostMatchesSearch(Post(@"alice2.bsky.social", @"coffee"), NFBParseBookmarkSearch(@"from:alice")));
    CHECK(!NFBBookmarkPostMatchesSearch(Post(@"alice.example", @"coffee"), NFBParseBookmarkSearch(@"from:alice")));
    CHECK(NFBBookmarkPostMatchesSearch(Post(@"alice.example", @"coffee"), NFBParseBookmarkSearch(@"from:@alice.example")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"from:did:plc:alice")));
    CHECK(!NFBBookmarkPostMatchesSearch(@{}, NFBParseBookmarkSearch(@"from:alice")));
    CHECK(!NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"from:")));
    CHECK(!NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"from:@")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"  from:alice  COFFEE \n")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"Coffee from:alice at the park")));
    CHECK(!NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"from:alice tea")));
    CHECK(!NFBBookmarkPostMatchesSearch(bob, NFBParseBookmarkSearch(@"from:alice coffee")));
    CHECK(NFBBookmarkPostMatchesSearch(bob, NFBParseBookmarkSearch(@"from:alice from:bob coffee")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"coffee at the park")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"\n  ")));
    CHECK(NFBBookmarkPostMatchesSearch(Post(@"bob.bsky.social", @"Try from:alice here"), NFBParseBookmarkSearch(@"\"from:alice\"")));
    CHECK(!NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"\"from:alice\"")));
    CHECK(NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"from:alice \"Coffee at the park\"")));
    CHECK(!NFBBookmarkPostMatchesSearch(alice, NFBParseBookmarkSearch(@"unknown:value")));
    CHECK(NFBBookmarkPostMatchesSearch(@{@"author": @{@"handle": @"alice.bsky.social"}}, NFBParseBookmarkSearch(@"from:alice")));
    CHECK(!NFBBookmarkPostMatchesSearch(@{@"record": @{@"text": [NSNull null]}}, NFBParseBookmarkSearch(@"coffee")));
    puts("PASS: bookmark author operators, combined text, literal operators, malformed input, and clear");
  }
  return 0;
}
