# Using System FFmpeg Instead of Bundled FFmpeg

This guide explains how to modify the WebRTC build system to use the system-installed FFmpeg libraries instead of building and bundling a custom FFmpeg version.

## Overview

By default, WebRTC builds its own minimal FFmpeg configuration and statically links it into libwebrtc. This approach:
- Bundles FFmpeg directly into the final library (~increases size)
- Uses pre-generated configurations specific to Chromium's needs
- Includes only the codecs/features WebRTC requires
- Ensures consistent behavior across platforms

To use system FFmpeg instead, we need to modify several build configuration files and scripts.

## Required Modifications

### 1. Modify FFmpeg BUILD.gn

**File**: `src/third_party/ffmpeg/BUILD.gn`

**Step 1: Add pkg-config import at the top**
After line 10 (after the existing imports), add:
```gn
import("//build/config/linux/pkg_config.gni")
```

**Step 2: Replace the ffmpeg_internal target**
Delete everything from line 198 to line 416 (the entire `target(link_target_type, "ffmpeg_internal")` block) and replace it with:

```gn
# Use pkg-config to find system FFmpeg libraries
if (is_linux) {
  pkg_config("system_ffmpeg") {
    packages = [
      "libavcodec",
      "libavformat", 
      "libavutil",
    ]
  }
}

# Replace the ffmpeg_internal target with a simple group
group("ffmpeg_internal") {
  if (is_linux) {
    public_configs = [ ":system_ffmpeg" ]
  } else {
    # Fallback to error for non-Linux platforms
    assert(false, "System FFmpeg only supported on Linux")
  }
}
```

**Step 3: Modify the conditional shared library/source set section**
Replace lines 418-456 (the entire `if (is_component_ffmpeg)` block and the `else` block) with:

```gn
if (is_component_ffmpeg) {
  group("ffmpeg") {
    public_configs = [ ":ffmpeg_dependent_config" ]
    deps = [ ":ffmpeg_internal" ]
  }
} else {
  group("ffmpeg") {
    public_configs = [ ":ffmpeg_dependent_config" ]
    deps = [ ":ffmpeg_internal" ]
  }
}
```

**Step 4: Handle the nasm target**
After line 76 (after the closing brace of the `nasm_assemble("ffmpeg_nasm")` block), add:

```gn
} else {
  # Empty target when not using bundled FFmpeg
  static_library("ffmpeg_nasm") {
    sources = []
  }
```

**Summary of changes:**
- Lines to keep: 1-197 (everything before `ffmpeg_internal`)
- Lines to delete: 198-416 (the entire `ffmpeg_internal` target)
- Lines to replace: 418-456 (the conditional ffmpeg target)
- Add the pkg-config import after line 10
- Add the empty nasm target after line 76

### 2. Create a System FFmpeg Options File

**File**: `src/third_party/ffmpeg/ffmpeg_options_system.gni`

Create a new GNI file for system FFmpeg configuration:

```gn
declare_args() {
  # Use system FFmpeg instead of bundled
  use_system_ffmpeg = true
  
  # System FFmpeg doesn't use branding
  ffmpeg_branding = "System"
  
  # Assume system FFmpeg has these features
  ffmpeg_has_h264_decoder = true
  ffmpeg_has_hevc_decoder = true
  ffmpeg_has_vp9_parser = true
}
```

### 3. Modify Build Scripts

#### Linux Build Script
**File**: `build_linux.sh`

Replace the FFmpeg-related build arguments (around line 103-105):

```bash
# Original:
# ffmpeg_branding=\"Chrome\" \\
# rtc_use_h264=true \\
# rtc_use_ffmpeg_h264_encoder=true \\

# Replace with:
rtc_use_h264=true \\
```

#### Windows Build Script
**File**: `build_windows.cmd`

For Windows, system FFmpeg is more complex. You would need to:
1. Install FFmpeg development files
2. Set include/library paths appropriately
3. Modify the build arguments similar to Linux

### 4. Modify WebRTC Build Configuration

**File**: `src/webrtc.gni`

Add a build argument for system FFmpeg:

```gn
declare_args() {
  # ... existing args ...
  
  # Use system FFmpeg instead of bundled
  use_system_ffmpeg = false
}
```

### 5. Update H264 Decoder Implementation

**File**: `src/modules/video_coding/codecs/h264/h264_decoder_impl.cc`

The H264 decoder includes FFmpeg headers directly. When using system FFmpeg, these includes need to use system paths:

