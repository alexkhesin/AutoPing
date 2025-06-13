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

Install cmd line tools, installed with macports:

* create-dmg-js, https://github.com/sindresorhus/create-dmg
* ImageMagick, to scale icons with https://imagemagick.org/script/convert.php
* xmlstarlet
* jq

Icon:

* https://developer.apple.com/design/human-interface-guidelines/app-icons
* generated icon with Gemini, used https://pixlr.com/remove-background/ to make background transparent

## Connect to Github pages

Github serves files in raw mode with `Content-Type: text/plain`, which prevents Sparkle from properly downloading appcast.xml or release notes (https://github.com/sparkle-project/Sparkle/issues/1564). Followed instructions in https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site to configure publishing the root directory of the `main` branch of my repo to https://alexkhesin.github.io/AutoPing.

## For every new release (automate this!)
From project's root directory (~/src/AutoPing):
* Project-level Build Settings, filter for Versioning, adjust
  * Current Project Version and Marketing Version (TODO automate this somehow!)
* Product/Archive
* Distribute for Direct Distribution
* Export Notarized App to ~/Downloads
* `xcrun stapler staple ~/Downloads/AutoPing.app` (because https://developer.apple.com/documentation/security/customizing-the-notarization-workflow#Staple-the-ticket-to-your-distribution)
* `create-dmg ~/Downloads/AutoPing.app releases`
* `VERSION=1.0.1` (or whatever create-dmg says it is)
* notarize the DMG, not sure if it is needed ([this says it is](https://forum.c-command.com/t/do-i-have-to-notarize-my-dmg-and-my-app-when-distributing/14604)):
  * (first time) `xcrun notarytool store-credentials "notarytool-password"`
    * it will ask for Team ID, which is available in https://developer.apple.com/account
    * and App-specific password that can be created at https://account.apple.com/account/manage
  * `xcrun notarytool submit releases/AutoPing\ ${VERSION}.dmg --keychain-profile "notarytool-password" --wait --webhook "https://example.com/notarization"`
  * `xcrun stapler staple releases/AutoPing\ ${VERSION}.dmg`
* `syspolicy_check distribution releases/AutoPing\ ${VERSION}.dmg` (optional)
* `mv releases/AutoPing\ ${VERSION}.dmg releases/AutoPing_${VERSION}.dmg`
* 1$(xcodebuild -showBuildSettings -scheme AutoPing -json 2> /dev/null | jq -r '.[0].buildSettings.BUILD_DIR')/../../SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --full-release-notes-url=https://alexkhesin.github.io/AutoPing/ReleaseNotes.html --link=https://github.com/alexkhesin/AutoPing --download-url-prefix=https://github.com/alexkhesin/AutoPing/releases/download/${VERSION}/ --maximum-versions=1 releases -o ./appcast.xml`
  * (`--maximum-versions=1` because `--download-url-prefix` includes version number, invalidating paths for previous versions)
* `xmlstarlet ed -L -a /rss/channel/item/sparkle:fullReleaseNotesLink -t elem -n sparkle:releaseNotesLink -v "https://alexkhesin.github.io/AutoPing/ReleaseNotes.html" ./appcast.xml`
* submit appropriate files via git
* `git tag ${VERSION} -m "Release version ${VERSION}"`
* `git push --tags`
* create release in github and upload .dmg and .delta files

### TODO

* Automate this mess:
  * https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
  * https://developer.apple.com/documentation/security/customizing-the-xcode-archive-process
  * Sample workflows:
    * https://github.com/TheAcharya/MarkerData/tree/main/.github/workflows

* publish on AppStore? https://defn.io/2023/10/22/distributing-mac-app-store-apps-with-github-actions/

* test on VMs (Using Parallels), images: https://osxdaily.com/where-download-macos-installers/
