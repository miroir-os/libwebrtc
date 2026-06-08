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
  # Exclude protobuf .o files from the ar step — despite rtc_enable_protobuf=false,
  # protobuf-lite objects still get compiled as transitive deps (perfetto/trace).
  sedi 's|-not -path "\*/third_party/nasm/\*"|-not -path "*/third_party/nasm/*" -not -path "*/third_party/protobuf/*"|' "$f"

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
  local f="$1"
  sedi 's/ffmpeg_branding=\\"Chrome\\" \\$//' "$f"
  sedi 's/rtc_use_h264=true/rtc_use_h264=false/' "$f"
  patch_common "$f"
}

patch_mac() {
  local f="$1"
  # Use s/// with embedded newline instead of a\ — POSIX defines \\ in s// replacement
  # but leaves it undefined in a\ text, causing macOS 15 BSD sed to emit a literal \\
  # that breaks bash line continuation inside the gn gen --args="..." string.
  sedi 's/rtc_use_h264=true \\/rtc_use_h264=false \\\
  rtc_objc_prefix=\\"MR\\" \\/' "$f"
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
