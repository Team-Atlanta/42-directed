#!/bin/bash
# Directed Fuzzer Runner
# Downloads build artifacts and executes AFL++ against instrumented targets
#
# Environment variables (REQUIRED):
#   OSS_CRS_TARGET_HARNESS - Name of the harness binary to fuzz
#   OSS_CRS_CPUSET         - CPU cores allocated (e.g., "4-7,10,12-14")
#
# Environment variables (OPTIONAL):
#   OUT                    - Build output directory (default: /out)

set -e

OUT_DIR="${OUT:-/out}"

# =============================================================================
# Environment Validation (STRICT - per user decision)
# =============================================================================

echo "[runner] Starting directed AFL++ runner..."

# Validate OSS_CRS_TARGET_HARNESS
if [ -z "$OSS_CRS_TARGET_HARNESS" ]; then
    echo "[runner] ERROR: OSS_CRS_TARGET_HARNESS environment variable not set"
    echo "[runner] Set OSS_CRS_TARGET_HARNESS to the name of the harness binary to fuzz"
    exit 1
fi

# Validate OSS_CRS_CPUSET
if [ -z "$OSS_CRS_CPUSET" ]; then
    echo "[runner] ERROR: OSS_CRS_CPUSET environment variable not set"
    echo "[runner] Set OSS_CRS_CPUSET to the CPU cores allocated (e.g., '4-7,10,12-14')"
    exit 1
fi

echo "[runner] OSS_CRS_TARGET_HARNESS=$OSS_CRS_TARGET_HARNESS"
echo "[runner] OSS_CRS_CPUSET=$OSS_CRS_CPUSET"

# =============================================================================
# Artifact Download
# =============================================================================

echo "[runner] Downloading build artifacts..."
mkdir -p "$OUT_DIR"
libCRS download-build-output build "$OUT_DIR"

# Verify harness exists
HARNESS_PATH="$OUT_DIR/$OSS_CRS_TARGET_HARNESS"
if [ ! -f "$HARNESS_PATH" ]; then
    echo "[runner] ERROR: Harness '$OSS_CRS_TARGET_HARNESS' not found in build artifacts"
    echo "[runner] Available files in $OUT_DIR:"
    ls -la "$OUT_DIR"
    exit 1
fi

# Set executable bit
chmod +x "$HARNESS_PATH"
echo "[runner] Harness ready: $HARNESS_PATH"

# =============================================================================
# CPU Set Parsing
# =============================================================================

# parse_cpuset: Parse cpuset format into space-separated core IDs
# Input: cpuset string like "4-7,10,12-14"
# Output: Sets CORES array with individual core IDs (4 5 6 7 10 12 13 14)
parse_cpuset() {
    local cpuset="$1"
    CORES=()

    # Split by comma
    IFS=',' read -ra segments <<< "$cpuset"

    for segment in "${segments[@]}"; do
        if [[ "$segment" == *-* ]]; then
            # Range: "4-7" -> 4 5 6 7
            local start="${segment%-*}"
            local end="${segment#*-}"
            for ((i=start; i<=end; i++)); do
                CORES+=("$i")
            done
        else
            # Individual core: "10" -> 10
            CORES+=("$segment")
        fi
    done
}

# Parse the cpuset
parse_cpuset "$OSS_CRS_CPUSET"
echo "[runner] Parsed ${#CORES[@]} CPU cores: ${CORES[*]}"

# =============================================================================
# Directory Setup and libCRS Registration
# =============================================================================

# Create AFL++ directories
SYNC_DIR="/fuzzer/sync"
mkdir -p "$SYNC_DIR"
mkdir -p /fuzzer/crashes

# Register POV directory for continuous submission
libCRS register-submit-dir pov /fuzzer/crashes
echo "[runner] Registered POV directory: /fuzzer/crashes"

# Register AFL++ main queue directly as seed dir
# libCRS will pick up new files as AFL++ discovers them
mkdir -p "$SYNC_DIR/main/queue"
libCRS register-submit-dir seed "$SYNC_DIR/main/queue"
echo "[runner] Registered seed directory: $SYNC_DIR/main/queue"

