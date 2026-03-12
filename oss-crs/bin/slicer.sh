#!/bin/bash
# Slicer entrypoint - fetches diff, parses for changed functions, submits slice target
#
# Environment variables:
#   SRC             - Source directory containing the project (required)
#   PROJECT_NAME    - Name of the project directory within SRC (required)
#   OUT             - Output directory (default: /out)
#   SLICE_TIMEOUT   - Timeout for slicing operations in seconds (default: 600)
#
# Output:
#   /artifacts/slice/slice_target_functions.txt - "path function_name" lines

set -e

# Validate required environment variables
if [ -z "$SRC" ]; then
    echo "[slicer] ERROR: SRC environment variable not set"
    exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
    echo "[slicer] ERROR: PROJECT_NAME environment variable not set"
    exit 1
fi

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

# Step 2: Parse diff to identify changed functions
echo "[slicer] Parsing diff for changed functions..."
python3 /scripts/parse_diff.py "$DIFF_DIR" "$SRC/$PROJECT_NAME" > /tmp/slice_target_functions.txt

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

# Step 3: Placeholder for bitcode compilation (Plan 02)
# Will compile target to LLVM bitcode using writebc.so

# Step 4: Placeholder for LLVM analyzer (Plan 02)
# Will run static analyzer to find code paths to target functions

# Step 5: Placeholder for allowlist generation (Plan 02)
# Will generate AFL_LLVM_ALLOWLIST from slice results

# Step 6: Submit slice output via libCRS
echo "[slicer] Submitting slice output..."
mkdir -p /artifacts/slice
cp /tmp/slice_target_functions.txt /artifacts/slice/
# Allowlist will be added by Plan 02
libCRS submit-build-output /artifacts/slice slice

echo "[slicer] Slicing complete."
