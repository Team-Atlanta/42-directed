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
mkdir -p /fuzzer/queue

# Register POV directory for continuous submission (RUN-03)
libCRS register-submit-dir pov /fuzzer/crashes
echo "[runner] Registered POV directory for continuous submission"

# Register seed directory for continuous submission (RUN-04)
libCRS register-submit-dir seed /fuzzer/queue
echo "[runner] Registered seed directory for continuous submission"

# Set up corpus directory
if [ -d "$OUT_DIR/corpus" ] && [ "$(ls -A "$OUT_DIR/corpus" 2>/dev/null)" ]; then
    CORPUS_DIR="$OUT_DIR/corpus"
    echo "[runner] Using corpus from build artifacts: $CORPUS_DIR"
else
    CORPUS_DIR="/corpus"
    mkdir -p "$CORPUS_DIR"
    echo "AAAA" > "$CORPUS_DIR/initial"
    echo "[runner] Created minimal corpus: $CORPUS_DIR/initial"
fi

# =============================================================================
# AFL++ Execution
# =============================================================================

NUM_CORES=${#CORES[@]}
HARNESS="$HARNESS_PATH"

# Skip AFL++ startup checks that don't apply in containers
export AFL_SKIP_CPUFREQ=1
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
export AFL_NO_AFFINITY=1

echo "[runner] Launching AFL++ with $NUM_CORES instances on cores: ${CORES[*]}"

# Launch main instance (-M) on first core (RUN-07)
# Use explicit -b core binding to avoid Docker CPU affinity issues
afl-fuzz -M main -i "$CORPUS_DIR" -o "$SYNC_DIR" -b "${CORES[0]}" -- "$HARNESS" @@ &
MAIN_PID=$!
echo "[runner] Started main instance (PID $MAIN_PID) on core ${CORES[0]}"

# Launch secondary instances (-S) on remaining cores (RUN-07)
for ((i=1; i<NUM_CORES; i++)); do
    afl-fuzz -S "secondary$i" -i "$CORPUS_DIR" -o "$SYNC_DIR" -b "${CORES[$i]}" -- "$HARNESS" @@ &
    echo "[runner] Started secondary$i instance on core ${CORES[$i]}"
done

echo "[runner] All $NUM_CORES AFL++ instances launched"

# =============================================================================
# Crash/Seed Monitor for Continuous Submission
# =============================================================================

# Initialize timestamp file for incremental copy
touch /tmp/.last_crash_check
touch /tmp/.last_seed_check

# Background crash copier - copies crashes from all instances to registered POV directory
(
    while true; do
        # Copy new crashes from all AFL++ instances to /fuzzer/crashes
        find "$SYNC_DIR" -path "*/crashes/*" -type f -newer /tmp/.last_crash_check 2>/dev/null | while read -r crash; do
            # Skip README.txt files that AFL++ creates
            [[ "$(basename "$crash")" == "README.txt" ]] && continue
            cp "$crash" /fuzzer/crashes/ 2>/dev/null || true
        done
        touch /tmp/.last_crash_check
        sleep 5
    done
) &
CRASH_MONITOR_PID=$!

# Background seed copier - copies new seeds from all instances to registered seed directory
(
    while true; do
        # Copy new queue items from all AFL++ instances to /fuzzer/queue
        find "$SYNC_DIR" -path "*/queue/*" -type f -newer /tmp/.last_seed_check 2>/dev/null | while read -r seed; do
            # Skip README.txt files and .state directories
            [[ "$(basename "$seed")" == "README.txt" ]] && continue
            [[ "$seed" == *".state"* ]] && continue
            cp "$seed" /fuzzer/queue/ 2>/dev/null || true
        done
        touch /tmp/.last_seed_check
        sleep 5
    done
) &
SEED_MONITOR_PID=$!

echo "[runner] Started crash/seed monitor for continuous submission (PIDs: $CRASH_MONITOR_PID, $SEED_MONITOR_PID)"

# =============================================================================
# Wait for AFL++ Execution
# =============================================================================

# Wait for all AFL++ instances to complete
# This keeps the container running until fuzzing is done or killed
wait

echo "[runner] AFL++ execution complete"
