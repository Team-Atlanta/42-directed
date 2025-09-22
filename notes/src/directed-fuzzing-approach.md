# Directed Fuzzing Approach: AFL++ Allowlist vs Distance-Based Scheduling

## Overview

The 42-b3yond-6ug team's directed fuzzing implementation reveals another instance of their strategic choice of **proven simplicity over sophisticated techniques**. Instead of using distance-based scheduling approaches like AFLGo, they implemented **AFL++ allowlist-based selective instrumentation** combined with **LLVM program slicing**.

## Technical Implementation

### Core Architecture: Slicing + Allowlist Pipeline

**Step 1: Delta Analysis** ([`components/directed/src/daemon/daemon.py:447-468`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L447-L468)):
```python
def _handle_delta_fuzzing(self, dmsg: DirectedMsg, workspace: WorkspaceManager):
    """Extract modified functions from patches for targeted testing."""
    changed_functions = []
    if dmsg.task_type == 'delta':
        patch_manager = PatchManager(dmsg, workspace)
        changed_functions = patch_manager.extract_changed_functions()
    return changed_functions
```

**Step 2: LLVM Program Slicing** ([`components/directed/src/daemon/daemon.py:78-124`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L78-L124)):
```python
def _send_slice_request_and_wait(self, slice_queue_name: str, slice_msg_data: SliceMsg, task_id: str):
    """Sends slice request to R14/R18 LLVM slicing services and waits for results."""
    # Sends SliceMsg with target functions to slice component
    # Waits for DirectedSlice results containing code paths to targets
```

**Step 3: Allowlist Generation** ([`components/directed/src/daemon/daemon.py:252-260`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L252-L260)):
```python
# Copy slice result to workspace as allowlist
focused_repo_path = workspace.get_focused_repo()
workspace_result_path = focused_repo_path / "aixcc_beyond_allowlist.txt"
if not result_path:
    # Create blank allowlist if slicing fails
    with open(workspace_result_path, 'w') as f:
        f.write('')
else:
    shutil.copy(result_path, workspace_result_path)
```

