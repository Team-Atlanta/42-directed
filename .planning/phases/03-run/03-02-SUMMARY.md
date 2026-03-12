---
phase: 03-run
plan: 02
subsystem: runner
tags: [afl++, fuzzing, bash, libcrs, oss-crs, parallel]

# Dependency graph
requires:
  - phase: 03-run/01
    provides: Runner foundation with artifact download and cpuset parsing
provides:
  - AFL++ parallel execution with master/secondary instances
  - libCRS directory registration for continuous POV/seed submission
  - Crash/seed monitor for streaming to OSS-CRS
affects: [runner container, oss-crs integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - AFL++ master/secondary parallel execution with -M/-S flags
    - Explicit core binding with -b to avoid Docker affinity issues
    - Background monitor loop for continuous file submission

key-files:
  created: []
  modified:
    - oss-crs/bin/runner.sh

key-decisions:
  - "Continuous submission via register-submit-dir (not batched) per user decision"
  - "Background copy loop for crashes/seeds from all AFL++ instances to registered directories"
  - "Explicit -b core binding to avoid Docker CPU affinity issues per research pitfall #1"

patterns-established:
  - "AFL++ parallel pattern: -M main on core[0], -S secondary$i on remaining cores"
  - "File monitor pattern: find with -newer flag for incremental copy"

requirements-completed: [RUN-03, RUN-04, RUN-05, RUN-07]

# Metrics
duration: 1min
completed: 2026-03-12
---

# Phase 3 Plan 02: AFL++ Execution Summary

**AFL++ parallel fuzzing with master/secondary instances, libCRS continuous crash and seed submission**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-12T05:54:57Z
- **Completed:** 2026-03-12T05:56:25Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- libCRS directory registration for continuous POV (/fuzzer/crashes) and seed (/fuzzer/queue) submission
- AFL++ main instance (-M) on first allocated core with explicit -b binding
- N-1 AFL++ secondary instances (-S) on remaining cores for parallel fuzzing
- Background crash/seed monitor copying from all instances to registered directories

## Task Commits

Each task was committed atomically:

1. **Task 1: Add libCRS directory registration for POV and seed submission** - `e3e431d` (feat)
2. **Task 2: Add AFL++ master/secondary instance launching** - `18923c7` (feat)
3. **Task 3: Wire crash output to registered POV directory** - `946051d` (feat)

## Files Created/Modified
- `oss-crs/bin/runner.sh` - Complete runner with AFL++ execution, libCRS registration, and crash/seed monitoring

## Decisions Made
- Continuous submission via libCRS register-submit-dir (per user decision in CONTEXT.md)
- Background copy loop approach for crash/seed monitoring (captures from all instances, not just main)
- Explicit -b core binding to avoid Docker CPU affinity issues (per research pitfall #1)
- Skip README.txt and .state files in monitor to avoid copying AFL++ metadata

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Runner container fully functional with AFL++ parallel execution
- Continuous crash and seed submission ready for OSS-CRS integration
- Phase 03-run complete

---
*Phase: 03-run*
*Completed: 2026-03-12*

## Self-Check: PASSED

- FOUND: oss-crs/bin/runner.sh
- FOUND: commit e3e431d
- FOUND: commit 18923c7
- FOUND: commit 946051d
