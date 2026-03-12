---
phase: 02-build-target
plan: 02
subsystem: slicer
tags: [llvm, bitcode, static-analysis, afl-allowlist, slicing]
dependency_graph:
  requires:
    - phase: 02-01
      provides: slicer-container, diff-parser, function-detector
  provides:
    - llvm-builder-stage
    - bitcode-compilation
    - static-analyzer-integration
    - afl-allowlist-generation
  affects: [02-03-PLAN, builder.Dockerfile]
tech_stack:
  added: [writebc.so, san-clang, analyzer, llvm-14]
  patterns: [multi-stage-dockerfile, abort-on-failure]
key_files:
  created:
    - oss-crs/scripts/generate_allowlist.py
  modified:
    - oss-crs/dockerfiles/slicer.Dockerfile
    - oss-crs/bin/slicer.sh
key_decisions:
  - "Multi-stage build with llvm-builder stage for LLVM tool caching"
  - "Strict abort-on-failure semantics - no fallback to function-level allowlist"
  - "WRITEBC_DIR environment variable for bitcode output location"
patterns_established:
  - "llvm-builder: Multi-stage Dockerfile pattern for LLVM tool compilation"
  - "san-clang: Compiler wrapper exports CC/CXX for bitcode extraction"
requirements_completed: [SLC-06, SLC-07, SLC-08, SLC-09]
duration: 102s
completed: 2026-03-12T04:52:17Z
---

# Phase 02 Plan 02: LLVM Slicing Pipeline Summary

**LLVM bitcode compilation via san-clang wrappers, static analyzer integration for code path slicing, and AFL_LLVM_ALLOWLIST generation with abort-on-failure semantics**

## Performance

- **Duration:** 102s
- **Started:** 2026-03-12T04:50:35Z
- **Completed:** 2026-03-12T04:52:17Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Multi-stage Dockerfile with llvm-builder stage for LLVM tool compilation and caching
- Complete slicer.sh pipeline: bitcode compilation, analyzer execution, allowlist generation
- Strict abort-on-failure semantics throughout the pipeline (no fallback per user decision)
- generate_allowlist.py converts slice results to AFL++ fun:function_name format

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend slicer.Dockerfile with LLVM tools** - `35d48a4` (feat)
2. **Task 2: Complete slicer.sh with slicing pipeline** - `d757587` (feat)
3. **Task 3: Create generate_allowlist.py** - `65fe936` (feat)

## Files Created/Modified

- `oss-crs/dockerfiles/slicer.Dockerfile` - Multi-stage build with llvm-builder, copies writebc.so, sancc, analyzer
- `oss-crs/bin/slicer.sh` - Complete pipeline: bitcode compilation, LLVM analyzer, allowlist generation
- `oss-crs/scripts/generate_allowlist.py` - Converts .slicing_func_result files to AFL_LLVM_ALLOWLIST format

## Key Links Verified

- slicer.Dockerfile -> llvm-builder: `FROM ubuntu:22.04 AS llvm-builder`
- slicer.Dockerfile -> writebc.so: `COPY --from=llvm-builder /usr/local/lib/writebc.so`
- slicer.sh -> san-clang: `export CC=/usr/local/bin/san-clang`
- slicer.sh -> analyzer: `/usr/local/bin/analyzer --srcroot=... --slicing=true`
- slicer.sh -> generate_allowlist.py: `python3 /scripts/generate_allowlist.py`

## Decisions Made

- **Multi-stage build:** LLVM compilation in llvm-builder stage enables Docker layer caching across targets
- **Abort-on-failure:** No fallback to function-level allowlist per user decision - empty allowlist = abort
- **WRITEBC_DIR convention:** 42_aixcc_bitcode directory matches existing component patterns
- **san-clang wrappers:** Using sancc/san-clang from klaus directory for bitcode extraction

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Slicer pipeline complete with all LLVM tools integrated
- AFL_LLVM_ALLOWLIST generated and submitted via libCRS
- Ready for builder container to consume allowlist (Plan 03)

---
*Phase: 02-build-target*
*Completed: 2026-03-12*

## Self-Check: PASSED

All created/modified files exist:
- oss-crs/dockerfiles/slicer.Dockerfile
- oss-crs/bin/slicer.sh
- oss-crs/scripts/generate_allowlist.py

All commits verified:
- 35d48a4, d757587, 65fe936
