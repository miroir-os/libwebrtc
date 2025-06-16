# macOS System FFmpeg Support

This document describes the changes made to support system FFmpeg on macOS builds.

## Changes Made

### 1. FFmpeg BUILD.gn Configuration
Added macOS-specific configuration to handle different FFmpeg installation locations:
- **Homebrew on Apple Silicon**: `/opt/homebrew`
- **Homebrew on Intel**: `/usr/local`
- **MacPorts**: `/opt/local`

The configuration automatically includes all common paths to ensure FFmpeg is found regardless of installation method.

### 2. Build Script Updates
- Modified `build_macos.sh` to include `use_system_ffmpeg=true` flag
- Updated `patch_system_ffmpeg.sh` to handle macOS sed syntax differences

### 3. Verification Script
Enhanced `verify_system_ffmpeg.sh` to:
- Detect macOS and check common FFmpeg locations
- Support both Linux and macOS build directories
- Provide macOS-specific installation instructions

## Installation Instructions

### Installing FFmpeg on macOS

**Using Homebrew (Recommended):**
```bash
brew install ffmpeg
```

**Using MacPorts:**
```bash
sudo port install ffmpeg-devel
```

### Building with System FFmpeg

1. Apply the patch:
```bash
./patch_system_ffmpeg.sh
```

2. Clean previous builds:
```bash
rm -rf src/out*
rm -rf mac-*
```

3. Build for your architecture:
```bash
# For Apple Silicon (M1/M2/M3)
./build_macos.sh --arch arm64 --profile release

# For Intel Macs
./build_macos.sh --arch x64 --profile release
```

4. Verify the build:
```bash
./verify_system_ffmpeg.sh
```

## Architecture-Specific Notes

### Apple Silicon (arm64)
The build system will look for FFmpeg in this order:
1. `/opt/homebrew` (default Homebrew location on Apple Silicon)
2. `/usr/local` (fallback)
3. `/opt/local` (MacPorts)

### Intel (x64)
The build system will look for FFmpeg in this order:
1. `/usr/local` (default Homebrew location on Intel)
2. `/opt/homebrew` (fallback)
3. `/opt/local` (MacPorts)

## Troubleshooting

### FFmpeg Not Found
If the build fails to find FFmpeg, check:
1. FFmpeg is installed: `brew list ffmpeg` or `port installed ffmpeg`
2. Headers are accessible: `ls /opt/homebrew/include/libavcodec/avcodec.h`
3. Libraries are present: `ls /opt/homebrew/lib/libavcodec.dylib`

### Custom FFmpeg Location
If FFmpeg is installed in a non-standard location, you may need to manually edit the paths in the generated `src/third_party/ffmpeg/BUILD.gn` file after running the patch script.

### Linking Issues
When building applications that use libwebrtc.a with system FFmpeg, ensure you link with FFmpeg:
```bash
-lavcodec -lavformat -lavutil
```

And include the FFmpeg library paths:
```bash
-L/opt/homebrew/lib  # or your FFmpeg installation path
```