# SeedGen Component Analysis

## Key Seed Generation Strategies

The seedgen component is an LLM-powered seed generation system that creates initial fuzzing inputs to maximize code coverage. It implements a parallel processing architecture with **four distinct strategies** (three active, one unused):

**Main Workflow Entry Point**: [`components/seedgen/task_handler.py`](../components/seedgen/task_handler.py)
- Listens to RabbitMQ queue (`seedgen_queue`) for incoming tasks
- Processes tasks in parallel using multiple generative models (GPT-4.1, Claude-4-sonnet, O4-mini)
- Orchestrates seed generation strategies based on environment variables

### Four Seed Generation Strategies

1. **Full Mode** ([`run_full_mode`](../components/seedgen/infra/aixcc.py:595) in lines 595-751)
   - Uses [`SeedGenAgent`](../components/seedgen/seedgen2/seedgen.py:35) class
   - **Does NOT support Java/JVM projects** (lines 606-610: early return for Java)
   - Requires compilation of the project with instrumentation
   - Runs SeedD daemon (Go service) in Docker container for dynamic analysis
   - Collects coverage information and function call graphs
   - Most comprehensive but resource-intensive

2. **Mini Mode** ([`run_mini_mode`](../components/seedgen/infra/aixcc.py:340) in lines 340-459)
   - Uses [`SeedMiniAgent`](../components/seedgen/seedgen2/seedmini.py:20) class
   - **Supports Java/JVM projects**
   - Lightweight approach using only harness source code
   - No compilation or dynamic analysis required
   - Faster but less context-aware
   - Java projects skip corpus minimization ([`send_to_cmin=not is_java`](../components/seedgen/infra/aixcc.py:415))

3. **MCP Mode** ([`run_mcp_mode`](../components/seedgen/infra/aixcc.py:461) in lines 461-593)
   - Uses [`SeedMcpAgent`](../components/seedgen/seedgen2/seedmcp.py:148) class
   - **Supports Java/JVM projects**
   - Integrates Model Context Protocol for enhanced code understanding
   - Uses filesystem and tree-sitter servers for code analysis
   - Seeds can be directly sent to triage as potential bugs
   - **Currently enabled** in deployment ([`ENABLE_MCP=1`](../deployment.yaml:64))

4. **Codex Mode** ([`run_codex_mode`](../components/seedgen/infra/aixcc.py:754) in lines 754-876) **[UNUSED]**
   - Uses [`SeedCodexAgent`](../components/seedgen/seedgen2/seedcodex.py:16) class
   - **Supports Java/JVM projects**
   - Alternative to MCP mode, analyzes harness and codebase together
   - Uses Codexbot graph for seed generation
   - **Not enabled** in current deployment (would require `ENABLE_CODEX=1`)
   - Mutually exclusive with MCP mode (see [`task_handler.py:173-207`](../components/seedgen/task_handler.py:173))
   - Skips Claude models ([line 766](../components/seedgen/infra/aixcc.py:766): `if "claude" in gen_model: return`)
   - Java projects skip corpus minimization ([`send_to_cmin=not is_java`](../components/seedgen/infra/aixcc.py:834))

### Java/JVM Support Summary

| Mode | Java Support | Note |
|------|-------------|------|
| Full | ❌ No | Explicitly skips Java projects ([lines 608-610](../components/seedgen/infra/aixcc.py:608)) |
| Mini | ✅ Yes | Works with Java, skips cmin queue |
| MCP | ✅ Yes | Works with Java |
| Codex | ✅ Yes | Works with Java, skips cmin queue |

## Overall Workflow

