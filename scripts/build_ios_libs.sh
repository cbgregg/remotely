#!/bin/bash
set -euo pipefail

# This script builds universal iOS libraries for llama.cpp.
# It clones llama.cpp if not already present, builds for device and simulator,
# and merges the resulting dylibs using lipo.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="$REPO_DIR/llama.cpp"
IOS_DEVICE_BUILD="$LLAMA_DIR/build_ios"
IOS_SIM_BUILD="$LLAMA_DIR/build_ios_sim"
OUTPUT_DIR="$REPO_DIR/LLMtest/llama_ios"

if [ ! -d "$LLAMA_DIR" ]; then
    git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
fi

mkdir -p "$IOS_DEVICE_BUILD" "$IOS_SIM_BUILD" "$OUTPUT_DIR"

# Build for iOS devices (arm64)
cmake -S "$LLAMA_DIR" -B "$IOS_DEVICE_BUILD" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF
xcodebuild -project "$IOS_DEVICE_BUILD/llama.xcodeproj" -configuration Release -sdk iphoneos BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for iOS simulator (x86_64/arm64)
cmake -S "$LLAMA_DIR" -B "$IOS_SIM_BUILD" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF
xcodebuild -project "$IOS_SIM_BUILD/llama.xcodeproj" -configuration Release -sdk iphonesimulator BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Merge device and simulator libraries
LIBS=(libllama.dylib libggml.dylib libggml-base.dylib libggml-blas.dylib libggml-cpu.dylib libggml-metal.dylib)
for lib in "${LIBS[@]}"; do
    DEVICE_LIB="$IOS_DEVICE_BUILD/Release-iphoneos/$lib"
    SIM_LIB="$IOS_SIM_BUILD/Release-iphonesimulator/$lib"
    if [ -f "$DEVICE_LIB" ] && [ -f "$SIM_LIB" ]; then
        lipo "$DEVICE_LIB" "$SIM_LIB" -create -output "$OUTPUT_DIR/$lib"
    fi
done

# Copy headers
cp -R "$LLAMA_DIR"/*.h "$REPO_DIR/LLMtest/llama" 2>/dev/null || true

echo "iOS libraries built in $OUTPUT_DIR"
