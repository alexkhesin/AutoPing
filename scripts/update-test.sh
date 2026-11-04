#!/bin/bash
# Test a release built by scripts/release.sh before publishing it: the
# installed AutoPing is pointed at a copy of the new appcast served from this
# Mac, so it updates exactly as users would.
#
#   scripts/update-test.sh start VERSION [--tamper]
#   scripts/update-test.sh stop
#
# start   Serves build/VERSION (DMG, appcast, ReleaseNotes.html) on 127.0.0.1,
#         points /Applications/AutoPing.app at it, and relaunches it. Then use
#         Check for Updates in AutoPing's menu.
#         The local appcast has its URLs changed, so it is re-signed with the
#         Sparkle key from 1Password. --tamper changes it after signing:
#         an AutoPing that requires signed feeds must then refuse it.
# stop    Removes the override and stops the server. Always run this after
#         testing, or AutoPing keeps checking the local address.
set -euo pipefail

SPARKLE_KEY_REF="op://Private/AutoPing Sparkle EdDSA key/password"
SITE=https://alexkhesin.github.io/AutoPing
PORT=8765
LOCAL=http://127.0.0.1:$PORT
PREFS=$HOME/Library/Containers/com.khesin.autoping/Data/Library/Preferences/com.khesin.autoping

cd "$(dirname "$0")/.."
ROOT=$PWD
SRV=$ROOT/build/update-test
SPARKLE_BIN=$ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin

die() { echo "error: $*" >&2; exit 1; }

stop_server() {
  if [ -f "$SRV.pid" ]; then
    kill "$(cat "$SRV.pid")" 2>/dev/null || true
    rm -f "$SRV.pid"
  fi
}

case ${1:-} in
start)
  V=${2:-}
  [ -n "$V" ] || die "usage: $0 start VERSION [--tamper]"
  TAMPER=0
  [ "${3:-}" != --tamper ] || TAMPER=1
  OUT=$ROOT/build/$V
  [ -f "$OUT/appcast.xml" ] || die "nothing built for $V; run scripts/release.sh build $V first"
  stop_server
  rm -rf "$SRV"
  mkdir -p "$SRV"
  cp -c "$OUT"/assets/* "$SRV"/
  cp "$OUT/ReleaseNotes.html" "$SRV/"
  # Same appcast and release notes, with the GitHub URLs swapped for the local server.
  sed -e "s|https://github.com/alexkhesin/AutoPing/releases/download/$V/|$LOCAL/|g" \
      -e "s|$SITE/ReleaseNotes.html|$LOCAL/ReleaseNotes.html|g" \
      "$OUT/appcast.xml" >"$SRV/appcast.xml"
  op read "$SPARKLE_KEY_REF" | "$SPARKLE_BIN/sign_update" --ed-key-file - "$SRV/appcast.xml" >/dev/null
  if [ $TAMPER = 1 ]; then
    sed -i '' 's|<title>AutoPing</title>|<title>AutoPing (tampered)</title>|' "$SRV/appcast.xml"
    echo "appcast changed after signing: AutoPing should report an improperly signed feed"
  fi
  grep -o 'url="[^"]*"' "$SRV/appcast.xml"

  osascript -e 'tell application "AutoPing" to quit' 2>/dev/null || true
  sleep 2
  pkill -x -u "$(id -u)" AutoPing 2>/dev/null || true
  (cd "$SRV" && exec python3 -I -m http.server $PORT --bind 127.0.0.1 >"$SRV.log" 2>&1) &
  echo $! >"$SRV.pid"
  sleep 1
  curl -sf "$LOCAL/appcast.xml" >/dev/null || die "local server did not start; see $SRV.log"
  defaults write "$PREFS" SUFeedURL "$LOCAL/appcast.xml"
  open /Applications/AutoPing.app
  echo "Relaunched $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/AutoPing.app/Contents/Info.plist) with the local feed."
  echo "Use Check for Updates in AutoPing's menu, then run: $0 stop"
  ;;
stop)
  defaults delete "$PREFS" SUFeedURL 2>/dev/null || true
  stop_server
  echo "Feed override removed and local server stopped."
  ;;
*)
  sed -n '6,7p' "$0" | sed 's/^# *//' >&2
  exit 2
  ;;
esac
