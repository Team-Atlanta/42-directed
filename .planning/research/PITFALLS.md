# Pitfalls Research

**Domain:** OSS-CRS directed fuzzing integration
**Researched:** 2026-03-11
**Confidence:** HIGH (based on existing codebase analysis and OSS-CRS documentation)

## Critical Pitfalls

### Pitfall 1: Silent Slice Failure Fallback Creates Empty Allowlist

**What goes wrong:**
When program slicing fails (timeout, service unavailable, invalid input), the system creates an empty allowlist file instead of failing fast. AFL++ then instruments the entire codebase rather than targeting changed code, negating the directed fuzzing benefit.

**Why it happens:**
- Defensive coding pattern to "keep the fuzzer running"
- Slice service reliability issues (timeouts, network failures)
- Existing pattern in `components/directed/src/daemon/daemon.py:432-434`:
  ```python
  if not result_path:
      logging.error('Slicing result path not found, create a blank file')
      with open(workspace_result_path, 'w') as f:
          f.write('')
  ```

**How to avoid:**
1. Implement retry logic with exponential backoff before fallback
2. Track slice failure rate as a metric
3. Distinguish "no relevant code to slice" (valid empty) from "slice service failed" (error)
4. Add explicit empty-slice validation in build phase before invoking AFL++

**Warning signs:**
- AFL++ build takes unexpectedly long (instrumenting full codebase)
- Fuzzer finds crashes unrelated to diff locations
- Slice metrics show high timeout/failure rates

**Phase to address:**
Build-target phase (slice integration validation)

---

### Pitfall 2: Diff Path Not Accessible in Build Container

**What goes wrong:**
The diff file is staged to `OSS_CRS_FETCH_DIR/diffs/` but the build script attempts to read from a different path or the volume mount is misconfigured. The build proceeds without diff information.

**Why it happens:**
- OSS-CRS uses `--diff <file>` which places diff at `FETCH_DIR/diffs/ref.diff`
- Build scripts must explicitly `libCRS fetch diff <local_dir>` to copy the diff
- Existing microservices architecture passed diff directly via message queue, not filesystem

**How to avoid:**
1. Always use `libCRS fetch diff /work/diffs` at the start of build script
2. Validate diff file exists and is non-empty before proceeding
3. Fail fast with clear error message if diff not found
4. Add integration test verifying diff accessibility in build container

**Warning signs:**
- Build completes but no slice results generated
- `libCRS fetch diff` returns empty list
- Build logs show "diff not found" or similar warnings

**Phase to address:**
Build-target phase (diff fetch validation)

---

### Pitfall 3: Incorrect CPU Core Allocation for AFL++ Slaves

**What goes wrong:**
AFL++ slave count is derived incorrectly from `OSS_CRS_CPUSET`, leading to either underutilization (few slaves on many cores) or resource contention (many slaves on few cores).

**Why it happens:**
- `OSS_CRS_CPUSET` uses range format like "4-7" or "0,2,4,6"
- Existing code in `fuzzer_runner.py:71-80` parses this format
- However, the crs-libfuzzer reference uses a different parsing logic in `run_fuzzer_wrapper.sh:72-81`
- Mismatch between expected format and actual format

**How to avoid:**
1. Use consistent CPUSET parsing logic across all components
2. Add unit tests for edge cases: single CPU, ranges, comma-separated, mixed
3. Validate slave count matches available cores before starting fuzzers
4. Log both CPUSET value and computed slave count for debugging

**Warning signs:**
- Fuzzer starts but CPU usage is unexpectedly low/high
- AFL++ reports "insufficient cores" warnings
- Container CPU metrics don't match expected utilization

**Phase to address:**
Run phase (AFL++ configuration)

---

### Pitfall 4: Build Output Path Mismatch Between build-target and run

**What goes wrong:**
Build-target phase uses `libCRS submit-build-output $OUT build` but run phase attempts `libCRS download-build-output` with a different path, causing "output not found" failures.

**Why it happens:**
- `crs.yaml` declares `outputs: [build]` but script submits to different path
- Path naming conventions differ between components
- OSS-CRS documentation shows path must match exactly between phases

**How to avoid:**
1. Define output paths as constants in a shared config
2. Validate `crs.yaml` output declarations match actual submit calls
3. Add integration test that runs full prepare -> build-target -> run cycle
4. Use explicit path validation in run phase entry script

**Warning signs:**
- Run phase fails immediately with "build output not found"
- `OSS_CRS_BUILD_OUT_DIR` directory is empty or missing expected artifacts
- Build phase logs show successful submit but different path

**Phase to address:**
Build-target phase (output path validation), Run phase (download validation)

---

### Pitfall 5: Missing `required_inputs: [diff]` Declaration

**What goes wrong:**
CRS starts without diff file because `required_inputs` was not declared in `crs.yaml`. OSS-CRS does not validate that `--diff` was provided, and the CRS runs in non-directed mode silently.

**Why it happens:**
- `required_inputs` is optional in OSS-CRS schema
- Easy to forget when porting from microservices architecture
- Validation only happens if field is present

