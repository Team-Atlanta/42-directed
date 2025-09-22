# SeedGen Component Analysis

The seedgen component is an LLM-powered seed generation system that creates initial fuzzing inputs to maximize code coverage. It implements a parallel processing architecture with **four distinct strategies** (three active, one unused):

**Main Workflow Entry Point**: [`components/seedgen/task_handler.py`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py)
- Listens to RabbitMQ queue (`seedgen_queue`) for incoming tasks
- Processes tasks in parallel using multiple generative models (GPT-4.1, Claude-4-sonnet, O4-mini)
- Orchestrates seed generation strategies based on environment variables

## Key Design Choice: One-Time Generation Strategy

**🔑 N.B. Seedgen operates as a ONE-TIME generation at task arrival, NOT continuous generation based on coverage feedback.**

All four modes (Full, Mini, MCP, Codex) follow this same pattern ([task_handler.py#L143-207](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L143)):
- Seeds are generated **once** when a new task arrives from the queue
- No feedback loop from fuzzing back to seedgen
- Fuzzing takes these initial seeds and mutates them independently
- Multiple LLM models run in parallel for the same task, but each runs only once

```text
Task Arrival → Seedgen (once) → Initial Seeds → Fuzzing (continuous mutation) → Bug Discovery
     ↓              ↓                  ↓                    ↓
  Queue msg    3 models × N        cmin_queue         Fuzzers mutate
              seeds per harness                      independently
```

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

The seedgen component follows a multi-layered parallel processing workflow with three levels of parallelism:

- **Task Reception and Distribution**: [`task_handler.py#L384-557`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L384)
- **Archive Extraction**: [`task_handler.py#L78-94`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L78)
- **Diff Application**: [`task_handler.py#L97-122`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L97)
- **Parallel Model Processing**: [`task_handler.py#L464-490`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L464)
- **Strategy Selection and Execution**: [`task_handler.py#L143-207`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L143)
- **Result Storage and Distribution**: [`task_handler.py#L246-290`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L246)
- **Error Handling and Retry Logic**: [`task_handler.py#L494-527`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L494)

### Key Infrastructure Components

The infrastructure components provide the underlying technical capabilities that enable specific parts of the workflow:

**1. SeedD Service** ([`components/seedgen/seedd/`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedd/)):
- **Purpose**: Go-based gRPC daemon that powers the Full Mode strategy's dynamic analysis capabilities
- **Integration**: Started via Docker container at [`aixcc.py#L654-697`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L654)
- **Workflow Connection**: Enables the "Dynamic analysis" feature shown in the Full Mode box of the workflow
- **Usage**: Each harness (H1, H2, HN) in Full Mode communicates with this daemon via gRPC for coverage collection and function enumeration
- **Scope**: Only used by Full Mode; not needed for Mini, MCP, or Codex modes

**2. Compilation Tools** (deployed at [`aixcc.py#L151-159`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L151)):
- **Purpose**: Custom instrumentation toolchain that enables Full Mode's code analysis
- **Components**:
  - `clang-argus/clang-argus++`: Instrumented compiler wrappers replacing standard compilers
  - `bandld`: Custom linker for binary instrumentation
  - `libcallgraph_rt.a`: Runtime library for call graph generation
  - `SeedMindCFPass.so`: LLVM pass for control flow instrumentation
- **Integration**: Deployed via [`compile_project()`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L151) before Full Mode execution
- **Workflow Connection**: Provides the "Instrumentation" capability mentioned in the Full Mode box
- **Prerequisite**: Must instrument the code before SeedD can perform dynamic analysis

**3. LiteLLM Proxy Integration**:
- **Purpose**: Unified API interface that powers the parallel LLM model execution
- **Configuration**: Set up via [`deployment.yaml:43-46`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment.yaml:43) with multiple models
- **Integration**: Used by [`task_handler.py:464-470`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py:464) with ThreadPoolExecutor
- **Workflow Connection**: Enables the "LLM Models (Parallel)" subgraph containing GPT-4.1, Claude-4-sonnet, and O4-mini
- **Model Selection**: Controlled via `GEN_MODEL_LIST` environment variable and `SeedGen2GenerativeModel.set_custom_model()`

## Four Key Seed Generation Strategies

| Mode | Agent Class | Language Support | Compilation Required | Key Features | Coverage Feedback | Script Evolution | Infrastructure | Corpus Minimization | Deployment Status |
|------|------------|-----------------|---------------------|--------------|-------------------|------------------|----------------|-------------------|------------------|
| **[Full](./seedgen-fullmode.md)** | [`SeedGenAgent`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedgen.py#L35) | C/C++ only | Yes (instrumented) | • Binary instrumentation with LLVM<br>• SeedD daemon for dynamic analysis<br>• Function call graph collection | Yes (via SeedD) | 3 iterations with refinement | Complex (SeedD, getcov, LLVM) | Always for C/C++ | Active |
| **[Mini](./seedgen-minimode.md)** | [`SeedMiniAgent`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedmini.py#L20) | All languages | No | • Lightweight harness-only analysis<br>• Docker-based seed execution<br>• Fastest execution time | No | Single generation | Simple (Docker only) | C/C++ only, skip for Java | Active (default) |
| **[MCP](./seedgen-mcpmode.md)** | [`SeedMcpAgent`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedmcp.py#L148) | All languages | No | • Tree-sitter AST analysis<br>• MCP filesystem access<br>• Direct bug triage submission | No (static only) | Single-pass with MCP context | MCP servers (Node.js/Python) | None (direct to triage) | **Enabled** ([`ENABLE_MCP=1`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment.yaml#L64)) |
| **[Codex](./seedgen-codexmode.md)** | [`SeedCodexAgent`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedcodex.py#L16) | All languages | No | • Codexbot graph analysis<br>• Harness + codebase context<br>• Skips Claude models | No | Single generation | Codexbot graph | C/C++ only, skip for Java | **Unused** (needs `ENABLE_CODEX=1`) |

### Implementation Entry Points
- **Full Mode**: [`run_full_mode`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L595) (lines 595-751)
- **Mini Mode**: [`run_mini_mode`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L340) (lines 340-459)  
- **MCP Mode**: [`run_mcp_mode`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L461) (lines 461-593)
- **Codex Mode**: [`run_codex_mode`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L754) (lines 754-876)

### Mode Selection Logic
- Strategy selection: [`task_handler.py#L173-207`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L173)
- MCP and Codex are mutually exclusive
- Java projects: Skip Full Mode ([`aixcc.py#L606-610`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L606))
- Corpus minimization: Java projects skip in Mini/Codex modes ([`aixcc.py#L415`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L415), [`aixcc.py#L834`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L834))
