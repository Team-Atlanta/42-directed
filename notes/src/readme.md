# Roadmap of the CRS study

## Overview

The [local copy of blog](blog.md) provides the overview of the 42-b3yond-6ug team's CRS (in section "About 42-b3yond-6ug").
According to the blog, its main component is a traditional fuzzing pipeline, with LLMs assisting on the following components:

- [Seedgen Component](seedgen.md) - LLM-powered seed generation with multiple strategies
  - [Full Mode Deep Dive](seedgen-fullmode.md) - Compiler instrumentation and dynamic analysis for C/C++
  - [Mini Mode Deep Dive](seedgen-minimode.md) - Lightweight static analysis for all languages
  - [MCP Mode Deep Dive](seedgen-mcpmode.md) - Model Context Protocol for deep code analysis (currently enabled)
  - [Codex Mode Deep Dive](seedgen-codexmode.md) - Autonomous codebase exploration via external CLI tool (not used in competition)
- [Corpus Grabber Component](corpus_grabber.md) - Intelligent corpus acquisition with two-tier selection strategy
- [Patch Agent Component](patch_agent.md)
- [SARIF Component](sarif.md)

Besides:
- A [tentative doc](./how-seeds-used.md) recording how seeds are used in fuzzers.
- The `prime fuzzing` & `directed fuzzing` in the following diagram seems not correctly reflect its usage, validate and fix them later
- The core fuzzer is bandfuzz, which seems like an advanced ensemble fuzzing framework? Need to check more detail in code & [paper](https://arxiv.org/pdf/2507.10845)

## Complete System Workflow

```mermaid
graph TB
    %% External Input
    subgraph "External Input"
        COMP["Competition API<br/>New Challenge"]
        USER["User API<br/>SARIF Reports"]
    end
    
    %% Gateway and Initial Processing
    COMP --> GATEWAY["Gateway<br/>(API Interface)<br/>• Receive tasks<br/>• Store in DB"]
    USER --> GATEWAY
    
    %% Database and Scheduler
    GATEWAY --> DB[("Database<br/>• Tasks<br/>• Bugs<br/>• Seeds<br/>• Patches")]
    
    DB --> SCHEDULER["Scheduler<br/>(components/scheduler)<br/>• Poll pending tasks<br/>• Download sources<br/>• Broadcast to queues"]
    
    %% Task Broadcast Exchange
    SCHEDULER --> BROADCAST{{"task_broadcast_exchange<br/>(Fanout)<br/>Broadcasts to all<br/>task queues"}}
    
    %% Parallel Task Processing Queues
    BROADCAST ==> SEEDGEN_Q["seedgen_queue"]
    BROADCAST ==> CORPUS_Q["corpus_queue"]
    BROADCAST ==> PRIME_Q["prime_fuzzing_queue"]
    BROADCAST ==> GENERAL_Q["general_fuzzing_queue"]
    BROADCAST ==> DIRECTED_Q["directed_fuzzing_queue"]
    BROADCAST ==> FUNCTEST_Q["func_test_queue"]
    BROADCAST ==> ARTIFACT_Q["artifact_queue"]
    
    %% Components Processing
    SEEDGEN_Q --> SEEDGEN["Seedgen Component<br/>(3 LLM models × 4 strategies)<br/>• Full Mode (C/C++)<br/>• Mini Mode (all)<br/>• MCP Mode (enabled)<br/>• Codex Mode (unused)"]
    
    CORPUS_Q --> CORPUS["Corpus Grabber<br/>• Project-specific corpus<br/>• LLM filetype detection<br/>• Build & find harnesses"]
    
    PRIME_Q --> PRIMEFUZZ["Prime Fuzzer<br/>(Prioritized fuzzing)"]
    GENERAL_Q --> BANDFUZZ["Band Fuzzer<br/>(General fuzzing)"]
    DIRECTED_Q --> DIRECTED["Directed Fuzzer<br/>(Target-specific)"]
    FUNCTEST_Q --> FUNCTEST["Functional Testing"]
    ARTIFACT_Q --> ARTIFACT["Artifact Processing"]
    
    %% Corpus Minimization (C/C++ only)
    SEEDGEN --> |"C/C++ seeds"| CMIN_Q["cmin_queue"]
    CORPUS --> |"C/C++ corpus"| CMIN_Q
    
    CMIN_Q --> LIBCMIN["LibCmin<br/>(Corpus Minimization)<br/>• Deduplicate<br/>• Minimize corpus"]
    
    %% Seeds reach fuzzers through different paths
    SEEDGEN --> |"All seeds (stored in DB)"| SEED_DIST[["Seeds distributed to fuzzers<br/>via DB storage & retrieval"]]
    CORPUS --> |"All corpus (stored in DB)"| SEED_DIST
    LIBCMIN --> |"Minimized C/C++ seeds"| SEED_DIST
    
    %% Fuzzing produces bugs
    PRIMEFUZZ --> |"Bugs found"| BUG_DB[("Bug Records<br/>in Database")]
    BANDFUZZ --> |"Bugs found"| BUG_DB
    DIRECTED --> |"Bugs found"| BUG_DB
    FUNCTEST --> |"Test failures"| BUG_DB
    
    %% Bug Processing Pipeline
    BUG_DB --> |"Scheduler polls"| TRIAGE_Q["triage_queue<br/>(Priority queue)"]
    
    TRIAGE_Q --> TRIAGE["Triage Component<br/>• Deduplication<br/>• Clustering<br/>• Prioritization<br/>• Timeout/OOM handling"]
    
    TRIAGE --> |"Unique bugs"| PATCH_Q["patch_queue<br/>(Priority queue)"]
    
    %% Patch Generation
    PATCH_Q --> PATCH_AGENTS["Patch Agents<br/>• patch-gpt<br/>• patch-claude<br/>• patch-reproducer"]
    
    PATCH_AGENTS --> PATCH_DB[("Patch Records<br/>in Database")]
    
    %% SARIF Processing (Alternative Path)
    USER --> |"SARIF reports"| SARIF_Q["sarif_queue"]
    SARIF_Q --> SARIF["SARIF Component<br/>• Validate reports<br/>• Check duplicates<br/>• LLM verification"]
    SARIF --> |"Valid bugs"| BUG_DB
    
    %% Submission
    PATCH_DB --> SUBMITTER["Patch Submitter<br/>• Validate patches<br/>• Submit to competition"]
    
    SUBMITTER --> COMP_API["Competition API<br/>(Patch submission)"]
    
    %% Direct Bug Submission from Components
    SEEDGEN -.-> |"MCP Mode bugs"| BUG_DB
    CORPUS -.-> |"All corpus files<br/>as potential bugs"| BUG_DB
    
    %% Styling
    classDef external fill:#ffecb3,stroke:#f57c00,stroke-width:2px
    classDef core fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef queue fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef component fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef storage fill:#fff3e0,stroke:#e65100,stroke-width:2px
    
    class COMP,USER,COMP_API external
    class GATEWAY,SCHEDULER,BROADCAST core
    class SEEDGEN_Q,CORPUS_Q,PRIME_Q,GENERAL_Q,DIRECTED_Q,FUNCTEST_Q,ARTIFACT_Q,CMIN_Q,TRIAGE_Q,PATCH_Q,SARIF_Q queue
    class SEEDGEN,CORPUS,PRIMEFUZZ,BANDFUZZ,DIRECTED,FUNCTEST,ARTIFACT,LIBCMIN,TRIAGE,PATCH_AGENTS,SARIF,SUBMITTER,FUZZER_CORPUS component
    class DB,BUG_DB,PATCH_DB,SEEDS_DB storage
```

1. **Fanout Architecture**: The scheduler broadcasts tasks to all relevant queues simultaneously ([`scheduler/internal/messaging/initializer.go#L41-49`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/scheduler/internal/messaging/initializer.go#L41)), enabling parallel processing across multiple components.

2. **Priority Queuing**: Critical queues (`triage_queue` and `patch_queue`) support priority levels ([`initializer.go#L50-53`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/scheduler/internal/messaging/initializer.go#L50)) to ensure important bugs are processed first.

# references

- [blog](https://lkmidas.github.io/posts/20250808-aixcc-recap/), a good blog which summarizes their systems and their impressions of other systems
