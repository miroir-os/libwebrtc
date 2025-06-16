# FFmpeg Build Integration in WebRTC

This document details how FFmpeg is built and integrated within the WebRTC build system, including configuration, codec selection, and platform-specific builds.

## Overview

FFmpeg is integrated as a third-party dependency in WebRTC at `src/third_party/ffmpeg/`. The build system uses **pre-generated configurations** that are committed to the repository, not generated during the WebRTC build process.

## Pre-generated FFmpeg Configurations

### Where They Come From

The FFmpeg configurations are **NOT generated during WebRTC builds**. Instead:
- Pre-built configuration files are maintained by the Chromium project
- They are generated using FFmpeg's configure script with specific flags for each platform/architecture/branding combination
- These configurations are committed to the repository at `src/third_party/ffmpeg/chromium/config/`
- The configure commands shown in `config.h` files indicate how these pre-built configs were originally generated

### Configuration Structure

Pre-generated configs are organized by branding/platform/architecture:
- `src/third_party/ffmpeg/chromium/config/Chrome/linux/x64/`
- `src/third_party/ffmpeg/chromium/config/Chromium/linux/x64/`
- Similar structures for other platforms (mac, win, android) and architectures (arm, arm64, ia32)

Each configuration directory contains:
- `config.h` - Main FFmpeg configuration with all feature flags
- `config.asm` - Assembly configuration
- `config_components.h` - Component configuration
- `libavutil/avconfig.h` - Architecture-specific definitions
- `libavutil/ffversion.h` - Version information
- `libavcodec/codec_list.c` - Enabled codec list
- `libavcodec/parser_list.c` - Enabled parser list
- `libavformat/demuxer_list.c` - Enabled demuxer list
- `libavformat/muxer_list.c` - Enabled muxer list

## FFmpeg Configure Command (Extracted from Pre-built Configs)

**Note**: This configure command is NOT executed during WebRTC builds. It is extracted from the pre-generated `config.h` files (e.g., `src/third_party/ffmpeg/chromium/config/Chrome/linux/x64/config.h`) where it appears as a comment showing how the Chromium project originally generated these configurations.

The FFmpeg configure command that was used by Chromium to generate the Chrome branding configuration for Linux x64:

```bash
./configure \
  --disable-everything \
  --disable-all \
  --disable-doc \
  --disable-htmlpages \
  --disable-manpages \
  --disable-podpages \
  --disable-txtpages \
  --disable-static \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-static \
  --enable-libopus \
  --disable-debug \
  --disable-bzlib \
  --disable-error-resilience \
  --disable-iconv \
  --disable-network \
  --disable-schannel \
  --disable-sdl2 \
  --disable-symver \
  --disable-xlib \
  --disable-zlib \
  --disable-securetransport \
  --disable-faan \
  --disable-alsa \
  --disable-autodetect \
  --enable-decoder='vorbis,libopus,flac' \
  --enable-decoder='pcm_u8,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,mp3' \
  --enable-decoder='pcm_s16be,pcm_s24be,pcm_mulaw,pcm_alaw' \
  --enable-demuxer='ogg,matroska,wav,flac,mp3,mov' \
  --enable-parser='opus,vorbis,flac,mpegaudio,vp9' \
  --extra-cflags=-I/chromium/src/third_party/opus/src/include \
  --disable-linux-perf \
  --x86asmexe=nasm \
  --optflags='"-O2"' \
  --enable-lto \
  --arch=x86_64 \
  --target-os=linux \
  --enable-pic \
  --cc=clang \
  --cxx=clang++ \
  --ld=clang \
  --extra-ldflags='-fuse-ld=lld' \
  --enable-decoder='aac,h264' \    # Chrome branding adds these
  --enable-demuxer=aac \
  --enable-parser='aac,h264'
```

## Codec Configuration in WebRTC

### H.264 Support

**Important**: `rtc_use_h264` enables H.264 support using a **hybrid approach**:
- **Encoding**: Uses **OpenH264** library (not FFmpeg)
- **Decoding**: Uses **FFmpeg** H.264 decoder (when `ffmpeg_branding="Chrome"`)

For H.264 support in WebRTC:
1. **Build Flag**: `rtc_use_h264 = true` (enables both OpenH264 encoder and FFmpeg decoder)
2. **FFmpeg Branding**: `ffmpeg_branding = "Chrome"` (provides H.264 decoder in FFmpeg)
3. **Proprietary Codecs**: `proprietary_codecs = true` (automatically set with Chrome branding)
4. **Platform**: Not Android or iOS (these use hardware codecs)

The relationship is defined in `webrtc.gni`:
```gn
rtc_use_h264 = proprietary_codecs && !is_android && !is_ios && !(is_win && !is_clang)
```

### VP8/VP9 Support

VP8 and VP9 codecs use **libvpx** (not FFmpeg):
- **Build Flag**: `rtc_libvpx_build_vp9 = true` (enables VP9 support)
- **Library**: Uses libvpx for both encoding and decoding
- VP8 is typically enabled by default
- VP9 must be explicitly enabled in build scripts

