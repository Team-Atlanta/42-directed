# Roadmap: Bug-finding Directed OSS-CRS

## Overview

This roadmap delivers a standalone directed fuzzer for OSS-CRS that parses diff files, generates AFL++ allowlists from sliced code paths, and fuzzes until bugs are found at changed locations. The work proceeds through OSS-CRS's three-phase architecture: configuration and prepare, build-target (combining slicing and compilation), run-phase execution, and validation against the afc-freerdp-delta-01 benchmark.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Configuration** - OSS-CRS discovery files: crs.yaml and docker-bake.hcl (completed 2026-03-12)
- [ ] **Phase 2: Build-Target** - Diff parsing, slicing, AFL++ allowlist generation, instrumented compilation
- [ ] **Phase 3: Run** - AFL++ execution with CPU allocation, POV/seed submission
- [ ] **Phase 4: Validation** - End-to-end verification with afc-freerdp-delta-01 benchmark

## Phase Details

### Phase 1: Configuration
**Goal**: OSS-CRS can discover and validate the CRS, enabling prepare phase completion
**Depends on**: Nothing (first phase)
**Requirements**: CFG-01, CFG-02, CFG-03, CFG-04
**Success Criteria** (what must be TRUE):
  1. `oss-crs prepare` completes without errors against the CRS directory
  2. crs.yaml declares diff as required input, preventing runs without diff metadata
  3. CRS is recognized as bug-finding type with delta mode and c/c++ language support
**Plans**: 1 plan

Plans:
- [x] 01-01-PLAN.md — Create CRS configuration files (crs.yaml, docker-bake.hcl, stub Dockerfiles)

### Phase 2: Build-Target
**Goal**: Build-target phase produces instrumented AFL++ harnesses targeting diff-identified code paths
**Depends on**: Phase 1
**Requirements**: SLC-01, SLC-02, SLC-03, SLC-04, SLC-05, SLC-06, SLC-07, SLC-08, SLC-09, SLC-10, BLD-01, BLD-02, BLD-03, BLD-04, BLD-05
**Success Criteria** (what must be TRUE):
  1. Slicer container fetches diff via libCRS and parses changed file paths and line ranges
  2. Slicer generates AFL_LLVM_ALLOWLIST containing functions reachable from diff targets
  3. Builder compiles target with AFL++ using the generated allowlist
  4. Build artifacts (instrumented harnesses) are submitted via libCRS for run phase retrieval
  5. Slice failure aborts build-target (no fallback per user decision)
**Plans**: 4 plans

Plans:
- [ ] 02-01-PLAN.md — Slicer container foundation (Dockerfile, libCRS, diff parsing)
- [ ] 02-02-PLAN.md — Slicing pipeline (bitcode compilation, LLVM analyzer, allowlist generation)
- [ ] 02-03-PLAN.md — Builder container (AFL++ compilation with allowlist)
- [ ] 02-04-PLAN.md — Integration (crs.yaml update, verification checkpoint)

### Phase 3: Run
**Goal**: Run phase executes AFL++ against instrumented targets and streams POVs/seeds to OSS-CRS
**Depends on**: Phase 2
**Requirements**: RUN-01, RUN-02, RUN-03, RUN-04, RUN-05, RUN-06, RUN-07
**Success Criteria** (what must be TRUE):
  1. Runner downloads build artifacts via libCRS and locates target harness
  2. Runner parses OSS_CRS_CPUSET to launch correct number of AFL++ master/slave instances
  3. POV output directory is registered and crashes are continuously submitted
  4. Seed corpus directory is registered for seed sharing
**Plans**: 2 plans

Plans:
- [ ] 03-01-PLAN.md — Runner container foundation (Dockerfile, libCRS, artifact download, harness validation)
- [ ] 03-02-PLAN.md — AFL++ execution (cpuset parsing, master/secondary instances, POV/seed submission)

### Phase 4: Validation
**Goal**: End-to-end verification that the CRS works with a real benchmark
**Depends on**: Phase 3
**Requirements**: VAL-01, VAL-02, VAL-03
**Success Criteria** (what must be TRUE):
  1. afc-freerdp-delta-01 benchmark passes prepare phase with CRS compose.yaml
  2. afc-freerdp-delta-01 benchmark passes build-target phase producing instrumented harness
  3. afc-freerdp-delta-01 benchmark passes run phase with AFL++ executing and finding instrumented paths
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Configuration | 1/1 | Complete   | 2026-03-12 |
| 2. Build-Target | 2/4 | In Progress|  |
| 3. Run | 1/2 | In Progress|  |
| 4. Validation | 0/1 | Not started | - |
