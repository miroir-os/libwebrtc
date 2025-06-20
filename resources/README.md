# Resources
Resources used during patch & compilation.
Scripts present here are not mean to be run directly.

## Details
`patch_system_ffmpeg.sh` modifies:
- msrc/third_party/ffmpeg/BUILD.gn (replaced with system FFmpeg config)
- the H264 decoder (uses system headers)
