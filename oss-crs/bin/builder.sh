#!/bin/bash
# Directed Fuzzer Builder
# Downloads allowlist from slicer and compiles target with AFL++
#
# Environment variables:
#   PROJECT_NAME - OSS-Fuzz project name (required)
#   SRC          - Source directory (default: /src)
#   OUT          - Build output directory (default: /out)
#   OSS_CRS_TARGET_HARNESS - Target harness to build (optional)

set -e

PROJECT_NAME="${PROJECT_NAME:-$(basename $SRC)}"
SRC_DIR="${SRC:-/src}"
OUT_DIR="${OUT:-/out}"

echo "[builder] Starting directed AFL++ build..."
echo "[builder] PROJECT_NAME=$PROJECT_NAME"
echo "[builder] SRC_DIR=$SRC_DIR"
echo "[builder] OUT_DIR=$OUT_DIR"

# Step 1: Download slice output from slicer
echo "[builder] Downloading slice output..."
SLICE_DIR="/slice"
mkdir -p "$SLICE_DIR"
libCRS download-build-output slice "$SLICE_DIR"

# Verify allowlist exists
if [ ! -f "$SLICE_DIR/AFL_LLVM_ALLOWLIST" ]; then
    echo "[builder] ERROR: AFL_LLVM_ALLOWLIST not found in slice output"
    ls -la "$SLICE_DIR"
    exit 1
fi

# Step 2: Set up AFL++ with allowlist
echo "[builder] Configuring AFL++ with allowlist..."
export AFL_LLVM_ALLOWLIST="$SLICE_DIR/AFL_LLVM_ALLOWLIST"
echo "[builder] AFL_LLVM_ALLOWLIST=$AFL_LLVM_ALLOWLIST"
echo "[builder] Allowlist contains $(wc -l < $AFL_LLVM_ALLOWLIST) functions"

# CC and CXX should already be set to AFL++ compilers by target_base_image
# (e.g., afl-clang-fast, afl-clang-lto)
echo "[builder] CC=$CC"
echo "[builder] CXX=$CXX"

# Step 3: Run OSS-Fuzz compile
echo "[builder] Running compile..."
compile

# Step 4: Verify target harness if specified
if [ -n "$OSS_CRS_TARGET_HARNESS" ]; then
    if [ ! -f "$OUT_DIR/$OSS_CRS_TARGET_HARNESS" ]; then
        echo "[builder] WARNING: Requested harness $OSS_CRS_TARGET_HARNESS not found"
    else
        echo "[builder] Target harness: $OSS_CRS_TARGET_HARNESS"
    fi
fi

# Step 5: Verify build output
HARNESS_COUNT=$(find "$OUT_DIR" -maxdepth 1 -type f -executable | wc -l)
if [ "$HARNESS_COUNT" -eq 0 ]; then
    echo "[builder] ERROR: No executable harnesses found in $OUT_DIR"
    exit 1
fi
echo "[builder] Built $HARNESS_COUNT harness(es)"

# Step 6: Submit build output via libCRS
echo "[builder] Submitting build output..."
mkdir -p /artifacts/build

# Copy harnesses and support files
cp "$OUT_DIR"/* /artifacts/build/ 2>/dev/null || true

# Include the allowlist for debugging
cp "$SLICE_DIR/AFL_LLVM_ALLOWLIST" /artifacts/build/

libCRS submit-build-output /artifacts/build build

echo "[builder] Build complete."
echo "[builder] Output directory contents:"
ls -la /artifacts/build/
