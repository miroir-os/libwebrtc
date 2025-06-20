# Libwebrtc patch
This patches and build the [libwebrtc](https://github.com/livekit/rust-sdks/tree/main/webrtc-sys/libwebrtc) for Livekit.
It removes the statically linked FFmpeg and use the host one at runtime instead.

## Prerequisites
- Linux: libavcodec-dev libavformat-dev libavutil-dev
- MacOS: FFmpeg from Homebrew or MacPorts

## Usage
### Build
This patch is meant to be run from the same platform you are building for.

Make sure you cloned this repository with `--recurse-submodules`, or synchronize with:
```sh
git submodule init
git submodule update --recursive
```

Then build:
```sh
# Linux
./build.sh --platform linux --arch x64 --profile release

# MacOS
./build.sh --platform macos --arch arm64 --profile release
```

### Release
To use the built library in [one-click-os](https://github.com/one-click-studio/one-click-os):
- Zip the output folder  
  Ex: on Linux the whole `rust-sdks/webrtc-sys/libwebrtc/linux-x64-release/` folder
- Host this update version on a public URL (ex: Backblaze)
- If changed, update the URL in `one-click-os/crates/meeting/build.rs`

## Details
`build.sh`
- Patches the build scripts to remove old ffmpeg arguments
- Add a call to the patch_system_ffmpeg.sh script to be run during build

`verify_build.sh`
- Check after a build if the patch was correclty applied to the source code
- Verifies that the resulting library does not contain FFmpeg anymore

## TODO
- `verify_build.sh` is AI generated and not really tested