# Set up corpus directory - unzip seed corpus if available (OSS-Fuzz convention)
CORPUS_DIR="/corpus"
mkdir -p "$CORPUS_DIR"

SEED_CORPUS_ZIP="$OUT_DIR/${OSS_CRS_TARGET_HARNESS}_seed_corpus.zip"
if [ -f "$SEED_CORPUS_ZIP" ]; then
    unzip -o -q "$SEED_CORPUS_ZIP" -d "$CORPUS_DIR" 2>/dev/null || true
    echo "[runner] Unpacked seed corpus: $SEED_CORPUS_ZIP ($(ls "$CORPUS_DIR" | wc -l) files)"
elif [ -d "$OUT_DIR/corpus" ] && [ "$(ls -A "$OUT_DIR/corpus" 2>/dev/null)" ]; then
    cp -r "$OUT_DIR/corpus/"* "$CORPUS_DIR/" 2>/dev/null || true
    echo "[runner] Using corpus directory from build artifacts"
fi

# Ensure at least one seed exists
if [ ! "$(ls -A "$CORPUS_DIR" 2>/dev/null)" ]; then
    echo "AAAA" > "$CORPUS_DIR/initial"
    echo "[runner] Created minimal corpus: $CORPUS_DIR/initial"
else
    echo "[runner] Corpus contains $(ls "$CORPUS_DIR" | wc -l) seeds"
fi

# Set up dictionary if available
DICT_FILE="$OUT_DIR/${OSS_CRS_TARGET_HARNESS}.dict"
DICT_ARG=""
if [ -f "$DICT_FILE" ]; then
    DICT_ARG="-x $DICT_FILE"
    echo "[runner] Using dictionary: $DICT_FILE"
fi

# =============================================================================
# AFL++ Execution
# =============================================================================

NUM_CORES=${#CORES[@]}
HARNESS="$HARNESS_PATH"

# Skip AFL++ startup checks that don't apply in containers
export AFL_SKIP_CPUFREQ=1
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

echo "[runner] Launching AFL++ with $NUM_CORES instances on cores: ${CORES[*]}"

# Launch main instance (-M) on first core
afl-fuzz -M main -i "$CORPUS_DIR" -o "$SYNC_DIR" $DICT_ARG -b "${CORES[0]}" -- "$HARNESS" @@ &
MAIN_PID=$!
echo "[runner] Started main instance (PID $MAIN_PID) on core ${CORES[0]}"

# Launch secondary instances (-S) on remaining cores (RUN-07)
for ((i=1; i<NUM_CORES; i++)); do
    afl-fuzz -S "secondary$i" -i "$CORPUS_DIR" -o "$SYNC_DIR" $DICT_ARG -b "${CORES[$i]}" -- "$HARNESS" @@ &
    echo "[runner] Started secondary$i instance on core ${CORES[$i]}"
done

echo "[runner] All $NUM_CORES AFL++ instances launched"

# =============================================================================
# Crash/Seed Monitor for Continuous Submission
# =============================================================================

# Background crash copier - copies crashes from all AFL++ instances to registered POV dir
touch /tmp/.last_crash_check
(
    while true; do
        find "$SYNC_DIR" -path "*/crashes/*" -type f -newer /tmp/.last_crash_check 2>/dev/null | while read -r crash; do
            [[ "$(basename "$crash")" == "README.txt" ]] && continue
            cp "$crash" /fuzzer/crashes/ 2>/dev/null || true
        done
        touch /tmp/.last_crash_check
        sleep 5
    done
) &
echo "[runner] Started crash monitor (PID $!)"
# Seeds are submitted directly from $SYNC_DIR/main/queue via libCRS register-submit-dir

# =============================================================================
# Wait for AFL++ Execution
# =============================================================================

# Wait for all AFL++ instances to complete
# This keeps the container running until fuzzing is done or killed
wait

echo "[runner] AFL++ execution complete"
