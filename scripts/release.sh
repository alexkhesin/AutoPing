#!/bin/bash
# Build and publish an AutoPing release.
#
#   scripts/release.sh build VERSION [--no-deltas]
#   scripts/release.sh publish VERSION
#
# build    Bumps the version, archives, notarizes, and makes the DMG, delta
#          updates and appcast, and signs the appcast and ReleaseNotes.html
#          (the app requires both to be signed). Nothing leaves this Mac, so
#          the update can be tested first (scripts/update-test.sh).
# publish  Commits, tags and pushes, creates the GitHub release, checks that
#          the downloads work, and only then publishes the appcast together
#          with ReleaseNotes.html (GitHub Pages serves both from main), so
#          users are never offered an update whose files aren't online yet.
#
# Edit ReleaseNotes.html before running build, and not between build and
# publish: its signature is in the appcast. One-time setup is in NOTES.md.
# --no-deltas: ship only the full DMG. Needed when SUPublicEDKey changes,
# because delta updates are always checked against the old key.
set -euo pipefail

TEAM_ID=5H2NK6TXE8
NOTARY_PROFILE=notarytool-password
SPARKLE_KEY_REF="op://Private/AutoPing Sparkle EdDSA key/password"
REPO=alexkhesin/AutoPing
SITE=https://alexkhesin.github.io/AutoPing
PBXPROJ=AutoPing.xcodeproj/project.pbxproj

cd "$(dirname "$0")/.."
ROOT=$PWD

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
usage() { sed -n '4,5p' "$0" | sed 's/^# *//' >&2; exit 2; }
need() { local t; for t in "$@"; do command -v "$t" >/dev/null || die "$t is not installed"; done; }
plist() { /usr/libexec/PlistBuddy -c "Print $1" "$2"; }
# has PATTERN CMD...: does CMD's output (stdout and stderr) match PATTERN?
# Reads all the output first; piping into grep -q would break under pipefail.
has() { local out; out=$("${@:2}" 2>&1) || true; grep -q -- "$1" <<<"$out"; }

[ $# -ge 2 ] || usage
CMD=$1 VERSION=$2
shift 2
NO_DELTAS=0
for a in "$@"; do
  case $a in --no-deltas) NO_DELTAS=1 ;; *) usage ;; esac
done
[[ $VERSION =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "version must look like 1.2 or 1.2.3"

OUT=$ROOT/build/$VERSION
DD=$ROOT/build/DerivedData
RELEASES=$ROOT/releases           # every released DMG, kept to make future delta updates
ASSET_DIR=$OUT/assets             # what generate_appcast sees, and what gets uploaded
SPARKLE_BIN=$DD/SourcePackages/artifacts/sparkle/Sparkle/bin
DMG_NAME=AutoPing_$VERSION.dmg
DOWNLOAD_PREFIX=https://github.com/$REPO/releases/download/$VERSION/

# Value of a build setting in the project file; all configurations must agree.
setting() {
  local v
  v=$(sed -n "s/^[[:space:]]*$1 = \(.*\);/\1/p" "$PBXPROJ" | sort -u)
  [ -n "$v" ] || die "$1 not found in $PBXPROJ"
  [ "$(printf '%s\n' "$v" | wc -l | tr -d ' ')" = 1 ] || die "$1 differs between build configurations: $v"
  printf '%s' "$v"
}

# Fail if the working copy has changes other than the given paths.
only_changed() {
  local f
  for f in $(jj diff --name-only); do
    case " $* " in
      *" $f "*) ;;
      *) die "unexpected change in working copy: $f (commit or restore it first)" ;;
    esac
  done
}

# Exactly one usable Developer ID Application identity for our team; prints its hash.
signing_identity() {
  local ids
  ids=$(security find-identity -v -p codesigning | grep "\"Developer ID Application: .*($TEAM_ID)\"" | awk '{print $2}')
  [ -n "$ids" ] || die "no valid Developer ID Application identity for team $TEAM_ID in the keychain"
  printf '%s\n' "$ids" | head -1
}

# Submit a file for notarization, wait, and fail with Apple's log unless accepted.
notarize() {
  local file=$1 json status id
  json=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || true
  status=$(plutil -extract status raw -o - - <<<"$json" 2>/dev/null) || status=unknown
  id=$(plutil -extract id raw -o - - <<<"$json" 2>/dev/null) || id=
  if [ "$status" != Accepted ]; then
    echo "$json" >&2
    [ -z "$id" ] || xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    die "notarization of $(basename "$file") finished with status: $status"
  fi
  echo "notarized $(basename "$file") (submission $id)"
}

