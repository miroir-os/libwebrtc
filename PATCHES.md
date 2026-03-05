# Patch Justification

This documents the symbol conflicts that arise when linking libwebrtc alongside other native libraries in the MiroirOS compositor, and the patches applied to resolve them.

The compositor links **LiveKit** (which statically bundles Google's libwebrtc) and **smelter** (which bundles CEF/Chromium). These two C++ monoliths each embed their own copies of shared dependencies, causing symbol conflicts when linked into the same binary.

| # | Conflict | Platforms | Fix | Source |
|---|----------|-----------|-----|--------|
| 1 | FFmpeg symbols | linux, macOS | `rtc_use_h264=false` | Our patch |
| 2 | ObjC classes | macOS | `rtc_objc_prefix="MR"` | Our patch |
| 3 | Protobuf symbols | linux, macOS | Exclude from ar step | Our patch |
| 4 | BoringSSL symbols | linux | `objcopy --redefine-syms` | Upstream LiveKit |

## Why monoliths clash

Most software avoids symbol conflicts through dynamic linking — every library links against the system's single copy of `libavcodec.so` via `pkg-config`, and the OS deduplicates. Google's libwebrtc breaks this model: it's built with GN/Ninja in a monolithic Chromium-style build that compiles and statically links its own copies of FFmpeg, BoringSSL, libvpx, etc. When `libwebrtc.a` is linked into a binary that has its own FFmpeg, the two worlds collide.

This is a known cost across the industry — Twilio, Signal, and LiveKit's own mobile SDKs all maintain custom WebRTC builds with their own patches.

## Conflict 1: FFmpeg duplicate symbols (linux + macOS)

**Patch**: `rtc_use_h264=false` + remove `ffmpeg_branding` GN arg

libwebrtc statically links a minimal FFmpeg for H.264 decoding. The compositor also depends on `ffmpeg-next` which links system FFmpeg shared libraries. When both are in the same binary, duplicate C symbols (`avcodec_*`, `avformat_*`, `avutil_*`) cause linker errors, or worse: the static (minimal, audio-only) copy shadows the system one at link time, causing missing codec features at runtime.

FFmpeg inside libwebrtc is **only** used for H.264 decoding. All other codecs use dedicated bundled libraries that don't conflict:

| Codec | Library | Conflicts with ffmpeg-next? |
|-------|---------|---------------------------|
| VP8/VP9 | libvpx (bundled) | No |
| AV1 | dav1d/libaom (bundled) | No |
| Opus | built-in | No |
| H.264 encode | OpenH264 (bundled) | No |
| H.264 decode | FFmpeg (bundled) | **Yes** |

### What `rtc_use_h264` controls per platform

LiveKit's Rust SDK builds set `rtc_use_h264=true` on both Linux and macOS (confirmed at the `webrtc-0001d84-2` tag — the source matches the release). Combined with `ffmpeg_branding="Chrome"` on Linux, this bundles a minimal FFmpeg into `libwebrtc.a`.

Setting `rtc_use_h264=false`:

| Platform | What's removed | What still works |
|----------|---------------|-----------------|
| Linux | FFmpeg software H.264 decode + OpenH264 software encode | VA-API hardware decode (if available) |
| macOS | OpenH264 software encode + FFmpeg software decode | VideoToolbox hardware H.264 encode/decode (**unconditionally included** regardless of this flag) |

**macOS has zero practical trade-off** — VideoToolbox is always present.

**Linux risk is narrow**: if a remote LiveKit participant sends H.264 and the receiving machine has no hardware decoder (e.g. headless server without VA-API), it can't decode that stream. In practice this doesn't affect us — LiveKit SFUs negotiate codecs, VP8/VP9 are the defaults, and we control the server config.

LiveKit's own non-Rust SDK builds already use `rtc_use_h264=false` — the `COMMON_GN_ARGS` in `webrtc-sdk/webrtc-build/run.py` disables H.264 by default. Only the Rust SDK build scripts enable it via `ffmpeg_branding="Chrome"`.

### Alternatives considered

- **Symbol localization** (`llvm-objcopy --localize-symbol`): makes FFmpeg symbols local inside `libwebrtc.a`. Works reliably for C symbols, but requires maintaining a regex list and a post-build step. Keeps H.264 support if ever needed.
- **Replace bundled FFmpeg with system FFmpeg**: what the previous `miroir-os/libwebrtc` repo did (patching `BUILD.gn` + `#include` paths). Works but fragile — patches break on libwebrtc version bumps.

Disabling FFmpeg entirely is the simplest: one GN arg, zero patches, zero maintenance.

## Conflict 2: ObjC class duplication (macOS only)

**Patch**: `rtc_objc_prefix="MR"`

On macOS, both libwebrtc and CEF register Objective-C classes like `RTCVideoFrame`, `RTCEncodedImage`, `RTCVideoCodecInfo`. The ObjC runtime maintains a single global flat namespace for all classes — when the same class name is registered twice, one silently wins, leading to crashes from vtable/isa pointer mismatches:

```
objc[88686]: Class RTCVideoFrame is implemented in both
  .../examples/simple (0x10783dfc8) and
  .../Chromium Embedded Framework.framework (0x1339992d0).
```

WebRTC has built-in support for prefixing all ObjC classes at compile time via `rtc_objc_prefix`. This transforms `RTCVideoFrame` → `MRRTCVideoFrame`, `RTCEncodedImage` → `MRRTCEncodedImage`, etc. CEF keeps its unprefixed copies — no conflict. This is proven in production by Twilio (`TVI` prefix), LiveKit's own iOS SDK (`LK` prefix), and Signal.

The Rust SDK communicates with libwebrtc through C++ APIs via CXX, so prefixing ObjC classes (which are internal to libwebrtc's platform layer) is transparent to the `webrtc-sys` bindings.

Note that the `rtc_objc_prefix` GN arg is cleaner than LiveKit's own approach for their Apple SDK — their `apple_prefix.patch` hardcodes `#define RTC_OBJC_TYPE_PREFIX LK` directly in the header file. The GN arg achieves the same result without a patch file.

LiveKit's Rust SDK builds do **not** apply this prefix — only their Apple/Android SDKs do. We are the first Rust SDK user to need it (due to the unusual combination of livekit + CEF/smelter in one binary).

### Alternatives considered

All standard linker tricks fail for ObjC classes:

| Approach | Why it fails |
|----------|-------------|
| `-unexported_symbols_list` | Controls linker symbol table, not ObjC runtime registration |
| `dlopen(RTLD_LOCAL)` | ObjC runtime ignores `RTLD_LOCAL`, registers classes anyway |
| Two-level namespaces | macOS dylib feature, ObjC runtime maintains its own flat table |
| `llvm-objcopy --redefine-sym` | Renames symbol table entry but not `__objc_classname`/`__objc_classlist` metadata sections |
| Disable WebRTC in CEF | `enable_webrtc=false` GN flag no longer exists in modern Chromium |

`rtc_objc_prefix` is the only solution that works at the ObjC runtime level.

## Conflict 3: Protobuf duplicate symbols (linux + macOS)

**Patch**: Exclude `third_party/protobuf` from ar archive step

ONNX Runtime (via `ort-sys`) statically bundles protobuf-lite. libwebrtc also compiles protobuf objects. When both are in the same binary, ~128 duplicate `google::protobuf::*` symbols cause linker errors:

```
rust-lld: error: duplicate symbol: google::protobuf::internal::ArenaStringPtr::Destroy()
>>> defined at arenastring.o in libwebrtc_sys-*.rlib
>>> defined at arenastring.cc.o in libort_sys-*.rlib
```

LiveKit's build scripts already set `rtc_enable_protobuf=false`, which replaces WebRTC's own protobuf usage with lightweight hand-written serializers. However, **this is necessary but not sufficient** — protobuf-lite `.o` files still get compiled as transitive deps of perfetto/trace and swept into `libwebrtc.a` by the `find | ar` aggregation step.

This is a known problem. The established solution is to blacklist protobuf objects at archive time — both [sourcey/webrtc-builds](https://github.com/sourcey/webrtc-builds/blob/master/util.sh) and [vsimon/webrtcbuilds](https://github.com/vsimon/webrtcbuilds/blob/master/util.sh) maintain an explicit blacklist that filters out `protobuf_lite` objects before archiving. For LiveKit's build scripts, the equivalent is adding a `-not -path "*/third_party/protobuf/*"` exclusion to the `find` command.

### Alternatives considered

- **Switch `ort` to dynamic linking** (`features = ["load-dynamic"]`): loads `libonnxruntime.so` at runtime via `dlopen`, removing `ort-sys` from the link step entirely. Eliminates the conflict regardless of libwebrtc state. Trade-off: requires shipping `libonnxruntime.so` separately. This is the [recommended approach by ort documentation](https://ort.pyke.io/setup/linking) for production and provides defense-in-depth alongside the archive exclusion.
- **Symbol localization** (`objcopy --localize-symbols`): same technique LiveKit uses for BoringSSL (`LK_` prefix), but C++ mangled protobuf symbols are far harder to target than BoringSSL's C symbols. Fragile and breaks on every version bump.
- **Source-level namespace rename** (`sed -i 's/namespace google/namespace lk_google/g'`): extremely invasive, also requires renaming `.proto` files themselves (ONNX [discovered this](https://github.com/onnx/onnx/pull/555)). Protobuf upstream has an open [feature request](https://github.com/protocolbuffers/protobuf/issues/4004) for a `--namespace` flag but it remains unimplemented.

## Conflict 4: BoringSSL vs OpenSSL (linux)

**No patch needed** — handled by upstream LiveKit.

libwebrtc bundles BoringSSL. Our project also links OpenSSL via `openssl-sys` (through livekit's `native-tls` and reqwest). LiveKit's Linux build scripts already handle this with `objcopy --redefine-syms boringssl_prefix_symbols.txt`, prefixing all BoringSSL symbols with `LK_`. We get this for free by building from their scripts.

## Related issues in livekit/rust-sdks

Others have hit similar symbol conflicts:

- [#89](https://github.com/livekit/rust-sdks/issues/89) — BoringSSL symbols from libwebrtc conflicting with `openssl-sys`. Suggested fix: `rtc_build_ssl=false`. LiveKit's Linux build now prefixes BoringSSL symbols via `objcopy --redefine-syms`.
- [#482](https://github.com/livekit/rust-sdks/issues/482) — Android `org.webrtc.*` package shadowing. User compiled WebRTC themselves with namespace changes applied to source. Reported as blocking adoption.
- [#531](https://github.com/livekit/rust-sdks/issues/531) — User tried `LK_CUSTOM_WEBRTC`, got missing headers errors. No resolution.

No issues exist for FFmpeg symbol conflicts or ObjC class conflicts specifically — we appear to be the first Rust SDK user hitting both simultaneously (due to the unusual combination of livekit + CEF/smelter + ffmpeg-next in one binary).

## How others handle custom WebRTC builds

| | Twilio | Signal | LiveKit |
|---|--------|--------|---------|
| Fork source | webrtc.googlesource.com | webrtc.googlesource.com | webrtc-sdk/webrtc |
| Current milestone | M124 | M142 | M137 |
| ObjC prefix | `TVI`/`TVO` | None (single-app) | `LK` (Apple SDK only, not Rust SDK) |
| FFmpeg | Not included | Kept (desktop only) | `ffmpeg_branding="Chrome"` on Linux |
| BoringSSL prefix | Unknown | No | `LK_` on Linux via objcopy |
| Distribution | XCFramework on GitHub | Archives on GCS | Zips on GitHub Releases |
| Build system | Internal CI | GitHub Actions + GCS | GitHub Actions + GH Releases |

Other notable projects: [Shiguredo](https://github.com/shiguredo-webrtc-build/webrtc-build) excludes H.264 from all builds (same as our approach). [Threema](https://github.com/threema-ch/webrtc-android) disables protobuf. [Intermedia](https://github.com/intermedia-net/jpkgchanger) renames Java packages on Android (the equivalent of `rtc_objc_prefix` for Android).

## `LK_CUSTOM_WEBRTC` integration

The custom `libwebrtc.a` is consumed via `LK_CUSTOM_WEBRTC` (set in `.cargo/config.toml`). The directory must contain `lib/libwebrtc.a`, `include/`, `webrtc.ninja`, and `desktop_capture.ninja`. The build system parses the first line of `webrtc.ninja` to extract all `-D` preprocessor flags via regex — these defines must exactly match what the CXX bridge expects, or you get ABI mismatches. Only LiveKit's build scripts produce this format.

## Why we can't use third-party builds

The `webrtc-sys` CXX bridge requires LiveKit-specific APIs (frame cryptor, SSL verification callback, custom sources) that only exist in `webrtc-sdk/webrtc` — not in upstream `webrtc.googlesource.com`. Every external project (Shiguredo, stasel, Jitsi, Threema, Signal/ringrtc) builds from upstream and is incompatible.

Among forks of LiveKit's build, [gethopp/rust-sdks](https://github.com/gethopp/rust-sdks) is closest (publishes full multi-platform binaries in `LK_CUSTOM_WEBRTC` format), but their builds still bundle FFmpeg and don't set `rtc_objc_prefix`. No existing fork applies all three of our patches.

See the full analysis in [one-click-os/rfcs/temp/libwebrtc.md](https://github.com/miroir-os/one-click-os/blob/v2-main/rfcs/temp/libwebrtc.md).
