# Project Research Summary

**Project:** Directed Fuzzing OSS-CRS Integration
**Domain:** Security testing tooling / OSS-CRS integration
**Researched:** 2026-03-11
**Confidence:** HIGH

## Executive Summary

This project integrates an existing directed fuzzing system into the OSS-CRS (Open Source Continuous Reasoning System) framework. The existing codebase has a microservices architecture with RabbitMQ orchestration, scheduler components, and PostgreSQL persistence - none of which port to OSS-CRS. The integration requires a ground-up rebuild using OSS-CRS's three-phase model (prepare, build-target, run) while preserving core directed fuzzing logic from existing components.

The recommended approach is to use AFL++ with allowlist-based selective instrumentation, driven by diff parsing and optional program slicing. OSS-CRS provides all orchestration through libCRS APIs and standard Docker patterns, eliminating the need for custom infrastructure. The critical path is: parse diff to extract modified functions, generate AFL allowlist, compile with selective instrumentation, and run AFL++ with proper CPU allocation and artifact submission.

The highest risk is silently falling back to empty allowlists when slicing fails, which negates the directed fuzzing benefit by instrumenting the entire codebase. This must be prevented through explicit validation and fail-fast error handling. Secondary risks include path mismatches between build and run phases, incorrect CPU allocation parsing, and missing required_inputs declarations that allow runs without diffs.

## Key Findings

### Recommended Stack

OSS-CRS integration requires adopting the framework's standard patterns rather than porting existing microservices. The stack centers on AFL++ for directed fuzzing, libCRS for all infrastructure communication, and OSS-Fuzz base images for build/run environments.

**Core technologies:**
- **OSS-CRS framework** (from ~/post/oss-crs-6): Three-phase orchestration model — required integration target
- **AFL++ 4.x** (from gcr.io/oss-fuzz-base): Directed fuzzer with allowlist support — AFL_LLVM_ALLOWLIST enables compile-time selective instrumentation
- **libCRS**: Container-infrastructure API — handles artifact transfer, service discovery, all I/O operations
- **Python 3.11+**: CRS runtime, diff parsing, slice integration — matches existing component stack
- **Docker Buildx with HCL**: Multi-stage image orchestration — OSS-CRS prepare phase standard
- **LLVM analyzer** (from components/slice): Program slicing for reachability analysis — generates function allowlists from diff targets

**Critical version requirements:**
- Python >= 3.10 (OSS-CRS requirement)
- LLVM 16+ (for AFL++ instrumentation compiler)
- Docker Buildx with HCL support

**What NOT to port:**
- RabbitMQ message queue (OSS-CRS handles orchestration)
- Redis and PostgreSQL (OSS-CRS manages state via filesystem)
- Kubernetes Helm charts (OSS-CRS abstracts deployment)
- Microservices scheduler (replaced by three-phase model)

### Expected Features

Directed fuzzing integration has two distinct feature sets: OSS-CRS compliance (table stakes) and directed fuzzing logic (differentiators).

**Must have (OSS-CRS compliance):**
- crs.yaml configuration file with supported_target and required_inputs declarations
- docker-bake.hcl for prepare phase image building
- Builder Dockerfile with libCRS integration and artifact submission
- Runner Dockerfile with libCRS integration and artifact download
- Build-target phase compiling targets with AFL++ instrumentation
- Run phase executing AFL++ with CPU allocation from OSS_CRS_CPUSET
- POV and seed submission via libCRS register-submit-dir

**Must have (directed fuzzing core):**
- Diff parsing to extract changed code locations from unified diff files
- Modified function detection mapping diff hunks to C/C++ function boundaries
- AFL allowlist generation producing AFL_LLVM_ALLOWLIST from analysis results
- Diff fetch via libCRS during build-target phase
- required_inputs: [diff] declaration for fail-fast validation

**Should have (differentiators):**
- Program slicing using LLVM static analysis for code path reachability
- Multi-harness support running directed fuzzing across multiple fuzz targets
- Crash location correlation reporting whether crashes are in targeted code regions

