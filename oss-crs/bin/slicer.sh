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

# Map OSS_CRS_REPO_PATH to SRC/PROJECT_NAME for OSS-Fuzz compatibility
# e.g., /src/FreeRDP -> SRC=/src, PROJECT_NAME=FreeRDP
export SRC="$(dirname "$OSS_CRS_REPO_PATH")"
export PROJECT_NAME="$(basename "$OSS_CRS_REPO_PATH")"

# Set defaults
OUT="${OUT:-/out}"
SLICE_TIMEOUT="${SLICE_TIMEOUT:-600}"

echo "[slicer] Starting slicer pipeline"
echo "[slicer] SRC=$SRC, PROJECT_NAME=$PROJECT_NAME, OUT=$OUT"
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
python3 /scripts/diff_parser.py "$DIFF_DIR" "$SRC/$PROJECT_NAME" > /tmp/slice_target_functions.txt

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

# writebc plugin writes to $OUT/42_aixcc_bitcode (uses OUT env var)
BITCODE_DIR="$OUT/42_aixcc_bitcode"
mkdir -p "$BITCODE_DIR"

# Set compiler wrappers for bitcode extraction
export CC=/usr/local/bin/san-clang
export CXX=/usr/local/bin/san-clang++

# Skip libfuzzer compilation - slicer only needs bitcode, not fuzzer runtime.
# But targets may reference libFuzzingEngine.a in their CMake, so provide a stub.
export FUZZING_ENGINE=none
ar rcs /usr/lib/libFuzzingEngine.a 2>/dev/null || true

# Run the target's compile script (OSS-Fuzz convention)
# Full compile may fail (e.g., clang 14 header path differences),
# but we only need bitcode files to be generated for slicing.
cd "$SRC/$PROJECT_NAME"
timeout "${SLICE_TIMEOUT}" compile || {
    echo "[slicer] WARNING: Compile returned non-zero. Checking for bitcode files..."
}

# Verify bitcode was generated - this is what matters for slicing
BC_COUNT=$(find "$BITCODE_DIR" -name "*.bc" | wc -l)
if [ "$BC_COUNT" -eq 0 ]; then
    echo "[slicer] ERROR: No bitcode files generated. Aborting."
    exit 1
fi
echo "[slicer] Generated $BC_COUNT bitcode files"

# Step 4: Run LLVM analyzer for slicing (call analyzer directly like original)
echo "[slicer] Running LLVM analyzer..."
SLICE_OUTPUT="$OUT/slice_results"
mkdir -p "$SLICE_OUTPUT"

# Find all .bc files
BC_FILES=$(find "$BITCODE_DIR" -name "*.bc" | tr '\n' ' ')

timeout "${SLICE_TIMEOUT}" /usr/local/bin/analyzer \
    --srcroot="$SRC/$PROJECT_NAME" \
    --callgraph=true \
    --slicing=true \
    --output="$SLICE_OUTPUT" \
    --multi=/tmp/slice_target_functions.txt \
    $BC_FILES || {
    echo "[slicer] WARNING: LLVM analyzer returned non-zero."
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
