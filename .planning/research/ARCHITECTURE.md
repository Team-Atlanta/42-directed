# Architecture Patterns: OSS-CRS Directed Fuzzer Integration

**Domain:** Directed Fuzzing for OSS-CRS
**Researched:** 2026-03-11
**Confidence:** HIGH (based on direct analysis of OSS-CRS source code and reference implementations)

## Recommended Architecture

### OSS-CRS Three-Phase Model

OSS-CRS orchestrates CRS execution through three distinct phases with well-defined boundaries:

```
                        Orchestrator (crs-compose.yaml)
                                    |
         +-------------+------------+------------+
         |             |                         |
         v             v                         v
    +----------+  +-------------+          +----------+
    | PREPARE  |  | BUILD-TARGET|          |   RUN    |
    | Phase    |->|   Phase     |--------->|  Phase   |
    +----------+  +-------------+          +----------+
         |             |                         |
    Build CRS     Compile target           Launch CRS
    Docker        with CRS                 containers
    images        instrumentation          against target
```

### Phase Boundaries

| Phase | Input | Output | Docker Context |
|-------|-------|--------|----------------|
| **Prepare** | CRS source repo, `docker-bake.hcl` | CRS Docker images (base, builder, runner) | Host buildx |
| **Build-Target** | Target base image, diff file (optional), CRS images | Build artifacts in `BUILD_OUT_DIR`, snapshot images (optional) | Per-build container |
| **Run** | Build artifacts, harness name, diff/pov/seed files | PoVs, seeds, bug-candidates, patches in `SUBMIT_DIR` | Multi-container network |

### Component Architecture for Directed Fuzzer

```
+---------------------------------------------------------------------------+
|                          OSS-CRS Infrastructure                            |
|                                                                            |
|  +-----------------+    +------------------+    +----------------------+   |
|  | LiteLLM Proxy   |    | Exchange Sidecar |    | Storage (volumes)    |   |
|  | (LLM budget)    |    | (artifact sync)  |    |  - BUILD_OUT_DIR     |   |
|  +-----------------+    +------------------+    |  - SUBMIT_DIR        |   |
|                                                 |  - FETCH_DIR         |   |
|                                                 |  - SHARED_DIR        |   |
+---------------------------------------------------------------------------+
                              |
          +-------------------+-------------------+
          |                                       |
+---------+---------+                   +---------+---------+
|  Directed Fuzzer  |                   |  Other CRS        |
|  (Isolated)       |                   |  (Isolated)       |
|                   |                   |                   |
|  +-------------+  |                   |  +-------------+  |
|  | fuzzer      |  |                   |  | module-1    |  |
|  | (AFL++)     |  |                   |  +-------------+  |
|  +-------------+  |                   |  +-------------+  |
|  +-------------+  |                   |  | module-2    |  |
|  | slicer      |  |   Private Net     |  +-------------+  |
|  | (optional)  |  |                   |                   |
|  +-------------+  |                   |  Private Net      |
|                   |                   |                   |
+---------+---------+                   +-------------------+
          |
          | libCRS
          |
     (submit-build-output, register-submit-dir, fetch, etc.)
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| **crs.yaml** | CRS configuration: phases, modules, requirements | OSS-CRS orchestrator reads at startup |
| **builder.Dockerfile** | Target compilation with AFL++ instrumentation and allowlist | Receives `target_base_image`, libCRS context |
| **runner.Dockerfile** | Fuzzer execution container with harness binaries | Reads BUILD_OUT_DIR, writes SUBMIT_DIR |
| **libCRS** | Infrastructure API (artifact transfer, service discovery) | All CRS containers use for I/O |
| **DiffParser** | Extract modified functions from unified diff | Used by builder to generate AFL allowlist |
| **SlicerModule** | Static analysis to find code paths to modified functions | Optional: outputs function allowlist |

## Data Flow

### Build-Target Phase Data Flow

```
                                BUILD-TARGET PHASE
+-----------------------------------------------------------------------+
|                                                                       |
|  Input:                                                               |
|    - target_base_image (OSS-Fuzz base with source)                    |
|    - diff file (via --diff flag, staged to FETCH_DIR)                 |
|                                                                       |
|  +------------------+                                                 |
|  | Builder Container|                                                 |
|  |                  |                                                 |
|  |  1. libCRS fetch diff /work/diff                                   |
|  |  2. Parse diff -> modified functions                               |
|  |  3. Generate AFL allowlist from functions                          |
|  |  4. Compile with AFL_LLVM_ALLOWLIST=allowlist.txt                  |
|  |  5. libCRS submit-build-output $OUT build                          |
|  |                                                                    |
|  +------------------+                                                 |
|          |                                                            |
|          v                                                            |
|  BUILD_OUT_DIR/                                                       |
|    build/                                                             |
|      fuzz_harness_1                                                   |
|      fuzz_harness_2                                                   |
|      allowlist.txt (optional, for debugging)                          |
|                                                                       |
+-----------------------------------------------------------------------+
```

### Run Phase Data Flow

```
                                  RUN PHASE