**Defer (v2+):**
- SARIF bug-candidate support as alternative targeting mechanism
- Beyond-allowlist fallback for cases where allowlist covers zero functions
- Multi-sanitizer support (start with ASan only)
- Crash reproduction validation

**Anti-features (explicitly avoid):**
- Microservices architecture with RabbitMQ/scheduler
- Database persistence layer
- Kubernetes deployment configurations
- Patch generation (bug-finding only)
- Custom seed sharing protocols (use OSS-CRS provided)

### Architecture Approach

OSS-CRS enforces a strict three-phase model with isolated containers and filesystem-based artifact transfer. All infrastructure communication happens through libCRS APIs - no direct inter-container communication or custom networking.

**Phase boundaries:**
- **Prepare phase:** Builds CRS Docker images via docker-bake.hcl
- **Build-target phase:** Compiles target with AFL++ instrumentation, fetches diff via libCRS, generates allowlist, submits artifacts
- **Run phase:** Downloads build artifacts, executes AFL++ with master/slave parallelism, streams POVs and seeds via background daemons

**Major components:**
1. **crs.yaml** — CRS configuration declaring phases, requirements, supported targets
2. **builder.Dockerfile** — Build-target container with diff parsing, allowlist generation, AFL++ compilation
3. **runner.Dockerfile** — Run container with AFL++ execution, CPU allocation parsing, artifact submission
4. **libCRS integration** — All artifact transfer (submit-build-output, download-build-output, register-submit-dir)
5. **DiffParser** — Extract modified functions from unified diff (port from components/directed)
6. **SlicerModule** — Optional LLVM-based static analysis for code path reachability

**Data flow:**
- Build phase: diff file → libCRS fetch → parse diff → generate allowlist → compile with AFL_LLVM_ALLOWLIST → submit build output
- Run phase: download build artifacts → parse OSS_CRS_CPUSET → register POV/seed dirs → run AFL++ master+slaves → background daemons submit artifacts

**Key architectural patterns:**
- Single build step with explicit outputs declaration in crs.yaml
- Background daemon pattern for continuous artifact submission
- CPU-aware AFL parallelism derived from OSS_CRS_CPUSET range parsing
- Fail-fast validation at each phase boundary

### Critical Pitfalls

1. **Silent slice failure creating empty allowlist** — When slicing fails (timeout, service unavailable), defensive coding creates empty allowlist instead of failing fast. AFL++ then instruments entire codebase, negating directed benefit. Prevention: retry with exponential backoff, distinguish "no relevant code" from "service failed", validate allowlist non-empty before compilation.

2. **Diff path not accessible in build container** — Build script attempts wrong path or volume mount misconfigured. Prevention: always use libCRS fetch diff at build start, validate file exists and non-empty, fail fast with clear error if missing.

3. **Incorrect CPU core allocation for AFL++ slaves** — OSS_CRS_CPUSET range format ("4-7" or "0,2,4-6") parsed incorrectly, causing under/over-utilization. Prevention: consistent parsing logic handling ranges, lists, and mixed formats; validate slave count matches cores; unit tests for edge cases.

4. **Build output path mismatch between phases** — Build submits to one path, run downloads from different path. Prevention: define paths as constants, validate crs.yaml outputs match actual submit calls, integration test full cycle.

5. **Missing required_inputs: [diff] declaration** — CRS runs without diff because validation not declared. Prevention: always declare required_inputs for directed fuzzers, add startup validation as defense-in-depth.

6. **Hardcoded engine type breaks AFL++ integration** — Existing code hardcodes FUZZING_ENGINE=libfuzzer in multiple places. Prevention: read from environment variable consistently, remove all hardcoded references, document in supported_target.fuzzing_engine.

7. **POV submission without register-submit-dir daemon** — Crashes written but never submitted because daemon not started. Prevention: explicit daemon startup with trailing &, healthcheck for daemon running, integration test verifying crash → POV flow.

## Implications for Roadmap

Based on research, the integration follows OSS-CRS's phase model strictly. The roadmap must proceed sequentially because each phase depends on the previous working correctly.

