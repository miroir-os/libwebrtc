# Libwebrtc patch
This patches and build the [libwebrtc](https://github.com/livekit/rust-sdks/tree/main/webrtc-sys/libwebrtc) for Livekit.
It remove the statically linked FFmpeg and use the host one at runtime instead.

## Prerequisites
- Linux: libavcodec-dev libavformat-dev libavutil-dev
- MacOS: FFmpeg from Homebrew or MacPorts

## Usage
This patch is meant to be run from the same platform you are building for.

```sh
# Linux
./build.sh --platform linux --arch x64 --profile release

# MacOS
./build.sh --platform macos --arch arm64 --profile release
```

## Details
`build.sh`
- Patches the build scripts to remove old ffmpeg arguments
- Add a call to the patch_system_ffmpeg.sh script to be run during build (it needs to run after the source code is downloaded and before the build actually starts)

`verify_build.sh`
- Allows to check after a build if the patch was correclty applied to the source code and that the resulting library does not contain FFmpeg anymore

`patch_system_ffmpeg.sh`
- It is not meant to be run directly !
- Modifies msrc/third_party/ffmpeg/BUILD.gn (replaced with system FFmpeg config)
- Modifies the H264 decoder (uses system headers)