**How to avoid:**
1. Always declare `required_inputs: [diff]` for directed fuzzers
2. Add startup validation in CRS entry script as defense-in-depth
3. Include in CRS development checklist
4. Fail with descriptive error if diff is required but missing

**Warning signs:**
- Fuzzer runs but never targets diff locations
- `oss-crs run` succeeds even when `--diff` not provided
- Slice service never receives requests

**Phase to address:**
Configuration phase (crs.yaml setup)

---

### Pitfall 6: Hardcoded Engine Type Breaks AFL++ Integration

**What goes wrong:**
Existing code hardcodes `FUZZING_ENGINE=libfuzzer` or `afl` in various places. When OSS-CRS passes a different engine configuration, the CRS ignores it or fails.

**Why it happens:**
- Existing codebase in `components/submitter/submission.py:31-32` shows:
  ```python
  engine = "libfuzzer"  # workaround for generalization of engine type
  ```
- Multiple components make engine-specific assumptions
- AFL++ integration requires `FUZZING_ENGINE=afl` but some paths assume libfuzzer

**How to avoid:**
1. Read `FUZZING_ENGINE` from environment variable consistently
2. Remove all hardcoded engine references
3. Add engine compatibility validation in prepare phase
4. Document supported engines in `supported_target.fuzzing_engine` in crs.yaml

**Warning signs:**
- Build succeeds but produces wrong fuzzer type
- Harness binary missing AFL++ instrumentation
- Environment variable `FUZZING_ENGINE` differs from actual build output

**Phase to address:**
Build-target phase (engine configuration validation)

---

### Pitfall 7: PoV Submission Without register-submit-dir Daemon

**What goes wrong:**
PoVs are written to `/output/povs/` but never submitted because `libCRS register-submit-dir pov` was not started as a background daemon. Crashes are found but not reported.

**Why it happens:**
- `register-submit-dir` must be run with `&` to fork daemon
- Easy to miss trailing `&` or forget to start the daemon entirely
- Existing code assumes external submission mechanism (RabbitMQ/scheduler)

**How to avoid:**
1. Use consistent entry script pattern with explicit daemon startup
2. Add healthcheck for submission daemon (verify daemon running)
3. Log submission activity to detect silent failures
4. Add integration test verifying crash -> PoV submission flow

**Warning signs:**
- Fuzzer finds crashes (AFL++ output shows crashes)
- `OSS_CRS_SUBMIT_DIR/povs/` is empty
- No PoV artifacts in OSS-CRS artifact query

**Phase to address:**
Run phase (submission daemon setup)

---

### Pitfall 8: Docker Image Tag Mismatch Between Prepare and Build

**What goes wrong:**
`docker-bake.hcl` builds images with one tag, but `crs.yaml` references a different tag. The build-target phase fails with "image not found".

**Why it happens:**
- Version string in `crs.yaml` becomes image tag
- `docker-bake.hcl` has its own tag definitions
- Tags must match exactly or image pull fails

**How to avoid:**
1. Use variables in HCL that reference crs.yaml version
2. Pin exact version strings, avoid `latest` tag
3. Run `docker images` check after prepare phase
4. Add validation that declared images exist before build-target

**Warning signs:**
- Prepare phase succeeds but build-target fails
- Error message: "unable to pull image" or "image not found"
- Mismatched tags visible in `docker images` output

**Phase to address:**
Prepare phase (image tag validation)

---

### Pitfall 9: Workspace Cleanup Race in Concurrent Tasks

**What goes wrong:**
When processing multiple tasks concurrently, workspace cleanup from one task interferes with another task using overlapping paths.

**Why it happens:**
- Existing workspace pattern from `components/directed/src/daemon/modules/workspace.py:70`:
  ```python
  logging.error(f'Error removing workspace directory {self.workspace_dir}: {e}')
  ```
- OSS-CRS runs single-task per CRS container, but internal parallelism exists
- Shared filesystem paths without proper locking

**How to avoid:**
1. Use unique workspace paths per task (include task ID in path)
2. Never share workspace directories between concurrent operations
3. Implement proper directory locking if parallelism required
4. Use OSS-CRS provided directories which are scoped per-CRS

**Warning signs:**
- Intermittent "file not found" errors during concurrent runs
- Workspace contents appear corrupted or missing
- Task A's output contains Task B's files

**Phase to address:**
Run phase (workspace isolation)

---

### Pitfall 10: Slice Service Connection Timeout Too Short

**What goes wrong:**
Complex projects require longer slicing time, but timeout causes premature failure. The fallback creates empty allowlist (see Pitfall 1).

**Why it happens:**
- Existing timeout in `daemon/daemon.py:115` set for quick response
- Large codebases (like FreeRDP) have many functions to analyze
- No adaptive timeout based on codebase size

**How to avoid:**
1. Make timeout configurable via environment variable
2. Base timeout on codebase size heuristics
3. Implement progressive timeout (short first attempt, longer retry)
4. Consider async slicing with result polling