# Set ASSETS to the names of all files the appcast points at (DMG and deltas),
# each of which must exist in $ASSET_DIR.
read_assets() {
  local url
  ASSETS=
  for url in $(grep -o 'url="[^"]*"' "$OUT/appcast.xml" | sed -e 's/^url="//' -e 's/"$//'); do
    case $url in
      "$DOWNLOAD_PREFIX"*) ASSETS="$ASSETS ${url#"$DOWNLOAD_PREFIX"}" ;;
      *) die "appcast URL outside $DOWNLOAD_PREFIX: $url" ;;
    esac
  done
  [ -n "$ASSETS" ] || die "appcast has no download URLs"
  for url in $ASSETS; do [ -f "$ASSET_DIR/$url" ] || die "appcast refers to missing file $ASSET_DIR/$url"; done
}

build() {
  step "Pre-flight checks"
  need xcodebuild xcrun op jj python3 ditto hdiutil
  only_changed ReleaseNotes.html
  local old_version old_build build_num identity f
  old_version=$(setting MARKETING_VERSION)
  old_build=$(setting CURRENT_PROJECT_VERSION)
  build_num=$((old_build + 1))
  [ "$VERSION" != "$old_version" ] || die "$VERSION is already the current version"
  grep -q "data-sparkle-version=\"$build_num\"" ReleaseNotes.html ||
    die "ReleaseNotes.html needs an entry for $VERSION with data-sparkle-version=\"$build_num\""
  identity=$(signing_identity)
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    die "notarization credentials missing; run: xcrun notarytool store-credentials $NOTARY_PROFILE"
  [ ! -e "$OUT" ] || die "$OUT already exists; delete it to rebuild"
  [ ! -e "$RELEASES/$DMG_NAME" ] || die "$RELEASES/$DMG_NAME already exists"
  if [ $NO_DELTAS = 0 ] && ! ls "$RELEASES"/AutoPing_*.dmg >/dev/null 2>&1; then
    die "no earlier DMGs in releases/ to make delta updates from (copy them there, or pass --no-deltas)"
  fi
  op read "$SPARKLE_KEY_REF" >/dev/null || die "cannot read the Sparkle key from 1Password ($SPARKLE_KEY_REF)"

  step "Version $old_version ($old_build) -> $VERSION ($build_num)"
  sed -i '' \
    -e "s/^\([[:space:]]*MARKETING_VERSION = \).*;/\1$VERSION;/" \
    -e "s/^\([[:space:]]*CURRENT_PROJECT_VERSION = \).*;/\1$build_num;/" "$PBXPROJ"
  [ "$(setting MARKETING_VERSION)/$(setting CURRENT_PROJECT_VERSION)" = "$VERSION/$build_num" ] ||
    die "version bump in $PBXPROJ failed"
  mkdir -p "$OUT" "$RELEASES"

  step "Archive (log: build/$VERSION/archive.log)"
  # Package.resolved pins the exact dependency versions; never resolve newer ones here.
  xcodebuild -project AutoPing.xcodeproj -scheme AutoPing -configuration Release \
    -derivedDataPath "$DD" -onlyUsePackageVersionsFromResolvedFile \
    -archivePath "$OUT/AutoPing.xcarchive" archive >"$OUT/archive.log" 2>&1 ||
    { tail -30 "$OUT/archive.log" >&2; die "archive failed"; }

  step "Export with Developer ID signing"
  cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF
  xcodebuild -exportArchive -archivePath "$OUT/AutoPing.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" >"$OUT/export.log" 2>&1 ||
    { tail -30 "$OUT/export.log" >&2; die "export failed"; }
  local app=$OUT/export/AutoPing.app info
  info=$app/Contents/Info.plist
  [ "$(plist CFBundleShortVersionString "$info")" = "$VERSION" ] || die "built app has the wrong version"
  [ "$(plist CFBundleVersion "$info")" = "$build_num" ] || die "built app has the wrong build number"
  codesign --verify --strict --deep "$app"
  has "^TeamIdentifier=$TEAM_ID$" codesign -dv "$app" || die "app is not signed by team $TEAM_ID"
  has "flags=.*runtime" codesign -dv "$app" || die "app is not signed with the hardened runtime"
  echo "SUPublicEDKey: $(plist SUPublicEDKey "$info")"
  echo "SURequireSignedFeed: $(plist SURequireSignedFeed "$info" 2>/dev/null || echo NO)"
  echo "Sparkle: $(plist CFBundleShortVersionString "$app/Contents/Frameworks/Sparkle.framework/Resources/Info.plist")"

  step "Notarize and staple the app"
  ditto -c -k --keepParent "$app" "$OUT/AutoPing.zip"
  notarize "$OUT/AutoPing.zip"
  xcrun stapler staple -q "$app"
  has "source=Notarized Developer ID" spctl -a -t exec -vv "$app" || die "Gatekeeper rejects the app"

  step "Make, sign, notarize and staple the DMG"
  local stage=$OUT/dmg-contents dmg=$OUT/$DMG_NAME
  mkdir "$stage"
  ditto "$app" "$stage/AutoPing.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname AutoPing -srcfolder "$stage" -format UDZO -ov "$dmg"
  codesign --timestamp -s "$identity" "$dmg"
  notarize "$dmg"
  xcrun stapler staple -q "$dmg"
  has "source=Notarized Developer ID" spctl -a -t open --context context:primary-signature -vv "$dmg" ||
    die "Gatekeeper rejects the DMG"

  step "Appcast (signed with the Sparkle key from 1Password)"
  # generate_appcast makes deltas from every older DMG it sees, so with
  # --no-deltas it sees only the new one.
  mkdir "$ASSET_DIR"
  cp -c "$dmg" "$ASSET_DIR/"
  if [ $NO_DELTAS = 0 ]; then
    for f in "$RELEASES"/AutoPing_*.dmg; do cp -c "$f" "$ASSET_DIR/"; done
  fi
  op read "$SPARKLE_KEY_REF" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - \
    --download-url-prefix="$DOWNLOAD_PREFIX" \
    --full-release-notes-url="$SITE/ReleaseNotes.html" \
    --link="https://github.com/$REPO" \
    --maximum-versions=1 \
    -o "$OUT/appcast.xml" "$ASSET_DIR"

  # Sign ReleaseNotes.html. The first time, sign_update also adds a warning
  # comment to the top of the file, so the signed copy is what gets published.
  local notes_sig
  notes_sig=$(op read "$SPARKLE_KEY_REF" | "$SPARKLE_BIN/sign_update" --ed-key-file - ReleaseNotes.html | grep 'sparkle:edSignature=') || true
  [[ $notes_sig =~ ^sparkle:edSignature=\"[A-Za-z0-9+/=]+\"\ sparkle:length=\"[0-9]+\"$ ]] ||
    die "unexpected sign_update output for ReleaseNotes.html: '$notes_sig'"
  cp ReleaseNotes.html "$OUT/ReleaseNotes.html"

  # Also show the release notes in the update dialog, not only under "Version
  # History", with their signature.
  python3 -I - "$OUT/appcast.xml" "$SITE/ReleaseNotes.html" "$notes_sig" <<'PY'
import re, sys
path, url, sig = sys.argv[1:]
s = open(path).read()
if "<sparkle:releaseNotesLink" in s:
    sys.exit("appcast already has a releaseNotesLink")
s, n = re.subn(r"(\n([ \t]*)<sparkle:fullReleaseNotesLink>[^<]*</sparkle:fullReleaseNotesLink>)",
               lambda m: m.group(1) + "\n" + m.group(2) + "<sparkle:releaseNotesLink " + sig + ">" + url + "</sparkle:releaseNotesLink>", s)
if n != 1:
    sys.exit("could not add releaseNotesLink to the appcast")
open(path, "w").write(s)
PY
  # Sign the finished appcast (replacing any signature generate_appcast added
  # before the edit above).
  op read "$SPARKLE_KEY_REF" | "$SPARKLE_BIN/sign_update" --ed-key-file - "$OUT/appcast.xml" >/dev/null
  has '<!-- sparkle-signatures:' cat "$OUT/appcast.xml" || die "appcast is not signed"

  local ac=$OUT/appcast.xml
  [ "$(grep -c '<item>' "$ac")" = 1 ] || die "appcast should have exactly one item"
  grep -q "<sparkle:version>$build_num</sparkle:version>" "$ac" || die "appcast has the wrong build number"
  grep -q "url=\"$DOWNLOAD_PREFIX$DMG_NAME\"" "$ac" || die "appcast does not point at $DMG_NAME"
  [ $NO_DELTAS = 0 ] || ! grep -q '<sparkle:deltas>' "$ac" || die "appcast has deltas despite --no-deltas"
  read_assets
  # Keep the DMG for making future deltas.
  cp "$dmg" "$RELEASES/$DMG_NAME"

  step "Built AutoPing $VERSION ($build_num)"
  echo "Files to upload:$ASSETS"
  echo "Appcast:         build/$VERSION/appcast.xml"
  echo "Next: scripts/update-test.sh start $VERSION, then: scripts/release.sh publish $VERSION"
  echo "To abandon: jj restore $PBXPROJ (ReleaseNotes.html now also carries a signing comment)"
}

publish() {
  step "Pre-flight checks"
  need jj gh curl
  gh auth status >/dev/null 2>&1 || die "gh is not logged in; run: gh auth login"
  local ac=$OUT/appcast.xml f
  [ -f "$ac" ] || die "nothing built for $VERSION; run build first"
  [ "$(setting MARKETING_VERSION)" = "$VERSION" ] || die "project version is not $VERSION"
  only_changed ReleaseNotes.html "$PBXPROJ"
  # publish makes the commits itself, in an order that keeps the live files
  # consistent, so build's changes must still be uncommitted.
  local changed
  changed=" $(jj diff --name-only | tr '\n' ' ')"
  for f in "$PBXPROJ" ReleaseNotes.html; do
    case $changed in
      *" $f "*) ;;
      *) die "$f has no uncommitted changes. publish commits build's changes itself; if you committed them by hand, move them back into the working copy (jj squash --from <that commit> --into @) first" ;;
    esac
  done
  cmp -s ReleaseNotes.html "$OUT/ReleaseNotes.html" ||
    die "ReleaseNotes.html changed since build, so its signature in the appcast no longer matches; delete $OUT, run jj restore $PBXPROJ, and build again"
  read_assets
  jj git fetch
  [ -n "$(jj log --no-graph -r 'main@origin & ::@' -T 'commit_id')" ] ||
    die "the working copy is not on top of main@origin; rebase first"
  ! gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1 || die "GitHub release $VERSION already exists"

  step "About to publish AutoPing $VERSION"
  echo "Commits to push to main:"
  jj log --no-graph -r 'main@origin..@-' -T 'description.first_line() ++ "\n"' | sed 's/^/  /'
  echo "  release $VERSION   (version bump)"
  echo "  appcast and release notes for $VERSION"
  echo "Release assets:$ASSETS"
  local answer
  read -r -p "Publish? [y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ] || die "cancelled"

  step "Commit, tag and push"
  # Only the version bump: ReleaseNotes.html must go live together with the
  # appcast that carries its signature.
  jj commit -m "release $VERSION" "$PBXPROJ"
  jj bookmark set main -r @-
  jj git push --bookmark main
  jj tag set "$VERSION" -r main
  jj git push --tag "$VERSION"

  step "Create the GitHub release"
  local paths=()
  for f in $ASSETS; do paths+=("$ASSET_DIR/$f"); done
  gh release create "$VERSION" --repo "$REPO" --verify-tag --title "$VERSION" \
    --notes "Release notes: $SITE/ReleaseNotes.html" "${paths[@]}"

  step "Check that every download works"
  local want got
  for f in $ASSETS; do
    want=$(stat -f %z "$ASSET_DIR/$f")
    got=$(curl -sfIL "$DOWNLOAD_PREFIX$f" | tr -d '\r' | awk 'tolower($1)=="content-length:"{n=$2} END{print n}')
    [ "$got" = "$want" ] || die "$DOWNLOAD_PREFIX$f: expected $want bytes, server reports '$got'. The appcast was NOT published."
    echo "ok $f ($got bytes)"
  done

  step "Publish the appcast and release notes"
  cp "$ac" appcast.xml
  jj commit -m "appcast and release notes for $VERSION"
  jj bookmark set main -r @-
  jj git push --bookmark main
  echo "Waiting for GitHub Pages to serve them..."
  local i served=$OUT/served
  mkdir -p "$served"
  for i in $(seq 30); do
    if curl -sf "$SITE/appcast.xml?nocache=$RANDOM" -o "$served/appcast.xml" &&
       curl -sf "$SITE/ReleaseNotes.html?nocache=$RANDOM" -o "$served/ReleaseNotes.html" &&
       cmp -s "$served/appcast.xml" appcast.xml && cmp -s "$served/ReleaseNotes.html" ReleaseNotes.html; then
      echo "Live: $SITE/appcast.xml offers $VERSION, and both files match what was signed"
      return
    fi
    sleep 10
  done
  echo "warning: GitHub Pages is not serving the new appcast and release notes yet; check the Pages deployment on GitHub" >&2
}

case $CMD in
  build) build ;;
  publish) [ $NO_DELTAS = 0 ] || usage; publish ;;
  *) usage ;;
esac
