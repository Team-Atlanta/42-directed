#!/bin/bash
# Slicer entrypoint - fetches diff, parses for changed functions, runs LLVM slicing, generates allowlist
#
# Environment variables:
#   OSS_CRS_REPO_PATH - Source directory containing the project (required, set by oss-crs)
#   PROJECT_NAME      - Name of the project (required, for logging)
#   OUT               - Output directory (default: /out)
#   SLICE_TIMEOUT     - Timeout for slicing operations in seconds (default: 600)
#
# Output:
#   /artifacts/slice/slice_target_functions.txt - "path function_name" lines
#   /artifacts/slice/AFL_LLVM_ALLOWLIST - functions to instrument

set -e

# Validate required environment variables
if [ -z "$OSS_CRS_REPO_PATH" ]; then
    echo "[slicer] ERROR: OSS_CRS_REPO_PATH environment variable not set"
    exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
    echo "[slicer] ERROR: PROJECT_NAME environment variable not set"
    exit 1
fi

# Source root is the resolved repo path (effective workdir)
SRC_ROOT="$OSS_CRS_REPO_PATH"

# Set defaults
OUT="${OUT:-/out}"
SLICE_TIMEOUT="${SLICE_TIMEOUT:-600}"

echo "[slicer] Starting slicer pipeline"
echo "[slicer] SRC_ROOT=$SRC_ROOT, PROJECT_NAME=$PROJECT_NAME, OUT=$OUT"
echo "[slicer] SLICE_TIMEOUT=${SLICE_TIMEOUT}s"

# Step 1: Fetch diff via libCRS
echo "[slicer] Fetching diff..."
DIFF_DIR="/tmp/diff"
mkdir -p "$DIFF_DIR"
libCRS fetch diff "$DIFF_DIR"

# Verify diff was fetched
if [ ! "$(ls -A "$DIFF_DIR" 2>/dev/null)" ]; then
    echo "[slicer] ERROR: No diff files fetched from libCRS"
    exit 1
fi
echo "[slicer] Diff files fetched: $(ls "$DIFF_DIR" | wc -l) files"

# Step 2: Parse diff to identify changed functions (reuses components/directed diff_parser.py)
echo "[slicer] Parsing diff for changed functions..."
python3 /scripts/diff_parser.py "$DIFF_DIR" "$SRC_ROOT" > /tmp/slice_target_functions.txt

# Check if any functions found
if [ ! -s /tmp/slice_target_functions.txt ]; then
    echo "[slicer] ERROR: No functions found in diff. Aborting."
    exit 1
fi

FUNC_COUNT=$(wc -l < /tmp/slice_target_functions.txt)
echo "[slicer] Found $FUNC_COUNT target functions:"
head -20 /tmp/slice_target_functions.txt
if [ "$FUNC_COUNT" -gt 20 ]; then
    echo "[slicer] ... and $((FUNC_COUNT - 20)) more"
fi

# Step 3: Compile target to LLVM bitcode
echo "[slicer] Compiling target to LLVM bitcode..."
BITCODE_DIR="$SRC_ROOT/42_aixcc_bitcode"
mkdir -p "$BITCODE_DIR"

# Set compiler wrappers for bitcode extraction
export CC=/usr/local/bin/san-clang
export CXX=/usr/local/bin/san-clang++
export WRITEBC_DIR="$BITCODE_DIR"

# Run the target's compile script (OSS-Fuzz convention)
cd "$SRC_ROOT"
timeout "${SLICE_TIMEOUT}" compile || {
    echo "[slicer] ERROR: Bitcode compilation failed or timed out. Aborting."
    exit 1
}

# Verify bitcode was generated
BC_COUNT=$(find "$BITCODE_DIR" -name "*.bc" | wc -l)
if [ "$BC_COUNT" -eq 0 ]; then
    echo "[slicer] ERROR: No bitcode files generated. Aborting."
    exit 1
fi
echo "[slicer] Generated $BC_COUNT bitcode files"

# Step 4: Run LLVM analyzer for slicing (using slice.py from components/slice)
echo "[slicer] Running LLVM analyzer via slice.py..."
SLICE_OUTPUT="$OUT/slice_results"
mkdir -p "$SLICE_OUTPUT"

# Set environment for slice.py (matches components/slice/slice.py expectations)
export OUT="$SLICE_OUTPUT"
export SRC="$SRC_ROOT"

# Copy slice target file to expected location
cp /tmp/slice_target_functions.txt "$SRC_ROOT/slice_target_functions.txt"

timeout "${SLICE_TIMEOUT}" python3 /scripts/slice.py || {
    echo "[slicer] ERROR: LLVM analyzer failed or timed out. Aborting."
    exit 1
}

echo "[slicer] Analyzer complete."

# Step 5: Generate AFL_LLVM_ALLOWLIST
echo "[slicer] Generating AFL_LLVM_ALLOWLIST..."
python3 /scripts/generate_allowlist.py "$SLICE_OUTPUT" > "$OUT/AFL_LLVM_ALLOWLIST"

# Verify non-empty allowlist (per user decision: no fallback)
if [ ! -s "$OUT/AFL_LLVM_ALLOWLIST" ]; then
    echo "[slicer] ERROR: Empty allowlist generated. Aborting (no fallback per user decision)."
    exit 1
fi

echo "[slicer] Allowlist contains $(wc -l < "$OUT/AFL_LLVM_ALLOWLIST") functions"

# Step 6: Submit slice output via libCRS
echo "[slicer] Submitting slice output..."
mkdir -p /artifacts/slice
cp /tmp/slice_target_functions.txt /artifacts/slice/
cp "$OUT/AFL_LLVM_ALLOWLIST" /artifacts/slice/
cp -r "$SLICE_OUTPUT"/*.slicing_func_result /artifacts/slice/ 2>/dev/null || true
cp "$SLICE_OUTPUT"/callgraph.dot /artifacts/slice/ 2>/dev/null || true

libCRS submit-build-output /artifacts/slice slice

echo "[slicer] Slicing complete."
