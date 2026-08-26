#!/usr/bin/env bash

# Build HermesMobile for a physical iOS device and wrap the .app in an IPA.
# Signing is intentionally off — no Apple Developer account required.
#
# The resulting IPA will not install on a stock iPhone until a sideloading
# tool (AltStore, SideStore, Feather, etc.) re-signs it. This script
# only produces the archive.

# --- Xcode toolchain guard: build with a real Xcode.app (not the Command Line Tools),
# resolved via DEVELOPER_DIR (no sudo). ---
if [ -z "${DEVELOPER_DIR:-}" ]; then
  case "$(xcode-select -p 2>/dev/null)" in
    */Xcode*.app/Contents/Developer) : ;;
    *) for _xc in /Applications/Xcode.app /Applications/Xcode-*.app; do
         [ -x "$_xc/Contents/Developer/usr/bin/xcodebuild" ] && { export DEVELOPER_DIR="$_xc/Contents/Developer"; break; }
       done ;;
  esac
fi

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCHEME="${SCHEME:-HermesMobile}"
CONFIG="${CONFIG:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/build/DerivedData-ios}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/build}"
WORKSPACE="$REPO_ROOT/HermesMobile.xcworkspace"
PROJECT="$REPO_ROOT/HermesMobile.xcodeproj"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "this script requires macOS and Xcode (Linux cannot produce an iOS IPA)"

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found; install Xcode"
command -v ditto >/dev/null 2>&1 || die "ditto not found"

log "Xcode $(xcodebuild -version | tr '\n' ' ')"
log "iOS SDK $(xcrun --sdk iphoneos --show-sdk-version)"

# Tuist project is gitignored — generate when the workspace is missing.
if [[ ! -d "$WORKSPACE" && ! -d "$PROJECT" ]]; then
  log "Generated Xcode project missing; running tuist install + generate"
  command -v tuist >/dev/null 2>&1 || die "tuist not found; install Tuist or run make setup on a machine with it"
  (cd "$REPO_ROOT" && tuist install && tuist generate --no-open)
fi

if [[ -d "$WORKSPACE" ]]; then
  BUILD_ROOT=(-workspace "$WORKSPACE")
elif [[ -d "$PROJECT" ]]; then
  BUILD_ROOT=(-project "$PROJECT")
else
  die "neither HermesMobile.xcworkspace nor HermesMobile.xcodeproj found after generate"
fi

log "Resolving Swift packages"
xcodebuild -resolvePackageDependencies "${BUILD_ROOT[@]}" -scheme "$SCHEME"

log "Building unsigned $CONFIG $SCHEME for generic iOS"
mkdir -p "$DERIVED_DATA" "$OUT_DIR"
XCODEBUILD_EXTRA=()
if [[ -n "${IOS_BUILD_NUMBER:-}" ]]; then
  log "Using CI build number $IOS_BUILD_NUMBER as CFBundleVersion"
  XCODEBUILD_EXTRA+=(CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER")
fi
xcodebuild \
  "${BUILD_ROOT[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  ENABLE_PREVIEWS=NO \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  "${XCODEBUILD_EXTRA[@]}" \
  build

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/${CONFIG}-iphoneos"
APP_PATH=""
if [[ -d "$PRODUCTS_DIR/HermesMobile.app" ]]; then
  APP_PATH="$PRODUCTS_DIR/HermesMobile.app"
else
  # Discover the .app if the product name differs from the scheme.
  shopt -s nullglob
  apps=("$PRODUCTS_DIR"/*.app)
  shopt -u nullglob
  if [[ ${#apps[@]} -eq 1 ]]; then
    APP_PATH="${apps[0]}"
  elif [[ ${#apps[@]} -gt 1 ]]; then
    for candidate in "${apps[@]}"; do
      if [[ "$(basename "$candidate")" == "HermesMobile.app" ]]; then
        APP_PATH="$candidate"
        break
      fi
    done
    [[ -n "$APP_PATH" ]] || APP_PATH="${apps[0]}"
  fi
fi
[[ -d "$APP_PATH" ]] || die "build completed, but app bundle was not found under $PRODUCTS_DIR"

APP_BASENAME="$(basename "$APP_PATH")"

plist_value() {
  local key="$1"
  if command -v defaults >/dev/null 2>&1; then
    defaults read "$APP_PATH/Info" "$key" 2>/dev/null || true
  fi
}
VERSION="$(plist_value CFBundleShortVersionString)"
BUILD="$(plist_value CFBundleVersion)"
VERSION="${VERSION:-unknown}"
BUILD="${BUILD:-0}"
IPA_PATH="$OUT_DIR/HermesMobile-${VERSION}-${BUILD}-unsigned.ipa"

log "Packaging Payload/$APP_BASENAME → $IPA_PATH"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hermes-ipa.XXXXXX")"
cleanup_stage() { rm -rf "$STAGE"; }
trap cleanup_stage EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP_PATH" "$STAGE/Payload/$APP_BASENAME"
rm -f "$IPA_PATH"
ditto -c -k --norsrc --keepParent "$STAGE/Payload" "$IPA_PATH"

[[ -f "$IPA_PATH" ]] || die "IPA was not written"
STABLE_IPA="$OUT_DIR/HermesMobile.ipa"
cp "$IPA_PATH" "$STABLE_IPA"
if stat -f%z "$IPA_PATH" >/dev/null 2>&1; then
  IPA_SIZE="$(stat -f%z "$IPA_PATH")"
else
  IPA_SIZE="$(stat -c%s "$IPA_PATH")"
fi
python3 - "$OUT_DIR/ipa-meta.json" "$VERSION" "$BUILD" "$IPA_PATH" "$STABLE_IPA" "$IPA_SIZE" <<'PY'
import json, os, sys
out, version, build, ipa, stable, size = sys.argv[1:7]
payload = {
    "version": version,
    "build": str(build),
    "ipa": os.path.abspath(ipa),
    "ipaName": os.path.basename(ipa),
    "ipaStable": os.path.abspath(stable),
    "size": int(size),
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
PY
log "IPA ready: $IPA_PATH ($(du -h "$IPA_PATH" | awk '{print $1}'))"
printf '%s\n' "$IPA_PATH"