### AV1 Support

AV1 codec uses **libaom** (not FFmpeg):
- **Build Flag**: `enable_libaom = true` 
- **Library**: Uses libaom for both encoding and decoding
- Must be explicitly enabled in build scripts

### Other Codecs via FFmpeg

FFmpeg provides decoders for:
- **Audio**: Opus, Vorbis, FLAC, MP3, PCM variants, AAC (Chrome branding only)
- **Parsers**: For parsing these formats in containers
- **Demuxers**: For extracting streams from containers (OGG, Matroska, WAV, MOV, etc.)

## Build Configuration

### Branding Levels

WebRTC uses FFmpeg branding to control which codecs are available:

- **Chrome** (`ffmpeg_branding="Chrome"`): Includes proprietary codecs (H.264, AAC)
- **Chromium** (`ffmpeg_branding="Chromium"`): Open codecs only (no H.264/AAC)
- **ChromeOS** (`ffmpeg_branding="ChromeOS"`): Similar to Chrome branding

### Platform Build Arguments

The LiveKit WebRTC build scripts configure codecs per platform:

| Platform | FFmpeg Branding | H.264 | VP9 | AV1 |
|----------|-----------------|-------|-----|-----|
| Linux    | Chrome          | Yes   | Yes | Yes |
| Windows  | Chrome          | Yes   | Yes | Yes |
| macOS    | Not set         | Via system | Yes | Yes |
| Android  | Not set         | No (HW) | Yes | No |
| iOS      | Not set         | No (HW) | Yes | No |

## Build Process Flow

1. **Configuration Selection**: Based on `ffmpeg_branding` parameter, the build system selects appropriate pre-generated FFmpeg configurations

2. **Source File Generation**: The `generate_gn.py` script:
   - Processes the pre-generated FFmpeg build configurations
   - Creates `ffmpeg_generated.gni` with platform-specific source lists
   - Maps object files to source files based on the selected configuration

3. **GN Build Integration**: 
   - `BUILD.gn` uses the generated source lists
   - Conditionally includes files based on platform and branding
   - Builds FFmpeg as a static library

4. **WebRTC Integration**: 
   - FFmpeg library provides decoders for various formats
   - OpenH264 provides H.264 encoding
   - libvpx provides VP8/VP9 encoding/decoding
   - libaom provides AV1 encoding/decoding

## Codec Summary

| Codec | Encoder | Decoder | Build Flag |
|-------|---------|---------|------------|
| H.264 | OpenH264 | FFmpeg (Chrome) | `rtc_use_h264=true` |
| VP8 | libvpx | libvpx | Default enabled |
| VP9 | libvpx | libvpx | `rtc_libvpx_build_vp9=true` |
| AV1 | libaom | libaom | `enable_libaom=true` |
| Opus | libopus | FFmpeg/libopus | Default enabled |
| AAC | - | FFmpeg (Chrome) | `ffmpeg_branding="Chrome"` |

## Build Optimizations

- **Minimal Build**: Uses `--disable-everything` then selectively enables only needed components
- **Static Linking**: Built as static library with position-independent code (`--enable-pic`)
- **LTO**: Link-time optimization enabled (`--enable-lto`)
- **Compiler**: Uses Clang with LLD linker for consistent builds across platforms
- **No External Dependencies**: Disables zlib, bzlib, iconv, etc. to minimize dependencies

## Custom Patches

Chromium maintains FFmpeg patches in `src/third_party/ffmpeg/chromium/patches/` including:
- Windows build compatibility fixes
- Memory allocator integration with Chromium
- Size optimizations (removing unnecessary logging)
- Platform-specific symbol visibility fixes

## Key Files

- **Build Scripts**: 
  - `build_linux.sh`, `build_windows.cmd`, etc. - Set FFmpeg branding and codec flags
  - `src/third_party/ffmpeg/chromium/scripts/generate_gn.py` - Processes pre-generated configs
  
- **Configuration**:
  - `src/third_party/ffmpeg/chromium/ffmpeg_options.gni` - GN options
  - `src/third_party/ffmpeg/BUILD.gn` - Main build file
  - `src/third_party/ffmpeg/ffmpeg_generated.gni` - Generated source lists

- **WebRTC Integration**:
  - `src/webrtc.gni` - Defines rtc_use_h264 and other codec flags
  - `src/modules/video_coding/codecs/h264/h264_encoder_impl.cc` - Uses OpenH264
  - `src/modules/video_coding/codecs/h264/h264_decoder_impl.cc` - Uses FFmpeg
  - `src/modules/video_coding/codecs/vp8/` - VP8 implementation using libvpx
  - `src/modules/video_coding/codecs/vp9/` - VP9 implementation using libvpx
  - `src/modules/video_coding/codecs/av1/` - AV1 implementation using libaom

This architecture allows WebRTC to use the best available codec implementation for each use case while maintaining flexibility in codec selection and licensing compliance.