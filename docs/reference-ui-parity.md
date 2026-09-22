# Twitter 9.67 reference measurements

Reference: local `Twitter_9.67_decrypted.ipa`, specifically its T1Twitter and
TwitterSPMMigration frameworks. These are measurements from the 9.67 binaries,
not values inferred from the newer class dump in the parent directory.

| Surface | Reference evidence | Native implementation |
| --- | --- | --- |
| Tweet detail | `TAEStandardFontGroup tweetDetailFont` at 0x25d4284 forwards to `headline2Font` (body + 2) | 17pt baseline, replacing 23pt |
| Reader mode | `readerModeMediumFont` at 0x25d4450 forwards to `tweetDetailFont` | Same 17pt baseline; apply user's font scale once |
| Detail footer | `tweetDetailFooterFont` at 0x25d428c uses subtext1 | 14pt baseline |
| Composer | `composerTextEditorFont` at 0x25d3ba0 uses content base 14 + 3 | 17pt editor and placeholder |
| Message body | `directMessageBubbleBodyFont` at 0x25d3d14 uses content base 14 | 14pt rendering and measurement |
| Modal sheets | `_tfn_modalContentMaskPath` at 0x887134; content-host initializer at 0x87fad8 | 35pt top corners; 35 x 5pt grabber, y=6 |
| Action menu rows | `TFNMenuSheetActionItemAdapter` | Minimum 60pt, 24pt icon, 20pt icon/text gap, 4pt title/subtitle gap |
| Buttons | TFNButton size-class inset tables at 0x2cc9ec0 / 0x2cc9ee8 | Compact 4/12pt, small/medium 8/16pt, large 12/24pt vertical/horizontal insets; bold fonts |
| GIF categories | `T1FoundMediaStreamViewGroupAdapter`, group-cell layout | Two square columns, 1pt gutters, 20pt labels, 8pt label inset, black gradient |
| GIF results | `_updateAdapterOptionIfNeeded` at 0x232954 | Preserve result order and aspect ratio; fit rows to width with 1pt gutters and maximum 150pt height; partial last row stays at natural width |
| Pill buttons | `TFNButton layoutSubviews` at 0x83d4b0 | Pixel-floored half of the smaller bound; shared subclass handles intrinsic and fixed button sizes |
| Quote author | `TTAStatusAuthorViewLayoutDelegate` in TwitterAppSPMMigration at 0x4d9238 / 0x4d9700 | Bold name, handle, separator and timestamp; 20pt avatar |
| Quote text | `T1QuotedStandardStatusView _t1_displayTextOptionsForViewModel:...` at 0x24097c; `TFNTwitterDisplayTextModelConfiguration maxLinesForOptions:` at 0xc314c | Five-line text preview; photo/video quote body is not capped at three lines |
| Quote attachments | Default quote layout generator at 0x245810 cancels attachment side/bottom insets; `photoVideoCornerRadiusForOptions:` at 0x58f578 | Media/link previews reach the outer card edges, with no second rounded frame; ordinary inline media uses 12pt corners |
| Quote border | `_t1_setupViewBorder:` at 0x24351c | Divider color, one-pixel stroke, 12pt outer corners |
| Quote-of-quote | `T1QuotedStandardStatusView visibleQuotedStatusView` at 0x24286c returns nil | One embedded preview; opening it navigates to the quoted Tweet and its own quote |

Build 135 applies the shared quote corrections to feed/profile/search cells,
Tweet detail and thread replies, Reader, composer, and shared-Tweet message cards.
The composer now measures its quote from the content instead of fixed estimates.
Quote text padding derives from `T1QuotedStatusParameters` (12/12/4/12 times
line-height / 18, rounded up to pixels), adapted to UILabel edge spacing: the
text-only bottom inset balances the top, while attachments use the 8-unit text
gap and cancel the outer bottom inset. Quote media now uses the app's 16:9 inline
constraint instead of separate 132–188pt clamps. Full reference adaptive media
ratios, compact quote modes, and every server-dependent variant remain unverified.

Build 135 also enables controller-based status-bar appearance, removing the
global light-content override so light mode can display dark status text. The
full-screen media viewer can now apply its existing hidden-status-bar preference.

The app preserves its existing user-selectable font scale. Twitter's dynamic
font group also varies with window class and server flags. Navigation titles
use the reference's 17pt baseline; the reference also has a 19pt feature-flag
branch. Reader section spacing was tightened to fit the corrected body size.

The light, Dim, and Lights out palette values were checked against 9.67's
TAE color groups, including text, surfaces, separators, handles, and scrims.
The shared theme refresh handles the legacy application window as well as scene
windows, loaded navigation stacks, presented controllers, attributed text, and
CGColor-backed control borders. Media-viewer chrome retains its on-media palette.

## GIF provider and checks

`NFBGIFService` uses the same `https://gifs.bsky.app/klipy/v2/search` endpoint as
`twitter-clone/src/components/input/twitter-compose-picker.tsx`, including
`media_filter=gif,tinygif,mp4,tinymp4` and `contentfilter=high`.
The picker displays tinygif previews and preserves the native MP4 upload path.

- Live public search and next-page cursor requests succeeded.
- Tiny GIF and MP4 assets downloaded with an iOS app User-Agent and valid signatures.
- `tests/gif-row-geometry.c` tests the production row geometry with address and
  undefined-behavior sanitizers, covering ordered full/partial rows, mixed ratios,
  multiple viewport widths, empty input, and malformed dimensions.
- UIKit sources compile in the Linux/Theos arm64 build.

Full on-device screenshot parity is **not verified**. This Linux host can install
on the paired iPhone, but its screenshot/launch services are unavailable through
the current device tooling. Binary measurements and build checks cannot establish
that every screen/state is visually identical to the reference.

2026-09-19 delivery: the arm64 package compiled without warnings or errors and
xtool reported `Successfully installed!` on the newly connected iPhone
`00008160-0016642A36400036`. A fresh device app query confirmed
`XTL-3SKNP9V5W8.com.nottwitter.atproto`, version 0.1.5, build 135. The packaged
OAuth host/callback and status-bar plist settings were also checked. Remote launch
returned `DebugserverClient.Error.unknown`; screenshot capture was unavailable,
so this delivery does not constitute an on-device visual comparison.


## Build 136: profiles, galleries, drawer, gestures and player

Profile visibility now uses one relationship policy for own profiles, follows,
blocks (including list blocks and boolean `blockedBy`), messaging permission,
activity notifications, mutuals and counts. Empty bio/metadata rows do not reserve
space, unknown counts/dates are not invented, and long names/bios determine the
header height. Other people's empty Lists/Starter Packs tabs are hidden. The
existing Edit profile implementation is still a placeholder; this pass corrects
its visibility, not the editor itself.

Reference checks for profiles include `T1ProfileHeaderView` bannerless height at
0x1e24cc, `T1ResizableHeaderView` banner ratios at 0x1e967c, the notification
provider at 0x3a9b7c, direct-message visibility at 0x5d6b20, and mutual/count
visibility at 0x2c9514 / 0x2c955c / 0x2c9624. The native bell follows the reference's
following-only branch, without inventing its optional server feature flags.

Attachments use the current ATProto gallery union for 5–10 photos, preserving
legacy image embeds for 1–4 photos and record-with-media wrapping for quotes.
The gallery schema has a 20-item wire ceiling; the app uses Bluesky's announced
10-photo composer limit. One video/GIF remains separate from photos. Ordered
multi-selection imports/downsamples serially, preserves encoded dimensions and
alt text, and cancellation invalidates outstanding imports. Fullscreen galleries
load the current page and its neighbors, rather than retaining ten decoded full
photos at once.