+-----------------------------------------------------------------------+
|                                                                       |
|  Input:                                                               |
|    - BUILD_OUT_DIR/build/* (instrumented harnesses)                   |
|    - FETCH_DIR/diffs/ref.diff (diff file if provided)                 |
|    - FETCH_DIR/seeds/* (initial seeds if provided)                    |
|                                                                       |
|  +------------------+                                                 |
|  | Fuzzer Container |                                                 |
|  |                  |                                                 |
|  |  1. libCRS download-build-output build /out                        |
|  |  2. libCRS fetch seed /corpus (if seeds available)                 |
|  |  3. libCRS register-submit-dir pov /povs &                         |
|  |  4. libCRS register-submit-dir seed /corpus &                      |
|  |  5. Parse OSS_CRS_CPUSET for AFL slave count                       |
|  |  6. afl-fuzz -i /corpus -o /output -M main /out/$HARNESS           |
|  |  7. (background) Monitor crashes -> copy to /povs                  |
|  |                                                                    |
|  +------------------+                                                 |
|          |                                                            |
|          v                                                            |
|  SUBMIT_DIR/                                                          |
|    povs/                                                              |
|      <md5hash>.crash                                                  |
|    seeds/                                                             |
|      <md5hash>.seed                                                   |
|                                                                       |
+-----------------------------------------------------------------------+
```

### Artifact Transfer Mechanism

OSS-CRS uses libCRS for all artifact transfer. The mechanism is filesystem-based with background daemon polling:

| Direction | Command | Mechanism |
|-----------|---------|-----------|
| Build -> Run | `submit-build-output` / `download-build-output` | rsync to BUILD_OUT_DIR volume |
| CRS -> Infra | `register-submit-dir` / `submit` | Watchdog daemon copies to SUBMIT_DIR; exchange sidecar distributes |
| Infra -> CRS | `register-fetch-dir` / `fetch` | Poll FETCH_DIR for new files; InfraClient handles dedup |
| Inter-container | `register-shared-dir` | Symlink to SHARED_DIR volume |

**Key implementation details:**
- `register-submit-dir` forks a daemon that watches the directory with `watchdog`, deduplicates by MD5 hash, and batches submissions
- `fetch` returns list of newly downloaded files; idempotent for incremental polling
- All files are hash-named for natural deduplication across CRSs

## Patterns to Follow

### Pattern 1: Minimal CRS Configuration

**What:** Single build step, single run module, explicit outputs
**When:** Bug-finding CRS without LLM requirements
**Example:**

```yaml
# oss-crs/crs.yaml
name: directed-fuzzer
type:
  - bug-finding
version: "1.0.0"
docker_registry: ghcr.io/team-atlantis/directed-fuzzer

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
    - delta
  language:
    - c
    - c++
  sanitizer:
    - address
  architecture:
    - x86_64

required_inputs:
  - diff
```

### Pattern 2: Diff-Aware Build Instrumentation

**What:** Use `--diff` flag to pass diff file to build phase for AFL allowlist generation
**When:** Directed fuzzing that targets specific code changes
**Example:**

```bash
# bin/compile_target (build phase entrypoint)
#!/bin/bash
set -e

# 1. Fetch diff from FETCH_DIR (staged by oss-crs build-target --diff)
if [ -d "$OSS_CRS_FETCH_DIR/diffs" ]; then
    DIFF_FILE=$(find "$OSS_CRS_FETCH_DIR/diffs" -name "*.diff" | head -1)
    if [ -n "$DIFF_FILE" ]; then
        # 2. Parse diff to extract modified functions
        python3 /opt/directed/parse_diff.py "$DIFF_FILE" "$SRC" > /tmp/functions.txt

        # 3. Generate AFL allowlist from functions
        python3 /opt/directed/gen_allowlist.py /tmp/functions.txt > "$SRC/allowlist.txt"
        export AFL_LLVM_ALLOWLIST="$SRC/allowlist.txt"
    fi
fi

# 4. Compile with instrumentation
compile

# 5. Submit outputs
libCRS submit-build-output "$OUT" build
```

### Pattern 3: CPU-Aware AFL Parallelism

**What:** Parse `OSS_CRS_CPUSET` to determine AFL slave count
**When:** Running AFL++ with multiple parallel instances
**Example:**

```bash
# Parse CPU count from cpuset range (e.g., "0-7" or "0,2,4-6")
count_cpus() {
    count=0
    for range in $(echo "$1" | tr ',' ' '); do
        case "$range" in
            *-*) count=$((count + ${range#*-} - ${range%-*} + 1)) ;;
            *)   count=$((count + 1)) ;;
        esac
    done
    echo "$count"
}

FORK_JOBS=$(count_cpus "${OSS_CRS_CPUSET:-0}")

# Run AFL++ with parallel instances
afl-fuzz -i "$CORPUS" -o "$OUTPUT" -M main -T "$HARNESS" -- ./"$HARNESS" @@
for i in $(seq 1 $((FORK_JOBS - 1))); do
    afl-fuzz -i "$CORPUS" -o "$OUTPUT" -S "slave$i" -T "$HARNESS" -- ./"$HARNESS" @@ &
done
```

### Pattern 4: Background Artifact Submission

**What:** Use `register-submit-dir` as daemon for continuous artifact streaming
**When:** Fuzzer produces outputs continuously during run phase
**Example:**

```bash
#!/bin/bash
# Run phase entry script

# Register submission directories as background daemons
libCRS register-submit-dir pov /output/crashes &
libCRS register-submit-dir seed /output/corpus &

# Run fuzzer (blocks until timeout or termination)
afl-fuzz -i /corpus -o /output ...

# Daemons continue to flush any remaining artifacts
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Hardcoded Paths

**What:** Using absolute paths instead of environment variables
**Why bad:** Breaks portability across local/Azure environments
**Instead:** Always use `OSS_CRS_*` environment variables

```bash
# BAD
cp /artifacts/build /out

# GOOD
libCRS download-build-output build /out
```

### Anti-Pattern 2: Direct Inter-CRS Communication

**What:** CRS containers communicating directly with other CRS containers
**Why bad:** Violates isolation model; prevents proper artifact tracking
**Instead:** Use SUBMIT_DIR/FETCH_DIR through libCRS

```bash
# BAD
curl http://other-crs:8080/get_seeds

# GOOD
libCRS register-fetch-dir seed /shared-seeds &
```

### Anti-Pattern 3: Blocking on Artifact Availability

**What:** Waiting synchronously for artifacts from other CRSs
**Why bad:** Defeats asynchronous architecture; can cause deadlocks
**Instead:** Use polling with timeouts or daemon registration

```bash
# BAD
while [ ! -f /fetch/seeds/seed.txt ]; do sleep 1; done

# GOOD
libCRS register-fetch-dir seed /my-seeds &
# ... continue execution, seeds arrive asynchronously
```

### Anti-Pattern 4: Monolithic Build Phase

**What:** All instrumentation, slicing, and compilation in a single Dockerfile
**Why bad:** Difficult to debug; cache invalidation on any change
**Instead:** Multiple build steps with explicit dependencies

```yaml
# GOOD: Separate build steps
target_build_phase:
  - name: slice
    dockerfile: oss-crs/dockerfiles/slicer.Dockerfile
    outputs:
      - slice/allowlist.txt
  - name: build
    dockerfile: oss-crs/dockerfiles/builder.Dockerfile
    depends_on:
      - slice
    outputs:
      - build
```

## Docker Image Layering Strategy

### Recommended Layer Structure

```
                    +---------------------------+
                    | gcr.io/oss-fuzz-base/     |
                    | base-builder OR           |
                    | base-runner               |
                    +---------------------------+
                              |
                              v
                    +---------------------------+
                    | CRS Base Image            |
                    | (from docker-bake.hcl)    |
                    | - CRS dependencies        |
                    | - CRS source code         |
                    | - libCRS installation     |
                    +---------------------------+
                              |
            +-----------------+-----------------+
            |                                   |
            v                                   v
+---------------------------+     +---------------------------+
| Builder Image             |     | Runner Image              |
| (FROM target_base_image)  |     | (FROM base-runner OR      |
|                           |     |  CRS base image)          |
| - COPY --from=libcrs      |     |                           |
| - COPY compile scripts    |     | - COPY --from=libcrs      |
| - CMD ["compile_target"]  |     | - COPY run scripts        |
+---------------------------+     | - ENTRYPOINT ["run.sh"]   |
                                  +---------------------------+
```

### Key Layering Decisions

1. **libCRS installation:** Always via `COPY --from=libcrs . /opt/libCRS && RUN /opt/libCRS/install.sh`
2. **Builder base:** Must use `ARG target_base_image` and `FROM ${target_base_image}` to inherit OSS-Fuzz build env
3. **Runner base:** Use `gcr.io/oss-fuzz-base/base-runner` for minimal runtime dependencies
4. **CRS source:** Copy into base image during prepare phase, then COPY from base in build/run Dockerfiles

### docker-bake.hcl Structure

```hcl
// oss-crs/docker-bake.hcl

group "default" {
  targets = ["directed-base"]
}

target "directed-base" {
  dockerfile = "Dockerfile.base"
  context    = "."
  tags       = ["directed-base:latest"]
}
```

## Suggested Build Order for Integration

Based on the OSS-CRS architecture and existing `components/` structure, the recommended build order is:

### Phase 1: CRS Configuration (Foundation)

1. **Create `oss-crs/crs.yaml`**
   - Define CRS name, type, version
   - Declare `required_inputs: [diff]` for directed mode
   - Define single build step with `build` output
   - Define single run module `fuzzer`

2. **Create `oss-crs/docker-bake.hcl`**
   - Build base image with AFL++ and directed fuzzer dependencies
   - Install libCRS from context

### Phase 2: Build Phase Integration

3. **Create `oss-crs/dockerfiles/builder.Dockerfile`**
   - `FROM ${target_base_image}`
   - Install libCRS
   - Copy diff parser and allowlist generator
   - Copy compile script

4. **Create `bin/compile_target`**
   - Fetch diff from FETCH_DIR
   - Parse diff to extract modified functions (port `DiffParser`)
   - Generate AFL allowlist
   - Compile with `AFL_LLVM_ALLOWLIST`
   - Submit build outputs

### Phase 3: Run Phase Integration

5. **Create `oss-crs/dockerfiles/runner.Dockerfile`**
   - FROM base-runner
   - Install libCRS
   - Copy fuzzer scripts

6. **Create `bin/run_fuzzer`**
   - Download build outputs
   - Parse `OSS_CRS_CPUSET` for parallelism
   - Register submit directories for povs/seeds
   - Launch AFL++ with proper master/slave configuration
   - Monitor crashes and copy to pov directory

### Phase 4: Validation

7. **Test with afc-freerdp-delta-01**
   ```bash
   # Prepare
   uv run oss-crs prepare --compose-file directed-compose.yaml

   # Build target with diff
   uv run oss-crs build-target \
     --compose-file directed-compose.yaml \
     --fuzz-proj-path ~/post/CRSBench/benchmarks/afc-freerdp-delta-01 \
     --diff ~/post/CRSBench/benchmarks/afc-freerdp-delta-01/.aixcc/ref.diff

   # Run
   uv run oss-crs run \
     --compose-file directed-compose.yaml \
     --fuzz-proj-path ~/post/CRSBench/benchmarks/afc-freerdp-delta-01 \
     --target-harness TestFuzzCryptoCertificateDataSetPEM \
     --diff ~/post/CRSBench/benchmarks/afc-freerdp-delta-01/.aixcc/ref.diff \
     --timeout 3600
   ```

## Environment Variables Reference

| Variable | Phase | Description |
|----------|-------|-------------|
| `OSS_CRS_NAME` | Build, Run | CRS name from crs-compose.yaml |
| `OSS_CRS_TARGET` | Build, Run | Target project name |
| `OSS_CRS_TARGET_HARNESS` | Run | Harness binary name |
| `OSS_CRS_CPUSET` | Run | Allocated CPU cores (e.g., "4-7") |
| `OSS_CRS_MEMORY_LIMIT` | Run | Memory limit (e.g., "16G") |
| `OSS_CRS_BUILD_OUT_DIR` | Run | Build output directory (read-only) |
| `OSS_CRS_SUBMIT_DIR` | Run | Submission directory |
| `OSS_CRS_FETCH_DIR` | Build, Run | Fetch directory for diff/seeds |
| `OSS_CRS_SHARED_DIR` | Run | Inter-container shared directory |
| `FUZZING_ENGINE` | Build, Run | OSS-Fuzz engine (e.g., "afl") |
| `SANITIZER` | Build, Run | Sanitizer (e.g., "address") |

## Sources

- **Direct source analysis:**
  - `/home/andrew/post/oss-crs-6/docs/crs-development-guide.md` (OSS-CRS development guide)
  - `/home/andrew/post/oss-crs-6/docs/design/architecture.md` (OSS-CRS architecture)
  - `/home/andrew/post/oss-crs-6/docs/design/libCRS.md` (libCRS reference)
  - `/home/andrew/post/oss-crs-6/oss_crs/src/crs.py` (orchestrator implementation)
  - `/home/andrew/post/oss-crs-6/oss_crs/src/config/crs.py` (configuration schema)

- **Reference CRS implementations:**
  - `/home/andrew/post/crs-libfuzzer/oss-crs/crs.yaml` (minimal CRS example)
  - `/home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml` (multi-module CRS)
  - `/home/andrew/post/atlantis-multilang-wo-concolic/oss-crs/crs.yaml` (complex CRS with LLM)

- **Existing codebase:**
  - `/home/andrew/post/42-directed/components/directed/src/daemon/modules/diff_parser.py` (diff parsing)
  - `/home/andrew/post/42-directed/components/slice/slice.py` (slicing component)
  - `/home/andrew/post/42-directed/.planning/codebase/ARCHITECTURE.md` (microservices architecture)

---

*Architecture analysis: 2026-03-11*
