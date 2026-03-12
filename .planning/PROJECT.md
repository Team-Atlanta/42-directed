# Bug-finding Directed OSS-CRS

## What This Is

A standalone directed fuzzer for OSS-CRS that ports the directed fuzzing component from the existing CRS microservices architecture. Uses AFL++ with program slicing to target code changes identified by diff files. Designed for automated vulnerability research in C/C++ codebases.

## Core Value

Parse diff, generate AFL allowlist from sliced code paths, and fuzz until we find bugs at changed locations.

## Requirements

### Validated

<!-- Existing capabilities in this codebase -->

- ✓ Program slicing (`components/slice/`) — extracts relevant code paths from target locations
- ✓ Diff parsing — identifies target locations from patch files
- ✓ AFL++ integration — fuzzer invocation and corpus management
- ✓ Harness compilation — builds instrumented binaries for fuzzing

### Active

<!-- OSS-CRS integration scope -->

- [ ] OSS-CRS crs.yaml configuration with diff as required_metadata
- [ ] Prepare phase: docker-bake.hcl for CRS Docker dependencies
- [ ] Build-target phase: instrumentation Dockerfile with AFL allowlist generation
- [ ] Build-target phase: diff parsing integrated into instrumentation
- [ ] Build-target phase: submit-build-output for harness artifacts
- [ ] Run phase: download-build-output and fuzzer execution
- [ ] Run phase: register-submit-dir for PoV output
- [ ] Run phase: register-fetch-dir for seed input
- [ ] Run phase: AFL++ slave management with OSS_CRS_CPUSET
- [ ] Validation: afc-freerdp-delta-01 passes prepare phase
- [ ] Validation: afc-freerdp-delta-01 passes build-target phase
- [ ] Validation: afc-freerdp-delta-01 passes run phase

### Out of Scope

- Microservices architecture (scheduler, gateway, RabbitMQ) — existing CRS infrastructure not ported
- Patch generation — this is bug-finding only
- Kubernetes deployment — OSS-CRS handles orchestration
- Database persistence — OSS-CRS manages state

## Context

**Source codebase:**
- `components/slice/` — Python program slicing using static analysis
- `components/directed/` — Directed fuzzing component (if exists)
- Diff parser location TBD — need to locate diff_parser.py

**Target integration:**
- OSS-CRS framework at `~/post/oss-crs-6`
- Reference CRS implementations at `~/post/crs-libfuzzer`, `~/post/atlantis-multilang-wo-concolic`, `~/post/buttercup-bugfind`
- Example compose files at `~/post/oss-crs-6/{registry,example}/`

**Benchmark for validation:**
- `~/post/CRSBench/benchmarks/afc-freerdp-delta-01`
- Uses `.aixcc/ref.diff` for target locations

**Key research questions to resolve:**
1. How is the directed fuzzer invoked (location based, runtime N locations?)
2. How does instrumentation work with AFL allowlist?
3. What Docker dependencies are needed?
4. What build artifacts transfer from build-target to run?

## Constraints

- **Integration target**: OSS-CRS three-phase architecture (prepare, build-target, run)
- **Required metadata**: diff file must be provided to build-target and run phases
- **Build pattern**: Use `target_base_image` + `builder.Dockerfile` pattern
- **Artifact transfer**: Use libCRS submit-build-output / download-build-output
- **CPU allocation**: Respect OSS_CRS_CPUSET for AFL++ slave count

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Static slice → AFL allowlist | Both combined per user specification | — Pending |
| Single benchmark validation | afc-freerdp-delta-01 as v1 target | — Pending |

---
*Last updated: 2026-03-11 after initialization*
