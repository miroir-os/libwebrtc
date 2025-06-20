#!/bin/bash

libwebrtc_dir="rust-sdks/webrtc-sys/libwebrtc"
linux_script="build_linux.sh"
macos_script="build_macos.sh"

resources_dir="resources"
patch_script="patch_system_ffmpeg.sh"

# 1. Get the arch, profile and platform arguments
arch=""
profile="release"
platform=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch)
      arch="$2"
      if [ "$arch" != "x64" ] && [ "$arch" != "arm64" ]; then
        echo "Error: Invalid value for --arch. Must be 'x64' or 'arm64'."
        exit 1
      fi
      shift 2
      ;;
    --profile)
      profile="$2"
      if [ "$profile" != "debug" ] && [ "$profile" != "release" ]; then
        echo "Error: Invalid value for --profile. Must be 'debug' or 'release'."
        exit 1
      fi
      shift 2
      ;;
    --platform)
      platform="$2"
      if [ "$platform" != "linux" ] && [ "$platform" != "macos" ]; then
        echo "Error: Invalid value for --platform. Must be 'linux' or 'macos'."
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Error: Unknown argument '$1'"
      exit 1
      ;;
  esac
done

if [ -z "$arch" ]; then
  echo "Error: --arch must be set."
  exit 1
fi

if [ -z "$platform" ]; then
  echo "Error: --platform must be set."
  exit 1
fi

# 2. Modify Build Scripts
if [ ! -f "$libwebrtc_dir/$patch_script" ]; then
  cp "$resources_dir/$patch_script" "$libwebrtc_dir/$patch_script" || exit 1
fi

if [ "$platform" = "linux" ]; then
  echo "Patching $linux_script..."
  # Remove ffmpeg_branding line
  sed -i '/ffmpeg_branding=\\"Chrome\\" \\/d' "$libwebrtc_dir/$linux_script"
  # Remove rtc_use_ffmpeg_h264_encoder line
  sed -i '/rtc_use_ffmpeg_h264_encoder=true \\/d' "$libwebrtc_dir/$linux_script"
  # Add the call to the patch after source code is setup and before building
  if ! grep -qF "$patch_script" "$libwebrtc_dir/$linux_script"; then
    sed -i '/^# build static library$/i \
"$COMMAND_DIR/'"$patch_script"'"' "$libwebrtc_dir/$linux_script"
  fi
fi

if [ "$platform" = "macos" ]; then
  # macOS sed requires '' after -i

  echo "Patching $macos_script..."
  # Remove ffmpeg_branding line
  sed -i '' '/ffmpeg_branding=/d' "$libwebrtc_dir/$macos_script" 
  # Add the call to the patch after source code is setup and before building
  if ! grep -qF "$patch_script" "$libwebrtc_dir/$macos_script"; then
    sed -i '' '/^# build static library$/i \
"$COMMAND_DIR/'"$patch_script"'"' "$libwebrtc_dir/$macos_script"
  fi
fi

# 3. Run the build script
echo -e "Starting build...\n"
cd "$libwebrtc_dir" || exit 1

case "$platform" in
  linux)
    "./$linux_script" --arch "$arch" --profile "$profile"
    echo -e "\nBuild completed successfully:"
    echo "$libwebrtc_dir/linux-$arch-$profile/"
    ;;
  macos)
    "./$macos_script" --arch "$arch" --profile "$profile"
    echo -e "\nBuild completed successfully:"
    echo "$libwebrtc_dir/mac-$arch-$profile/"
    ;;
  *)
    echo "Error: Unknown platform '$platform'. Must be 'linux' or 'macos'."
    exit 1
    ;;
esac