### Phase 1: OSS-CRS Configuration Foundation
**Rationale:** OSS-CRS cannot discover or run the CRS without valid configuration. This is the absolute prerequisite for all other work.
**Delivers:** Working crs.yaml and docker-bake.hcl allowing prepare phase to succeed
**Addresses:** Table stakes features (crs.yaml, docker-bake.hcl, supported_target declarations, required_inputs)
**Avoids:** Pitfall #5 (missing required_inputs), Pitfall #8 (image tag mismatch)
**Research flag:** Standard pattern, reference implementations available (crs-libfuzzer, buttercup)

### Phase 2: Build-Target Integration
**Rationale:** Must produce instrumented binaries before run phase can execute. This is where directed fuzzing logic lives.
**Delivers:** Builder Dockerfile that compiles targets with AFL++ allowlist-based instrumentation
**Addresses:** Diff parsing, modified function detection, AFL allowlist generation, build artifact submission
**Uses:** AFL++ (from OSS-Fuzz base), Python diff parser (port from components/directed), libCRS submit-build-output
**Avoids:** Pitfall #1 (empty allowlist fallback), Pitfall #2 (diff path access), Pitfall #4 (output path mismatch), Pitfall #6 (hardcoded engine)
**Research flag:** Some custom logic needed for diff parsing and allowlist format, but AFL++ allowlist pattern is documented

### Phase 3: Run Phase Integration
**Rationale:** Executes the fuzzer against instrumented targets. Depends on build artifacts from Phase 2.
**Delivers:** Runner Dockerfile executing AFL++ with proper CPU allocation and artifact streaming
**Addresses:** Build artifact retrieval, CPU allocation parsing, AFL++ master/slave execution, POV/seed submission
**Uses:** AFL++ parallel mode, libCRS download-build-output and register-submit-dir, OSS_CRS_CPUSET parsing
**Implements:** Fuzzer execution component with background submission daemons
**Avoids:** Pitfall #3 (CPU allocation), Pitfall #7 (POV daemon), Pitfall #9 (workspace isolation)
**Research flag:** Standard fuzzer execution pattern, CPU parsing logic available from reference implementations

### Phase 4: Program Slicing Integration (Optional Enhancement)
**Rationale:** Enhances directed fuzzing precision beyond function-level allowlists. Optional because basic directed fuzzing works without it.
**Delivers:** LLVM-based static analysis producing code path reachability results
**Addresses:** Advanced directed features (program slicing, beyond-allowlist fallback)
**Uses:** LLVM analyzer from components/slice, bitcode compilation
**Avoids:** Pitfall #10 (slice timeout), Pitfall #1 (slice failure handling)
**Research flag:** NEEDS RESEARCH - complex LLVM integration, timeout configuration, result validation

### Phase 5: Validation and Benchmarking
**Rationale:** Verify integration works end-to-end with real benchmark (afc-freerdp-delta-01).
**Delivers:** Validated CRS running against CRSBench benchmark, metrics collection
**Addresses:** Integration testing, performance validation, crash location correlation
**Research flag:** Benchmark-specific validation, may need debugging of integration issues

### Phase Ordering Rationale

- **Configuration first:** Cannot test anything without valid crs.yaml that OSS-CRS accepts
- **Build before run:** Run phase requires build artifacts, cannot proceed without working builder
- **Slicing optional:** Directed fuzzing works at function-level without full program slicing, deferring reduces critical path
- **Validation last:** Requires working build and run phases to test end-to-end

**Dependency chain:**
```
Phase 1 (config) → Phase 2 (build) → Phase 3 (run) → Phase 5 (validation)
                                   ↘ Phase 4 (slicing, optional) ↗
```

**Risk mitigation:**
- Phase 1 uses reference implementations (low risk, no custom logic)
- Phase 2 has highest pitfall concentration (allowlist generation, diff parsing) - needs careful validation
- Phase 3 is standard fuzzer execution (medium risk, CPU parsing complexity)
- Phase 4 deferred to reduce critical path risk

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 4 (Program Slicing):** Complex LLVM integration, timeout configuration, result format validation, failure recovery strategy
- **Phase 5 (Validation):** Benchmark-specific configuration, performance baselines, debugging workflow

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Configuration):** Reference implementations available (crs-libfuzzer, buttercup-bugfind)
- **Phase 2 (Build):** AFL allowlist pattern documented, diff parsing logic exists in components/directed
- **Phase 3 (Run):** AFL++ execution patterns well-established, libCRS patterns documented

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Direct analysis of OSS-CRS source code, official documentation, and reference implementations |
| Features | HIGH | OSS-CRS requirements clearly documented, existing directed fuzzer components provide feature baseline |
| Architecture | HIGH | Three-phase model enforced by framework, reference CRS implementations demonstrate patterns |
| Pitfalls | HIGH | Based on existing codebase analysis revealing actual failure modes and defensive patterns |