Sources checked on 2026-09-19:
- [Gallery lexicon](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/embed/gallery.json)
- [Legacy images lexicon](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/embed/images.json)
- [Quote-plus-media union](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/embed/recordWithMedia.json)
- [Bluesky's 10-photo announcement](https://bsky.app/profile/bsky.app/post/3mnslrkd6ok2g)

A live public `getPosts` response for that announcement contained five
`app.bsky.embed.gallery#viewImage` items, using `thumbnail` rather than legacy
`thumb`. Native decoding retains the complete array, including quoted galleries.
The shared inline media view shows a snapping horizontal carousel with a next
photo peek and position badges above four photos; all remaining counts use the
existing grid. The composer still has its reorderable attachment rail.

The 9.67 Swift drawer types were recovered through their type/conformance
records, not the newer class dump. `DashPrimaryRow`'s icon helper at 0x106a774
requests a 24pt vector image; its font key path at 0x1435f30 is
`headline1BoldFont` (20pt baseline). `DashChildRow` uses `bodyMediumFont`
(key-path name at 0x1434570), and `DashFolderRow` uses `bodyBoldFont`
(0x1436cc8), both 15pt baselines. The native drawer now follows those icon/font
roles, allows row text to wrap instead of shrinking it, and uses consistent row
spacing. Row widths/spacing remain adaptations to this app's menu contents.

Gesture coverage in this build:
- Root left-edge opening follows the finger; drawer close pans are horizontal
  only and support cancellation/reversal.
- Edge-back uses UIKit; full-width back uses an interactive navigation transition
  with the real previous controller. Carousels and profile paging take priority
  over full-width back. An edge drag remains available for leaving a profile.
- Home feeds, profile tabs and notification tabs page horizontally; nested media
  scrolls independently. Profile/notification drags preserve the header position.
  Existing Tweet row action swipes were removed because they competed with these
  gestures; those actions remain in the action bar and overflow/context menus.
- Fullscreen photos support pinch, double-tap zoom, panning when zoomed, horizontal
  paging when at minimum scale, and vertical dismissal in either direction.
  Video supports pinch and center double-tap fit/fill.
- Action, Retweet, media-source, reply-permission, composer account, schedule,
  activity-notification, and media-option sheets support downward dismissal.
  Scrolling content owns upward drags and downward drags away from its top.
  The main account switcher's existing expand/collapse gesture now restores its
  previous state on cancellation. The composer header's downward drag invokes
  its existing Cancel/save-draft flow.
- Existing pull-to-refresh, scroll-to-top, keyboard dragging, crop/sticker
  gestures and attachment reordering remain available.

Player reference measurements: `T1AmplifyControlBar preferredHeight` at
0x4cb6c0 returns 48pt; `T1MediaSlider initWithFrame:style:` at 0x4b8124 uses a
16pt thumb and 3pt track; `T1AmplifyContentControlBar setupConstraints` at
0x2873e4 includes elapsed/divider/duration labels and 12pt trailing inset.
`newBarLabel` at 0x286e90 uses the normal font with monospaced digits. The native
player now includes those time labels, the corrected slider, pause/resume while
scrubbing, replay at the end, and chrome auto-hide. It removes the artificial
VIDEO badge and the floating media-relative control offsets.

`T1SlideshowSeekController _t1_seekStep` at 0x472f8 returns five seconds;
`canSeekForRecognizer:direction:` at 0x474b4 gates seeking to the outer 17.5%
on either side. Native edge double taps seek and repeated nearby taps continue
seeking; center double taps zoom. The reference's long-press video action at
0x11fc78 opens sharing, which is also used here.

Validation: production C policy tests pass under address/undefined-behavior
sanitizers for profile states, 4/5/10/11 attachment boundaries, all carousel items
being reachable across narrow/landscape widths, and cancelled/reversed/flicked
swipes. The existing GIF row geometry tests also pass. UIKit/Objective-C compiles
in the arm64 Theos build. No test posts, follows, messages or account changes were
sent. Runtime UIKit gesture arbitration and a complete screenshot-by-screenshot
comparison with the reference still require on-device observation; these checks
do not establish that every reference gesture and visual variant is identical.

## Build 137 — Standard.site reader and Discover topic destinations

The native Discover list now uses the web client's `app.bsky.unspecced.getTrends` endpoint and follows each returned feed destination. Relative `/profile/{actor}/feed/{rkey}`, bsky.app links, Not Twitter links, and feed AT URIs resolve to the native feed page. Actor resolution, `getFeedGenerator` metadata, `getFeed` contents, pull to refresh, and cursor pagination use the feed identity; the display label is not substituted as a search query. A missing destination alone retains the legacy search fallback.

Twitter 9.67 does contain a topic-specific header: `URTTimelineTopicLandingCondensedHeaderView`. Its Objective-C method list at `0x13b8190` and setup at `0xe01580` identify a vertical content stack, multiline primary and secondary labels, `jumboBoldFont` / `smallBoldFont`, zero custom spacing after the primary label, 16 after the secondary label, 16 top inset and a 16-point bottom spacer. Font implementations in TwitterSPMMigration are `TAEStandardFontGroup jumboBoldFont` at `0x25d0d0c` (base + 16 with Chirp, heavy; 31 at the default base) and `smallBoldFont` at `0x25d05b0` (base - 2, bold; 13). The new feed header uses those type and vertical spacing values with the app's existing native navigation and Tweet cells. Topic follow/not-interested/facepile controls depend on Twitter data not supplied by Bluesky's trend response; they are not displayed as nonfunctional imitations. Feed like counts remain real Bluesky metadata. This is binary-derived styling, not a verified screenshot match.

Article bodies now use a local, non-scrolling WebKit reader inside the existing native Tweet detail card. The native outer scroller owns vertical scrolling; ResizeObserver updates the actual body height after layout, images, rotation and text-size changes. Bundled Chirp regular/bold fonts, app colors and font scale are applied to the reader. Links route through the native URL router. Remote scripts, forms, frames and event handlers are excluded from the extracted body.

The body parser walks the complete article DOM rather than matching the first set of paragraph tags. It retains bare container text, nested paragraphs, headings, bold/italic combinations, underline/strikethrough/highlight, ordered and nested lists, blockquotes, tables, code whitespace, captions, images, and resolved relative links. Markdown uses bundled MIT-licensed Marked 15.0.12 (transformed with esbuild 0.25.12 for Safari 14; Array.at compatibility shim). Leaflet wrapper blocks, nested list schemas, UTF-8 byte-indexed overlapping text facets and footnotes are handled, along with common ProseMirror/Lexical content. Unsupported rich blocks cannot silently discard paragraphs present in `textContent`: missing paragraphs are retained alongside supported formatting. Website HTML is checked even when a record already contains a heading; partial/error/challenge pages cannot replace the complete record body. Direct HTTP reads use fresh-cache semantics and the web client's Jina reader fallback when needed.

Record requests are now deduplicated only while in flight, not cached permanently. Document refs are prioritized before applying the four-ref API maximum. Current record CIDs (or record contents) identify revisions. The reader refreshes on foreground return and every 60 seconds while visible, preserves successful content on failure, retries website fallback, and rejects old callbacks after view reuse. Recognition of enhanced external cards matches the web client's source/reading-time/date signals as well as Standard.site refs.

Validation: 10 article parser cases passed, including the live Welcome record and canonical webpage; coverage includes nested HTML, missing middle/final paragraphs, Unicode overlap, structured nested lists/tables/footnotes, Markdown emphasis, edited revisions, and rejecting challenge pages. Chromium checks of the exact bundled reader shell passed for formatting, final-paragraph retention, native height messages (1,443 points for the fixture), light/dark theme, larger font scale without horizontal page overflow, and preserving the visible body on failed refresh. This is desktop reader validation, not iPhone WebKit/UI proof. Live public requests resolved a current trend's feed metadata and returned posts plus a pagination cursor. The native arm64 build passed without warnings/errors before final packaging.

Reference source locations: web `src/lib/api/trends.ts`, `src/pages/profile/[actor]/feed/[rkey].tsx`, `src/lib/atproto/backend.ts`, `src/lib/hooks/use-standard-site-article.ts`, `src/lib/standard-site-loader.ts`; Standard.site verification metadata at https://standard.site/; Leaflet content/list/facet schemas at https://github.com/hyperlink-academy/leaflet/tree/main/lexicons/pub/leaflet. Parser tests run with `node tests/article-reader.cjs` and use the sibling web checkout's jsdom installation (override `NFB_WEB_REFERENCE` when needed). Broader unsupported publisher-specific widgets and arbitrary website CSS are not claimed to be reproduced.

Delivery verified: build 136 and then build 137 were successfully installed on the connected new iPhone `00008160-0016642A36400036`. A fresh device app inventory confirms bundle `XTL-3SKNP9V5W8.com.nottwitter.atproto`, version `0.1.5`, build `137`. Final build/install log: `/tmp/nfb-build137-install.log`; no compiler warnings/errors. The IPA includes reader resources byte-for-byte matching the checked source. Final IPA SHA-256: `96ec26aaa621dd31d6a8d57febe5e149683fba528ad163c2eba8ca060cf4be76`. Phone installation/version are verified; native gesture behavior and exact visual parity still lack a live on-device check.

## Build 138 — Thread branches, profile photos, topic scrolling and inline video

Topic navigation titles remain hidden until the expanded title's final line has
scrolled above the visible content boundary. The transition uses measured label
geometry so wrapped names, rotation and text scaling do not produce duplicate
titles. The description scrolls with the expanded header.

Thread screens now keep a URI-indexed parent/child graph. The first contiguous
same-author chain follows the focal Tweet; other author replies remain in their
actual branch instead of being collected into a false self-thread. Ancestors,
unavailable posts, branches and expansion rows retain their distinct roles.
Connector lines only join adjacent parent/child rows, never unrelated siblings or
across a missing branch. Reader mode stops at an unavailable post, another author,
a gap or a different branch. Expanding a branch preserves the visible post and
offset, merges by URI, and offers retry on failure.

Reference evidence from the supplied Twitter 9.67 binary:

- `T1StandardStatusConversationConnectorsConfiguration` at `0x21ce08` and
  `T1ConversationTreeConnectorsViewModel` at `0x52215c` distinguish ancestry,
  self-thread and branch context. `T1ConversationShowMoreCell` height at
  `0x21fe78` uses normal text height plus 23pt; its continuation dots are 3pt.
- The embedded `ios_tweet_detail_conversation_context_removal_enabled` default
  is true, so detail reply rows suppress redundant reply-context text.
- Same-profile selection at `0x38721c` calls `tfn_animateBounce` on the profile
  controller's view. TwitterSPMMigration implementation `0x972fb4` animates
  `position.x` with offsets 0, -5, 0, +3, 0 and key times 0, .5, .7, .8, 1
  over .3 seconds. Native reselection uses these values and respects Reduce Motion.
- Cover tapping at `0x1d8894` first scrolls the profile to the top. Expanded photo
  taps use a slideshow; `T1ProfileHeaderSlideshowDataSource` at `0x55bdb4` gives
  avatar zoom .85 and cover zoom 1. The native viewer uses a circular avatar
  preview, cover aspect fit, source-image transition and the IPA's embedded
  fullscreen transition duration .175 seconds. The collapsed profile blur now
  covers the actual navigation bar and subtitle bottom, including the handle.

Reply loading starts with one bounded `getPostThreadV2` request (below 6,
branching factor 10, oldest order), with the stable `getPostThread` as fallback.
It no longer waits for depth-1000 requests or serial author-feed scans. Concurrent
requests share an in-flight result and a 12-second account-scoped cache; explicit
refresh invalidates the cached thread. Expansion uses `moreReplies`, not the
post's aggregate `replyCount`. Additional replies are requested only when the user
opens their separate row. Live public checks returned 194 nodes for a post with
691 replies, with zero remaining direct replies, seven incomplete branches and
`hasOtherReplies=true`; branch expansion returned 23 nodes and the additional
endpoint returned 18. This exercises the distinction that previously generated
empty expansion rows. These were public network checks, not on-device timings.

API schemas checked on 2026-09-19:
[primary thread response](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/unspecced/getPostThreadV2.json)
and [additional replies](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/unspecced/getPostThreadOtherV2.json).

All shared inline media tiles, including quoted posts, now participate in muted
autoplay. One visible player is selected; clipped/covered tiles, background
screens, concealed media and composer previews cannot autoplay. VoiceOver,
Reduce Motion, Low Power Mode and the existing autoplay preference switches are
respected. Moving away releases the player and retains its position; fullscreen
playback and inline playback exchange position, including replay after an ended
video. The inline badge shows remaining time once duration is known, never the
word VIDEO. Unknown duration stays hidden instead of inventing a countdown.

The IPA's embedded `media_autoplay_start_player_view_visible_fraction` is .01;
`ios_looping_video_cards_enabled` is true and its duration threshold is 60 seconds.
These values drive the native eligibility and loop boundaries. GIF video items
loop independently of duration. `T1InlineMediaView setPillViewTime:` at `0x2e50bc`
hides an unknown time. Reference policies also gate autoplay on presentation,
accessibility and settings. The native player selection heuristic is an app
adaptation, not a reconstruction of Twitter's server experiments.

ALT consumption badges require a nonempty description and photo media. They are
suppressed for video/GIF transport, concealed content and profile photos;
composer description editing remains available. The reference's
`ios_images_hide_multiphoto_qt_alt_text_badge_enabled` default is false, so quoted
multi-photo descriptions retain their badges. `ios_alt_text_profile_images_read_enabled`
is false. Fullscreen badge constraints also reserve space above playback controls,
preventing overlap if a future media type supports both. Existing video options
still expose available video descriptions.

Validation uses production C policies under address/undefined-behavior sanitizers:
author chains, siblings, missing branches, unavailable posts, 2,000 malformed
graphs and a 10,000-post chain; ALT states; 1% visibility and 60-second loop
boundaries; fullscreen rewind/resume; and remaining-time rounding. Native UIKit
and Objective-C are compiled for arm64. No social-account mutations were used for
testing. Binary evidence, pure-policy tests and public API checks do not establish
complete screenshot or runtime gesture parity. Twitter's server-ranked modules
and experiments cannot be recovered solely from this IPA, and this environment
still cannot capture a live iPhone UI session.

Delivery verified: the final arm64 build completed with no compiler warnings or
errors, and xtool reported a successful USB installation. Fresh device inventory
confirms `XTL-3SKNP9V5W8.com.nottwitter.atproto`, version `0.1.5`, build `138` on
`00008160-0016642A36400036`. Packaged Info.plist independently confirms 138.
IPA SHA-256: `dc3346f60ce37d763d63a8d29095fb24dbed47d56116c860dc61969883175ce0`.
Build/install log: `/tmp/nfb-build138-install.log`; filtered inventory evidence
comes from `/tmp/nfb-build138-phone-apps.json`. Thread/media policy tests and the
existing profile/gesture policy tests all passed with sanitizers before delivery.

## Build 139: GIF playback, audio, composer attachments and article endings

External GIF cards previously used their still thumbnail for both the inline
image and fullscreen image. They now keep the thumbnail as a poster and resolve
the actual animation. Tenor uses the web client's Safari MP4 route through
`t.gifs.bsky.app`; direct KLIPY/Giphy GIF, MP4 and WebP URLs and Giphy page links
resolve to playable media. Unsupported provider pages retain an external card
instead of disappearing. Image GIFs use decoded animation frames; video GIFs use
the shared player and loop. Composer GIFs now animate and tapping them opens the
fullscreen viewer, including a local GIF restored from a draft. GIF and video
autoplay preferences remain independent, and concealed/background media stops.

The shared audio-session owner starts muted playback with the mixable Ambient
category. Only explicit unmute selects and activates nonmixable Playback.
Muting, leaving the screen, backgrounding, playback completion and teardown
release ownership and notify other audio apps. Inline and fullscreen mute
controls use the reference `sound` / `sound_off` vectors and suppress the toggle
for GIFs or a loaded video without audio tracks. This is compiled behavior;
other-app interruption/resumption has not been observed live on the phone.

Further measurements from the supplied Twitter 9.67 IPA:

- `T1InlineMediaView` audio-toggle creation at `0x2e1e8c` uses TFNButton style 15,
  size class 1. Its icon selection at `0x2e2268` uses `sound` / `sound_off`.
  TFNButton image sizing at `0x83e18c` in TwitterSPMMigration gives a 16pt icon;
  image-only layout uses 4pt insets, producing a 24pt button.
- Attachment cells use 12pt corners, 8pt control insets and a 29pt remove control.
  Edit/ALT are style 15, size class 2: 18pt icons with 8pt padding. The edit asset
  is `paintbrush_stroke`; `_t1_altTextIconImage` at `0x323d8` selects `alt_compose`
  or `alt_compose_pip` according to whether a description exists. Native hit
  areas expand to 44pt without enlarging the visible buttons.
- `maximumPreferredAttachmentsViewHeight` at `0x5b8bb4` is six avatar heights
  (240pt with the 40pt composer avatar). Aspect-aware previews replace the old
  fixed 88pt strip. The 10-photo adaptation is a horizontal carousel with a
  visible next-card hint, removal, crop/filter editing, ALT editing and reorder.
- Swift `PlaybackRateOption` at `0x14140d4` contains half, threeQuarters, normal,
  oneAndAQuarter, oneAndAHalf, oneAndThreeQuarters and double. Fullscreen options
  now offer all seven rates in a separate scrollable speed sheet, alongside the
  existing transport, scrubbing, seek gestures, zoom, replay and chrome hiding.

Pasted Bluesky and current/legacy Not Twitter post links normalize to a Bluesky
post URL, resolve the post's URI/CID and become a removable quoted-post preview.
The existing ATProto record / recordWithMedia serialization sends the quote.
Lookups debounce and discard stale results; failure keeps the normalized link.
Quoted-post drafts retain the quote. Lookups are triggered by paste or a completed
typed link, avoiding requests for partial keys while typing. No test posts were
published; native paste interaction and posting remain unverified on-device.

The article shell now disables automatic WKWebView safe-area insets because the
outer Tweet scroller owns those insets. It measures scaled scroll overflow as
well as the element bounds, adds bottom clearance, and remeasures when fonts
finish loading. Desktop probes did not reproduce the reported iPhone clipping;
the change addresses the inset/rounding boundary without changing article text.
The supplied "My Thoughts On AI & AI Coding" article retains its closing text
through "Back to the desktop". The shipped HTML, font files and height bridge
passed 63 width/scale/ending combinations in each of Chromium and WebKit, plus
image-load/font-change updates, long-to-short shrinkage and height convergence.
These are browser DOM checks, not UIKit screenshot parity.

Validation: `tests/article-layout.py` (both engines, including the user's HTML),
all 10 `tests/article-reader.cjs` cases, and sanitizer builds of the composer
geometry/reorder and media-presentation policy tests passed. The live KLIPY
endpoint returned both GIF and MP4 assets with the expected signatures and MIME
types. Full 1:1 runtime parity, native GIF playback and audio mixing still need
live iPhone observation; compilation and asset checks alone do not prove them.

Delivery: the final arm64 build completed with no compiler warnings or errors,
and xtool successfully installed it over USB. Fresh device inventory confirms
`XTL-3SKNP9V5W8.com.nottwitter.atproto`, version `0.1.5`, build `139` on
`00008160-0016642A36400036`. The IPA independently reports 139 and contains the
new reference icon assets. SHA-256:
`2093992511bb2e8bb4c431b9a92d39a4dad8f708a165a11f0870a61a4a18f6c8`.
Logs: `/tmp/nfb-build139-install.log`, `/tmp/nfb-build139-phone-apps.json`,
`/tmp/nfb-article139-layout.log`, `/tmp/nfb-gif139-assets.json`.

## Build 140 — composer ownership, media import and layout

The short-text spacing regression came from 142pt (media) / 118pt (quote)
minimum text heights plus a bottom text inset. The extracted Twitter 9.67
`T1TweetComposeSingleTweetViewController layoutIfNeeded` at `0x5b4d74` measures
`sizeThatFits:` and places attachments 8pt below the text/avatar extent
(`0x5b5124`–`0x5b515c`); quotes add 8pt (`0x5b5254`). Nested content now follows
the measured text height, including deletion, long pastes and rotation. The
root attachment/quote now precedes subsequent composer rows. Each additional
row owns its media, preview and height constraint and uses the same 240pt
maximum, aspect sizing, carousel, edit/ALT/remove and reorder controls. The
focused C regression was red against the old 142pt minimum and passes now.

Each composer text view accepts Paste when the clipboard contains images.
Images go to the active row, retain its text and share library import limits and
editing controls. Changing keyboard focus does not retarget an in-flight import.
Draft persistence retains each row's attachment bytes, ALT, warnings, order and
selected account. Sending each child uses its own media; created post results
retain the record so subsequent replies keep the original thread root.

Reference account selection: `tableViewController:didSwitchToAccount:` at
`0x62cec` calls the composer's `setAccount:` (`0x68830`). The persistent composer
avatar opens an account-list controller with a current-account selection and a
callback that changes the composer account (`0x2c392c`, `0x2c3b34`). The native
avatar/account picker now uses a posting client pinned to that account DID.
Blob uploads, createRecord and threadgate requests load that saved account's
OAuth/DPoP credentials without switching the app session. Refresh is coalesced
per account and writes rotated inactive credentials only to that saved account.
Missing/removed accounts and changed signing keys fail instead of falling back
to the active account. Draft lists and saves follow the selected composer account.

Current Bluesky sources checked 2026-09-19:
- `https://raw.githubusercontent.com/bluesky-social/social-app/main/src/lib/constants.ts`:
  4000px image dimension, 2,000,000 image bytes, 600 seconds, 300,000,000 video bytes.
- `https://raw.githubusercontent.com/bluesky-social/atproto/main/lexicons/app/bsky/embed/gallery.json`:
  authoring soft limit 10 images (schema ceiling 20).
- `https://raw.githubusercontent.com/bluesky-social/atproto/main/lexicons/app/bsky/embed/video.json`:
  MP4, 300,000,000 bytes.

The shared upload policy is enforced in the composer and posting client. The
video editor caps the selected range at 10 minutes and checks actual exported
bytes/duration, with a lower-quality retry if the highest-quality export exceeds
300 MB. Photos retain up to 4000px before reducing quality/dimensions to fit 2 MB.
Service-side errors remain authoritative; account quota is not simulated locally.

The old generic media-source menu now opens an in-app Photos grid with albums,
ordered selection, video duration badges, camera import and limited-library
access. Reference `T1PhotoGalleryViewController` uses a 3pt top offset, 1pt row
gaps and square cells computed from width/column count (`0xd5254`, `0xd7cd4`).
The editor uses the reference `paintbrush_stroke` / `settings_stroke` 24pt toolbar
assets (`0x1ee104`), a 90pt bounded timeline with 18pt inset (`0xdd718`), and a
transient duration label while dragging. Scrubbing pauses and previews the
changed endpoint; releasing seeks to the start and plays the selected range
(`0x1efd30`, `0x1f00ac`). Playback hides the central play button (`0x1efb54`).
Thumbnail extraction runs off the main queue. Cancel cancels an active export.
Content settings use the IPA's title and warning choices, adapted to ATProto
self-labels, and persist through drafts and uploads. Preview mute is separate
from the original video's audio track; muted previews leave other apps' audio alone.

Topic pills measure the complete title and selection mark using the theme's
insets, have flexible trailing row space, wrap very long names, and rebuild on
width changes. This removes middle ellipses such as the reported `Coo...ng`.

Validation before delivery: warning-free arm64 builds during development;
sanitizer-enabled C tests for composer text layout, composer media geometry,
media upload boundaries and token refresh; `tests/composer-source-contracts.py`
checks critical source ownership/identity boundaries. These are compile, policy
and source checks. They do not prove live OAuth posting, Photos/clipboard/native
video behavior or pixel-for-pixel UIKit parity. No test posts were published.

Delivery: final arm64 build completed without compiler warnings/errors and
installed successfully over USB. Fresh device inventory and the IPA both confirm
version `0.1.5`, build `140`, on iPhone `00008160-0016642A36400036` with bundle
`XTL-3SKNP9V5W8.com.nottwitter.atproto`. SHA-256:
`2fa0ade215ffc7ba7a2747a9046c384b370442937bb7cdd442d5affa7735d0a3`.
Logs: `/tmp/nfb-build140-install.log`, `/tmp/nfb-build140-phone-apps.json`.

## Message badge and account avatar — build 141

The Messages count now has an opaque Twitter blue (`#1d9bf0`) fill, white
digits, and an opaque page-background border (black in Lights out). Reference
9.67 `T1TabView initWithFrame:title:imageView:panelID:` at `0x519110` sets
`notificationBadgeColor` and `pillControlTextColor`; `setBackgroundColor:` at
`0x51c43c` also sets the badge border color. The darker palette resolves these
to primary blue and white at `0x25861d0` and `0x258c558`. Existing count geometry,
zero-count hiding and accessibility values are retained; theme changes update
the border instead of retaining a stale CGColor.

Home, Explore and Notifications now refresh their corner avatar on session
changes independently of feed loading. The selected account's saved photo is
loaded immediately, or the default avatar replaces the old account when no
photo is available. Both profile and image completions check the active DID
and refresh generation; image completions also check the current URL. Superseded
image tasks are canceled, and decoded photos are cached for return switches.
This fixes the missing account-change refresh outside Home and prevents late
old-account responses from restoring an outdated avatar.

Validation: the arm64 app compiles without warnings/errors, and the packaged
Info.plist confirms version `0.1.5`, build `141`. The account-change, missing-photo,
theme-update and stale-completion branches were reviewed in source. Native UI
interactions and visual parity have not been exercised on the phone.

Delivery attempt: the phone was visible at the initial USB check but disconnected
before install (`usbmuxd` reports removal at 00:03:14 on 2026-09-20). Build 141
is packaged; installation and device-version verification are pending reconnection.
IPA SHA-256: `d03faeda68664c94fee6116f3e8811e4e5708374c89216f03c09444dadad6d80`.
Build/install log: `/tmp/nfb-build141-install.log`.

Retry delivery: a fresh clean build and USB install succeeded on 2026-09-20.
Both the IPA and a fresh phone app inventory confirm `0.1.5` build `141` on
`00008160-0016642A36400036`, bundle `XTL-3SKNP9V5W8.com.nottwitter.atproto`.
Compiler warnings/errors: zero. Rebuilt IPA SHA-256:
`7576c8f6117f06cc3e74b4ecd9f7d01f889a5fee25220df0ebc169afe139b665`.
Logs: `/tmp/nfb-build141-retry-install.log`,
`/tmp/nfb-build141-retry-phone-apps.json`. On-device visual/interaction
verification remains unperformed.

## Account screen replacement and reply loading — build 142

The account-switch mismatch was reproduced by executing the production host
notification method with UIKit doubles: switching while the old timeline was
loading kept that account's controller/content visible. The old profile callback
could also replace the active account's identity, while per-screen avatar caches
required another download even when the picker already displayed the correct photo.

Reference 9.67 `T1HostViewController viewAccount:withPanelID:preserveModals:animated:completion:`
at `0x164d50` selects an account-bound navigation provider and preserves an available
current panel. Its `_useViewController:forAccount:animated:completion:` transition
uses 0.35 seconds (`0x163f90`, duration at `0x1644e8`). The dash switch invokes the
account action after dismissal (`T1AppSplitViewController` at `0x3cb6b8`).
The app now closes the picker/drawer, replaces all tab navigation controllers,
retains the selected tab, clears old badges, and crossfades for that duration.
Token renewal without an identity change leaves the current screen intact.

The picker, drawer, timeline headers and Messages header share a decoded-avatar
cache. A selected photo already shown in the picker is immediately reusable by
the new header; missing photos reset to the default. Image completions use unique
request tokens, and profile/read requests use an account generation. Late responses
cannot repaint the current account or save retired message controllers' content
under the new account. Profile caches include the viewer identity; profile/thread
in-flight requests also include the generation, so a rapid A-to-B-to-A switch does
not join the canceled original request. Root replacement also handles coalesced
identity notifications. Inbox/request-list generations prevent late list results
from overwriting the newly selected list.

Reply loading now follows the reference's `TFNActivityIndicatorCollectionViewCell`
(`TwitterSPMMigration`, init `0x8f0424`, layout `0x8f0568`, height `0x8f0638`):
a 44pt clear row, centered medium system activity indicator (style 100), disabled
interaction, and accessibility-only “Loading” text. The loading sentence is removed.
The indicator uses the IPA's gray700 values: light `#536471`, Dim `#8b98a5`,
Lights out `#71767b` (`_activityIndicatorColor` at `0x25c260c`, `0x2577770`,
`0x2586704`). Theme changes update the visible indicator.
`T1ConversationShowMoreCell setLoading:` at `0x21ffcc` replaces the continuation
dots with a medium system spinner without changing its action label; the branch
expansion row now does that too, retaining the upper connector and native spinner
color instead of the previous blue spinner plus “Loading…” label. Successful loads
remove the footer; failure retains the existing functional retry action.

Validation: `python3 tests/account-switch-runtime.py` and
`python3 tests/account-avatar-runtime.py` pass, executing extracted production
Objective-C control flow with Foundation and UIKit/network doubles. Cases cover
screen replacement while loading, late responses, selected-tab retention, badge
reset, token renewal, rapid/coalesced return switches, 0.35s duration, cached photo
handoff, missing photos, duplicate requests, and old image completions.
`python3 tests/composer-source-contracts.py` also passes. These checks do not run
native UIKit or live authenticated network traffic. Reply visuals were checked
against disassembly and source; on-device visual/interaction parity remains
unverified. No test posts or messages were sent.

Delivery: the final arm64 build completed with zero compiler warnings/errors,
and USB installation succeeded. A fresh device app inventory confirms version
`0.1.5`, build `142`, bundle `XTL-3SKNP9V5W8.com.nottwitter.atproto` on iPhone
`00008160-0016642A36400036`; the packaged IPA also reports build `142`.
IPA SHA-256: `315092a4e717875a64fd2b14725b59972b737f5083b2fd9641b3749395554e48`.
Logs: `/tmp/nfb-build142-final-build.log`, `/tmp/nfb-build142-install.log`,
`/tmp/nfb-build142-phone-apps.json`.

## Retweet context and DM permissions — build 147

The reference is the supplied `Twitter_9.67_decrypted.ipa`. Its T1Twitter and
TwitterSPMMigration binaries match the extracted binaries byte for byte.
`TFNTwitterStatus(T1StatusViewModel) socialBadgeName` (0x13ad94, retweet branch
at 0x13b06c) resolves `rt` to **retweet**, not `retweet_stroke`.
The header now uses a separately generated icon from that reference vector;
the action-bar icon retains its own asset. `T1TimelinesItemSocialContextView`
uses `smallBoldFont` (0x4d5158) and a badge square equal to `normalFont.pointSize`
(0x4d51b8): 13pt text and 15pt badge at the normal scale. The social-context
layout at 0x2171ec caps text at two lines and puts the badge's right edge two
points beyond the avatar's right edge (0x2177b0). Text aligns with the Tweet's
author column. The avatar follows the text's actual height, including larger
font settings and long names.

Reference localization keys `SOCIAL_CONTEXT_FOLLOW_AND_RETWEETS_LABEL` and
`SOCIAL_CONTEXT_YOU_RETWEET_LABEL` supply the forms “%@ Retweeted” and
“You Retweeted”. Feed/profile `reasonRepost.by` supplies that person's identity;
notification reason strings, ordinary posts, and quoted Tweets do not become
retweet banners. Tapping the banner opens the reposter's profile.

`T1ProfileActionDirectMessageButtonProvider` (0x5d6e84) waits for a ready
relationship, checks `viewerCanDM`, and excludes blocks in either direction.
The button uses `messages_stroke` (0x5d6b24); the native vector matches the IPA.
Size class 2 uses an 18pt image and 8pt insets (tables at 0x2cc9f10 /
0x2cc9ee8), correcting the envelope inside the existing 34pt circle.
The app now waits for Bluesky's read-only `getConvoAvailability.canChat` before
showing the envelope. This delegates `allowIncoming` all/none/following,
recipient-follows-sender direction, and existing-conversation exceptions to the
chat service, matching Bluesky's own profile button. Unknown/malformed replies
and request failures never default to everyone being allowed to message.
Own profiles and individual/list blocks remain excluded. Account and request
generations prevent late responses from restoring stale permissions.

Opening a direct conversation checks availability again, returns an existing
conversation when allowed, and only creates one after a positive result.
Structured error names survive the session layer, so closed/blocked-recipient
errors use the IPA's `DIRECT_MESSAGE_ERROR_CANNOT_SEND_DIRECT_MESSAGE` copy
instead of raw server text. Network/authentication errors remain distinct.
An existing direct conversation with `canChat=false`, or a send rejected for
permission, hides the composer, retains its draft, and shows the reference's
`DIRECT_MESSAGES_READ_ONLY_FOOTER_MESSAGE` with a Bluesky Learn more link.
The footer uses native themed text; it is an adaptation of the reference copy,
not a proven pixel-identical reproduction of every reference footer variant.

Primary protocol/UI sources checked for this change:
- [Bluesky profile DM button](https://github.com/bluesky-social/social-app/blob/main/src/components/dms/MessageProfileButton.tsx)
- [Conversation availability](https://github.com/bluesky-social/atproto/blob/main/lexicons/chat/bsky/convo/getConvoAvailability.json)
- [Direct conversation and permission errors](https://github.com/bluesky-social/atproto/blob/main/lexicons/chat/bsky/convo/getConvoForMembers.json)
- [Chat declaration settings](https://github.com/bluesky-social/atproto/blob/main/lexicons/chat/bsky/actor/declaration.json)

Validation: `python3 tests/chat-permission-runtime.py` runs the production
permission/opening methods against a controlled Foundation chat proxy. It covers
all/none/following/unknown declaration fixtures with authoritative service
responses, blocks, self, network/malformed errors, reusing existing chats,
preventing creation on denial, permission changes between checking and creation,
account switches, named errors, and retweet labels/identities. The profile
visibility C checks also pass. These checks send no live messages or create test
conversations. Compilation and packaged-asset checks complement these tests;
full on-phone visual and gesture comparison against the reference is unverified.

Delivery: the final arm64 build completed without compiler warnings/errors and
USB installation succeeded. A fresh installation-proxy lookup confirms version
`1.0`, build `147`, bundle `XTL-3SKNP9V5W8.com.nottwitter.atproto` on iPhone
`00008160-0016642A36400036`. The packaged retweet context PNG matches the generated
reference asset; the IPA includes the structured repost and chat availability
paths. SHA-256: `f256da2e177fe6ea62aea0f9d415f1e1d5eb7230a73d767b11ce4d61c41010a2`.
Logs: `/tmp/nfb-147-final-build.log`, `/tmp/nfb-147-install.log`,
`/tmp/nfb-147-phone-version.json`.

## Search navigation and filters — 1.1 build 149

Inspected the supplied `Twitter_9.67_decrypted.ipa` again before this change:

- `T1SearchContainerViewControllerContext makeSearchResultsViewControllerWithScribeContext:searchParameters:viewController:subtitleAction:` at `0x1ce374` constructs the five Top, Latest, People, Photos, Videos configurations.
- `TTSSearchContainerViewController _t1_rightBarButtonItems` at `0x60fb64` uses the filter bar item in the ordinary mode; advanced search is feature-switch controlled. `_t1_presentFilterMenu:` at `0x610c78` presents Search filters with Cancel and initially disabled Apply.
- `TTSSearchFiltersViewController initWithContext:` at `0x614084` builds People (From anyone / People you follow) and Location (Anywhere / Near you) single-selection sections.
- The reference localization supplies the saved-search actions and advanced builder's Add search condition, phrase/word/account/date/count/reply labels. The generated filter icon's source SVG matches the IPA bytes.

Search results now have the compact back/search/filter navigation row, five underlined tabs, tap/swipe tab selection, paged actor rows with Follow controls, filtered native media results, the filter sheet, saved searches in typeahead, and Search settings. The optional advanced builder supports adding/deleting word, exact phrase, any/without-word, author, mention, hashtag, date, count, following, media/link and reply conditions. End dates entered through that builder are inclusive and become the next day's exclusive `until` boundary. Saved searches and search settings are scoped to the active account. Photo/video result content uses the app's existing tweet/media renderer.

The backend is `app.bsky.feed.searchPostsV2`: `top` versus `recent`, repeated `authors`/`mentions`/`hashtags`, dates, following, media/video and reply filters use its typed parameters. Operators inside quoted phrases remain literal. Short default usernames expand to `.bsky.social`; `from:me` resolves to the active DID. Minimum engagement and media-or-link conditions filter hydrated results. Photos exclude video-only posts and quoted-only media. Sparse filtered pages continue automatically for up to five pages before offering Show more results; duplicate items and immediately repeated cursors are suppressed. Query/tab/filter changes invalidate in-flight responses and reset pagination.

Bluesky's V2 schema has no geographic search or recipient-account filter equivalent to the reference's Near me / To accounts conditions. Near you remains visibly unavailable in the normal Location section, and those unsupported advanced conditions are not offered. Saved searches are local to this app, not Twitter or Bluesky server-synced. Existing account moderation continues to apply when search-specific sensitive/mute filtering is disabled. Pixel-exact media layouts, current server-side Twitter feature flags, and full on-device visual parity are not claimed.

Validation:

- `python3 tests/search-runtime.py` executes the production query/filter helpers and API methods with controlled responses: quoted operators, author exclusions and mentions, typed Boolean/array parameters, media classification, follow direction, content settings, engagement thresholds, cursors, response decoding and errors pass.
- Fresh optimized arm64 IPA build completed without compiler warnings/errors. Version 1.1/build 149 was inspected inside the IPA, copied to `/home/eric/Documents/Not Twitter/Not Twitter 1.1 (Build 149).ipa` with matching SHA-256, installed over USB, and verified through the phone's installation proxy.
- Live V2 Top, Photos, Videos and author requests returned five hydrated posts each. Video and author membership checks passed. The unauthenticated live next-page request returned HTTP 403; cursor forwarding/decoding is covered by the controlled runtime checks. Authenticated live pagination and follow-filter results were not inspected on the phone.
- `idevicescreenshot` could not start the phone's screenshot service (developer disk image unavailable), so no on-device screenshot comparison was performed.

API sources: [searchPostsV2 lexicon](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/feed/searchPostsV2.json), [searchActors lexicon](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/actor/searchActors.json).

## Search category paging — 1.1 build 150

Replaced build 149's two discrete `UISwipeGestureRecognizer`s with a horizontal,
`pagingEnabled` scroll view containing independent result controllers. Pages and
the tab underline now track the finger continuously; UIKit owns the release,
snap-back and deceleration physics, as in the reference. A committed tab keeps
its loaded rows, pagination cursor and vertical position when leaving/returning.
The current and neighboring pages load lazily; query/filter changes invalidate
requests for all loaded pages without mixing their result types.

Reference evidence in TwitterSPMMigration from the supplied 9.67 IPA:

- `TFNPagingViewController viewDidLoad` (`0x7fba80`, setup at `0x7fbcc8`–`0x7fbd24`) enables native paging, disables scroll-to-top/indicators on the horizontal scroller, and enables failure beyond both outer extents. There is no custom release-distance cutoff in `scrollViewWillEndDragging:withVelocity:targetContentOffset:` (`0x7fd578`).
- `TFNPagingScrollView _tfn_panGestureRecognizerShouldBegin` (`0x7fb4ec`) requires `abs(vx) > 2 * abs(vy)` and rejects outward motion at the first/last page.
- `gestureRecognizerShouldBegin:` (`0x7fb22c`) cancels vertical descendant pans when horizontal paging wins. Its simultaneous-recognition method (`0x7fb3b8`) allows a vertical scroller while the pager is still possible, not after the pager begins/changes. `shouldRequireFailureOfGestureRecognizer:` (`0x7fb49c`) defers to the screen-edge recognizer.
- `indexPathForContentOffset:` (`0x7ff12c`) truncates `offset / (pageWidth + spacing)` while tracking. The app follows that indexing for gesture arbitration and uses the settled native page boundary for the final category selection.

The native app also preserves slider, zoomed-media and horizontal-carousel
priority. Navigation's full-width back gesture yields to a category page when a
previous category exists; at Top the outward drag can go back. Screen-edge back
remains available from every category. A size change or leaving the screen
cancels any partial page at the committed category. Only the selected result
list responds to status-bar scroll-to-top. Child appearance and row-interaction
state follow page completion, including a cancelled/returned native scroll.

Validation: optimized arm64 build; `tests/search-paging-policy.c` tests the exact
2:1 threshold, both extent failures, tracking/settled indexes and size bounds;
`tests/search-paging-runtime.py` executes the production recognizer and nested
scroll arbitration methods with deterministic UIKit doubles (including vertical
fling cancellation, media/slider priority and edge/full-width back);
`tests/gesture-policy.c` and `tests/search-runtime.py` also pass. These checks do
not simulate UIKit's native scrolling physics or prove on-device visual parity.

Delivery: 1.1/build 150 was verified inside the packaged IPA and on the connected
iPhone through installation-proxy lookup after a successful USB installation.
The copy in `/home/eric/Documents/Not Twitter/Not Twitter 1.1 (Build 150).ipa`
matches the package SHA-256
`1ffeff6de6dc371d89cf621d3347ae488a3cf9f973c67947d182d3a3f68c3776`.
The reference's edge-failure class pointer at `0x3882950` was additionally
resolved through chained import 3971 to `UIScreenEdgePanGestureRecognizer`.
No on-device gesture recording or screenshot comparison was available.


## Message pagination and back swipes (1.1 build 151)

History prefetch starts 240–480pt from the top depending on viewport height.
Responses anchor the first visible message by ID at response time, including
its offset within that row. Reading can continue while loading; prepends,
shared-post hydration, and removing the paging header preserve that anchor.
Inbox/request pagination continues through short or locally filtered pages,
keeps older loaded conversations on refresh, and preserves the visible row.
Both pagers expose loading/retry controls, reject cursor cycles, and isolate
late responses by account and request generation. A truncated cache never
retains a cursor from beyond omitted rows; history caches keep the newest 500
messages. The getLog fallback no longer supplies a cursor to getMessages.

Reference `TwitterSPMMigration` evidence:

- `TFNNavigationControllerTransitionAnimator gestureRecognizerShouldBegin:`
  at `0x8dce94` accepts the full-width pan when horizontal velocity points back
  and `abs(vy / vx) <= 1`; it cancels descendant vertical scroll pans.
- `_pan:` at `0x8dc88c` normalizes translation and velocity for RTL. Its release
  branch at `0x8dca08`–`0x8dca50` cancels for velocity below -200pt/s; otherwise
  finishes for progress >=0.6 or velocity >=200pt/s, unless cancelled. Completion
  speed is 0.99 and the completion curve is ease-in-out.
- The initializer at `0x8dac74` stores a 0.4s transition duration. The app's
  full-width transition now follows these values, retains interaction state
  through completion/cancellation, stops the active vertical list, and protects
  media controls, category paging, modal presentation and the native edge pop.
- `information_circle.svg` from the IPA's main TwitterAppearance bundle is
  byte-identical to the bundled source used for `nfb_conversation_info` (24pt).
  Conversation Info now uses it instead of the question-mark help icon.

Validation: `tests/chat-pagination-runtime.py` executes production callbacks
with delayed transport responses: reading while loading, duplicate/empty/cyclic
pages, retries, both refresh/page completion orders, account/request isolation,
and newest-message cache truncation. `tests/back-swipe-runtime.py` executes
production gesture handlers with UIKit doubles, including transition lifetime,
vertical scrolling takeover, media/modal conflicts and RTL. The back-swipe C
boundary tests and existing search-paging runtime checks pass. These are focused
control-flow tests, not on-device animation or screenshot parity evidence.

Delivery: optimized arm64 1.1/build 151 compiled without warnings, installed
successfully over USB, and installation-proxy lookup confirmed Not Twitter
1.1/build 151. The Documents IPA matches the packaged build:
`/home/eric/Documents/Not Twitter/Not Twitter 1.1 (Build 151).ipa`, SHA-256
`dfe72d3d8f922515a011b3a5cd012f47846ff1518e8fc71caa2235b975e2ac1a`.
The packaged information icon was verified against the generated source asset.
Release notes were updated alongside the IPA. No live on-device gesture or
message-scrolling session was performed.


## Linked post cards (1.1 build 152)

Bluesky `/profile/{actor}/post/{rkey}` and Not Twitter `/{user}/status/{id}`
and `/tweet/{id}` URLs resolve to existing `NFBQuotedPostView` tweet components.
Not Twitter IDs follow `twitter-clone/src/lib/routes.ts` (base64url AT URIs),
including the GitHub Pages path prefixes. DM discovery uses the same parser.
Feed, bookmark, search, and thread API responses receive a presentation-only
linked-post field before layout. A native quote always takes precedence;
otherwise one linked tweet is displayed per source post, with other links kept.
Card taps use existing native quote navigation and media interactions.

Handle resolution and post fetches are deduplicated and batched at 25, per the
[getProfiles lexicon](https://raw.githubusercontent.com/bluesky-social/atproto/main/lexicons/app/bsky/actor/getProfiles.json)
and [getPosts lexicon](https://raw.githubusercontent.com/bluesky-social/atproto/main/lexicons/app/bsky/feed/getPosts.json).
Raw preview lookups avoid recursive hydration and preserve authenticated block
state. Self-links, missing/deleted/blocked targets and lookup errors retain the
original link. Account-generation checks cover both the initial response and
preview resolution. No posting or record writes occur during resolution.

A separate display record removes only the resolved URL and remaps UTF-8 facet
indices, preserving mentions, unrelated links, Unicode, and the original record
for copy/edit operations. A matching website preview is suppressed. In messages,
only the represented post link is hidden; remaining web links remain tappable.

Validation: `tests/post-link-resolver-runtime.py` compiles the production resolver
and extracts production DM discovery/display helpers. It covers both share URL
formats, strict hosts/routes, batching/deduplication, no recursive resolution,
native quote/self-link handling, immutable records, UTF-8 facet remapping,
multiple links and error/blocked fallbacks. Account-switch runtime tests also
cover a switch during linked-card resolution. Existing search and chat-pagination
runtime tests pass. Visual behavior has not been checked in a live phone session.

Delivery: arm64 1.1/build 152 compiled without warnings and was successfully
installed over USB. Installation-proxy lookup confirmed Not Twitter 1.1/build
152. The Documents copy matches the packaged IPA at
`/home/eric/Documents/Not Twitter/Not Twitter 1.1 (Build 152).ipa`, SHA-256
`cf15f2b64e6f3075146178f7602edfced8460ae00c564497cb037a6cea633199`.
The packaged binary contains the linked-post resolver and display-record keys.


## Composer and Home feedback (1.1 build 153)

Inspected Twitter 9.67's `T1TweetComposeViewController`
`_t1_updateConversationControlContainerFrameForNumberOfLines:origin:fitSize:`
(0x561d8 in T1Twitter): the conversation control uses a 16-point inset and
full-width separator. The app's 68-point inset was incorrectly borrowed from
the tweet text column. The reply control now uses 16 points and the divider
spans its container. Its label uses Bold instead of Heavy.

`TFNScrollingSegmentedViewController._tfn_updateFont` (0x899afc in
TwitterSPMMigration) supplies one `normalBoldFont` to the label bar. Home tabs
now share Bold in both states and retain the same horizontal padding when
selected. A per-navigation-item appearance removes the extra separator between
the title bar and the tabs; the bottom tab separator remains.

`TFNNavigationController.navigationBarCollapsedHeight` (0x8d9948) returns zero;
its scroll callbacks track expansion/collapse and restore the expanded state.
This UIKit implementation uses `hidesBarsOnSwipe` on Home, explicitly binds the
vertical feed on supported OS versions, restores the bar at the top and on exit,
and leaves feed tabs available. The horizontal tab strip and preview table no
longer compete for status-bar scroll-to-top. UIKit owns the collapse animation;
this is not a port of Twitter's private animation engine or accessory collapse.

The missing reply context came from a profile-only opt-in flag in `NFBPostCell`.
Ordinary timeline replies now show their parent handle by default; thread rows
can still explicitly suppress the label when their connected parent is visible.
Unavailable parents show “Replying to a post” without inventing an account name.

Validation: the production-method runtime fixture first failed on an ordinary
feed reply and now passes for feed/profile envelopes, explicit thread suppression,
non-replies and unavailable parents. Existing composer source checks, search
paging and back-gesture runtime tests pass. Reference geometry assertions and
`git diff --check` pass. The arm64 IPA builds without warnings. No live on-device
visual or collapse-animation comparison was performed.

Documents artifact: `Not Twitter 1.1 (Build 153).ipa`, SHA-256
`59428711b545436526175f5f4bd8fc36198b122f7d8196012f899551a652ef3d`.
Release notes include all four feedback fixes.

Delivery: USB installation succeeded; installation-proxy lookup confirmed
Not Twitter 1.1/build 153 on the paired phone.


## Media opening and feed names (1.2 build 154)

Inspected the supplied Twitter 9.67 IPA, specifically
`TFNFullscreenMediaTransition` in TwitterSPMMigration:

- `TFNFullscreenMediaTransitionDefaultDuration` at 0x2ccc558 is 0.25 seconds.
- `_toFullScreenAnimationBlock:` at 0x8c25b0 and its invocation at 0x8c2968
  animate source geometry into the target frame with options 0x20001
  (LayoutSubviews | CurveEaseOut), while bringing background alpha to one.
- `_sourceFrameContentMode`, `_sourceFrameContentsRect`, source clipping and
  `_cornerRadiusAnimationFrom:to:` establish the crop and corner treatment.
- `TFNTwitterAccount(T1Performance).fullscreenMediaTransitionDuration` at
  0x1e50e8 accepts a feature-switch override; this app uses the IPA's default.

The previous generic crossfade for tweet media is replaced by a source-to-fit
opening animator. The tapped preview explicitly supplies its image/player,
geometry and validity through cell/quote delegates, including reader-mode tweet
threads, actor-list tweets, shared quotes in DMs, and composer GIF previews.
The opening clip preserves aspect-fill crop, clips to visible ancestors and the
window, expands to the selected fullscreen page, and removes rounded corners.
The paused inline AVPlayer is retained during the transition so the video path
can display its current frame; the fullscreen player retains the existing saved
playback position. Invalid/missing sources and Reduce Motion use a fade. Profile
photos retain their separate reference-derived 0.175-second animator. Existing
swipe-to-dismiss behavior is unchanged. This adapts the reference's opening
geometry and default timing; private staged exclusion/rotation transitions are
not ported. Live device rendering and video-frame handoff remain unverified.

Feed tabs measure the full label against their content width when tapped. A
truncated label opens a full-name dialog after switching; tapping an already
selected truncated tab also opens it. Short names preserve normal selection.

Validation: the production animator runtime harness covers selected-page
geometry, image/video sources, partial clipping, invalid source and reduced-motion
fallbacks, timing/options, and cancellation cleanup. C geometry tests cover square
video crops, portrait clipping and missing dimensions. The production feed-tab
handler passes selected/unselected truncation, regular tabs and modal-conflict
cases. Back-swipe, search-paging, linked-post, reply-context and composer checks
pass. The arm64 IPA builds without warnings; packaged version is 1.2/build 154.

Documents artifact: `Not Twitter 1.2 (Build 154).ipa`, SHA-256
`705b67cd9798ecc7737619faae2306c2e9d1a003dcd2649464043155faf1115c`. Release notes are saved as `Release Notes 1.2.md` beside it.

Delivery: USB installation succeeded. Installation-proxy lookup confirmed
Not Twitter 1.2/build 154 on the paired iPhone.


## In-place feed title expansion (1.2 build 155)

Replaces build 154's full-name dialog with in-place tab expansion. A tap on a
truncated tab raises its minimum/maximum width to the measured full text width
plus the existing 16-point padding on each side. This also works for the current
tab. The horizontal strip lays out again and scrolls the title's beginning into
view; titles wider than the screen remain horizontally scrollable. Expanded
widths last for the lifetime of those tab buttons and reset when tabs rebuild.
No modal is presented. Short titles and normal feed selection are unchanged.

The production tap-handler runtime test covers selected/unselected expansion,
short names, repeat taps, unrelated constraints and leading-edge scrolling.
The arm64 build and diff checks pass without warnings. UIKit layout has not been
visually checked on-device. Version remains 1.2; build is 155.

Documents copy: `Not Twitter 1.2 (Build 155).ipa`, SHA-256
`2e132b5ce50fa69f98d627193691312f64fceb2166046bea495d583fca4ff9b7`. Release notes updated beside it.

USB installation succeeded; installation-proxy lookup confirmed Not Twitter
1.2/build 155 on the paired iPhone.


## Collapse inactive feed titles (1.2 build 156)

Expanded tabs return to the normal 128-point minimum / 176-point maximum width
when another feed becomes selected. This runs in the shared selection update for
taps, committed swipes and programmatic changes. The selected title remains
expanded during same-feed updates; returning to an old feed keeps it shortened
until tapped again. Layout is refreshed before scrolling the new selection.

The production handler regression covers expand, same-feed retention, switch,
return without expansion and re-expansion, plus short names and unrelated
constraints. The arm64 build and diff checks pass without warnings. No live
on-device visual check was performed.

Documents copy: `Not Twitter 1.2 (Build 156).ipa`, SHA-256
`762761256e7125e8910923ddc1f94ffb2b45c2265f61b633ee2bff685f4d9bbd`. Release notes updated beside it.

USB installation succeeded; installation-proxy lookup confirmed Not Twitter
1.2/build 156 on the paired iPhone.