```cpp
#if defined(USE_SYSTEM_FFMPEG)
// System FFmpeg headers
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libavutil/log.h>
}
#else
// Bundled FFmpeg headers
extern "C" {
#include "third_party/ffmpeg/libavcodec/avcodec.h"
#include "third_party/ffmpeg/libavformat/avformat.h"
#include "third_party/ffmpeg/libavutil/imgutils.h"
#include "third_party/ffmpeg/libavutil/log.h"
}
#endif
```

### 6. Modify WebRTC Video Coding BUILD.gn

**File**: `src/modules/video_coding/BUILD.gn`

Update the FFmpeg dependency for H264 decoder:

```gn
if (rtc_use_h264) {
  if (use_system_ffmpeg) {
    # System FFmpeg uses public configs from the group target
    deps += [ "//third_party/ffmpeg:ffmpeg_internal" ]
  } else {
    # Original bundled FFmpeg dependency
    deps += [ "//third_party/ffmpeg:ffmpeg_internal" ]
  }
}
```

### 7. Handle Missing Pre-generated Files

When using system FFmpeg, the pre-generated configuration files won't exist. Create a minimal `ffmpeg_generated.gni` for system builds:

**File**: `src/third_party/ffmpeg/ffmpeg_generated_system.gni`

```gn
# Minimal generated file for system FFmpeg
ffmpeg_c_sources = []
ffmpeg_gas_sources = []
ffmpeg_nasm_sources = []
ffmpeg_yasm_sources = []
```

Modify `src/third_party/ffmpeg/BUILD.gn` to conditionally include this file:

```gn
if (use_system_ffmpeg) {
  import("ffmpeg_generated_system.gni")
} else {
  import("ffmpeg_generated.gni")
}
```

## Platform-Specific Considerations

### Linux
- Requires FFmpeg development packages: `libavcodec-dev`, `libavformat-dev`, `libavutil-dev`
- pkg-config must be able to find FFmpeg libraries
- May need to set `PKG_CONFIG_PATH` if FFmpeg is in a non-standard location

### macOS
- Would need to use a different mechanism than pkg-config
- Could use homebrew or MacPorts FFmpeg
- Requires additional BUILD.gn modifications for macOS-specific linking

### Windows
- Most complex due to lack of standard package management
- Would need to manually specify library and include paths
- Requires appropriate import libraries (.lib files)

### Android/iOS
- Not recommended due to platform restrictions
- These platforms typically use hardware codecs anyway

## Build Process

After making these modifications:

1. Ensure system FFmpeg is installed:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install libavcodec-dev libavformat-dev libavutil-dev
   
   # Fedora/RHEL
   sudo dnf install ffmpeg-devel
   ```

2. Clean any previous builds:
   ```bash
   rm -rf out/
   ```

3. Run the modified build script:
   ```bash
   ./build_linux.sh --arch x64 --profile release
   ```

## Advantages of System FFmpeg

1. **Smaller binary size** - No FFmpeg code bundled
2. **System updates** - Security updates handled by system package manager
3. **Full codec support** - Access to all codecs in system FFmpeg
4. **Shared memory** - FFmpeg shared by multiple applications

## Disadvantages

1. **Version compatibility** - Must handle different FFmpeg versions
2. **Platform inconsistency** - Behavior may vary across systems
3. **Missing codecs** - System FFmpeg might lack required codecs
4. **ABI stability** - FFmpeg ABI changes between versions
5. **Distribution restrictions** - Some codecs may not be available in all distributions

## Testing

After building with system FFmpeg:

1. Verify linking:
   ```bash
   ldd linux-x64-release/lib/libwebrtc.a | grep ffmpeg
   ```

2. Check that H.264 decoding works in WebRTC applications

3. Verify no missing symbols:
   ```bash
   nm -u linux-x64-release/lib/libwebrtc.a | grep av_
   ```

## Troubleshooting

### Missing pkg-config files
Ensure FFmpeg development packages are installed and pkg-config can find them:
```bash
pkg-config --libs libavcodec
```

### Version mismatches
System FFmpeg API may differ from bundled version. Check FFmpeg version:
```bash
pkg-config --modversion libavcodec
```

### Missing codecs
System FFmpeg might be built without proprietary codecs. Check available codecs:
```bash
ffmpeg -codecs | grep h264
```

## Reverting Changes

To revert back to bundled FFmpeg:
1. Restore original BUILD.gn files
2. Restore original ffmpeg_branding settings
3. Clean and rebuild