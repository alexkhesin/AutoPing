# Build notes

## Initial project configuration
Generated a project using App template, selecting
* Interface: SwiftUI
* Language: Swift
* Testing System: None
* Storage: None

Add package dependencies for RingBuffer and SimplePing

* https://github.com/alexkhesin/RingBuffer
* https://github.com/alexkhesin/SimplePing

Add icons under AutoPing/Assets

In project properties, for AutoPing target:

* General
  * Minimum Deployments: macOS 15.5
* Identity
  * App Category: Utilities
  * Display Name: AutoPing
* Signing & Capabilities
  * Signing
    * Turn off "Automatically manage signing"
    * Bundle Identifier: low-case com.khesin.autoping
    * Add Team and Signing Certificate "Developer ID Application"
  * App Sandbox
    * Network: enable Incoming and Outgoing connections
* Build Settings
  * Application is Agent (UIElement): Yes
  * Dead Code Stripping: Yes

* Add icons under Assets

Install ImageMagick, to scale icons with https://imagemagick.org/script/convert.php

Icon:

* https://developer.apple.com/design/human-interface-guidelines/app-icons
* generated icon with Gemini, used https://pixlr.com/remove-background/ to make background transparent

## Connect to Github pages

Github serves files in raw mode with `Content-Type: text/plain`, which prevents Sparkle from properly downloading appcast.xml or release notes (https://github.com/sparkle-project/Sparkle/issues/1564). Followed instructions in https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site to configure publishing the root directory of the `main` branch of my repo to https://alexkhesin.github.io/AutoPing.

## Releases

### One-time setup on a new Mac

* Developer ID Application certificate for team 5H2NK6TXE8 in the login keychain.
  A backup (.p12 and its password) is in 1Password as "AutoPing Developer ID".
  If it's lost, create a new one at https://developer.apple.com/account (Certificates, +,
  Developer ID Application); Sparkle and Gatekeeper only check the team. Only the Account
  Holder can do this, after accepting any pending agreement on that site. If Keychain says
  "not trusted", install https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
* Notarization credentials: `xcrun notarytool store-credentials notarytool-password`
  (Apple ID, team ID, and an app-specific password from https://account.apple.com/account/manage)
* Sparkle EdDSA private key: in 1Password at `op://Private/AutoPing Sparkle EdDSA key/password`,
  plus an offline copy. It's the one secret that can't simply be recreated (see Key history).
  Install the 1Password CLI (`op`) and turn on its desktop app integration.
* GitHub CLI: `brew install gh`, then `gh auth login`
* Commit email: GitHub blocks pushes that expose the private address, so use
  `jj config set --repo user.email 1182112+alexkhesin@users.noreply.github.com`
* `releases/`: every released DMG signed with the current Sparkle key, used to make delta
  updates. Not in git; re-download from the GitHub releases if missing. DMGs signed with an
  older key go in `releases/old-key/` (deltas from them would be rejected).
* AutoPing installed in /Applications, for testing updates.

### Every release

1. Add an entry to ReleaseNotes.html with `data-sparkle-version` set to the next build number.
2. `scripts/release.sh build VERSION` bumps the version, archives, notarizes, and makes the
   DMG, deltas and appcast under build/VERSION, and signs the appcast and ReleaseNotes.html
   (which gets a signing comment at the top). Nothing is published. Don't edit
   ReleaseNotes.html again until after publish. Use `--no-deltas` when SUPublicEDKey changes.
3. Test, then always finish with `scripts/update-test.sh stop`:
   * `scripts/update-test.sh start VERSION`, then Check for Updates in AutoPing's menu: it
     should offer VERSION and install it.
   * Now that VERSION is installed, `start VERSION` again: Check for Updates should say it's
     up to date (the signature checks passed). With `start VERSION --tamper` it should say the
     update feed is improperly signed.
4. `scripts/release.sh publish VERSION` commits, tags, pushes, creates the GitHub release,
   checks the downloads, then publishes the appcast and ReleaseNotes.html together and waits
   until GitHub Pages serves them.

`build` warns, at its start and end, if a newer Sparkle release exists than the one pinned in
Package.resolved. Sparkle releases often include security fixes; to upgrade, use Xcode's
File > Packages > Update to Latest Package Versions, commit Package.resolved, and build again.

GitHub rulesets ("Protect main", "Protect release tags", under Settings > Rules) block deleting
or force-pushing `main` and deleting or moving tags. Normal pushes, like the ones `publish`
makes, are unaffected. Don't add "require pull requests", or `publish` can't push.

To abandon a build: `jj restore AutoPing.xcodeproj/project.pbxproj`, undo the signing comment
in ReleaseNotes.html if wanted, and delete build/VERSION and releases/AutoPing_VERSION.dmg.

### Signed appcast and release notes

Since 1.1.4 the app sets `SURequireSignedFeed` (and `SUVerifyUpdateBeforeExtraction`, which
Sparkle requires with it), so appcast.xml and ReleaseNotes.html must carry valid EdDSA
signatures. The release script signs both. Consequences:

* Don't edit ReleaseNotes.html or appcast.xml outside a release: the live appcast holds the
  release notes' signature, and an unsigned appcast change makes Sparkle refuse the feed.
  If you must, re-sign with the tools in
  `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`: `sign_update` on
  ReleaseNotes.html, put the new signature and length on `sparkle:releaseNotesLink` in
  appcast.xml, then `sign_update` appcast.xml (key via `op read ... | sign_update --ed-key-file -`).
* If the Sparkle key is ever lost, installed apps reject the new feed for 20 days
  (`SUSignedFeedFailureExpirationInterval`), then accept a key rotation release.

### Key history

* Up to 1.1.2: Sparkle key `IHNLenwncSlrbywVtovsXgBmk0uRIVMVuoOY3PmkjeE=` and the original
  Developer ID certificate. Both private keys were only in an old Mac's login keychain, whose
  password was lost.
* 1.1.3 (Nov 2026): rotated to Sparkle key `LFoVIQv7SopF4aYsZSNcKNgcEFVWHsL2lfnktqEGE/g=` and a
  new Developer ID certificate (expires 2027-12-04). Sparkle accepted the change because the
  new app passes the old app's code-signing requirement (any Developer ID cert of team
  5H2NK6TXE8). Shipped without deltas, since deltas are always checked against the old key.
* To rotate again: new key, update SUPublicEDKey, keep the same team's Developer ID signing,
  build with `--no-deltas`, test the update from the previous version before publishing.

### TODO

* publish on AppStore? https://defn.io/2023/10/22/distributing-mac-app-store-apps-with-github-actions/

* test on VMs (Using Parallels), images: https://osxdaily.com/where-download-macos-installers/
