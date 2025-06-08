# Build notes

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

Icon:

* https://developer.apple.com/design/human-interface-guidelines/app-icons
* generate icon with Gemini, use https://pixlr.com/remove-background/ to make background transparent

To package:

* Product/Archive
* Distribute for Direct Distribution
* Export Notarized App
* xcrun stapler staple AutoPing.app (because https://developer.apple.com/documentation/security/customizing-the-notarization-workflow#Staple-the-ticket-to-your-distribution)
* create-dmg AutoPing.app
* notarize the DMG, not sure if it is needed ([this says it is](https://forum.c-command.com/t/do-i-have-to-notarize-my-dmg-and-my-app-when-distributing/14604)):
  * (first time) xcrun notarytool store-credentials "notarytool-password"
    * it will ask for Team ID, which is available in https://developer.apple.com/account
    * and App-specific password that can be created at https://account.apple.com/account/manage
  * xcrun notarytool submit AutoPing\ 1.0.dmg --keychain-profile "notarytool-password" --wait --webhook "https://example.com/notarization"
  * xcrun stapler staple AutoPing\ 1.0.dmg
  * syspolicy_check distribution AutoPing\ 1.0.dmg

TODO:

* Automate this mess:
  * https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
  * https://developer.apple.com/documentation/security/customizing-the-xcode-archive-process

Add Sparkle for updates

* https://sparkle-project.org/documentation/
* https://medium.com/@alex.pera/automating-xcode-sparkle-releases-with-github-actions-bd14f3ca92aa / https://github.com/AlexPerathoner/SparkleReleaseTest?tab=readme-ov-file

* announce on r/macapps, like https://www.reddit.com/r/macapps/comments/qp6c4d/pingr_your_internet_speed_in_your_macs_menu_bar/

* publish on AppStore? https://defn.io/2023/10/22/distributing-mac-app-store-apps-with-github-actions/

* test on VMs (Using Parallels), images: https://osxdaily.com/where-download-macos-installers/
