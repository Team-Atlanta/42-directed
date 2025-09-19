## How Generated Seeds Are Used

### Seed Storage and Distribution Architecture

Seeds follow a **dual-path distribution** system for robustness and optimization:

#### C/C++ Projects
1. **ALL seeds stored in database** ([`task_handler.py#L266-275`](../components/seedgen/task_handler.py#L266)) - provides persistence and fallback
2. **ALSO sent to `cmin_queue`** ([`task_handler.py#L278-284`](../components/seedgen/task_handler.py#L278)) - for corpus minimization
3. Minimized corpus available via:
   - **LibCmin HTTP service**: `http://libcmin-host/cmin/{taskId}/{harness}` ([`libcmin.go#L33`](../components/bandfuzz/internal/corpus/libcmin.go#L33))
   - **Redis cache**: `cmin:{taskId}:{harness}` ([`cmin.go#L39`](../components/bandfuzz/internal/corpus/cmin.go#L39))

#### Java Projects
- **Skip minimization entirely** ([`aixcc.py#L415`](../components/seedgen/infra/aixcc.py#L415))
- Seeds go directly to database only
- Retrieved via DBSeedGrabber when fuzzing

#### MCP Mode (Special Case)
- Seeds treated as **potential bugs**, not fuzzing inputs ([`task_handler.py#L293-342`](../components/seedgen/task_handler.py#L293))
- Directly saved as bug records for triage
- Bypasses fuzzing entirely

### Fuzzer Corpus Retrieval Mechanism

Fuzzers use a **priority-based corpus grabber** ([`grab.go#L33-38`](../components/bandfuzz/internal/corpus/grab.go#L33)) that tries sources in order and **returns immediately on first success**:

1. **LibCminCorpusGrabber** (Priority 1)
   - HTTP endpoint to LibCmin service
   - Returns minimized C/C++ corpus
   - Fails for Java, moves to next

2. **DBSeedGrabber** (Priority 2) ([`database.go#L48`](../components/bandfuzz/internal/corpus/database.go#L48))
   - Retrieves ALL seed types from database
   - Works for both C/C++ and Java
   - Fallback when LibCmin unavailable

3. **CminSeedGrabber** (Priority 3)
   - Redis cache of minimized corpus
   - Another fallback for C/C++ seeds

4. **MockSeedGrabber** (Priority 4)
   - Random/mock seeds as last resort
   - Ensures fuzzer always has input

### Seeds as Initial Corpus

Seeds are prepared **BEFORE** fuzzer starts ([`aflpp.go#L89-97`](../components/bandfuzz/internal/fuzz/aflpp/aflpp.go#L89)):

1. Create seedsFolder directory
2. **CollectCorpusToDir** retrieves and unpacks tar.gz into directory
3. AFL++ launched with `-i seedsFolder` ([`instance.go#L150`](../components/bandfuzz/internal/fuzz/aflpp/instance.go#L150))
4. **Replaces** any default OSS-Fuzz seeds completely

### Fuzzer Scheduling and Seed Usage

**No continuous restart problem** - seeds generated once, fuzzers rotate efficiently:

1. **Fuzzlets** (harness+sanitizer combinations) created during build phase ([`upload.go#L56-61`](../components/bandfuzz/internal/builder/upload.go#L56))
2. **Round-robin scheduling** with time slices ([`scheduler.go#L80-92`](../components/bandfuzz/internal/scheduler/scheduler.go#L80)):
   - Each epoch picks one fuzzlet ([`pick.go#L29-58`](../components/bandfuzz/internal/scheduler/pick.go#L29))
   - Runs for `schedulingInterval` duration
   - Retrieves pre-generated seeds from storage
3. **No seed generation delays** - seeds already available in DB/Redis

### Continuous Seed Evolution

During fuzzing, new interesting inputs are:
1. Collected by SeedManager ([`seeds.go#L104-137`](../components/bandfuzz/internal/seeds/seeds.go#L104))
2. Batched into tar.gz archives
3. Sent back to `cmin_queue` for minimization
4. Stored as `general` fuzzer type in database
5. Available for future fuzzing epochs
