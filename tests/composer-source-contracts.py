"""Source boundary checks; these do not replace UIKit or live OAuth tests."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
compose = (root / 'NFBComposeViewController.m').read_text()
client = (root / 'NFBAtprotoClient.m').read_text()
session = (root / 'NFBAtprotoSession.m').read_text()
store = (root / 'NFBLocalPostStore.m').read_text()
assert 'switchToAccountWithDID:' not in compose, 'Composer must never switch the app session'
submit = compose.split('- (void)submitPostNow {', 1)[1].split('- (void)beginUndoTweetCountdown', 1)[0]
assert '[NFBAtprotoClient sharedClient]' not in submit
assert 'postingClientForAccountDID:accountDID' in submit
assert 'mediaItems:post[@"mediaItems"]' in submit
assert 'mediaItems:self.mediaItems' in submit
posting = client.split('- (void)createPostWithText:(NSString *)text\n', 1)[1].split('- (void)fetchPostThreadForURI:', 1)[0]
assert posting.count('forAccountDID:self.postingAccountDID') == 3, 'Blob, post and threadgate must share identity'
assert 'createdWithRecord[@"record"] = record' in posting, 'Later replies must preserve reply.root'
scoped = session.split('- (void)sendAccountPOST:', 1)[1].split('- (void)sendXrpc:', 1)[0]
assert 'self.did =' not in scoped and 'saveStoredSessionLocked' not in scoped
assert 'storedAccountForDID:accountDID' in scoped and 'privateKey:key' in scoped
assert '![account[@"dpopPrivateKey"] isEqual:key]' in scoped, 'Retries must reject replaced credentials'
assert 'for (NSDictionary *row in threadPosts)' in store and 'post[@"threadPosts"] = rows' in store
assert 'UIPasteboard.generalPasteboard.hasImages' in compose and 'self.mediaTargetTextView = target' in compose
for callback in ('didSelectItemAtIndex:', 'didTapRemoveItemAtIndex:', 'didTapAltForItemAtIndex:', 'moveItemAtIndex:'):
    part = compose.split('- (void)mediaPreviewView:(NFBMediaPreviewView *)view ' + callback, 1)[1].split('\n}', 1)[0]
    assert '[self targetMediaPreview:view]' in part, callback
print('Composer source contracts: account isolation, thread media ownership, reply roots, clipboard and editing targets passed')
