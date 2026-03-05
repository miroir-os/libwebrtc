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

patch_common() {
  local f="$1"
  # Exclude protobuf .o files from the ar step — despite rtc_enable_protobuf=false,
  # protobuf-lite objects still get compiled as transitive deps (perfetto/trace).
  sed -i 's|-not -path "\*/third_party/nasm/\*"|-not -path "*/third_party/nasm/*" -not -path "*/third_party/protobuf/*"|' "$f"
}

patch_linux() {
  local f="$1"
  sed -i 's/ffmpeg_branding=\\"Chrome\\" \\$//' "$f"
  sed -i 's/rtc_use_h264=true/rtc_use_h264=false/' "$f"
  patch_common "$f"
}

patch_mac() {
  local f="$1"
  sed -i 's/rtc_use_h264=true/rtc_use_h264=false/' "$f"
  sed -i '/rtc_use_h264=false/a\  rtc_objc_prefix=\\"MR\\" \\' "$f"
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
