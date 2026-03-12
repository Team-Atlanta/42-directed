# Requirements: Bug-finding Directed OSS-CRS

**Defined:** 2026-03-11
**Core Value:** Parse diff, generate AFL allowlist from sliced code paths, and fuzz until we find bugs at changed locations.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Configuration

- [x] **CFG-01**: crs.yaml exists at oss-crs/crs.yaml with `type: [bug-finding]`
- [x] **CFG-02**: crs.yaml declares `required_inputs: [diff]` for fail-fast validation
- [x] **CFG-03**: crs.yaml declares `supported_target` with mode: delta, language: c/c++, sanitizer: address
- [x] **CFG-04**: docker-bake.hcl exists for prepare phase dependencies

### Build-Target Phase 1: Slice

- [x] **SLC-01**: slicer.Dockerfile uses `ARG target_base_image` and `FROM $target_base_image`
- [x] **SLC-02**: Slicer installs libCRS via standard COPY pattern
- [x] **SLC-03**: Slicer fetches diff via `libCRS fetch diff`
- [x] **SLC-04**: Slicer parses diff to extract changed file paths and line ranges
- [x] **SLC-05**: Slicer detects affected functions from diff using tree-sitter AST parsing
- [ ] **SLC-06**: Slicer compiles target to LLVM bitcode for static analysis
- [ ] **SLC-07**: Slicer runs LLVM analyzer to find code paths to changed functions
- [ ] **SLC-08**: Slicer generates AFL_LLVM_ALLOWLIST from slice results
- [ ] **SLC-09**: Slicer handles timeout/failure gracefully (fallback to function-level allowlist)
- [x] **SLC-10**: Slicer submits allowlist via `libCRS submit-build-output $OUT slice`

### Build-Target Phase 2: Build

- [x] **BLD-01**: builder.Dockerfile uses `ARG target_base_image` and `FROM $target_base_image`
- [x] **BLD-02**: Builder installs libCRS via standard COPY pattern
- [x] **BLD-03**: Builder downloads slice output via `libCRS download-build-output slice`
- [x] **BLD-04**: Builder compiles target with AFL++ using downloaded allowlist
- [x] **BLD-05**: Builder submits instrumented harnesses via `libCRS submit-build-output $OUT build`

### Run Phase

- [ ] **RUN-01**: runner.Dockerfile uses libCRS for artifact retrieval
- [ ] **RUN-02**: Runner downloads build artifacts via `libCRS download-build-output build /out`
- [ ] **RUN-03**: Runner registers PoV output directory via `libCRS register-submit-dir pov`
- [ ] **RUN-04**: Runner registers seed corpus directory via `libCRS register-submit-dir seed`
- [ ] **RUN-05**: Runner parses OSS_CRS_CPUSET to determine AFL++ parallel instance count
- [ ] **RUN-06**: Runner uses OSS_CRS_TARGET_HARNESS for fuzzer target binary
- [ ] **RUN-07**: Runner executes AFL++ with appropriate master/slave configuration

### Validation

- [ ] **VAL-01**: oss-crs prepare completes successfully with compose.yaml
- [ ] **VAL-02**: oss-crs build-target completes with afc-freerdp-delta-01 benchmark
- [ ] **VAL-03**: oss-crs run starts AFL++ fuzzer targeting instrumented harness

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Directed Features

- **ADV-01**: Multi-harness support — run directed fuzzing across multiple fuzz targets
- **ADV-02**: SARIF bug-candidate support — accept SARIF reports as alternative to diff
- **ADV-03**: Beyond-allowlist fallback — continue fuzzing if allowlist covers zero functions
- **ADV-04**: Crash location correlation — report whether crash is in targeted code region

### Multi-Sanitizer

- **SAN-01**: Support building with multiple sanitizers (UBSan, MSan) beyond ASan

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Microservices architecture (RabbitMQ, scheduler) | OSS-CRS handles orchestration; not needed |
| Database persistence (PostgreSQL) | OSS-CRS manages state via filesystem/libCRS |
| Kubernetes deployment | OSS-CRS abstracts deployment; CRS should be deployment-agnostic |
| Patch generation | Bug-finding only; use separate patch CRS |
| Custom seed sharing protocol | Use `libCRS register-shared-dir` instead |
| Web API gateway | Not needed in OSS-CRS model |
| LibFuzzer support | AFL++ only for v1 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CFG-01 | Phase 1 | Complete |
| CFG-02 | Phase 1 | Complete |
| CFG-03 | Phase 1 | Complete |
| CFG-04 | Phase 1 | Complete |
| SLC-01 | Phase 2 | Complete |
| SLC-02 | Phase 2 | Complete |
| SLC-03 | Phase 2 | Complete |
| SLC-04 | Phase 2 | Complete |
| SLC-05 | Phase 2 | Complete |
| SLC-06 | Phase 2 | Pending |
| SLC-07 | Phase 2 | Pending |
| SLC-08 | Phase 2 | Pending |
| SLC-09 | Phase 2 | Pending |
| SLC-10 | Phase 2 | Complete |
| BLD-01 | Phase 2 | Complete |
| BLD-02 | Phase 2 | Complete |
| BLD-03 | Phase 2 | Complete |
| BLD-04 | Phase 2 | Complete |
| BLD-05 | Phase 2 | Complete |
| RUN-01 | Phase 3 | Pending |
| RUN-02 | Phase 3 | Pending |
| RUN-03 | Phase 3 | Pending |
| RUN-04 | Phase 3 | Pending |
| RUN-05 | Phase 3 | Pending |
| RUN-06 | Phase 3 | Pending |
| RUN-07 | Phase 3 | Pending |
| VAL-01 | Phase 4 | Pending |
| VAL-02 | Phase 4 | Pending |
| VAL-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after roadmap creation*