**Step 4: AFL++ Selective Instrumentation** ([`components/directed/src/daemon/modules/fuzzer_runner.py:149-154`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/modules/fuzzer_runner.py#L149-L154)):
```python
cmd = [
    'python3', self.helper_path, 'build_fuzzers',
    '--engine', 'afl',
    '-e', f'AFL_LLVM_ALLOWLIST={workdir}/aixcc_beyond_allowlist.txt',
    '--clean', self.project_name, self.focused_repo
]
```

## Technical Approach Comparison

### AFL++ Allowlist (Implemented)

**Mechanism**:
- **Compile-time selective instrumentation** based on allowlist file
- Binary decision: instrument or don't instrument each function/basic block
- Standard AFL fuzzing with **targeted coverage feedback**

**Advantages**:
- ✅ **Zero runtime overhead**: No distance calculations during fuzzing
- ✅ **Deterministic behavior**: Consistent instrumentation across runs
- ✅ **Mature feature**: Well-tested AFL++ functionality
- ✅ **Simple integration**: File-based configuration
- ✅ **Graceful degradation**: Falls back to standard AFL if allowlist empty

**Implementation Details**:
- **Allowlist format**: Function names and/or basic block addresses
- **LLVM integration**: Uses AFL++'s LLVM pass for selective instrumentation
- **OSS-Fuzz compatibility**: Works within existing build infrastructure

### Distance-Based Scheduling (Not Implemented)

**Alternative Approaches**:
- **AFLGo**: Runtime distance calculation with power scheduling
- **Directed greybox fuzzing**: Distance-guided seed prioritization
- **Hawk**: Static analysis + distance-based mutation

**Why Not Implemented**:
- ❌ **Runtime overhead**: Distance calculations during fuzzing execution
- ❌ **Complex implementation**: Requires extensive modifications to AFL
- ❌ **Reliability concerns**: More moving parts and potential failure modes
- ❌ **Tuning complexity**: Distance metrics and power scheduling parameters

## Strategic Analysis

### Alignment with "Keep It Simple & Stable" Philosophy

**Consistent Pattern**: This directed fuzzing choice follows the same strategic pattern observed across other components:

| Component | Sophisticated Approach | 42-b3yond-6ug Choice | Rationale |
|-----------|----------------------|---------------------|-----------|
| **Directed Fuzzing** | AFLGo distance scheduling | AFL++ allowlist | Compile-time vs runtime complexity |
| **Counterexamples** | Semantic analysis | Random sampling | Predictable vs optimal selection |
| **BandFuzz** | Ensemble learning | Simplified scaling | Proven techniques vs experimental |
| **Patch Agent** | Interaction optimization | Direct LLM communication | Reliability vs sophistication |

### Competitive Advantages

**Operational Benefits**:
1. **Predictable Resource Usage**: No runtime distance computation overhead
2. **Reliable Targeting**: Compile-time decisions eliminate runtime failures
3. **Easy Debugging**: File-based allowlist enables inspection and validation
4. **Fallback Strategy**: Empty allowlist gracefully degrades to standard AFL

**Engineering Benefits**:
1. **OSS-Fuzz Integration**: Minimal changes to existing build infrastructure
2. **Testing Simplicity**: Easier to validate allowlist generation than distance metrics
3. **Component Isolation**: Slicing and fuzzing components remain loosely coupled
4. **Maintenance**: Fewer complex algorithms to maintain and debug

## Implementation Quality Assessment

### Production-Ready Features

**Robust Error Handling**:
```python
if not result_path:
    logging.error('Task %s | Slicing result path not found, create blank file', task_id)
    with open(workspace_result_path, 'w') as f:
        f.write('')  # Graceful degradation to standard AFL
```

**Multi-Service Redundancy**:
- **R14 and R18 slicing services**: Automatic fallback between LLVM versions
- **Timeout handling**: 900-second timeout for slicing operations
- **Retry logic**: Task retry mechanisms for transient failures

**Docker Integration**:
- **Isolated workspaces**: Each task gets separate container environment
- **Volume mounting**: Proper allowlist file sharing between services
- **Resource cleanup**: Automatic workspace and container cleanup

### Missing Sophistication (Intentional)

**Compared to Research Approaches**:
- ❌ **No distance optimization**: No attempt to optimize distance metrics
- ❌ **No adaptive targeting**: Static allowlist vs dynamic target adjustment
- ❌ **No multi-objective optimization**: Pure coverage vs coverage + distance
- ❌ **No target prioritization**: Equal weight to all allowlisted functions

**Strategic Justification**: These omissions reflect deliberate engineering choices prioritizing **reliability over optimality** in a competitive environment requiring 10-day autonomous operation.

## LLVM Slicing Integration

### Slice Component Architecture

**Input Processing**: [`components/slice/src/daemon/slice_msg.py`](../components/slice/src/daemon/slice_msg.py):
```python
@dataclass
class SliceMsg:
    slice_id: str
    task_id: str
    project_name: str
    focus: str
    repo: List[str]
    fuzzing_tooling: str
    slice_target: List[List[str]]  # [function_name, file_path] pairs
    diff: Optional[str] = None
```

**LLVM Analysis**: The slice component uses LLVM-based static analysis to:
1. **Build call graphs** from fuzzing harnesses to target functions
2. **Identify reachable code paths** using interprocedural analysis
3. **Generate function/basic block lists** for allowlist file
4. **Handle C++ name mangling** and template instantiations

**Output Format**: The allowlist file contains function names and basic block identifiers suitable for AFL++ instrumentation.

## Operational Experience

### Exhibition Round Lessons

**R14 vs R18 LLVM Versions**:
- **Exhibition Round 1**: LLVM 14-based slicing failed on C23 code
- **Solution**: Implemented R18 (LLVM 18) slicing service as fallback
- **Result**: Automatic fallback between LLVM versions for compatibility

**Performance Characteristics**:
- **Slicing timeout**: 900 seconds (15 minutes) maximum per slice request
- **Allowlist size**: Varies by project complexity and target function reachability
- **Overhead**: Minimal impact on fuzzing performance vs standard AFL

## Comparison with Academic Research

### Academic Distance-Based Approaches

**Typical Research Focus**:
- **Optimal distance metrics**: Control flow distance, call graph distance, data flow distance
- **Power scheduling algorithms**: Exponential, linear, adaptive scheduling
- **Multi-objective optimization**: Coverage + distance + diversity objectives

**Research Evaluation**:
- **Controlled experiments**: Fixed benchmarks with known vulnerabilities
- **Optimal performance**: Measured improvement over baseline AFL
- **Short-term evaluation**: Hours to days of fuzzing time

### Production Competition Requirements

**AIxCC Operational Constraints**:
- **10-day autonomous operation**: No human intervention allowed
- **Unknown target programs**: No prior knowledge of vulnerability locations
- **Resource limitations**: Fixed compute and LLM budgets
- **Reliability over optimality**: System failures more costly than suboptimal performance

**Directed Fuzzing Success Metrics**:
- **System uptime**: Continuous operation without crashes
- **Delta task handling**: Effective fuzzing of modified code regions
- **Integration reliability**: Seamless coordination with other CRS components

## Lessons for AI Competition Systems

### Engineering Principles Validated

1. **Compile-time vs Runtime Decisions**: When possible, move complexity to build-time rather than execution-time
2. **File-based Coordination**: Simple file interfaces enable robust inter-component communication
3. **Graceful Degradation**: Always provide fallback behavior for component failures
4. **Tool Ecosystem Leverage**: Use mature tool features (AFL++ allowlist) rather than implementing from scratch

### Strategic Trade-offs

**Sophistication vs Reliability**:
- **Academic optimal**: Distance-based scheduling for theoretical maximum efficiency
- **Production optimal**: Allowlist-based targeting for guaranteed functionality

**Performance vs Maintainability**:
- **Research focus**: Squeeze maximum performance from directed fuzzing algorithms
- **Competition focus**: Ensure directed fuzzing never fails and degrades gracefully

## Java Directed Fuzzing: Different but Similar Strategy

### Java Implementation: Jazzer `--instrumentation_includes`

Interestingly, **Java projects do NOT use the directed fuzzing component at all**. Instead, they have a completely separate but parallel approach:

**Java Detection and Skip** ([`components/directed/src/daemon/daemon.py:247-252`](../components/directed/src/daemon/daemon.py#L247-L252)):
```python
# Check if JVM project
if is_jvm_project(oss_fuzz_path, dmsg.project_name):
    logging.warning('Task %s | JVM project detected, skipping', dmsg.task_id)
    return None  # Skip entirely
```

**Separate Java Pipeline**:
1. **JavaSlicer Component** ([`components/javaslicer/`](../components/javaslicer/)) uses IBM WALA for program slicing
2. **PrimeFuzz Integration** consumes JavaSlicer results for targeted fuzzing
3. **Jazzer Instrumentation** uses `--instrumentation_includes` parameter

### Java Slicing Pipeline

**Step 1: WALA-Based Program Slicing** ([`components/javaslicer/src/main/java/org/b3yond/SliceCmdGenerator.java`](../components/javaslicer/src/main/java/org/b3yond/SliceCmdGenerator.java)):
```java
// 1. Parse diff to identify changed methods
// 2. Use IBM WALA for bytecode analysis
// 3. Generate three output files:
//    - .results.txt (raw slicing results)
//    - .instrumentation_includes.txt (class patterns with .** suffix)
//    - .filtered_classes.txt (filtered class lists)
```

**Step 2: Fuzzer Integration** ([`components/primefuzz/utils/target_utils.py:294-312`](../components/primefuzz/utils/target_utils.py#L294-L312)):
```python
def get_slicing_extra_args(slice_result, harness_name) -> str:
    slice_res_file = Path(slice_result) / f"{harness_name}.instrumentation_includes.txt"
    if slice_res_file.exists():
        return f"FUZZER_ARGS=--instrumentation_includes={slicing_res_file_to_arg(slice_res_file)}"
    return "FUZZER_ARGS="
```

**Step 3: Jazzer Execution**:
```bash
# Jazzer runs with instrumentation includes
jazzer --instrumentation_includes=com.example.package.**,com.target.class.**
```

### Comparison: C/C++ vs Java Directed Fuzzing

| Aspect | C/C++ (AFL++ Allowlist) | Java (Jazzer Instrumentation) |
|--------|-------------------------|-------------------------------|
| **Slicing Tool** | LLVM-based (slice component) | IBM WALA-based (JavaSlicer) |
| **Target Format** | Function names/addresses | Java class patterns with `.**` |
| **Fuzzer Integration** | AFL++ `AFL_LLVM_ALLOWLIST` | Jazzer `--instrumentation_includes` |
| **Scope** | Function/basic block level | Class/package level granularity |
| **File Format** | Plain text allowlist | Class patterns (e.g., `com.example.**`) |
| **Component** | Directed component (skips Java) | PrimeFuzz + JavaSlicer |

### Strategic Consistency

**Same Underlying Philosophy**: Both approaches use **selective instrumentation** rather than **distance-based scheduling**:

- **C/C++**: AFL++ compiles only allowlisted functions/blocks
- **Java**: Jazzer instruments only specified class patterns

**Consistent Engineering Choice**: Both avoid runtime overhead of distance calculation in favor of compile-time/startup-time decisions.

### Java-Specific Challenges

**Bytecode vs Source Analysis**:
- **Compilation Required**: JavaSlicer needs successful public build with compiled `.class` files
- **JAR Extraction**: Handles both loose `.class` files and JAR archives
- **Method Mapping**: Maps source line changes to bytecode methods using JavaParser

**Class-Level Granularity**:
- **Package Patterns**: Uses `.**` wildcards for package inclusion
- **Coarser Targeting**: Less precise than C/C++ function-level targeting
- **JVM Limitations**: Limited by Jazzer's instrumentation capabilities

## Conclusion

The 42-b3yond-6ug directed fuzzing approach exemplifies their overall strategic philosophy: **choose proven, simple techniques that work reliably over sophisticated approaches that might fail**. By using AFL++ allowlist functionality with LLVM program slicing, they achieved:

1. **Effective targeting** of modified code regions in delta tasks
2. **Zero runtime overhead** compared to distance-based scheduling
3. **Robust integration** with existing OSS-Fuzz infrastructure
4. **Graceful degradation** when slicing fails or targets are unreachable

This implementation demonstrates that in competitive AI systems, **engineering maturity often trumps algorithmic sophistication**—a lesson validated by their success in the AIxCC finals. The allowlist approach provides "good enough" directed fuzzing without the complexity and reliability risks of more advanced distance-based scheduling techniques.