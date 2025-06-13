# AutoPing

[![different states](assets/states.png)](https://github.com/alexkhesin/AutoPing/releases)

A macOS menu bar widget which shows a weighted moving average of recent ping times and
packet loss (percentage of failed pings) if any, helpful for monitoring health of a
computer's internet connection. Inspired by a
[similar utility published by Memset in 2010s](https://web.archive.org/web/20160410212547/https://itunes.apple.com/gb/app/autoping/id632347870?mt=12).
I was sad to let it go and had to build something similar.

The app uses [Sparkle 2 framework](https://sparkle-project.org/) to notify of and download updates.
If the "Automtically download" option is chosen, the updates will happen quietly in background,
waiting for the computer or the application to be restarted. If this option is not selected,
the background color of the menubar item will turn orange when updates become available, prompting
to interact with the gadget and select the "Update to \<version\>" menu item to update it.

![when update detected](assets/updated.png)

## Installation

To install, please download a .dmg file from the latest release at https://github.com/alexkhesin/AutoPing/releases.

Select "Launch at Login" in Preferences to continue running after a reboot.

Minimum required macOS version is 15.5 (due to what I am running on my laptop).
Happy to take contributions that make it work on earlier versions.
