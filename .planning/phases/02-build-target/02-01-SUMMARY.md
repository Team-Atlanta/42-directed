---
phase: 02-build-target
plan: 01
subsystem: slicer
tags: [dockerfile, diff-parsing, tree-sitter, libcrs]
dependency_graph:
  requires: []
  provides: [slicer-container, diff-parser, function-detector]
  affects: [02-02-PLAN, builder.Dockerfile]
tech_stack:
  added: [tree-sitter, tree-sitter-c, unidiff]
  patterns: [libCRS-fetch-submit, target-base-image]
key_files:
  created:
    - oss-crs/dockerfiles/slicer.Dockerfile
    - oss-crs/bin/slicer.sh
    - oss-crs/scripts/parse_diff.py
  modified: []
decisions:
  - SLICE_TIMEOUT default set to 600 seconds (10 minutes) per research recommendation
  - Using tree-sitter-c for function detection (tree-sitter-cpp not added yet - can extend later)
  - Strict error handling - abort if no functions found in diff
metrics:
  duration: 107s
  completed: 2026-03-12T04:47:48Z
---

# Phase 02 Plan 01: Slicer Foundation Summary

Slicer container foundation with diff fetching, tree-sitter function detection, and libCRS artifact submission pipeline.

## What Was Built

### slicer.Dockerfile
The slicer container definition following OSS-CRS patterns:
- `ARG target_base_image` / `FROM ${target_base_image}` pattern for compatibility
- libCRS installation via `COPY --from=libcrs` and install script
- Python dependencies: tree-sitter, tree-sitter-c, unidiff
- Script files: slicer.sh entrypoint, parse_diff.py for function detection

### slicer.sh
Orchestration script implementing the slicer pipeline:
1. Validates required environment variables (SRC, PROJECT_NAME)
2. Fetches diff via `libCRS fetch diff`
3. Parses diff to identify changed functions via parse_diff.py
4. Submits slice output via `libCRS submit-build-output`
5. Placeholders for bitcode compilation and LLVM analysis (Plan 02)

### parse_diff.py
Diff parsing and function detection using tree-sitter:
- Parses unified diff files (.diff, .patch) using unidiff library
- Extracts changed line numbers from added/modified lines
- Locates source files in the project tree
- Uses tree-sitter C parser to find function_definition nodes
- Checks if changed lines fall within function boundaries
- Outputs "path function_name" format for LLVM analyzer

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 046ca3d | feat(02-01): create slicer.Dockerfile with libCRS |
| 2 | a2a5d00 | feat(02-01): create slicer.sh entrypoint script |
| 3 | a01ca46 | feat(02-01): create parse_diff.py for function detection |

## Key Links Verified

- slicer.Dockerfile -> slicer.sh: `CMD ["/slicer.sh"]`
- slicer.sh -> parse_diff.py: `python3 /scripts/parse_diff.py`

## Deviations from Plan

None - plan executed exactly as written.

## Next Steps (Plan 02)

The placeholders in slicer.sh will be filled by Plan 02:
- Step 3: Bitcode compilation using writebc.so
- Step 4: LLVM static analyzer for code path analysis
- Step 5: AFL_LLVM_ALLOWLIST generation from slice results

## Self-Check: PASSED

All created files exist:
- oss-crs/dockerfiles/slicer.Dockerfile
- oss-crs/bin/slicer.sh
- oss-crs/scripts/parse_diff.py

All commits verified:
- 046ca3d, a2a5d00, a01ca46
