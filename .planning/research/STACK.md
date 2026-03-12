# Technology Stack

**Project:** Directed Fuzzing OSS-CRS Integration
**Researched:** 2026-03-11

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| OSS-CRS | latest (from ~/post/oss-crs-6) | CRS orchestration framework | Required integration target; three-phase architecture (prepare, build-target, run) |
| libCRS | bundled with OSS-CRS | Container<->infrastructure communication | Required for build output management, artifact submission, diff fetching |
| Python | 3.11+ | CRS runtime, slicing, diff parsing | Matches existing component stack, OSS-CRS requires >= 3.10 |
| Docker Buildx | latest | Multi-stage image builds via HCL | OSS-CRS prepare phase uses `docker buildx bake` |

### Fuzzing Engine

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| AFL++ | 4.x (from gcr.io/oss-fuzz-base/base-builder) | Directed fuzzer with allowlist support | `AFL_LLVM_ALLOWLIST` enables compile-time selective instrumentation for targeting changed code |
| OSS-Fuzz base images | gcr.io/oss-fuzz-base/base-builder, base-runner | Build and run environments | Standard OSS-Fuzz toolchain provides `compile`, AFL++ compilers, runtime instrumentation |
| LLVM/Clang | 16+ (bundled in base-builder) | AFL++ instrumentation compiler | Required for `afl-clang-fast` compilation with allowlist |

### Program Slicing

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| LLVM analyzer | from components/slice | Static analysis for reachability | Generates function/basic-block lists from diff targets |
| llvm-nm | bundled | Bitcode symbol extraction | Extracts function symbols from .bc files for slice analysis |
| Bitcode compilation | via WLLVM or -emit-llvm | LLVM IR for analysis | Required input for static slicing tools |

### Docker Base Images

| Image | Tag | Purpose | When |
|-------|-----|---------|------|
| gcr.io/oss-fuzz-base/base-builder | latest | Target compilation with AFL++ instrumentation | build-target phase |
| gcr.io/oss-fuzz-base/base-runner | latest | Fuzzer execution runtime | run phase |
| ubuntu:noble | 24.04 | CRS component base (if needed) | prepare phase for CRS-specific tooling |

### Build System

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Docker Buildx Bake | latest | HCL-based multi-target builds | OSS-CRS prepare phase standard; enables image layering |
| HCL | Docker native | Build orchestration config | Required by `crs.yaml prepare_phase.hcl` |
| rsync | latest | Build artifact transfer | libCRS uses rsync for submit/download-build-output |

### libCRS Commands (Critical Integration Points)

| Command | Phase | Purpose |
|---------|-------|---------|
| `libCRS fetch diff <dir>` | build-target | Retrieve diff from OSS_CRS_FETCH_DIR for allowlist generation |
| `libCRS submit-build-output <src> <dst>` | build-target | Upload compiled harnesses with AFL++ instrumentation |
| `libCRS download-build-output <src> <dst>` | run | Retrieve compiled harnesses for fuzzing |
| `libCRS register-submit-dir pov <path>` | run | Auto-submit crash-triggering inputs |
| `libCRS register-submit-dir seed <path>` | run | Auto-submit interesting corpus inputs |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Fuzzer | AFL++ | AFLGo | AFLGo requires complex distance computation; AFL++ allowlist is simpler compile-time selection |
| Fuzzer | AFL++ | libFuzzer | libFuzzer lacks native allowlist support for directed fuzzing |
| Base images | gcr.io/oss-fuzz-base | Custom Ubuntu | OSS-Fuzz images are OSS-CRS standard; include compile script, AFL++ toolchain |
| Slicing | LLVM static analyzer | DySlicer | LLVM static analysis is already implemented in components/slice |
| Build system | Docker Buildx | Plain Docker | HCL required by OSS-CRS prepare phase |

## What NOT to Use

| Technology | Why Avoid |
|------------|-----------|
| RabbitMQ | Existing microservices architecture not ported; OSS-CRS handles orchestration |
| Redis | External state management not needed; OSS-CRS provides SUBMIT/FETCH_DIR |
| PostgreSQL | Database persistence not needed; OSS-CRS manages state |
| Kubernetes Helm charts | Out of scope; OSS-CRS handles deployment |
| --engine libfuzzer | Does not support selective instrumentation for directed fuzzing |
| Custom base images | Use OSS-Fuzz standard images for compatibility |

## Docker Image Layering Pattern

```
Prepare Phase (docker-bake.hcl):
  directed-crs-base (optional tooling image)

Build-Target Phase:
  target_base_image (ARG, provided by OSS-CRS)
    + libCRS installation
    + compile script with AFL++ allowlist generation
    + diff parsing for target extraction

Run Phase:
  gcr.io/oss-fuzz-base/base-runner
    + libCRS installation
    + CRS fuzzer wrapper script
    + seed/crash submission daemons
```

## crs.yaml Configuration Pattern

