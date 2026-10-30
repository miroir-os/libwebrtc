# Patch Justification

The MiroirOS compositor links libwebrtc, through LiveKit's `webrtc-sys`, into one binary with the system's FFmpeg (`ffmpeg-next`, Smelter) and CEF. libwebrtc bundles its own copies of shared libraries, which clash with those.

| Conflict | Platforms | Fix |
|---|---|---|
| FFmpeg symbols | linux | `LK_` prefix, in LiveKit's builds since `webrtc-a545de4` ([livekit/rust-sdks#1534](https://github.com/livekit/rust-sdks/pull/1534)) |
| FFmpeg symbols | macOS | The same prefix: [`patches/build_macos-ffmpeg-prefix.patch`](patches/build_macos-ffmpeg-prefix.patch), proposed upstream as [livekit/rust-sdks#UPSTREAM_PR](https://github.com/livekit/rust-sdks/pull/UPSTREAM_PR) |
| BoringSSL symbols | linux | `LK_` prefix, in LiveKit's builds |
| ObjC classes | macOS | None needed |

Once LiveKit builds a release with the macOS prefix, no patch is left: MiroirOS consumes LiveKit's builds directly and this repository retires.

## FFmpeg

libwebrtc bundles a minimal FFmpeg for H.264 decoding and exports its symbols. Linked into a binary that also calls the system's FFmpeg, it wins at link time: `ffmpeg-next` then calls a copy built against other headers, with no mp4 muxer, no H.264 decoder and no file protocol.

The patch renames every bundled FFmpeg symbol to `LK_…` across the archive, as `build_linux.sh` does: libwebrtc keeps its copy, the application gets the system's. Mach-O names carry a leading underscore, and Chromium's macOS toolchain ships `llvm-objcopy` but not `llvm-nm`, so Xcode's `nm` lists them.

| Compositor engine tests on macOS, LiveKit's `webrtc-51ef663` | Result |
|---|---|
| as LiveKit ships it | 79/84: `Requested output format 'mp4' is not known` |
| with the prefix | 84/84, over 4 runs |

Earlier builds set `rtc_use_h264=false` instead, which also dropped libwebrtc's software H.264 encoder and decoder. With the prefix, H.264 is back.

## ObjC classes

CEF's framework holds 9 Objective-C classes that libwebrtc also defines (`RTCVideoFrame`, `RTCEncodedImage`, `RTCVideoCodecInfo`, `SckHelper`…). The runtime logs `Class … is implemented in both` and registers one name, but each image's code reaches its own class through direct references, and the two never exchange objects. H.264 through VideoToolbox, which uses those classes, encodes and decodes with CEF loaded, and the engine tests above load CEF.

Earlier builds set `rtc_objc_prefix="MR"` to silence the warning.

## Protobuf

Builds up to `webrtc-51ef663` excluded `third_party/protobuf` from the archive to link beside `ort`, which MiroirOS dropped (miroir-os/miroir-os#834). Nothing else links C++ protobuf.

## Consuming a release

Each release holds `webrtc-{platform}-{arch}-release.zip` archives in LiveKit's layout, so `webrtc-sys` downloads one in place of LiveKit's own when `LK_WEBRTC_RELEASE` (set in MiroirOS's `.cargo/config.toml`, read by its patched `webrtc-sys-build`) names the release's download URL. The unpacked directory, which `LK_CUSTOM_WEBRTC` can also name, must contain `lib/libwebrtc.a`, `include/`, `webrtc.ninja`, and `desktop_capture.ninja`; `webrtc-sys` takes its preprocessor defines from the first line of `webrtc.ninja`, so only LiveKit's build scripts produce a matching build.
