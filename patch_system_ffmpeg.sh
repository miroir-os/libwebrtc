#!/bin/bash

# Script to patch WebRTC to use system FFmpeg instead of bundled FFmpeg
# This permanently replaces bundled FFmpeg with system FFmpeg

set -e

echo "Patching WebRTC to use system FFmpeg..."

# 1. Replace the entire BUILD.gn file with system FFmpeg version
echo "Replacing src/third_party/ffmpeg/BUILD.gn..."
cp src/third_party/ffmpeg/BUILD.gn src/third_party/ffmpeg/BUILD.gn.backup 2>/dev/null || true

cat > src/third_party/ffmpeg/BUILD.gn << 'EOF'
# Copyright 2014 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import("//build/buildflag_header.gni")
import("//build/config/compiler/compiler.gni")

if (is_linux) {
  import("//build/config/linux/pkg_config.gni")
}

# Path to platform configuration files (used for includes)
platform_config_root = "chromium/config/Chrome/linux/x64"

config("ffmpeg_dependent_config") {
  include_dirs = [
    platform_config_root,
    ".",
  ]
}

buildflag_header("ffmpeg_features") {
  header = "ffmpeg_features.h"
  flags = []
}

# System FFmpeg configuration
if (is_linux) {
  config("system_ffmpeg") {
    # Standard locations for FFmpeg on Linux distributions
    # Adjust paths for other architectures:
    # - ARM64: /usr/lib/aarch64-linux-gnu
    # - ARM32: /usr/lib/arm-linux-gnueabihf
    cflags = [
      "-isystem/usr/include/x86_64-linux-gnu",
      "-isystem/usr/include",
    ]
    
    libs = [
      "avcodec",
      "avformat",
      "avutil",
    ]
    
    lib_dirs = [
      "/usr/lib/x86_64-linux-gnu",
      "/usr/lib",
    ]
  }
} else if (is_mac) {
  config("system_ffmpeg") {
    # macOS system FFmpeg paths
    if (target_cpu == "arm64") {
      # Apple Silicon paths
      cflags = [
        "-isystem/opt/homebrew/include",
        "-isystem/usr/local/include",
        "-isystem/opt/local/include",
      ]
      lib_dirs = [
        "/opt/homebrew/lib",
        "/usr/local/lib",
        "/opt/local/lib",
      ]
    } else {
      # Intel Mac paths
      cflags = [
        "-isystem/usr/local/include",
        "-isystem/opt/homebrew/include",
        "-isystem/opt/local/include",
      ]
      lib_dirs = [
        "/usr/local/lib",
        "/opt/homebrew/lib",
        "/opt/local/lib",
      ]
    }
    
    libs = [
      "avcodec",
      "avformat",
      "avutil",
    ]
  }
}

# Simple group target for system FFmpeg
group("ffmpeg_internal") {
  if (is_linux || is_mac) {
    public_configs = [ ":system_ffmpeg" ]
  } else {
    assert(false, "System FFmpeg only supported on Linux and macOS")
  }
}

# Main ffmpeg target
group("ffmpeg") {
  public_configs = [ ":ffmpeg_dependent_config" ]
  deps = [ 
    ":ffmpeg_internal",
    ":ffmpeg_features",
  ]
}

# Empty nasm target (not needed for system FFmpeg)
static_library("ffmpeg_nasm") {
  sources = []
}
EOF

# 2. Modify Build Scripts
echo "Patching build scripts..."

# Linux Build Script
if [ -f build_linux.sh ]; then
    echo "Patching build_linux.sh..."
    # Remove ffmpeg_branding line
    sed -i '/ffmpeg_branding=\\"Chrome\\" \\/d' build_linux.sh
    # Remove rtc_use_ffmpeg_h264_encoder line if it exists
    sed -i '/rtc_use_ffmpeg_h264_encoder=true \\/d' build_linux.sh
fi

# macOS Build Script  
if [ -f build_macos.sh ]; then
    echo "Patching build_macos.sh..."
    # Remove ffmpeg_branding line if it exists
    sed -i '/ffmpeg_branding=/d' build_macos.sh
fi

# 3. Update H264 Decoder Implementation to use system FFmpeg headers
echo "Patching H264 decoder implementation..."
H264_DECODER="src/modules/video_coding/codecs/h264/h264_decoder_impl.cc"
if [ -f "$H264_DECODER" ]; then
    # Create a backup
    cp "$H264_DECODER" "$H264_DECODER.backup" 2>/dev/null || true
    
    # Replace bundled FFmpeg headers with system headers
    sed -i 's|#include "third_party/ffmpeg/libavcodec/avcodec.h"|#include <libavcodec/avcodec.h>|' "$H264_DECODER"
    sed -i 's|#include "third_party/ffmpeg/libavformat/avformat.h"|#include <libavformat/avformat.h>|' "$H264_DECODER"
    sed -i 's|#include "third_party/ffmpeg/libavutil/imgutils.h"|#include <libavutil/imgutils.h>|' "$H264_DECODER"
    sed -i 's|#include "third_party/ffmpeg/libavutil/log.h"|#include <libavutil/log.h>|' "$H264_DECODER"
fi

echo "Patching complete!"
echo ""
echo "System FFmpeg will now be used instead of bundled FFmpeg."
echo ""
echo "Prerequisites:"
echo "- Linux: libavcodec-dev libavformat-dev libavutil-dev"
echo "- macOS: FFmpeg from Homebrew or MacPorts"
echo ""
echo "The patch modifies:"
echo "- src/third_party/ffmpeg/BUILD.gn (replaced with system FFmpeg config)"
echo "- build scripts (removed ffmpeg_branding lines)"
echo "- H264 decoder (uses system headers)"