```yaml
name: directed-fuzzer
type:
  - bug-finding
version: "1.0.0"
docker_registry: "ghcr.io/[org]/directed-fuzzer"

prepare_phase:
  hcl: oss-crs/docker-bake.hcl

target_build_phase:
  - name: build
    dockerfile: oss-crs/dockerfiles/builder.Dockerfile
    outputs:
      - build  # Directory containing instrumented harnesses

crs_run_phase:
  fuzzer:
    dockerfile: oss-crs/dockerfiles/runner.Dockerfile

supported_target:
  mode:
    - delta  # Directed fuzzing requires diff input
  language:
    - c
    - c++
  sanitizer:
    - address
  architecture:
    - x86_64
  fuzzing_engine:
    - afl  # AFL++ for allowlist support

required_inputs:
  - diff  # Mandatory: OSS-CRS validates before spawning containers
```

## Environment Variables

### Build-Target Phase (via OSS-CRS)

| Variable | Description |
|----------|-------------|
| `OSS_CRS_FETCH_DIR` | Read-only directory containing diff file (when --diff provided) |
| `SRC` | Target source directory (OSS-Fuzz standard) |
| `OUT` | Build output directory (OSS-Fuzz standard) |
| `FUZZING_ENGINE` | Set to "afl" for AFL++ |
| `SANITIZER` | Default "address" for ASan |

### Run Phase (via OSS-CRS)

| Variable | Description |
|----------|-------------|
| `OSS_CRS_CPUSET` | CPU allocation (e.g., "4-7") for AFL++ slave count |
| `OSS_CRS_TARGET_HARNESS` | Harness binary name to fuzz |
| `OSS_CRS_SUBMIT_DIR` | Directory for artifact submission |
| `OSS_CRS_FETCH_DIR` | Read-only directory for inter-CRS data and bootup data |

## AFL++ Configuration

### Compiler Flags

```bash
# In build script, after fetching diff and generating allowlist
export CC="afl-clang-fast"
export CXX="afl-clang-fast++"
export AFL_LLVM_ALLOWLIST=/path/to/allowlist.txt
```

### Allowlist Format

```
# Function names (from slice analysis)
freerdp_certificate_policies
freerdp_certificate_get_pem_ex

# File:function format also supported
libfreerdp/crypto/certificate.c:freerdp_certificate_policies
```

### Runtime Configuration

```bash
# In run script
FORK_JOBS=$(count_cpus "$OSS_CRS_CPUSET")  # Use allocated CPUs

# AFL++ master/slave mode
$OUT/afl-fuzz -M master -i $CORPUS -o $OUT/afl_out $HARNESS &
for i in $(seq 1 $((FORK_JOBS-1))); do
  $OUT/afl-fuzz -S slave$i -i $CORPUS -o $OUT/afl_out $HARNESS &
done
wait
```

## Installation

### Build-Target Dockerfile

```dockerfile
ARG target_base_image
FROM ${target_base_image}

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Copy build script
COPY oss-crs/bin/compile_directed.sh /compile_directed.sh
RUN chmod +x /compile_directed.sh

CMD ["/compile_directed.sh"]
```

### Run Dockerfile

```dockerfile
FROM gcr.io/oss-fuzz-base/base-runner

RUN apt-get update && apt-get install -y --no-install-recommends \
    inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

COPY oss-crs/bin/run_directed.sh /run_directed.sh
RUN chmod +x /run_directed.sh

ENTRYPOINT ["/run_directed.sh"]
```

## Critical Integration Flow

```
1. Prepare Phase:
   docker buildx bake -f oss-crs/docker-bake.hcl

2. Build-Target Phase:
   oss-crs build-target --diff ref.diff

   Inside container:
   a) libCRS fetch diff /work/diff
   b) Parse diff -> extract modified functions
   c) Run static slice analysis
   d) Generate allowlist.txt (function names)
   e) Compile with AFL_LLVM_ALLOWLIST=allowlist.txt
   f) libCRS submit-build-output $OUT build

3. Run Phase:
   oss-crs run --target-harness <harness>

   Inside container:
   a) libCRS download-build-output build /out
   b) libCRS register-submit-dir pov /artifacts/povs &
   c) libCRS register-submit-dir seed /artifacts/seeds &
   d) Calculate slave count from OSS_CRS_CPUSET
   e) Run AFL++ master + slaves
```

## Sources

- OSS-CRS Development Guide: /home/andrew/post/oss-crs-6/docs/crs-development-guide.md (HIGH confidence)
- OSS-CRS crs.yaml Reference: /home/andrew/post/oss-crs-6/docs/config/crs.md (HIGH confidence)
- libCRS Reference: /home/andrew/post/oss-crs-6/docs/design/libCRS.md (HIGH confidence)
- crs-libfuzzer Reference Implementation: /home/andrew/post/crs-libfuzzer/oss-crs/crs.yaml (HIGH confidence)
- buttercup-bugfind Reference Implementation: /home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml (HIGH confidence)
- Existing Directed Fuzzer Components: /home/andrew/post/42-directed/components/directed/ (HIGH confidence)
- AFL++ Allowlist Pattern: /home/andrew/post/42-directed/components/directed/src/daemon/modules/fuzzer_runner.py (HIGH confidence)
