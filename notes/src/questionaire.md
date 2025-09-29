# Questionnaire
My answer by digging the source code.

# System Architecture

## General Design Choice
**Q:** Is the CRS an LLM-centric system or a traditional toolchain with LLM
augmentation?

**A:** Traditional toolchain with strategic LLM augmentation. Some subtasks like patch generation and SARIF assessment are LLM-centric.

---

**Q:** How does LLM integration differ between bug finding and patching modules? Why?

**A:** Bug finding is traditional fuzzing-centric with LLM augmentation (one-time seed generation only), while patching uses LLM-centric approach with iterative agents and tool APIs.


## Infrastructure
**Q:** What framework manages compute resources? (Kubernetes, custom scheduler built on Azure API, etc.)

**A:** Kubernetes on Azure with Helm charts for deployment. Each component runs as separate pods with ConfigMaps and Secrets for configuration.

---

**Q:** How are CPU cores, memory, and nodes scheduled across tasks?

**A:** Hybrid Kubernetes deployment with both fixed and auto-scaled pods consuming tasks from RabbitMQ queues. No dedicated infrastructure per challenge project.

- **Architecture**: All pods listen to their RabbitMQ queue channels and process tasks when available
- **Fixed replicas (always running)**: BandFuzz ([24 pods](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L125)), PrimeFuzz ([8](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L118)), JavaDirected ([8](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L147)), Patch-Claude ([8](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L205)), Patch-Reproducer ([12](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L219))
- **Auto-scaled by KEDA (0 to N)**: Seedgen ([0-8](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L73-L76)), Triage ([0-18](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L183-L186)), SARIF ([0-4](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L236-L239)) scale based on queue depth
- **Resource allocation**: Global limits ([30-32 CPU cores](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L4-L8)); BandFuzz internally allocates fuzzing time using [weights](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L37-L52) (ASAN=5, UBSAN=1, MSAN=1)
- **Task concurrency**: [Max 8 concurrent challenge projects](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L3) system-wide
- **Shared resource pool**: All pods share work across all concurrent tasks (e.g., [24 BandFuzz pods](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L125) pick from [shared Redis fuzzlet pool](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/fuzzlets.go#L20) containing all tasks)
- **No dynamic provisioning**: Pods run on pre-provisioned Azure node pool, no per-task VM/node creation or Azure API calls

---

**Q:** Does LLM participate in resource scheduling?

**A:** No. Resource scheduling is deterministic via Kubernetes configs and RabbitMQ queue distribution. LLMs are only used for seed generation and patch synthesis, not infrastructure decisions.

---

**Q:** How does the system handle failures? (component crashes, VM node failures, network partitions)

**A:** Multi-layer resilience through Kubernetes, RabbitMQ, and application-level mechanisms.

- **Pod crashes**: Kubernetes restarts failed pods automatically; KEDA maintains replica counts
- **Message failures**: RabbitMQ durable queues with [retry headers](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L498-L522) (max 3 retries)
- **Connection failures**: [Connection pooling](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/scheduler/internal/messaging/mq.go#L108) with automatic reconnection
- **Redis failures**: [Sentinel for HA](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/utils/redis.py#L19-L58) with automatic failover
- **Database failures**: Transaction rollback and retry logic
- **VM node failures**: Kubernetes reschedules pods to healthy nodes (within pre-provisioned pool)


# LLM

## LLM Component Design
**Q:** What LLM application frameworks or scaffolds are used? (e.g., LangChain, MCP, custom frameworks, Claude Code/Cursor/Gemini wrappers)

**A:** Mixed approach with framework usage varying by component:
- **SeedGen**: [LangGraph StateGraph](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/graphs/mcpbot.py#L4) for workflow; [MCP adapters](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedmcp.py#L10-L11) with filesystem/treesitter servers ([enabled in prod](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/seedgen/templates/deployment.yaml#L141))
- **PatchAgent**: [LangChain ChatPromptTemplate](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/common.py#L42) with custom tool calling
- **SARIF**: [MCP-agent](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/crs-prime-sarif-evaluator/README.md#L18) for code analysis
- **Infrastructure**: [LiteLLM Proxy](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/values.yaml#L4) for unified LLM API interface

---

**Q:** How are agentic components designed?

**A:** Tool-based agents with structured prompts and error handling loops.

- **Tool selection**: Domain-specific tools ([viewcode, locate, validate](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L47-L70) for patching; [filesystem, treesitter](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedmcp.py#L38-L48) MCP servers for seedgen)
- **Prompt engineering**: Language-specific system/user prompts with [detailed format specs](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L71-L84) and psychological techniques
- **Iterative loops**: Patch only - generation → validation → retry with [32 configs](https://github.com/Team-Atlanta/42-afc-crs/blob/main/notes/src/patch_agent.md#L31); Seedgen is [one-time generation](https://github.com/Team-Atlanta/42-afc-crs/blob/main/notes/src/seedgen.md#L12) with script error retry only

---

**Q:** What prompting techniques are employed? (e.g., CoT, few-shot, context engineering, deep research loops, RAG, voting, ensembles)

**A:** Multiple advanced techniques including psychological persuasion:

- **Chain-of-Thought (CoT)**: [Explicit CoT](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/graphs/cotbot.py#L20) with self-doubt ("CONSIDER YOU MAY BE WRONG", "ACTUALLY RE-EXAMINE")
- **Ultra-thinking prompt**: [Exists in code](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/graphs/codexbot.py#L29) but NOT USED (codex mode [disabled in prod](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L173), only MCP enabled)
- **Psychological tricks**: ["ten dollar tip"](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L176) and ["save thousands of lives"](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/prompt.py#L190) appeals
- **Model ensembles**: [Parallel execution](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L465-L470) of 3 models ([GPT-4.1, O4-mini, Claude-3.7-sonnet](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L592-L594))
- **No voting/RAG**: Each model runs independently; no consensus mechanism or retrieval augmentation

---

## LLM Infrastructure
**Q:** Did you use any framework or implemented one? (e.g., LiteLLM Proxy)

**A:** Yes, [LiteLLM Proxy](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/values.yaml#L4) deployed as [1 replica service](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L51) for unified API interface and load balancing.

---

**Q:** Did you use any observability tool? (OpenLIT, Traceloop, Phoenix, etc.)

**A:** Yes, [OpenLIT v1.33.11](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/requirements.txt#L22) deployed across ALL components ([seedgen](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/utils/telemetry.py#L29), [patchagent](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_generator/telemetry.py#L40), [SARIF](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/crs-prime-sarif-evaluator/evaluator/telemetry.py#L44), [primefuzz](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/primefuzz/utils/telemetry.py#L18), etc.) for LLM observability with OpenTelemetry integration.

---

**Q:** How did you handle LLM failure? (rate limit, timeout, …)

**A:** Simple retry without exponential backoff or vendor fallback:

- **PatchAgent**: [3 retries for APIError](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/base.py#L33-L39) with immediate retry (no sleep/backoff)
- **SeedGen MCP**: [5 error retries max](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/graphs/mcpbot.py#L223) for script generation errors
- **LiteLLM Proxy**: [600s timeout](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/files/config.yaml#L71), handles provider-specific rate limits
- **No vendor fallback**: Models run in [parallel](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L465-L470) (GPT-4.1, O4-mini, Claude-3.7), not as fallbacks
- **No exponential backoff**: All retries are immediate without delay strategy


## LLM Model/Quota Usage
**Q:** How are LLM quotas and throughput managed?

**A:** Through LiteLLM Proxy centralization and pod replica limits:

- **Centralized routing**: ALL components route through [LiteLLM Proxy at port 4000](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/presets.py#L21):
  - SeedGen: [via LITELLM_BASE_URL](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/presets.py#L21)
  - PatchAgent: [via OPENAI_BASE_URL](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/patch-gpt/templates/deployment.yaml#L78)
  - SARIF: [via OPENAI_BASE_URL](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/sarif/templates/deployment.yaml#L53-L54)
- **Parallel execution**: [3 models run concurrently](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L465-L470) per task in seedgen
- **Throughput control**: Fixed pod counts limit concurrent calls ([8 patch-claude](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L205), [1 patch-gpt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L212))
- **No explicit quota management**: Relies on provider rate limits and [600s timeout](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/files/config.yaml#L71)

---

**Q:** Token budget allocation per task/component

**A:** No explicit per-task token budgets, relies on model-specific limits and natural consumption patterns:

- **Model limits**: [32K-64K max_tokens for Claude models](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/files/config.yaml#L30-L45)
- **Natural budget control**: Limited LLM usage (only SeedGen, PatchAgent, SARIF) means unlikely to exceed competition quotas
- **Indirect controls**: Pod replica limits ([8 patch-claude](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L205), [1 patch-gpt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L212)) and [600s timeout](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/files/config.yaml#L71)
- **Strategy implication**: Traditional-first approach with selective LLM augmentation naturally limits token consumption

---

**Q:** Model selection strategy (reasoning vs non-reasoning models, price/performance, priority hierarchy)

**A:** Task-specific static model assignment with diversity-focused parallel execution:

- **SeedGen diversity strategy**: [3 models in parallel](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L465-L470) (GPT-4.1, O4-mini, Claude-3.7-sonnet) for generation diversity
- **SeedGen role-based models**: Different models for different roles:
  - [Generative: claude-3.5-sonnet](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/presets.py#L74)
  - [Refiner: o1](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/presets.py#L79) (reasoning model)
  - [Inference: o3-mini](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/presets.py#L84)
  - [Context analysis: gpt-4.1](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/presets.py#L89)
- **PatchAgent exploration**: [Temperature variations [0, 0.3, 0.7, 1]](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/generator.py#L38) for patch diversity
- **Component-specific assignments**:
  - Patch-claude: [Claude-4-opus](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/patch-claude/values.yaml#L2) (strongest)
  - Patch-gpt: [GPT-4.1](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/patch-gpt/values.yaml#L1)
  - Triage: [O4-mini](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/triage/values.yaml#L4) (fast classification)
  - SARIF: [Dual-model with provider toggle](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/tasks.py#L184) (OpenAI/Anthropic)
- **No dynamic selection or fallback**: Static assignment per component/task type

---

**Q:** Downgrade strategy when quota exhausted

**A:** No downgrade strategy

---

**Q:** What controls LLM usage across components? (LiteLLM, custom rate limiters, priority queues)

**A:** LiteLLM proxy with pod-level concurrency control:

- **Central routing**: [LiteLLM proxy at port 4000](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/litellm/files/config.yaml#L1-L76) for all components
- **Pod replica limits**: Control concurrent requests ([8 patch-claude](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L205), [1 patch-gpt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L212))
- **RabbitMQ prefetch**: [Task-level throttling](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L547) (e.g., prefetch_count=8 for seedgen)
- **No custom rate limiters or priority queues**: Relies on infrastructure-level controls


# Bug Finding

## Overall Bug Finding Strategy
**Q:** What is the overall bug finding strategy and pipeline?

**A:** Corpus-enhanced multi-engine fuzzing strategy combining prepared and LLM-generated seeds:

**Core Strategy**: Use both prepared corpus and LLM-generated seeds to bootstrap multiple fuzzing engines running in parallel

**Corpus Enhancement Pipeline**:
1. **Prepared Corpus**: [CorpusGrabber](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/corpusgrabber/grabber.py#L123-L160) provides initial seeds:
   - [Project-specific corpus](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/corpusgrabber/grabber.py#L123-L128) from `corpus/projects/<project>` (pre-collected)
   - [LLM-guided filetype corpus](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/corpusgrabber/grabber.py#L157-L160) as fallback (analyzes harness to detect file types)
   - Note: [Crawler script referenced but not released](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/corpusgrabber/README.md#L4) (`PoC_crawler.py` missing from codebase)
2. **LLM-Generated Seeds**: [SeedGen with 3 models](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L464-L470) (GPT-4.1, O4-mini, Claude-3.7-sonnet):
   - [One-time generation per task](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L143-L207) (no feedback loop)
   - Multiple strategies: Full (instrumented), Mini (lightweight), MCP (AST-based)

**Multi-Engine Fuzzing Execution**:
- [BandFuzz](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/scheduler.go#L153-L214): RL-scheduled 15-min epochs, 24 replicas, C/C++ only
- [PrimeFuzz](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/primefuzz/task_handler.py#L99-L152): Continuous LibFuzzer/Jazzer, 8 replicas, all languages
- [Directed](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L342): Delta-mode targeting changed functions
- [Slice](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/slice/src/daemon/daemon.py#L285): Program slicing for focused paths

**Corpus Refinement**:
- [Cmin++ minimization](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/cminplusplus/cmin_calculator.cpp) removes redundant seeds
- [Redis coordination](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/fuzzlets.go#L50) shares corpus between engines
- [Batch sync after epochs](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/executor/upload.go#L19-L54) in BandFuzz

---

**Q:** Are there bug-type-specific finding approaches or components?

**A:** No targeted bug-type finding strategies; bug classification happens post-crash in triage:

**Finding Phase (No CWE awareness)**:
- Fuzzers use generic crash detection without bug-type targeting
- [BandFuzz multi-sanitizer](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/builder/afl.go#L26-L45): Builds for different sanitizers but no CWE-specific strategies
- [SeedGen prompts](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen): No CWE or vulnerability-type guidance in LLM prompts
- No specialized fuzzers for specific vulnerability classes

**Triage Phase (CWE classification)**:
- [UnifiedParser CWE extraction](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/parser/unifiedparser.py#L87-L91): Post-crash analysis
- [Jazzer CWE mapping](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/parser/jazzer.py#L14-L31): Maps Java exceptions to CWEs after crash
- Classification by sanitizer type (ASAN→memory, UBSAN→undefined behavior)

**Strategy**: Generic crash-driven fuzzing with post-hoc bug classification rather than targeted vulnerability hunting


## Static Analysis
**Q:** How is static analysis used to guide other components? (call graph, program slicing for LLM context)

**A:** Extensive static analysis infrastructure guides fuzzing, seed generation, and patching:

**Program Slicing for Directed Fuzzing**:
- [LLVM-based slicing](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/slice/slice.py#L66-L73) extracts call graphs: `--callgraph=true --slicing=true`
- [AFL++ allowlist generation](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L252-L260) from slice results
- [IBM WALA for Java](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/javaslicer/src/main/java/org/b3yond/SliceCmdGenerator.java) bytecode slicing
- Results guide [selective instrumentation](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/modules/fuzzer_runner.py#L149-L154) in fuzzers

**AST Analysis for Seed Generation (MCP Mode)**:
- [Tree-sitter AST analysis](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedmcp.py#L241-L263) via MCP servers
- [Code structure discovery](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/graphs/mcpbot.py#L33-L105) for LLM context
- [Backdoor pattern detection](https://github.com/Team-Atlanta/42-afc-crs/blob/main/notes/src/seedgen-mcpmode.md#L293-L298) in harnesses
- [Function enumeration](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/seedmcp.py#L91) without compilation

**Language Server for Patch Generation**:
- [Clangd hover hints](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/internal.py#L43-L68) for C/C++ symbol definitions
- [Auto-hint for stack traces](https://github.com/Team-Atlanta/42-afc-crs/blob/main/notes/src/patchagent-autohint.md#L24-L48): Provides symbol context at crash locations
- [Locate tool](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L55-L65) uses LSP to find symbol definitions
- Character-level analysis to identify relevant variables/functions (C/C++ only)

**Note on Static Analysis Usage**:
- CorpusGrabber uses simple string search and LLM reasoning, not static analysis
- Static analysis primarily serves as **input** to other components rather than driving decisions
- No sophisticated dataflow or taint analysis found in the codebase

---

**Q:** How do dynamic techniques and LLM enhance static analysis? (runtime feedback, LLM-guided patterns)

**A:** No enhancements found - dynamic and LLM operate independently from static analysis:

- **No runtime feedback to static analysis**: Dynamic execution results don't refine static slicing or call graphs
- **No LLM-guided static analysis**: LLM consumes AST/LSP outputs but doesn't improve static analysis algorithms
- **Separate pipelines**: Static analysis (slice) → Dynamic fuzzing → LLM patching, with no feedback loops
- **Example**: [Indirect calls handled at runtime](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/callgraph/llvm/SeedMindCFPass.cpp#L59-L60) via dynamic hooking, not static resolution improvements


## Dynamic Analysis / Fuzzing
**Q:** What fuzzing strategies are implemented? (ensemble, concolic, directed, coverage-guided)

**A:** Multiple fuzzing strategies with ensemble execution but no concolic testing:

**Implemented Strategies**:
- **Ensemble fuzzing**: [Multiple engines run in parallel](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L116-L176) (BandFuzz, PrimeFuzz, Directed, JavaDirected)
- **Coverage-guided**: [AFL++ and LibFuzzer](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/builder/afl.go#L26) with edge coverage feedback
- **Directed fuzzing**: [AFL++ allowlist](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/modules/fuzzer_runner.py#L149-L154) for targeting modified functions
- **Multi-sanitizer**: [ASAN, MSAN, UBSAN](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/builder/afl.go#L26-L45) parallel execution
- **Factor-based scheduling**: [BandFuzz weighted factors](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/pick.go#L21-L24) (TaskFactor, SanitizerFactor) with probabilistic selection

**NOT Implemented**:
- **No RL scheduling**: Uses [simple factor scoring](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L37-L52), not reinforcement learning
- **No concolic execution**: No symbolic/concrete hybrid testing
- **No grammar-based fuzzing**: Despite structured input support
- **No taint-guided fuzzing**: No dataflow tracking

---

**Q:** How does LLM augment fuzzing? (seed/dictionary/oracle generation, mutator/generator synthesis, feedback mechanisms)

**A:** LLM augments fuzzing through initial corpus/seed generation only:

**Implemented Augmentations**:
- **Initial corpus selection**: [CorpusGrabber uses LLM](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/corpusgrabber/agent/filetype.py#L34-L54) to analyze harness and select filetype-based corpus
- **Seed generation**: [SeedGen creates initial seeds](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L464-L470) with format-aware Python generators
- **Structure understanding**: [LLM analyzes harness code](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/agents/alignment.py#L26-L41) to identify input structure
- **Filetype detection**: LLM identifies expected formats in both [CorpusGrabber](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/corpusgrabber/agent/filetype.py#L41-L44) and [SeedGen](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/agents/filetype.py#L11)
- **One-time generation**: Both corpus selection and seed generation happen once at task arrival

**NOT Implemented**:
- **No dictionary generation**: No LLM-created fuzzing dictionaries for AFL++/LibFuzzer
- **No crash oracles**: LLM doesn't classify crashes during fuzzing (only post-triage)
- **No mutator synthesis**: No LLM-generated mutation strategies
- **No feedback mechanisms**: No LLM refinement based on coverage/crashes
- **No continuous generation**: LLM not consulted during fuzzing execution

---

**Q:** Which sanitizers are deployed and what is the strategy considering performance/coverage trade-offs?

**A:** Multiple sanitizers with probabilistic scheduling favoring ASAN:

**Deployed Sanitizers**:
- **ASAN (AddressSanitizer)**: [Score 5](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L42) - Memory corruption bugs
- **MSAN (MemorySanitizer)**: [Score 1](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L46) - Uninitialized memory reads
- **UBSAN (UndefinedBehaviorSanitizer)**: [Score 1](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L44) - Undefined behavior

**Scheduling Strategy**:
- **Probabilistic selection**: [Weighted random picker](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/pick.go#L47-L53) selects next fuzzlet
- **5:1:1 probability ratio**: Within same task, ASAN has ~71% chance, MSAN/UBSAN each ~14%
- **Two-factor scoring**: [TaskFactor](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L27) (1/n per task) × [SanitizerFactor](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L42-L46) (5 or 1)
- **Rationale**: Prioritizes memory corruption (most critical) while maintaining coverage diversity

---

**Q:** How are fuzzing resources allocated across targets? (time-slicing, worker distribution, harness assignment)

**A:** Fixed pod allocation with epoch-based time-slicing:

**Worker Distribution**:
- **Fixed replicas**: [BandFuzz: 24](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L40), [PrimeFuzz: 8](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L121), [Directed: 0-6](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L152-L157)
- **No dynamic scaling**: Pods pre-allocated at deployment time
- **Per-pod fuzzing**: Each pod runs single fuzzing instance

**Time-Slicing (BandFuzz)**:
- **15-minute epochs**: [Scheduling interval](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/scheduler.go#L91) per fuzzlet
- **Round-robin with weights**: [Probabilistic picker](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/pick.go#L29-L58) selects next fuzzlet
- **No preemption**: Epoch runs to completion

**Harness Assignment**:
- **All harnesses per task**: Fuzzers receive [all harness binaries](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/builder/yamlParser.go#L20-L30) for the task
- **No specialization**: Any fuzzer can run any harness
- **Shared corpus**: [Redis-coordinated](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/fuzzlets.go#L50) corpus sharing

---

**Q:** Does fuzzing provide feedback to other bug finding components? (program dynamics for LLM context, crash validation)

**A:** No direct feedback - fuzzing operates as isolated pipeline stage:

- **No program dynamics sharing**: Fuzzing execution traces not provided to LLM components
- **No crash validation loop**: Crashes go to triage, no feedback to adjust fuzzing
- **One-way data flow**: Fuzzing → Triage → Patch, without backward connections
- **Corpus sharing only**: [Redis-based corpus](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/fuzzlets.go#L50) shared between fuzzer instances only

## Build-Time Configuration
**Q:** What custom instrumentation is added?

**A:** Custom instrumentation only for SeedGen's dynamic call graph collection:

**SeedGen Full Mode (C/C++ only)**:
- [SeedMindCFPass LLVM pass](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/callgraph/llvm/SeedMindCFPass.cpp#L57-L73): Hooks all function calls including indirect
- [clang-argus/clang-argus++ wrappers](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/infra/aixcc.py#L141-L165): Replace CC/CXX compilers
- [bandld custom linker](https://github.com/Team-Atlanta/42-afc-crs/blob/main/notes/src/seedgen-fullmode.md#L264-L266): Links instrumentation runtime
- [libcallgraph_rt.a runtime](https://github.com/Team-Atlanta/42-afc-crs/blob/main/notes/src/seedgen-fullmode.md#L273-L276): Collects dynamic call graphs

**Purpose**: Enable [get_related_functions](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/seedgen2/agents/predicates.py#L87) to find ancestors/successors in call graph for LLM context when generating documentation and improving seeds

---

**Q:** How does the CRS prevent build breakage from custom instrumentation?

**A:** Parallel execution provides implicit fallback:

- **Parallel modes**: [Full and Mini run concurrently](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L144-L170), not sequentially
- **Independent failures**: If Full mode instrumentation fails, [Mini mode still completes](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/seedgen/task_handler.py#L209-L218)
- **No instrumentation in Mini/MCP**: These modes use harness source analysis only, no compilation
- **Result**: At least one mode succeeds even if custom instrumentation breaks


## Non-Memory Safety Bugs
**Q:** How does the CRS handle non-memory safety findings? (logic bugs, OOM, timeout, stack overflow, uncaught exceptions)

**A:** Standard fuzzer crash detection with multiple sanitizers:

- Uses standard fuzzer capabilities (AFL++, LibFuzzer, Jazzer) for crash/timeout/OOM detection
- [UBSAN for undefined behavior](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/bandfuzz/internal/scheduler/simpleFactors.go#L44) in addition to ASAN/MSAN


## Bug/Finding Processing
**Q:** How are duplicate findings detected and deduplicated? (stack-based, root cause, patch-based grouping)

**A:** Two-stage deduplication: pentuple signature matching first, then cluster-based comparison using stack traces or AI root cause analysis.

**Execution Workflow:**
1. **Stage 1 - Pentuple Signature Check** ([task_handler.py#L436-L446](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L436-L446)):
   - Creates MD5 hash of `task_id:harness:sanitizer:bug_type:trigger_point`
   - Redis lookup: if exists → use existing bug_profile_id, skip to clustering
   - If new → create bug profile, proceed to Stage 2

2. **Stage 2 - Cluster Deduplication** (only for new profiles, [task_handler.py#L491-L495](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L491-L495)):
   - Retrieves all existing clusters for the task
   - Compares new crash against each cluster using configured method:

   **Method A - ClusterFuzz** ([clusterfuzz_dedup.py#L87-L105](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/dedup/clusterfuzz_dedup.py#L87-L105)):
   - Stack trace similarity via CrashComparer
   - Instrumentation key matching for Java
   - 80% similarity threshold

   **Method B - Codex AI** ([codex_dedup.py#L26-L93](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/dedup/codex_dedup.py#L26-L93)):
   - LLM analyzes root cause using source code
   - Conservative: requires 100% confidence
   - Returns YES/NO for duplication

3. **Result**: Either assigns to existing cluster or creates new cluster

**Special Handling - Timeout/OOM:**
- **Deduplication Strategy**: Uses same two-stage process but with simplified signatures:
  - [bug_type="timeout" or "out-of-memory"](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L419)
  - [trigger_point="N/A" for Java](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/parser/jazzer.py#L78), varies for other languages
  - Pentuple becomes: `task_id:harness:sanitizer:timeout/out-of-memory:N/A`
  - Results in one bug profile per harness/sanitizer for all timeouts, another for all OOMs
- **Pod Separation** ([task_handler.py#L414-L429](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L414-L429)):
  - `TIMEOUT_OOM_TRIAGE="sender"`: Regular pods forward to dedicated queue
  - `TIMEOUT_OOM_TRIAGE="processor"`: Dedicated pods only process timeout/OOM
  - `TIMEOUT_OOM_TRIAGE="none"`: No separation (default)

---

**Q:** What criteria determine finding prioritization for submission?

**A:** Priority based on cluster novelty, patch mode, and bug type.

**Priority Assignment:**
- **New clusters:** [Priority 8-10, sent 3 times with "generic" patch mode](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L546-L548)
- **Active tasks:** [Priority 3-7 with "fast" patch mode](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L395-L398)
- **Timeout/OOM:** [Priority 10 via dedicated queue](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L350)

**Submission Strategy:**
- [One representative per cluster: smallest bug_profile_id](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/utils/db.py#L308-L310)
- [Cluster representatives sent to patch queue](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L522-L524)
- Avoids submitting duplicate bugs from same cluster


## Fallback Mechanisms
**Q:** What fallback strategies exist when advanced techniques fail? (vanilla libFuzzer fallback, static-only mode)

**A:** No fallback strategies found - components run in parallel with fixed resources.


# Patch Generation
**Q:** What patch generation strategies are employed?

**A:** LLM-based patch generation with dual-mode strategy and exhaustive parameter exploration:

**Dual-Mode Architecture**:
- **Generic Mode** ([32 configurations](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/generator.py#L36-L46)): Exhaustive grid search for new bug clusters
  - Parameters: `counterexample_num ∈ {0, 3}` × `temperature ∈ {0, 0.3, 0.7, 1}` × `auto_hint ∈ {True, False}` = 32 combinations
  - Execution: Sequential exploration until valid patch found
  - Priority: 8-10 (high priority)
- **Fast Mode** ([single random config](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/generator.py#L27-L35)): Quick single-shot attempt for known patterns
  - Random temperature, random auto_hint, no counterexamples
  - Max iterations: 15 (vs. 30 in generic mode)
  - Priority: 3-7 (medium) or 0 (auto-fallback)

**LLM Tool-Based Agent System**:
- **Tool APIs** ([C/C++](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/default.py#L14-L68), [Java](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/proxy/default.py#L6-L39)):
  - `viewcode`: Line-numbered code viewing
  - `locate`: Symbol definition lookup via LSP (clangd for C/C++, tree-sitter for Java)
  - `validate`: Patch validation via build + PoC replay
- **Auto-Hint** (C/C++ only): [Character-level LSP hover analysis](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/internal.py#L43-L68) on stack trace lines
- **Counterexamples**: [Random sampling](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/common.py#L115-L130) of up to 3 failed patches
- **Prompting**: [Language-specific prompts](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py) with psychological techniques ("ten dollar tip", "save thousands of lives")

**Multi-Model Support**:
- Models: Claude-4-opus ([patch-claude](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/patch-claude/values.yaml#L2)), GPT-4.1 ([patch-gpt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/charts/patch-gpt/values.yaml#L1))
- Replicas: [8 patch-claude pods](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L205), [1 patch-gpt pod](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L212)

**Workflow Strategy**:
- New clusters: [3× generic mode messages](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L543-L548) (priority 8-10)
- Existing clusters: [1× fast mode per cluster](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L395-L398) (priority 3-7)
- Every message: [Auto-enqueue fast fallback](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_generator/main.py#L40-L62) (priority 0)

---

**Q:** How are patches validated? (crash reproduction, regression tests, functional tests, post-patch fuzzing)

**A:** Three-stage validation with PoC-centric approach; functional tests NOT implemented:

**Validation Pipeline** ([task.py#L83-L113](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L83-L113)):

1. **Patch Format Validation** ([builder.py#L69-L79](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/builder.py#L69-L79)):
   - Uses `git apply` to verify syntax
   - Rejects empty patches
   - Returns `InvalidPatchFormat` if fails

2. **Build Verification** ([task.py#L89-L94](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L89-L94)):
   - Compiles patched code using OSS-Fuzz infrastructure
   - Returns `BuildFailed` or `BuildTimeout` on errors
   - Ensures patch doesn't break compilation

3. **PoC Replay Testing** ([task.py#L96-L104](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L96-L104)):
   - Runs original PoCs against patched binary
   - Returns `BugDetected` if crash still occurs
   - Success means vulnerability is fixed

4. **Functional Testing** ❌ **NOT IMPLEMENTED** ([task.py#L106-L111](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L106-L111)):
   - `function_test()` method is [empty stub](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/builder.py#L104)
   - Always passes (no regression testing)
   - Project test suites are not executed

**Cross-Profile Validation** (Patch Deduplication):
- [Reproducer component](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_generator/main.py#L126-L131) tests patches across different bug profiles
- If two patches from different profiles fix each other's PoCs → considered duplicates
- Only one patch submitted to avoid accuracy multiplier penalty

**No Post-Patch Fuzzing**:
- No continuous fuzzing after patch generation
- Validation happens once during patch generation only

---

**Q:** Are build processes optimized for patching? (incremental builds, cached compilation artifacts)

**A:** No incremental build optimization; full rebuilds for each patch validation attempt:

**Build Process**:
- Each patch triggers [full OSS-Fuzz build](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/builder.py#L81-L102) from scratch
- Uses standard OSS-Fuzz `compile` scripts without modifications
- [Redis Queue-based build system](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/prime-build/run_build_job.py) coordinates builds
- Docker-in-Docker execution for isolation

**No Incremental Build Support**:
- No ccache or sccache implementation
- No build artifact caching between patch attempts
- No dependency tracking for selective recompilation
- Fresh compilation every validation iteration

**Build Isolation**:
- [Git reset --hard + clean -fdx](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/builder.py#L69-L70) before each patch application
- Ensures clean state but prevents build optimization

**Trade-off**:
- Simplicity and correctness over speed
- Avoids build cache corruption issues
- Consistent with "Keep It Simple & Stable" philosophy

---

**Q:** Are there bug-type-specific patching strategies?

**A:** Yes - extensive CWE-based repair advice dynamically injected into prompts:

**CWE Classification System** ([cwe.py](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py)):

- [40+ CWE types recognized](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py#L4-L57) from sanitizer reports via regex patterns
- **AddressSanitizer**: heap/stack buffer overflow, use-after-free, double-free, null dereference, memory leak
- **MemorySanitizer**: uninitialized memory
- **UndefinedBehaviorSanitizer**: undefined behavior
- **Jazzer**: injection attacks (SQL, LDAP, command, XPath), path traversal, RCE, SSRF

**Bug-Type-Specific Repair Advice**:

Each CWE type has:
- [Specific description](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py#L59-L105) explaining the vulnerability nature
- [Tailored repair advice](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py#L107-L280) with 3-4 concrete repair steps

Examples:
- **Buffer overflow**: "Replace unsafe functions like memcpy, strcpy with strncpy, snprintf"
- **Use-after-free**: "Set pointers to NULL after freeing; track allocations systematically"
- **SQL injection**: "Use parameterized queries or prepared statements to separate SQL code from user input"

**Dynamic Injection Mechanism** ([address.py#L101-L112](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/address.py#L101-L112)):

```python
summary = (
    f"The sanitizer detected a {self.cwe.value} vulnerability. "
    f"The explanation of the vulnerability is: {CWE_DESCRIPTIONS[self.cwe]}. "
    f"Here is the detail: \n\n{self.purified_content}\n\n"
    f"To fix this issue, follow the advice below:\n\n{CWE_REPAIR_ADVICE[self.cwe]}"
)
```

The `.summary` property is [injected into user prompt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/common.py#L75) as `{report}` variable, providing bug-type-specific guidance to LLM.

**All Sanitizers Include CWE Advice**:
- [AddressSanitizerReport](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/address.py#L109), [MemorySanitizerReport](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/memory.py#L67), [UndefinedBehaviorSanitizerReport](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/undefined.py#L65)
- [JazzerSanitizerReport](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/jazzer.py#L84), [JavaNativeErrorReport](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/java_native.py#L44)

**No Sanitizer-Specific Prompt Templates**:
- C/C++ prompt always says "asan report" regardless of actual sanitizer (ASAN/MSAN/UBSAN/Leak)
- No separate templates per sanitizer type
- Sanitizer-specific info comes through dynamic `{report}` content

**Language-Specific Implementations**:
- **C/C++**: [CLikeAgent](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/common.py) with clangd LSP, LLVM AST
- **Java**: [JavaAgent](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/common.py) with tree-sitter
- Different prompt templates ([C/C++](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L72-L80), [Java](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/prompt.py#L82-L90))

**Uniform Parameter Exploration**:
- All bug types use same [32-configuration grid search](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/generator.py#L36-L46) (temperature, counterexamples, auto-hint)
- No per-CWE parameter tuning
- Specialization via **prompt content** (CWE-specific repair advice), not parameter values

---

**Q:** Does the CRS generate patches without proof-of-vulnerability (no-PoV patches)?

**A:** No - all patches require PoV for generation and validation:

**PoV-Mandatory Architecture**:
- Patch generation only triggered when [bug profile exists](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/triage/task_handler.py#L543) (requires triage-validated crash)
- Each patch must pass [PoC replay validation](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L96-L104) showing crash is fixed
- [PatchTask initialization](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L16-L29) requires `pocs` parameter

**SARIF-to-Patch Pipeline Not Implemented**:
- SARIF component validates reports independently
- No direct path from SARIF findings to patch generation
- Only fuzzing-discovered crashes trigger patching

**Workflow**:
1. Fuzzer finds crash → Triage validates → Creates bug profile with PoC
2. Bug profile sent to patch queue with PoC attached
3. Patch agent generates fix using [sanitizer report + PoC](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L120-L128)
4. Validation requires PoC no longer crashes

**No Speculative Patching**:
- No static-analysis-only patch generation
- No preventive patches based on code patterns
- All patches are reactive to discovered vulnerabilities


# SARIF
**Q:** How are SARIF reports validated? (PoV-based validation, static verification, no-PoV)

**A:** AI-first validation with language-specific strategies; Java uses no-PoV, C/C++ uses PoV when available:

**Core Design**: LLM-based analysis is primary validation mechanism for all languages

**Java/JVM - Direct AI Validation (No-PoV)** ([tasks.py#L88-L145](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/tasks.py#L88-L145)):
- Single-phase LLM analysis using [MCP Agent framework](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/crs-prime-sarif-evaluator/evaluator/main.py#L25-L87)
- Agent has autonomous filesystem access with [tree-sitter tools](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/crs-prime-sarif-evaluator/evaluator/main.py#L30-L34)
- [Tri-fold result](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/tasks.py#L130-L138): `correct` (TRUE) | `incorrect` (FALSE) | other (abstain)
- Up to 20 retry attempts for reliability
- **No empirical validation**: Relies entirely on static analysis without runtime evidence

**C/C++ - Multi-Phase Validation** ([seeds.py](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/seeds.py)):

**Phase 1: Preliminary Check (No-PoV)** ([seeds.py#L124-L170](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/seeds.py#L124-L170)):
- Same LLM evaluator as Java with `--preliminary` flag
- Conservative prompt: "only claim incorrect if confident enough"
- Outcomes:
  - `assessment == 'correct'` → Return TRUE
  - `assessment == 'incorrect'` → Return FALSE
  - Any other value → Fall through to Phase 2

**Phase 2: Crash-Based Validation (Has-PoV)** ([seeds.py#L173-L377](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/seeds.py#L173-L377)):
- Triggered only when preliminary check is uncertain
- [Polls BugProfiles table](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/seeds.py#L218-L231) for ALL crashes with same `task_id`
- For each crash: [LLM determines if crash validates SARIF](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/seeds.py#L279-L293)
- **No explicit crash-SARIF matching**: AI infers correlation from stack traces vs SARIF locations
- [First match wins](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/seeds.py#L353-L361): ANY crash validating SARIF returns TRUE

**Inactive Strategies** ([tasks.py#L155-L158](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/tasks.py#L155-L158)):
- **Directed Fuzzing**: Fully implemented but [commented out](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/checkers/directed_fuzzing.py)
- Would have actively fuzzed SARIF-reported vulnerabilities
- Disabled due to computational expense and reliability concerns

**AI Models Used**:
- [Dual-model with provider toggle](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/tasks.py#L184) (OpenAI/Anthropic)
- System prompt: [prompts.py#L1-L21](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/crs-prime-sarif-evaluator/evaluator/prompts.py#L1-L21)

---

# Delta Mode
**Q:** What technical adaptations are made for delta mode? (harness prioritization, vulnerability candidate ranking, LLM context specialization)

**A:** Directed fuzzing with program slicing to target modified functions; minimal LLM context adaptation:

**Directed Fuzzing Component** ([daemon.py](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py)):

**Patch Analysis** ([_handle_delta_fuzzing](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L185)):
- Extracts [modified functions from delta diff](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L185)
- Identifies target functions for focused fuzzing

**Program Slicing Integration**:
- **C/C++**: [LLVM-based slicing](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/slice/slice.py#L66-L73) extracts call graphs with `--callgraph=true --slicing=true`
- **Java**: [IBM WALA bytecode slicing](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/javaslicer/src/main/java/org/b3yond/SliceCmdGenerator.java)
- Results guide [AFL++ allowlist generation](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py#L252-L260) for selective instrumentation
- [Coordination via RabbitMQ](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/daemon/daemon.py) queues and [PostgreSQL DirectedSlice model](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/db/models/directed_slice.py)

**Fuzzer Execution**:
- [AFL++ directed fuzzing](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/directed/src/modules/fuzzer_runner.py#L149-L154) with allowlist targeting modified functions
- [JavaDirected fuzzing](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L147) for Java delta tasks
- [8 replicas with KEDA auto-scaling](https://github.com/Team-Atlanta/42-afc-crs/blob/main/deployment/crs-k8s/b3yond-crs/values.prod.yaml#L152-L157)

**Minimal Harness Prioritization**:
- No explicit harness ranking mechanism
- All harnesses fuzzed with focus on modified function paths

**No Vulnerability Candidate Ranking**:
- Traditional fuzzing approach without ML-based candidate scoring
- Coverage-guided fuzzing discovers vulnerabilities naturally

**Limited LLM Context Specialization**:
- **SeedGen**: No delta-specific seed generation strategies
- **PatchAgent**: Same prompts and tools for delta and full-scan tasks
- **SARIF**: [LLM diff analyzer mentioned](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/sarif/src/daemon.py) but not specialized for delta mode

**Architecture**: Traditional directed fuzzing (slicing + allowlist instrumentation) rather than LLM-guided vulnerability localization


# From ASC to AFC
**Q:** What are the key technical differences between ASC and AFC CRS versions?

**A:** _[Your answer here]_

---

**Q:** What lessons from ASC influenced AFC CRS design decisions?

**A:** _[Your answer here]_


# Gaming Strategy
**Q:** What bundling/submission strategies are proposed for maximizing scoring?

**A:** _[Your answer here]_

---

**Q:** How is submission timing optimized by CRS/module design?

**A:** _[Your answer here]_

---

**Q:** How are false positives filtered before submission for scoring? (accuracy multiplier estimation, PoV validation, patch testing)

**A:** _[Your answer here]_


# Unique/Interesting Practices
**Q:** Unique/interesting practices (e.g., Theori's logprobs-based classification, no-PoV patch submission)

**A:**
- Directed Fuzzing -> Slicing + AFL++ allow list + AFL/SeedGen (vs. traditional
  directed fuzzer) -> Might like Bullseye (more targeted path but not too
  focused).
  Similar for Java, so we need to only implement Java Slicer + Stock Jazzer.
  Does Jazzer have allowlist instrumentation?
- Grid search for patch agent parameters (vs. ours 6 different distinct agents)


# Corpus Preparation
**Q:** Corpus pre-operation pipeline?

**A:**: Similar to ours

- All POC seeds from OSS-Fuzz
- Classified using Magika
- Fallback: grouping by LLM

# Questions to authors
- Why don't you use traditional directed fuzzer (e.g. AFLGo?) Do you evaluate
  between them and find that slicing + AFL++/SeedGen works better??
  Or for easier and robust implementation? C/Java slicer + stock AFL++/Jazzer?
- Why no dict_gen for C? only Java. (Or I miss it??)
- Why only AI-based analysis for SARIF report in Java?
- Based on those questions? Do you implement more features for C because of
  lacking of human powers or other considerations?
- Do you do post-aixcc analysis why you perform so well on SARIF to get
  near-perfect scores?
