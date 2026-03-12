# Feature Landscape

**Domain:** Directed Fuzzer OSS-CRS Integration
**Researched:** 2026-03-11

## Table Stakes

Features required for OSS-CRS compliance. Missing = CRS will not function in the framework.

### OSS-CRS Framework Compliance

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `crs.yaml` configuration file | OSS-CRS requires this for CRS discovery and configuration | Low | Must be at `oss-crs/crs.yaml` in repo root |
| `docker-bake.hcl` for prepare phase | Framework uses `docker buildx bake` to build CRS images | Low | Referenced via `prepare_phase.hcl` |
| Builder Dockerfile with libCRS | Build phase requires libCRS for artifact submission | Low | Pattern: `COPY --from=libcrs . /opt/libCRS && RUN /opt/libCRS/install.sh` |
| Runner Dockerfile with libCRS | Run phase requires libCRS for artifact download and submission | Low | Same pattern as builder |
| `libCRS submit-build-output` usage | Framework expects build artifacts to be submitted via libCRS | Low | Maps to `outputs` in crs.yaml build step |
| `libCRS download-build-output` usage | Run containers must download build artifacts | Low | Retrieves what builder submitted |
| `supported_target` declaration | Framework validates CRS compatibility with target | Low | mode, language, sanitizer, architecture |

### Build-Target Phase (OSS-CRS Mandatory)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Target compilation with instrumentation | OSS-CRS expects CRS to compile target with its instrumentation | Medium | AFL++ with allowlist for directed fuzzing |
| Artifact submission via libCRS | Framework relies on libCRS for build output transfer | Low | `libCRS submit-build-output $OUT build` |
| Support for `target_base_image` ARG | Framework injects base image at build time | Low | Must use `ARG target_base_image; FROM $target_base_image` |

### Run Phase (OSS-CRS Mandatory)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Build artifact retrieval | Run containers must download compiled binaries | Low | `libCRS download-build-output build /out` |
| POV submission via `register-submit-dir` | Framework expects crash inputs in standard location | Low | `libCRS register-submit-dir pov $POV_DIR` |
| Seed submission via `register-submit-dir` | Framework expects corpus in standard location | Low | `libCRS register-submit-dir seed $CORPUS_DIR` |
| Respect `OSS_CRS_CPUSET` | Framework allocates CPU cores via this env var | Low | Parse range string for AFL++ slave count |
| Respect `OSS_CRS_TARGET_HARNESS` | Framework specifies which harness to run | Low | Use as fuzzer target binary name |

## Differentiators

Features specific to directed fuzzing that set this CRS apart from generic fuzzers.

### Directed Fuzzing Core (Required for Value Proposition)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Diff parsing | Parse unified diff to identify changed code locations | Medium | Extract file paths and line ranges from `.diff` files |
| Modified function detection | Map diff hunks to affected C/C++ functions | High | Requires AST parsing (tree-sitter) to find function boundaries |
| AFL++ allowlist generation | Generate `AFL_LLVM_ALLOWLIST` from slice results | Medium | Functions in slice -> allowlist file |
| Program slicing (optional) | Static analysis to find code paths leading to changed functions | High | Existing `components/slice/` uses LLVM-based analyzer |
| Delta mode support | Handle targets with `mode: delta` in project.yaml | Medium | Different from `mode: full` |

### Directed Fuzzing Input Handling (Required for OSS-CRS Integration)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Diff fetch via libCRS | Consume diff from `OSS_CRS_FETCH_DIR/diffs/` | Low | `libCRS fetch diff /work/diffs` or `register-fetch-dir` |
| `required_inputs: [diff]` declaration | Fail fast if diff not provided | Low | In crs.yaml, framework validates before run |
| Build-phase diff consumption | Use diff during build to generate allowlist | Medium | `--diff` flag to `oss-crs build-target` stages into FETCH_DIR |

### Advanced Directed Features (Differentiating)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| SARIF bug-candidate support | Accept SARIF reports pointing to specific locations | Medium | Alternative to diff for targeting specific code |
| Beyond-allowlist fallback | Continue fuzzing if allowlist covers zero functions | Medium | `aixcc_beyond_allowlist.txt` pattern in existing code |
| Multi-harness support | Run directed fuzzing across multiple fuzz targets | Medium | Each harness gets its own AFL++ instance |
| Crash location correlation | Report whether crash is in targeted code region | Medium | Valuable for directed fuzzing metrics |

## Anti-Features

Features to explicitly NOT build. These would add complexity without value or conflict with OSS-CRS patterns.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Microservices architecture (RabbitMQ, scheduler) | OSS-CRS handles orchestration; adds complexity | Use OSS-CRS three-phase model directly |
| Database persistence (PostgreSQL) | OSS-CRS manages state via filesystem and Redis patterns | Use libCRS artifact submission |
| Kubernetes deployment | OSS-CRS abstracts deployment; CRS should be deployment-agnostic | Write standard Dockerfiles; let OSS-CRS handle infra |
| Patch generation | Bug-finding CRS, not bug-fixing | Declare `type: [bug-finding]` only |
| Custom seed sharing protocol | OSS-CRS provides `register-shared-dir` and exchange sidecar | Use `libCRS register-shared-dir` |
| Web API gateway | No need for external API in OSS-CRS model | Use container entrypoint scripts |
| Custom corpus management | OSS-CRS provides seed submission and fetching | Use `libCRS register-submit-dir seed` |

## Feature Dependencies

```
Diff Parsing --> Modified Function Detection --> AFL Allowlist Generation
                                                         |
                                                         v
                                              Build with Instrumentation
                                                         |
                                                         v
                                                 Run Directed Fuzzer
                                                         |
                                                         v
                                                 POV/Seed Submission
```

