# MiroirOS libwebrtc

Builds custom libwebrtc from [LiveKit's rust-sdks](https://github.com/livekit/rust-sdks) with MiroirOS patches applied.

## Configuration

Two inputs control the build, set in [`.github/workflows/build.yml`](.github/workflows/build.yml):

| Var | Role |
|---|---|
| `RUST_SDKS_TAG` | The `livekit/rust-sdks` tag whose build scripts we use. Determines `build_*.sh`, patch files, GN args layout, and the webrtc-sys CXX bridge ABI this libwebrtc will be paired with. Pick a `webrtc-*` release tag from [LK's releases](https://github.com/livekit/rust-sdks/releases). |
| `WEBRTC_COMMIT` | Full 40-char `webrtc-sdk/webrtc` commit SHA baked into `libwebrtc.a`. Decides the C++ source we compile. Pin to the same commit LK built `RUST_SDKS_TAG` against so our build matches LK's tested combination. |

4 patches are applied on top of upstream LiveKit build scripts — see [PATCHES.md](PATCHES.md) for detailed conflict analysis and justification.

## CI workflow

Based on [LiveKit's webrtc-builds.yml](https://github.com/livekit/rust-sdks/blob/main/.github/workflows/webrtc-builds.yml). Uses [`jlumbroso/free-disk-space`](https://github.com/jlumbroso/free-disk-space) on Ubuntu runners because `gclient sync` downloads ~20GB of Chromium sources and the build itself produces ~15GB of output, exceeding the default runner disk.

## Triggering a build

- **Tag push**: push a tag matching `webrtc-*` to create a published release. By convention the tag matches `RUST_SDKS_TAG` (e.g., our `webrtc-51ef663` mirrors LK's `webrtc-51ef663`), so an LK release and our matching build can be correlated by name.
- **Manual**: trigger the `build` workflow via `workflow_dispatch` (creates a draft release).

## Updating to a new LiveKit release

1. Pick a new `RUST_SDKS_TAG` from [LK's releases](https://github.com/livekit/rust-sdks/releases) (a `webrtc-*` tag matching the webrtc-sys version you want to consume).

2. Resolve `WEBRTC_COMMIT` for that release. **Don't blindly trust the tag name** — LK's naming is inconsistent (`webrtc-0001d84` uses the first 7 chars of the SHA; `webrtc-51ef663` uses the last 7 of `aaeeee8077…51ef663`). Reliable method:
   - Note LK's release publish date: `gh release view <tag> -R livekit/rust-sdks --json publishedAt`.
   - Open the matching `mXXX_release` branch in `webrtc-sdk/webrtc` and pick the commit timestamped just before LK's publish date — that's what `gclient sync` resolved to.
   - Sanity-check: the LK tag suffix should match either the first 7 or last 7 hex chars of the SHA.

3. Update both env vars in `.github/workflows/build.yml`, commit.

4. Tag and push using the same name as `RUST_SDKS_TAG`:
   ```bash
   git tag <RUST_SDKS_TAG>
   git push origin <RUST_SDKS_TAG>
   ```

## Local build

Requires ~40GB disk, `ninja`, `python3`, and GCC 14 (linux) or Xcode (macOS).

```bash
# Pick the same values used in .github/workflows/build.yml
export RUST_SDKS_TAG="webrtc-51ef663"
export WEBRTC_COMMIT="aaeeee8077eb0a4cad1c9494e9c6433c751ef663"

# Clone LiveKit's rust-sdks at the pinned tag (sparse checkout)
git clone --depth 1 --branch "$RUST_SDKS_TAG" --filter=blob:none --sparse \
  https://github.com/livekit/rust-sdks.git rust-sdks
cd rust-sdks && git sparse-checkout set webrtc-sys/libwebrtc && cd ..

# Apply patches (reads WEBRTC_COMMIT from env; fails fast if unset)
./patch.sh linux rust-sdks/webrtc-sys/libwebrtc/build_linux.sh   # or mac / build_macos.sh

# Set up working directory and build (~40min)
mkdir -p work && cp rust-sdks/webrtc-sys/libwebrtc/.gclient work/
cd work
bash ../rust-sdks/webrtc-sys/libwebrtc/build_linux.sh --arch x64 --profile release
```

Output lands in `work/linux-x64-release/` (or `mac-{arch}-release/`), ready to use as `LK_CUSTOM_WEBRTC`.
