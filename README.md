# Not Twitter ATProto App

This is a clean standalone iOS app for the Bluesky-backed Not Twitter build. It does not inject into the Twitter/X app and it does not ship any Twitter networking code.

The app is native UIKit: Home, Explore, Notifications, Profile, and Compose are rendered on-device and backed by ATProto XRPC calls.

The native session layer uses Bluesky OAuth with DPoP and talks to:

```text
https://nottwitterapp.github.io/oauth/neofreebird-client-metadata.json
io.github.nottwitterapp:/not-twitter/oauth/neofreebird-callback
https://bsky.social
https://api.bsky.app
```

There is no WebView frontend wrapper in the app target.

Build on Linux:

```bash
./build-linux.sh
```

Install with xtool through the build helper so the bundle identifier is rewritten for the selected provisioning profile:

```bash
xtool auth login
./build-linux.sh --install --udid YOUR_CONNECTED_DEVICE_UDID
```

By default, the helper leaves the IPA bundle identifier as `com.nottwitter.atproto`
and lets xtool rewrite/sign it exactly once. Only set `XTOOL_BUNDLE_ID` when you
need to force a specific explicit Apple Developer App ID.

Use `idevice_id -l` to identify the currently connected phone. The helper prefers
`../_build/bin/xtool`; that local copy was rebuilt from xtool 1.19.0 with Swift 6.4
after the system binary failed with an unresolved Foundation symbol. Rebuild
using `swift build -c release --product xtool --jobs 4 --build-system native`
if the Swift runtime changes again.

## APNs setup

The native app already requests a device token through `UIApplication registerForRemoteNotifications`, stores the latest token, and registers it with Bluesky using `app.bsky.notification.registerPush`. The `appId` sent to Bluesky is the installed bundle identifier, so the Apple Developer App ID, provisioning profile, APNs topic, and installed bundle ID must all match.

For a normal Apple Developer build, create an explicit App ID for:

```text
com.nottwitter.atproto
```

Enable Push Notifications for that App ID, create a development provisioning profile with the target device included, and sign with an entitlement containing:

```xml
<key>aps-environment</key>
<string>development</string>
```

For a forced explicit bundle identifier, override it before running the helper:

```bash
XTOOL_BUNDLE_ID=com.nottwitter.atproto ./build-linux.sh --install --udid YOUR_CONNECTED_DEVICE_UDID
```

For TestFlight or App Store builds, use a production provisioning profile and change the entitlement environment to `production`.

## Session renewal

OAuth responses persist `expires_in` as an absolute expiry per account. Older
saved sessions fall back to the access JWT's expiry; opaque tokens without expiry
metadata are refreshed conservatively. Foreground entry, the maintenance timer,
and authenticated requests all use the same refresh coordinator.

Refreshes are coalesced per account, and rotated credentials are stored only if
the original refresh token and DPoP key still match. JSON and media-upload retries
retain their originating account/key, and a late 401 reuses an already-rotated
access token. Failed refreshes retain the saved session and have a 60-second
cooldown. The maintenance timer runs while iOS schedules the app; foreground and
request checks handle resuming after suspension.

Run the portable timing-policy checks:

```bash
cc -Wall -Wextra -Werror tests/token-refresh-policy.c -lm -o /tmp/nfb-token-refresh-policy
/tmp/nfb-token-refresh-policy
```

These checks exercise the production timing policy, not iOS networking or account
switch concurrency. Those paths require device/simulator integration testing.
Server-side revocation or the authorization server's maximum session lifetime can
still require signing in again.
