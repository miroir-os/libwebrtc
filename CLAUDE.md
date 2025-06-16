# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This directory contains build scripts and patches for WebRTC, used by the LiveKit Rust SDK. The scripts automate the process of checking out, patching, and building WebRTC for various platforms.

## Essential Commands

### Building WebRTC

**Linux:**
```bash
./build_linux.sh --arch x64 --profile release
./build_linux.sh --arch arm64 --profile debug
```

**macOS:**
```bash
./build_macos.sh --arch x64 --profile release
./build_macos.sh --arch arm64 --profile debug
```

**Windows:**
```cmd
build_windows.cmd --arch x64 --profile release
build_windows.cmd --arch arm64 --profile debug
```

**iOS:**
```bash
./build_ios.sh --arch arm64 --profile release --environment device
./build_ios.sh --arch arm64 --profile debug --environment simulator
```

**Android:**
```bash
./build_android.sh --arch arm64 --profile release
./build_android.sh --arch arm --profile debug
./build_android.sh --arch x64 --profile release
```

### Using Custom WebRTC Build in LiveKit Rust SDK

Add to `.cargo/config.toml`:
```toml
[env]
LK_CUSTOM_WEBRTC = { value = "webrtc-sys/libwebrtc/linux-x64-release", relative = true }
```

## Architecture

### Build System Flow
1. **depot_tools Setup**: Clones Google's build tools if not present
2. **Source Fetch**: Uses `gclient sync` to checkout WebRTC source
3. **Patching**: Applies custom patches for LiveKit requirements
4. **Build Configuration**: Uses GN to generate Ninja build files with platform-specific arguments
5. **Compilation**: Ninja builds the static library
6. **Artifact Collection**: Copies headers, library, and licenses to platform-specific directory

### Key Patches Applied
- `ssl_verify_callback_with_native_handle.patch`: Custom SSL verification
- `add_deps.patch`: Dependency management
- `add_licenses.patch`: License generation support
- `abseil_use_optional.patch`: Abseil compatibility
- `android_use_libunwind.patch`: Android-specific unwinding
- `windows_silence_warnings.patch`: Windows build compatibility

### Output Structure
After building, artifacts are placed in:
- `{platform}-{arch}-{profile}/lib/libwebrtc.a` (or `webrtc.lib` on Windows)
- `{platform}-{arch}-{profile}/include/` (all headers)
- `{platform}-{arch}-{profile}/LICENSE.md`

### Build Configuration
All platforms disable:
- Protobuf support
- Test building
- Example building
- Component builds (static linking only)

Platform-specific features:
- **Linux**: H.264, VP9, AV1 codecs enabled; X11 disabled
- **macOS/iOS**: Objective-C framework support
- **Android**: JNI library generation
- **Windows**: Clang-based build

## Important Notes

- Initial build downloads several GB and takes 30+ minutes
- Patches can only be applied once; re-running shows harmless warnings
- Each platform requires specific host OS (iOS needs macOS, etc.)
- Debug builds include ASAN/LSAN on Linux/Android