**Overall confidence:** HIGH

Research is based on:
- Direct source code analysis of OSS-CRS framework (~/post/oss-crs-6)
- Official OSS-CRS documentation (crs-development-guide.md, libCRS.md, config schemas)
- Reference CRS implementations (crs-libfuzzer, buttercup-bugfind, atlantis-multilang-wo-concolic)
- Existing directed fuzzer codebase analysis (components/directed, components/slice)
- CRSBench benchmark structure analysis (afc-freerdp-delta-01)

### Gaps to Address

**Slicing integration details:** Existing components/slice uses LLVM analyzer, but integration into OSS-CRS build phase needs design decisions around:
- Timeout configuration and retry strategy
- Failure mode handling (when to fallback vs. fail-fast)
- Result format compatibility with AFL allowlist expectations
- Performance characteristics with large codebases

**Handling during planning:** Phase 4 should trigger `/gsd:research-phase` to investigate LLVM slicing patterns, timeout strategies, and failure recovery. Initial implementation can skip slicing and use function-level allowlists only.

**Multi-harness execution:** AFL++ supports multiple harnesses, but OSS-CRS's OSS_CRS_TARGET_HARNESS is singular. Need to determine:
- Whether to run multiple CRS instances (one per harness)
- Whether to extend runner script to iterate harnesses
- How to aggregate results across harnesses

**Handling during planning:** Phase 3 planning should include harness enumeration strategy. Initial implementation can target single harness specified by OSS_CRS_TARGET_HARNESS.

**Crash location correlation:** Existing codebase has crash analysis components, but unclear how to report correlation metrics through OSS-CRS artifact system.

**Handling during planning:** Defer to post-MVP enhancement. Initial implementation submits POVs without correlation metadata.

## Sources

### Primary (HIGH confidence)
- `/home/andrew/post/oss-crs-6/docs/crs-development-guide.md` — OSS-CRS development patterns and integration requirements
- `/home/andrew/post/oss-crs-6/docs/design/libCRS.md` — libCRS API reference for artifact transfer
- `/home/andrew/post/oss-crs-6/docs/design/architecture.md` — OSS-CRS three-phase architecture
- `/home/andrew/post/oss-crs-6/docs/config/crs.md` — crs.yaml schema and validation rules
- `/home/andrew/post/oss-crs-6/oss_crs/src/crs.py` — Orchestrator implementation details
- `/home/andrew/post/crs-libfuzzer/oss-crs/crs.yaml` — Minimal CRS reference implementation
- `/home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml` — Multi-module CRS reference
- `/home/andrew/post/42-directed/components/directed/src/daemon/modules/diff_parser.py` — Existing diff parsing logic
- `/home/andrew/post/42-directed/components/directed/src/daemon/modules/fuzzer_runner.py` — Existing AFL++ integration with allowlist
- `/home/andrew/post/42-directed/components/slice/slice.py` — Existing LLVM-based slicing component

### Secondary (MEDIUM confidence)
- AFL++ documentation (gcr.io/oss-fuzz-base/base-builder) — Allowlist format and compilation flags
- OSS-Fuzz base image patterns — Standard compile script and environment variables
- CRSBench benchmark structure — Expected diff format and project layout

### Tertiary (LOW confidence, needs validation)
- Beyond-allowlist fallback patterns — Existing code shows aixcc_beyond_allowlist.txt pattern but needs validation
- SARIF integration — Mentioned as alternative targeting but not implemented in existing code

---
*Research completed: 2026-03-11*
*Ready for roadmap: yes*
