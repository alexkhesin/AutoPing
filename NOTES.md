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
  Developer ID Application); Sparkle and Gatekeeper only check the team. If Keychain says
  "not trusted", install https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
* Notarization credentials: `xcrun notarytool store-credentials notarytool-password`
  (Apple ID, team ID, and an app-specific password from https://account.apple.com/account/manage)
* Sparkle EdDSA private key: in 1Password at `op://Private/AutoPing Sparkle EdDSA key/password`,
  plus an offline copy. Losing it forces a key rotation release (as in 1.1.3).
  Install the 1Password CLI (`op`) and turn on its desktop app integration.
* GitHub CLI: `brew install gh`, then `gh auth login`
* `releases/`: every released DMG, used to make delta updates. Not in git; re-download
  from the GitHub releases if missing.

### Every release

1. Add an entry to ReleaseNotes.html with `data-sparkle-version` set to the next build number.
2. `scripts/release.sh build VERSION` bumps the version, archives, notarizes, and makes the
   DMG, deltas and signed appcast under build/VERSION. Nothing is published.
   Use `--no-deltas` when SUPublicEDKey changes.
3. Test the update from the previous version against build/VERSION/appcast.xml.
4. `scripts/release.sh publish VERSION` commits, tags, pushes, creates the GitHub release,
   checks the downloads, then publishes the appcast.

### TODO

* publish on AppStore? https://defn.io/2023/10/22/distributing-mac-app-store-apps-with-github-actions/

* test on VMs (Using Parallels), images: https://osxdaily.com/where-download-macos-installers/
