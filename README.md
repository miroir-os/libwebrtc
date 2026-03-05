# MiroirOS libwebrtc

Builds custom libwebrtc from [LiveKit's rust-sdks](https://github.com/livekit/rust-sdks) with MiroirOS patches applied.

Pinned LiveKit tag: `webrtc-0001d84-2` (webrtc-sys-build 0.3.13, livekit 0.7.32)

3 patches are applied on top of upstream LiveKit build scripts — see [PATCHES.md](PATCHES.md) for detailed conflict analysis and justification.

## CI workflow

Based on [LiveKit's webrtc-builds.yml](https://github.com/livekit/rust-sdks/blob/main/.github/workflows/webrtc-builds.yml). Uses [`jlumbroso/free-disk-space`](https://github.com/jlumbroso/free-disk-space) on Ubuntu runners because `gclient sync` downloads ~20GB of Chromium sources and the build itself produces ~15GB of output, exceeding the default runner disk.

## Triggering a build

- **Tag push**: push a tag matching `webrtc-*` to create a published release
- **Manual**: trigger the `build` workflow via `workflow_dispatch` (creates a draft release)

## Local build

Requires ~40GB disk, `ninja`, `python3`, and GCC 14 (linux) or Xcode (macOS).

```bash
# Clone LiveKit's rust-sdks at the pinned tag (sparse checkout)
git clone --depth 1 --branch webrtc-0001d84-2 --filter=blob:none --sparse \
  https://github.com/livekit/rust-sdks.git rust-sdks
cd rust-sdks && git sparse-checkout set webrtc-sys/libwebrtc && cd ..

# Apply patches
./patch.sh linux rust-sdks/webrtc-sys/libwebrtc/build_linux.sh   # or mac / build_macos.sh

# Set up working directory and build (~40min)
mkdir -p work && cp rust-sdks/webrtc-sys/libwebrtc/.gclient work/
cd work
bash ../rust-sdks/webrtc-sys/libwebrtc/build_linux.sh --arch x64 --profile release
```

Output lands in `work/linux-x64-release/` (or `mac-{arch}-release/`), ready to use as `LK_CUSTOM_WEBRTC`.