```mermaid
graph TB
    %% Input Task
    subgraph "Input Task Message"
        TASK["{<br/>task_id: '123',<br/>task_type: 'seedgen',<br/>project_name: 'libxml2',<br/>focus: 'libxml2-2.9.10',<br/>repo: ['source.tar.gz'],<br/>fuzzing_tooling: 'oss-fuzz.tar.gz',<br/>diff: 'patch.tar.gz'<br/>}"]
    end
    
    %% Task Reception
    QUEUE["RabbitMQ<br/>seedgen_queue"] --> LISTENER["Task Listener<br/>(task_handler.py:384-556)"]
    TASK --> QUEUE
    
    %% Archive Extraction
    LISTENER --> EXTRACT["Extract Archives<br/>(task_handler.py:78-94)<br/>• Source code<br/>• Fuzzing tooling<br/>• Diff files"]
    
    EXTRACT --> PATCH["Apply Diffs<br/>(task_handler.py:97-122)"]
    
    %% Model Parallelism
    PATCH --> MODEL_PARALLEL["Parallel Model Execution<br/>(task_handler.py:464-470)"]
    
    subgraph "LLM Models (Parallel)"
        GPT["GPT-4.1"]
        CLAUDE["Claude-4-sonnet"]
        O4["O4-mini"]
    end
    
    MODEL_PARALLEL --> GPT
    MODEL_PARALLEL --> CLAUDE
    MODEL_PARALLEL --> O4
    
    %% Strategy Selection
    GPT --> STRATEGY_SELECT["Strategy Selection<br/>(task_handler.py:172-207)"]
    CLAUDE --> STRATEGY_SELECT
    O4 --> STRATEGY_SELECT
    
    %% Strategy Execution (Per Model)
    STRATEGY_SELECT --> |"Always"| MINI["Mini Mode<br/>(aixcc.py:340-459)<br/>• Harness only<br/>• All languages"]
    
    STRATEGY_SELECT --> |"C/C++ only"| FULL["Full Mode<br/>(aixcc.py:595-751)<br/>• Instrumentation<br/>• Dynamic analysis<br/>• SeedD daemon"]
    
    STRATEGY_SELECT --> |"ENABLE_MCP=1"| MCP["MCP Mode<br/>(aixcc.py:461-593)<br/>• Tree-sitter<br/>• Filesystem access<br/>• All languages"]
    
    STRATEGY_SELECT -.-> |"ENABLE_CODEX=1<br/>(unused)"| CODEX["Codex Mode<br/>(aixcc.py:754-876)<br/>• Codebase analysis<br/>• All languages"]
    
    %% Harness Parallelism
    subgraph "Harness Processing (Parallel per Strategy)"
        H1["Harness 1"]
        H2["Harness 2"]
        HN["Harness N"]
    end
    
    MINI --> H1
    MINI --> H2
    MINI --> HN
    
    FULL --> H1
    FULL --> H2
    FULL --> HN
    
    MCP --> H1
    MCP --> H2
    MCP --> HN
    
    CODEX -.-> H1
    CODEX -.-> H2
    CODEX -.-> HN
    
    %% Output Processing
    H1 --> STORE["Store Seeds<br/>(task_handler.py:246-290)<br/>• Compress as tar.gz<br/>• Save to database<br/>• Record metrics"]
    H2 --> STORE
    HN --> STORE
    
    STORE --> |"C/C++ only"| CMIN["Corpus Minimization<br/>cmin_queue<br/>(task_handler.py:278-284)"]
    
    STORE --> |"Seeds from MCP Mode"| TRIAGE["Bug Triage<br/>(task_handler.py:293-342)<br/>• Create bug records<br/>• Direct to triage"]
    
    %% Error Handling
    STORE --> SUCCESS["ACK Message<br/>(task_handler.py:491-493)"]
    STORE --> |"On Error"| RETRY["Retry Logic<br/>(task_handler.py:498-522)<br/>• Max 3 attempts<br/>• Track in headers"]
    RETRY --> |"Retry < 3"| QUEUE
    RETRY --> |"Retry >= 3"| FAIL["NACK Message<br/>Drop task"]
    
    %% Styling
    classDef input fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef parallel fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef strategy fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef output fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef unused fill:#fafafa,stroke:#9e9e9e,stroke-width:1px,stroke-dasharray: 5 5
    
    class TASK input
    class MODEL_PARALLEL,GPT,CLAUDE,O4,H1,H2,HN parallel
    class MINI,FULL,MCP,CODEX strategy
    class STORE,CMIN,TRIAGE,SUCCESS output
    class CODEX unused
```

## Overall Workflow

The seedgen component follows a multi-layered parallel processing workflow with three levels of parallelism:

- **Task Reception and Distribution**: [`task_handler.py:384-557`](../components/seedgen/task_handler.py:384)
- **Archive Extraction**: [`task_handler.py:78-94`](../components/seedgen/task_handler.py:78)
- **Diff Application**: [`task_handler.py:97-122`](../components/seedgen/task_handler.py:97)
- **Parallel Model Processing**: [`task_handler.py:464-490`](../components/seedgen/task_handler.py:464)
- **Strategy Selection and Execution**: [`task_handler.py:143-207`](../components/seedgen/task_handler.py:143)
- **Result Storage and Distribution**: [`task_handler.py:246-290`](../components/seedgen/task_handler.py:246)
- **Error Handling and Retry Logic**: [`task_handler.py:494-527`](../components/seedgen/task_handler.py:494)

### Key Infrastructure Components

The infrastructure components provide the underlying technical capabilities that enable specific parts of the workflow:

**1. SeedD Service** ([`components/seedgen/seedd/`](../components/seedgen/seedd/)):
- **Purpose**: Go-based gRPC daemon that powers the Full Mode strategy's dynamic analysis capabilities
- **Integration**: Started via Docker container at [`aixcc.py:654-697`](../components/seedgen/infra/aixcc.py:654)
- **Workflow Connection**: Enables the "Dynamic analysis" feature shown in the Full Mode box of the workflow
- **Usage**: Each harness (H1, H2, HN) in Full Mode communicates with this daemon via gRPC for coverage collection and function enumeration
- **Scope**: Only used by Full Mode; not needed for Mini, MCP, or Codex modes

**2. Compilation Tools** (deployed at [`aixcc.py:151-159`](../components/seedgen/infra/aixcc.py:151)):
- **Purpose**: Custom instrumentation toolchain that enables Full Mode's code analysis
- **Components**:
  - `clang-argus/clang-argus++`: Instrumented compiler wrappers replacing standard compilers
  - `bandld`: Custom linker for binary instrumentation
  - `libcallgraph_rt.a`: Runtime library for call graph generation
  - `SeedMindCFPass.so`: LLVM pass for control flow instrumentation
- **Integration**: Deployed via [`compile_project()`](../components/seedgen/infra/aixcc.py:151) before Full Mode execution
- **Workflow Connection**: Provides the "Instrumentation" capability mentioned in the Full Mode box
- **Prerequisite**: Must instrument the code before SeedD can perform dynamic analysis

**3. LiteLLM Proxy Integration**:
- **Purpose**: Unified API interface that powers the parallel LLM model execution
- **Configuration**: Set up via [`deployment.yaml:43-46`](../deployment.yaml:43) with multiple models
- **Integration**: Used by [`task_handler.py:464-470`](../components/seedgen/task_handler.py:464) with ThreadPoolExecutor
- **Workflow Connection**: Enables the "LLM Models (Parallel)" subgraph containing GPT-4.1, Claude-4-sonnet, and O4-mini
- **Model Selection**: Controlled via `GEN_MODEL_LIST` environment variable and `SeedGen2GenerativeModel.set_custom_model()`