```
OSS-CRS Build-Target Phase:
  libCRS fetch diff --> Diff Parser --> Allowlist Generation --> compile with AFL_LLVM_ALLOWLIST

OSS-CRS Run Phase:
  libCRS download-build-output --> Run AFL++ --> libCRS register-submit-dir (pov, seed)
```

## MVP Recommendation

### Phase 1: Core OSS-CRS Compliance (Table Stakes)

Prioritize:
1. **crs.yaml configuration** - Required for OSS-CRS to recognize CRS
2. **Builder Dockerfile** - Compiles target with AFL++ instrumentation
3. **Runner Dockerfile** - Executes AFL++ fuzzer
4. **libCRS integration** - artifact submission/retrieval
5. **Basic entrypoint scripts** - build.sh, run.sh

### Phase 2: Directed Fuzzing MVP (Core Differentiator)

Prioritize:
1. **Diff parsing** - Extract changed locations from ref.diff
2. **Modified function detection** - Map diff to function names
3. **AFL allowlist generation** - Generate AFL_LLVM_ALLOWLIST file
4. **`required_inputs: [diff]`** - Fail fast without diff

### Phase 3: Enhanced Directed Features

Defer:
- **Program slicing**: Complex LLVM analysis; MVP can work with function-level allowlist without slice
- **SARIF bug-candidate support**: Alternative targeting mechanism; diff is primary
- **Crash location correlation**: Nice-to-have metrics
- **Multi-sanitizer support**: Start with ASan only

## libCRS API Usage Patterns

### Build Phase Pattern

```bash
#!/bin/bash
# bin/compile_target - invoked during build-target phase

# 1. Fetch diff for directed fuzzing
libCRS fetch diff /work/diffs
DIFF_FILE=$(find /work/diffs -name "*.diff" | head -1)

# 2. Parse diff and generate allowlist
python3 /crs/parse_diff.py "$DIFF_FILE" > /tmp/allowlist.txt

# 3. Compile with AFL++ instrumentation
export AFL_LLVM_ALLOWLIST=/tmp/allowlist.txt
compile  # OSS-Fuzz helper

# 4. Submit build output
libCRS submit-build-output $OUT build
```

### Run Phase Pattern

```bash
#!/bin/bash
# bin/run_fuzzer - invoked during run phase

# 1. Download build artifacts
libCRS download-build-output build /out

# 2. Set up submission directories
CORPUS_DIR="/artifacts/corpus"
POV_DIR="/artifacts/povs"
mkdir -p "$CORPUS_DIR" "$POV_DIR"

libCRS register-submit-dir pov "$POV_DIR"
libCRS register-submit-dir seed "$CORPUS_DIR"

# 3. Parse CPU allocation
CPUSET="${OSS_CRS_CPUSET:-0}"
JOBS=$(echo "$CPUSET" | tr ',' '\n' | wc -l)

# 4. Run AFL++
HARNESS="${OSS_CRS_TARGET_HARNESS}"
"/out/$HARNESS" \
    "$CORPUS_DIR" \
    -artifact_prefix="${POV_DIR}/" \
    -fork="$JOBS" \
    -max_total_time="${FUZZ_TIME:-3600}"
```

## crs.yaml Template for Directed Fuzzer

```yaml
name: directed-fuzzer
type:
  - bug-finding
version: "1.0.0"
docker_registry: ghcr.io/your-org/directed-fuzzer

prepare_phase:
  hcl: oss-crs/docker-bake.hcl

target_build_phase:
  - name: build
    dockerfile: oss-crs/dockerfiles/builder.Dockerfile
    outputs:
      - build

crs_run_phase:
  fuzzer:
    dockerfile: oss-crs/dockerfiles/runner.Dockerfile

supported_target:
  mode:
    - delta           # Directed fuzzing targets delta mode
    - full            # Optional: also support full mode
  language:
    - c
    - c++             # If C++ supported
  sanitizer:
    - address
  architecture:
    - x86_64
  fuzzing_engine:
    - afl             # AFL++ based

required_inputs:
  - diff              # Fail fast if diff not provided
```

## Validation Checkpoints

| Checkpoint | Validation Command | Expected Result |
|------------|-------------------|-----------------|
| crs.yaml valid | `oss-crs prepare --compose-file ...` completes | Images built successfully |
| Builder works | `oss-crs build-target --diff ref.diff ...` completes | Artifacts submitted |
| Runner works | `oss-crs run --diff ref.diff ...` starts | AFL++ running |
| POVs submitted | Check `$HOST_ARTIFACT_DIR/povs/` | Crash files appear |
| Seeds submitted | Check `$HOST_ARTIFACT_DIR/seeds/` | Corpus files appear |

## Sources

- OSS-CRS CRS Development Guide: `/home/andrew/post/oss-crs-6/docs/crs-development-guide.md`
- OSS-CRS libCRS Reference: `/home/andrew/post/oss-crs-6/docs/design/libCRS.md`
- OSS-CRS crs.yaml Schema: `/home/andrew/post/oss-crs-6/docs/config/crs.md`
- Reference implementation (crs-libfuzzer): `/home/andrew/post/crs-libfuzzer/`
- Reference implementation (buttercup): `/home/andrew/post/buttercup-bugfind/`
- Existing directed fuzzer components: `/home/andrew/post/42-directed/components/directed/`
- Existing diff parser: `/home/andrew/post/42-directed/components/directed/src/daemon/modules/diff_parser.py`
- Benchmark structure: `/home/andrew/post/CRSBench/benchmarks/afc-freerdp-delta-01/`