**Warning signs:**
- Large projects consistently produce empty slices
- Slice service logs show "processing" then timeout
- Smaller projects slice successfully but large ones fail

**Phase to address:**
Build-target phase (slice configuration)

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Empty allowlist fallback | Fuzzer keeps running | Loses directed benefit, wastes resources | Never for directed fuzzing (fail fast instead) |
| Hardcoded base-runner image | Works immediately | Version drift, reproducibility issues | Only in initial prototyping |
| Single-threaded slice service | Simpler implementation | Bottleneck with multiple CRSs | Until concurrent slicing needed |
| Skip build output validation | Faster iteration | Silent failures in run phase | Only during active development |

## Integration Gotchas

Common mistakes when connecting to OSS-CRS.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| libCRS fetch | Not calling fetch, assuming files are auto-mounted | Explicitly `libCRS fetch <type> <dir>` before use |
| Build outputs | Using absolute container paths | Use paths relative to `OSS_CRS_BUILD_OUT_DIR` |
| CPUSET parsing | Assuming single format | Handle ranges "4-7", lists "0,2,4", and mixed "0,2-4" |
| PoV submission | Direct file write without daemon | `libCRS register-submit-dir pov /povs &` with daemon |
| Environment variables | Hardcoding values | Read from `OSS_CRS_*` environment variables |
| Service discovery | Hardcoded hostnames | Use `libCRS get-service-domain <service>` |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full codebase instrumentation | 10x slower builds | Verify allowlist non-empty | Any project > 50k LOC |
| Synchronous slice requests | Build phase timeout | Async with polling | Slice time > 60s |
| Single AFL++ master | Underutilized CPUs | Configure slave count from CPUSET | > 4 cores allocated |
| No corpus deduplication | Disk fills up, slow sync | Use libCRS seed sharing | > 10k seeds generated |
| Blocking file I/O in crash handler | Delayed crash processing | Async queue for crash files | > 100 crashes/hour |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Unpinned base-runner image | Supply chain attack | Pin image by SHA256 hash |
| Diff file path traversal | Read arbitrary files during build | Validate diff paths stay within workspace |
| Unvalidated crash input reproduction | Malicious PoV execution | Run PoV reproduction in sandboxed container |
| Hardcoded credentials in config | Credential leak | Use OSS-CRS provided env vars for all secrets |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Build outputs:** Build succeeds, but check outputs actually exist in `OSS_CRS_BUILD_OUT_DIR`
- [ ] **Slice results:** Slice service responds, but verify result file is non-empty and valid
- [ ] **PoV submission:** Crashes written locally, but verify they appear in OSS-CRS artifacts
- [ ] **CPU allocation:** Fuzzer starts, but verify AFL++ slave count matches CPUSET
- [ ] **Diff consumption:** Build phase reads diff, but verify slice uses correct target locations
- [ ] **Harness binary:** Binary exists, but verify AFL++ instrumentation is present (not libfuzzer)

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Empty allowlist deployed | MEDIUM | Rebuild with fixed slice service, re-run fuzzing campaign |
| Wrong engine type built | MEDIUM | Fix engine config, rebuild target only (not prepare) |
| PoVs not submitted | LOW | Manually submit from local crash directory using `libCRS submit pov` |
| CPUSET mismatch | LOW | Update config and restart run phase |
| Diff not found | LOW | Re-run build-target with correct `--diff` flag |
| Image tag mismatch | MEDIUM | Fix docker-bake.hcl or crs.yaml, re-run prepare |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Empty allowlist fallback | Build-target | Allowlist file > 0 bytes, contains function names |
| Diff path not accessible | Build-target | `libCRS fetch diff` returns non-empty list |
| CPUSET parsing error | Run | Logged slave count matches expected from CPUSET |
| Output path mismatch | Build-target, Run | `download-build-output` succeeds in run phase |
| Missing required_inputs | Configuration | `oss-crs run` fails fast without `--diff` |
| Hardcoded engine type | Build-target | `FUZZING_ENGINE` env var used consistently |
| PoV daemon not started | Run | `register-submit-dir` process visible in `ps` |
| Image tag mismatch | Prepare | `docker images` shows expected tags |
| Workspace race | Run | No concurrent tasks share workspace paths |
| Slice timeout | Build-target | Configurable timeout, retry before fallback |

## Sources

- OSS-CRS documentation: `docs/crs-development-guide.md` (official integration guide)
- Existing codebase: `components/directed/src/daemon/` (error handling patterns)
- Reference implementations: `crs-libfuzzer/`, `atlantis-multilang-wo-concolic/`
- OSS-CRS config reference: `docs/config/crs.md` (required_inputs, outputs format)
- libCRS API: `libCRS/libCRS/local.py` (fetch, submit, build-output methods)
- Known issues: `.planning/codebase/CONCERNS.md` (tech debt, fragile areas)

---
*Pitfalls research for: OSS-CRS directed fuzzing integration*
*Researched: 2026-03-11*
