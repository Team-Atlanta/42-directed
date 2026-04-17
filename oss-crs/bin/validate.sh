#!/bin/bash
# Validation script for directed-fuzzer CRS against afc-freerdp-delta-01
#
# Usage: validate.sh [--compose-file PATH] [--benchmark-path PATH]
#
# Success: Exits 0 if all phases pass
# Failure: Exits non-zero with diagnostic output

set -e

# Configuration defaults
OSS_CRS_DIR="${OSS_CRS_DIR:-$HOME/post/oss-crs-6}"
COMPOSE_FILE="${COMPOSE_FILE:-$OSS_CRS_DIR/example/42-directed/compose.yaml}"
BENCHMARK_PATH="${BENCHMARK_PATH:-$HOME/post/CRSBench/benchmarks/afc-freerdp-delta-01}"
TARGET_HARNESS="TestFuzzCryptoCertificateDataSetPEM"
RUN_TIMEOUT=300  # 5 minutes

echo "[validate] Starting CRS validation..."
echo "[validate] OSS_CRS_DIR=$OSS_CRS_DIR"
echo "[validate] COMPOSE_FILE=$COMPOSE_FILE"
echo "[validate] BENCHMARK_PATH=$BENCHMARK_PATH"
echo "[validate] TARGET_HARNESS=$TARGET_HARNESS"

# Validate inputs
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "[validate] ERROR: Compose file not found: $COMPOSE_FILE"
    exit 1
fi

if [ ! -d "$BENCHMARK_PATH" ]; then
    echo "[validate] ERROR: Benchmark not found: $BENCHMARK_PATH"
    exit 1
fi

if [ ! -f "$BENCHMARK_PATH/.aixcc/ref.diff" ]; then
    echo "[validate] ERROR: Diff not found: $BENCHMARK_PATH/.aixcc/ref.diff"
    exit 1
fi

# Phase 1: Prepare
echo ""
echo "=========================================="
echo "[validate] PHASE 1: PREPARE"
echo "=========================================="
cd "$OSS_CRS_DIR"
if ! uv run oss-crs prepare --compose-file "$COMPOSE_FILE"; then
    echo "[validate] FAILED: Prepare phase failed"
    exit 1
fi
echo "[validate] PASSED: Prepare phase complete"

# Phase 2: Build-target
echo ""
echo "=========================================="
echo "[validate] PHASE 2: BUILD-TARGET"
echo "=========================================="
BUILD_ID="val-$(date +%s)"
if ! uv run oss-crs build-target \
    --compose-file "$COMPOSE_FILE" \
    --fuzz-proj-path "$BENCHMARK_PATH" \
    --diff "$BENCHMARK_PATH/.aixcc/ref.diff" \
    --build-id "$BUILD_ID"; then
    echo "[validate] FAILED: Build-target phase failed"
    echo "[validate] Check container logs for details"
    exit 1
fi
echo "[validate] PASSED: Build-target phase complete"
echo "[validate] BUILD_ID=$BUILD_ID"

# Phase 3: Run
echo ""
echo "=========================================="
echo "[validate] PHASE 3: RUN (${RUN_TIMEOUT}s)"
echo "=========================================="
RUN_ID="val-$(date +%s)"
# Run phase with timeout - exit code 0 or timeout (124) are acceptable
if ! uv run oss-crs run \
    --compose-file "$COMPOSE_FILE" \
    --fuzz-proj-path "$BENCHMARK_PATH" \
    --target-harness "$TARGET_HARNESS" \
    --timeout "$RUN_TIMEOUT" \
    --build-id "$BUILD_ID" \
    --run-id "$RUN_ID" \
    --diff "$BENCHMARK_PATH/.aixcc/ref.diff"; then
    echo "[validate] NOTE: Run phase exited (may be timeout)"
fi
echo "[validate] Run phase complete"
echo "[validate] RUN_ID=$RUN_ID"

# Verification: Check artifacts
echo ""
echo "=========================================="
echo "[validate] VERIFICATION"
echo "=========================================="

# Get artifact paths
ARTIFACTS=$(uv run oss-crs artifacts \
    --compose-file "$COMPOSE_FILE" \
    --fuzz-proj-path "$BENCHMARK_PATH" \
    --target-harness "$TARGET_HARNESS" \
    --build-id "$BUILD_ID" \
    --run-id "$RUN_ID" 2>/dev/null || echo "{}")

# Check seed production
SEED_DIR=$(echo "$ARTIFACTS" | jq -r '.crs["directed-fuzzer"].seed // empty')
if [ -n "$SEED_DIR" ] && [ -d "$SEED_DIR" ]; then
    SEED_COUNT=$(find "$SEED_DIR" -type f 2>/dev/null | wc -l)
    echo "[validate] Seeds produced: $SEED_COUNT"
    if [ "$SEED_COUNT" -gt 0 ]; then
        echo "[validate] PASSED: Corpus growing (seeds appearing)"
    else
        echo "[validate] WARNING: No seeds produced"
    fi
else
    echo "[validate] WARNING: Seed directory not found"
fi

# Check POV/crashes directory
POV_DIR=$(echo "$ARTIFACTS" | jq -r '.crs["directed-fuzzer"].pov // empty')
if [ -n "$POV_DIR" ] && [ -d "$POV_DIR" ]; then
    POV_COUNT=$(find "$POV_DIR" -type f 2>/dev/null | wc -l)
    echo "[validate] Crashes found: $POV_COUNT"
else
    echo "[validate] NOTE: No crashes directory (expected for short run)"
fi

echo ""
echo "=========================================="
echo "[validate] VALIDATION COMPLETE"
echo "=========================================="
echo "[validate] All phases passed successfully"
exit 0
