#!/bin/bash

# Script to verify that the system FFmpeg patch was applied correctly

echo "Verifying system FFmpeg patch..."
echo ""

# Check if FFmpeg is installed
echo "1. Checking system FFmpeg installation:"
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
echo ""

# Check if patch was applied to BUILD.gn
echo "2. Checking if BUILD.gn was patched:"
if [ -f "src/third_party/ffmpeg/BUILD.gn" ]; then
    if grep -q "use_system_ffmpeg" "src/third_party/ffmpeg/BUILD.gn"; then
        echo "   ✓ BUILD.gn contains system FFmpeg configuration"
    else
        echo "   ✗ BUILD.gn missing system FFmpeg configuration"
    fi
else
    echo "   ✗ BUILD.gn file not found"
fi
echo ""

# Check if build script was modified
echo "3. Checking if build script was modified:"
if [ -f "build_linux.sh" ]; then
    if grep -q "use_system_ffmpeg=true" "build_linux.sh"; then
        echo "   ✓ build_linux.sh contains use_system_ffmpeg=true"
    else
        echo "   ✗ build_linux.sh missing use_system_ffmpeg=true"
    fi
else
    echo "   ✗ build_linux.sh not found"
fi
echo ""

# Check if H264 decoder was patched
echo "4. Checking if H264 decoder was patched:"
H264_DECODER="src/modules/video_coding/codecs/h264/h264_decoder_impl.cc"
if [ -f "$H264_DECODER" ]; then
    if grep -q "USE_SYSTEM_FFMPEG" "$H264_DECODER"; then
        echo "   ✓ H264 decoder contains system FFmpeg includes"
    else
        echo "   ✗ H264 decoder missing system FFmpeg includes"
    fi
else
    echo "   ✗ H264 decoder file not found"
fi
echo ""

# Check if video coding BUILD.gn was patched
echo "5. Checking if video coding BUILD.gn was patched:"
VIDEO_CODING_BUILD="src/modules/video_coding/BUILD.gn"
if [ -f "$VIDEO_CODING_BUILD" ]; then
    if grep -q "USE_SYSTEM_FFMPEG" "$VIDEO_CODING_BUILD"; then
        echo "   ✓ Video coding BUILD.gn contains USE_SYSTEM_FFMPEG define"
    else
        echo "   ✗ Video coding BUILD.gn missing USE_SYSTEM_FFMPEG define"
    fi
else
    echo "   ✗ Video coding BUILD.gn not found"
fi
echo ""

# Check if the built library exists and uses system FFmpeg
if [ -d "linux-x64-release" ]; then
    echo "6. Checking built library:"
    if [ -f "linux-x64-release/lib/libwebrtc.a" ]; then
        echo "   ✓ libwebrtc.a exists"
        # Check if it's not linking bundled FFmpeg
        if nm "linux-x64-release/lib/libwebrtc.a" 2>/dev/null | grep -q "ff_h264_decode"; then
            echo "   ✗ Library appears to contain bundled FFmpeg symbols"
        else
            echo "   ✓ Library does not contain bundled FFmpeg symbols"
        fi
    else
        echo "   - libwebrtc.a not found (build may not be complete)"
    fi
else
    echo "6. Build directory not found - run build first"
fi
echo ""

echo "Verification complete!"