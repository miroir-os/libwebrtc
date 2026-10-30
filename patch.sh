#!/usr/bin/env bash
set -euo pipefail

# Applies MiroirOS patches to LiveKit's libwebrtc build scripts.
#
# Usage:
#   ./patch.sh <platform> <build_script_path>
#
# Examples:
#   ./patch.sh linux /path/to/webrtc-sys/libwebrtc/build_linux.sh
#   ./patch.sh mac   /path/to/webrtc-sys/libwebrtc/build_macos.sh

platform="${1:?Usage: ./patch.sh <linux|mac> <build_script_path>}"
build_script="${2:?Usage: ./patch.sh <linux|mac> <build_script_path>}"

if [ ! -f "$build_script" ]; then
  echo "Error: build script not found: $build_script"
  exit 1
fi

# macOS sed requires -i '' while GNU sed requires -i
sedi() {
  if [[ "$OSTYPE" == darwin* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

patch_common() {
  local f="$1"
  # Pin webrtc-sdk to WEBRTC_COMMIT. The .gclient from LK points to a moving
  # release branch (@mXXX_release); rewriting to @<sha> makes gclient sync
  # resolve deterministically across CI runs.
  if [ -z "${WEBRTC_COMMIT:-}" ]; then
    echo "Error: WEBRTC_COMMIT env var must be set" >&2
    exit 1
  fi
  sedi "s|webrtc-sdk/webrtc.git@m[0-9][0-9]*_release|webrtc-sdk/webrtc.git@${WEBRTC_COMMIT}|" \
    "$(dirname "$f")/.gclient"
}

patch_linux() {
  patch_common "$1"
}

patch_mac() {
  local f="$1"
  # Prefixes the bundled FFmpeg's symbols as build_linux.sh does: the change proposed upstream, see PATCHES.md.
  patch --forward "$f" < "$(dirname "$0")/patches/build_macos-ffmpeg-prefix.patch"
  patch_common "$f"
}

case "$platform" in
  linux) patch_linux "$build_script" ;;
  mac)   patch_mac "$build_script" ;;
  *)
    echo "Error: unsupported platform '$platform' (expected 'linux' or 'mac')"
    exit 1
    ;;
esac

echo "Patched: $build_script"
