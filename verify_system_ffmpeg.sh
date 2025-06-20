#!/bin/bash

# Script to verify that the system FFmpeg patch was applied correctly
# This checks the simplified patch that always uses system FFmpeg

echo "Verifying system FFmpeg patch..."
echo ""

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
fi

# Check if FFmpeg is installed
echo "1. Checking system FFmpeg installation:"
if [[ "$OS" == "linux" ]]; then
    if pkg-config --exists libavcodec libavformat libavutil; then
        echo "   ✓ FFmpeg libraries found"
        echo "   Versions:"
        echo "     libavcodec: $(pkg-config --modversion libavcodec)"
        echo "     libavformat: $(pkg-config --modversion libavformat)"
        echo "     libavutil: $(pkg-config --modversion libavutil)"
    else
        echo "   ✗ FFmpeg libraries not found. Install with:"
        echo "     Ubuntu/Debian: sudo apt-get install libavcodec-dev libavformat-dev libavutil-dev"
        echo "     Fedora/RHEL: sudo dnf install ffmpeg-devel"
    fi
elif [[ "$OS" == "macos" ]]; then
    # Check common FFmpeg locations on macOS
    FFMPEG_FOUND=false
    for dir in /opt/homebrew /usr/local /opt/local; do
        if [ -f "$dir/include/libavcodec/avcodec.h" ]; then
            echo "   ✓ FFmpeg found in $dir"
            FFMPEG_FOUND=true
            # Try to get version
            if command -v ffmpeg >/dev/null 2>&1; then
                echo "   FFmpeg version: $(ffmpeg -version | head -n1)"
            fi
            break
        fi
    done
    if [ "$FFMPEG_FOUND" = false ]; then
        echo "   ✗ FFmpeg libraries not found. Install with:"
        echo "     Homebrew: brew install ffmpeg"
        echo "     MacPorts: sudo port install ffmpeg-devel"
    fi
else
    echo "   ? Unknown OS: $OS"
fi
echo ""

# Check if patch was applied to BUILD.gn
echo "2. Checking if BUILD.gn was replaced:"
if [ -f "src/third_party/ffmpeg/BUILD.gn" ]; then
    # Check for key indicators of the system FFmpeg BUILD.gn
    if grep -q "config(\"system_ffmpeg\")" "src/third_party/ffmpeg/BUILD.gn" && \
       grep -q "libs = \[" "src/third_party/ffmpeg/BUILD.gn" && \
       grep -q "\"avcodec\"," "src/third_party/ffmpeg/BUILD.gn"; then
        echo "   ✓ BUILD.gn has been replaced with system FFmpeg configuration"
    else
        echo "   ✗ BUILD.gn does not contain system FFmpeg configuration"
    fi
else
    echo "   ✗ BUILD.gn file not found"
fi
echo ""

# Check if build script was modified
echo "3. Checking if build scripts were modified:"
if [ -f "build_linux.sh" ]; then
    if ! grep -q "ffmpeg_branding=\\"Chrome\\"" "build_linux.sh"; then
        echo "   ✓ build_linux.sh: ffmpeg_branding line removed"
    else
        echo "   ✗ build_linux.sh: still contains ffmpeg_branding"
    fi
else
    echo "   - build_linux.sh not found"
fi
if [ -f "build_macos.sh" ]; then
    if ! grep -q "ffmpeg_branding=" "build_macos.sh"; then
        echo "   ✓ build_macos.sh: ffmpeg_branding line removed"
    else
        echo "   ✗ build_macos.sh: still contains ffmpeg_branding"
    fi
else
    echo "   - build_macos.sh not found"
fi
echo ""

# Check if H264 decoder was patched
echo "4. Checking if H264 decoder was patched:"
H264_DECODER="src/modules/video_coding/codecs/h264/h264_decoder_impl.cc"
if [ -f "$H264_DECODER" ]; then
    # Check if using system headers (angle brackets)
    if grep -q "#include <libavcodec/avcodec.h>" "$H264_DECODER"; then
        echo "   ✓ H264 decoder uses system FFmpeg headers"
    elif grep -q "#include \"third_party/ffmpeg/libavcodec/avcodec.h\"" "$H264_DECODER"; then
        echo "   ✗ H264 decoder still uses bundled FFmpeg headers"
    else
        echo "   ? H264 decoder has unexpected include format"
    fi
else
    echo "   ✗ H264 decoder file not found"
fi
echo ""

# Check if the built library exists and uses system FFmpeg
echo "5. Checking built library:"
BUILD_DIR_FOUND=false
for dir in linux-*-* mac-*-*; do
    if [ -d "$dir" ]; then
        BUILD_DIR_FOUND=true
        if [ -f "$dir/lib/libwebrtc.a" ]; then
            echo "   ✓ libwebrtc.a exists in $dir"
            # Check if it's not linking bundled FFmpeg
            if nm "$dir/lib/libwebrtc.a" 2>/dev/null | grep -q "ff_h264_decode"; then
                echo "   ✗ Library appears to contain bundled FFmpeg symbols"
            else
                echo "   ✓ Library does not contain bundled FFmpeg symbols"
            fi
            # Check for undefined FFmpeg symbols (should be present)
            AVCODEC_SYMBOLS=$(nm "$dir/lib/libwebrtc.a" 2>/dev/null | grep " U avcodec_" | wc -l)
            if [ "$AVCODEC_SYMBOLS" -gt 0 ]; then
                echo "   ✓ Library has $AVCODEC_SYMBOLS undefined avcodec symbols (will link with system FFmpeg)"
            fi
        else
            echo "   - libwebrtc.a not found in $dir (build may not be complete)"
        fi
    fi
done

if [ "$BUILD_DIR_FOUND" = false ]; then
    echo "   - No build directory found - run build first"
fi
echo ""

echo "Verification complete!"