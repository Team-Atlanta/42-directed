# PatchAgent: Summary of Knowledge

## Short Version

This CRS employs a purely LLM-based approach for automated vulnerability patching without traditional program repair techniques. The system implements an autonomous agent architecture using tool-augmented large language models that iteratively explore vulnerable codebases through three specialized tools: viewcode for retrieving source code with optional Language Server Protocol hover hints, locate for symbol definition lookup via hybrid clangd and ctags indexing, and validate for testing patches against proof-of-concept inputs with sanitizer feedback.

The system enhances patch quality through vulnerability-specific guidance encoded as repair advice for over 40 Common Weakness Enumeration types, extracted from sanitizer reports including AddressSanitizer, MemorySanitizer, UndefinedBehaviorSanitizer for C/C++ and Jazzer for Java. To prevent repetitive failures, the agent receives counterexamples showing up to three previously failed patches. The implementation employs ensemble learning with 16 agent configurations exploring combinations of temperature values, counterexample quantities, and auto-hint modes for new vulnerability clusters, while using single random configurations for known clusters. Patches undergo multi-stage validation including format verification, compilation, and proof-of-concept replay.

The deduplication strategy operates at two levels: cross-profile patch reuse validates existing patches against new bug profiles before generating fresh attempts, while submission-time filtering eliminates dominated patches whose coverage sets are proper subsets of other patches, selecting only patches that incrementally expand bug profile coverage. Language-specific adaptations include distinct sanitizer mappings, prompt templates with varying formatting constraints, and separate LSP implementations. Delta-mode challenges apply vendor-provided diffs to source code before patching. Performance optimizations include builder object pooling, content-addressed build caching via MD5 hashing, and tar-based file transfers for network filesystem efficiency.

## Full Version

### Overall Patch Component Design

The patch component implements a two-stage pipeline consisting of patch generation followed by patch submission with deduplication. The system takes a purely LLM-based approach without incorporating traditional program repair techniques such as template-based fixes, static analysis transformations, or pattern-based mutations.

At the generation stage, bug profiles trigger an autonomous agent system built on LangChain's AgentExecutor framework. The LLM receives a task description, available tools, and vulnerability context, then autonomously decides which tools to invoke and how to reason about the problem. Unlike structured workflows with predetermined sequences, the agent makes independent decisions about exploration strategy, code locations to examine, and patch synthesis approaches.

The patch submission stage operates on rule-based algorithms for selecting optimal patches to submit, employing coverage analysis and dominance filtering to avoid redundant submissions. This separation allows the generation stage to explore diverse solutions while the submission stage ensures only high-quality, non-redundant patches reach the competition infrastructure.

### Techniques: LLM-Based and Traditional Approaches

The system relies exclusively on LLM-based patch generation with no traditional program repair components. The LLM agent operates through three tool APIs that enable autonomous codebase exploration:

The viewcode tool retrieves source code snippets with line numbers, accepting file paths and line ranges as parameters. When auto-hint mode is enabled for C/C++ projects, the tool augments responses with LSP hover information for symbols appearing on stack trace lines, providing type definitions and declarations to guide the LLM's understanding of vulnerable code context.

The locate tool performs symbol lookup using a hybrid approach that combines ctags indexing with clangd's definition-finding capabilities. The implementation employs fallback strategies: it first attempts fast-path location via language server, then parses viewed code regions with libclang to identify token locations, and finally searches stack traces for matching function names to locate definitions in vulnerable execution paths.

The validate tool applies patches and replays proof-of-concept inputs against all configured sanitizers, returning either success confirmation or detailed failure reports. The system limits each agent context to three validation attempts to prevent infinite retry loops. Before validation, patches undergo automatic revision to correct common formatting errors in LLM-generated diffs.

### Context Engineering for LLM-Based Generation

The LLM context construction integrates multiple information sources to guide patch synthesis. The sanitizer report undergoes parsing to extract the specific CWE type, then the system injects a structured summary containing the CWE description explaining the vulnerability nature and repair advice with 3-4 concrete fixing steps tailored to that weakness class. For example, heap buffer overflow advice recommends allocating sufficiently large buffers, adding explicit bounds checks, replacing unsafe string functions with safer alternatives, and checking for integer overflows in size calculations.

Counterexample sampling provides negative feedback by showing the LLM previous failed patches from the current bug profile, randomly selecting up to three examples to prevent the agent from repeating ineffective fix strategies. The counterexample_num hyperparameter controls this quantity, taking values of 0 or 3 in the ensemble configuration grid.

The auto-hint mechanism enables dynamic context augmentation during exploration for C/C++ projects. When the agent invokes viewcode on regions containing stack trace lines, the system queries the LSP hover endpoint for each alphabetic character on those lines, collecting unique symbol definitions and type information. This proactive hint injection helps the LLM understand data structure layouts and type relationships without requiring explicit locate invocations.

User prompts employ psychological persuasion techniques including monetary incentives and appeal to social impact, though these elements appear primarily cosmetic given the autonomous nature of LLM reasoning.

### Patch Validation Methods

Patches undergo a three-stage validation pipeline implemented in the PatchTask class. The check_patch stage verifies that the patch string follows valid git diff format with proper hunk headers, context lines, and addition/deletion markers. The build stage compiles the patched source code for each configured sanitizer, creating separate build artifacts per sanitizer type. The replay stage executes all proof-of-concept inputs against each sanitized binary, checking whether sanitizer reports still trigger.

Each validation stage can produce distinct failure modes tracked by the ValidationResult enum: invalid patch format, build failures, build timeouts, replay failures, and replay timeouts. Only patches achieving BugFree status across all stages advance to the patch database.

The validation tool available to the LLM agent invokes this pipeline and returns detailed error reports for any failure mode beyond simple bug detection, enabling the agent to iteratively refine patches based on concrete feedback about compilation errors or runtime failures.

### Patch Deduplication Strategies

The system implements two distinct deduplication mechanisms operating at different pipeline stages.

Cross-profile patch reuse occurs before generating new patches for a bug profile. The system queries the database for existing validated patches and tests each candidate against the new bug profile by executing the replay validation stage. If an existing patch successfully fixes all bugs in the new profile, the system creates a PatchBug association linking that patch to the new bugs without generating additional patches. This reuse mechanism exploits the common pattern where identical vulnerabilities appear across multiple bug profiles due to varied proof-of-concept inputs triggering the same underlying weakness.

Submission-time deduplication operates through coverage analysis and dominance filtering. The patch submitter first builds a coverage map associating each patch with the set of bug profiles it completely fixes. The system then identifies dominated patches where one patch's coverage set is a proper subset of another patch's coverage set, filtering these dominated patches as they provide strictly less value than their dominating counterparts. Finally, the submitter tracks which bug profiles have already been covered by previously submitted patches and only submits new patches that expand coverage to previously uncovered profiles, implementing an incremental coverage maximization strategy.

### Ensembling Approaches

The system employs two distinct ensembling modes controlled by the fast parameter to the agent generator. Generic mode executes a systematic grid search across 16 agent configurations formed by the Cartesian product of counterexample_num values [0, 3], temperature values [0, 0.3, 0.7, 1], and auto_hint values [True, False]. Each configuration creates a separate agent instance that attempts patch generation sequentially until one succeeds or all configurations exhaust their iteration budgets.

Fast mode generates a single agent with randomly selected auto_hint and temperature values, fixes counterexample_num to 0, and reduces max_iterations from 30 to 15. This mode targets known vulnerability patterns where the bug cluster already has associated profiles and extensive exploration provides diminishing returns.

The patch generator automatically creates fallback tasks by republishing failed generation attempts to the message queue with fast mode enabled and decremented priority. This retry mechanism ensures that expensive generic-mode failures receive additional fast-mode attempts without manual intervention.

Multi-model deployment provides another ensembling dimension through separate Kubernetes deployments for GPT-4 and Claude model instances, allowing the system to leverage different LLM reasoning capabilities and training data distributions.

### Language-Specific Handling for C and Java

C/C++ and Java challenges receive distinct treatment across multiple system components.

Prompt templates differ in their formatting constraints. C/C++ prompts require at least 3 lines of context at hunk boundaries and generically reference sanitizer reports, while Java prompts require at least 1 line of context, prohibit comments in patches, and mandate importing new packages. The user prompts mention ASAN for C/C++ and Jazzer for Java despite both templates receiving dynamically constructed sanitizer reports that specify the actual sanitizer type.

LSP implementations employ different strategies. The C/C++ HybridCServer combines ctags for fast symbol location with clangd for precise definition lookup and hover information, requiring compile_commands.json generation through Bear during the build process. The Java LSP uses tree-sitter for parsing without requiring compilation database generation.

Sanitizer mappings associate C/C++ with AddressSanitizer, MemorySanitizer, UndefinedBehaviorSanitizer, and LeakSanitizer, while Java uses Jazzer which the OSS-Fuzz builder maps to the address sanitizer type for consistency with infrastructure expectations.

Patch revision procedures differ in complexity. The revise_clike_patch function performs extensive transformations including expanding function signatures with libclang, adjusting context line counts, normalizing diff headers, and correcting hunk boundary markers. The Java revise_patch function only updates hunk headers without content transformation.

Auto-hint functionality operates only for C/C++ projects through the clangd LSP integration. Java projects do not receive LSP hover hints even when auto_hint is enabled, though the parameter remains part of the agent configuration.

### Delta-Mode Challenge Handling

Delta-mode challenges provide vendor-supplied diffs that modify the base source code before fuzzing begins. The AIXCCBuilder constructor detects delta-mode through the diff_path parameter, creates a pre-workspace directory, copies the focus directory to the pre-workspace, applies the vendor diff using the patch command with -p1 flag, then initializes the OSSFuzzBuilder with the pre-workspace path instead of the original source path.

This approach enables the patch generator to work with the modified source code while maintaining the same tool APIs and validation pipeline. The patch generator applies its fixes on top of the vendor-provided changes, and validation tests the combined patch against proof-of-concept inputs.

The system searches for .diff files in the provided diff_path directory and applies the first match, breaking after successful application. This single-diff assumption appears to match the competition infrastructure where each delta-mode challenge provides exactly one vendor diff.

### Performance Optimizations

Builder pool caching maintains a dictionary mapping task identifiers to AIXCCBuilder instances, avoiding repeated expensive operations including Docker container initialization, source code copying, and LSP server startup. Builders persist across multiple patch generation attempts for the same task.

Build indicator files implement content-addressed caching through MD5 hashing of patch content concatenated with sanitizer type. Before building, the system checks for .build indicator files in the hash-named workspace directory and skips compilation if the indicator exists. This optimization proves particularly valuable for the ensemble grid search where multiple agent configurations may propose identical patches.

Tar-based copying addresses network filesystem performance degradation when copying directories containing many small files. Rather than using shutil.copytree which issues individual operations per file, the system creates a tar archive locally, copies the single archive file over NFS, then extracts the archive at the destination. This batching approach significantly reduces NFS protocol overhead.

Replay timeout defaults to 360 seconds per proof-of-concept input, with various timeout thresholds throughout the builder and validator components to prevent resource exhaustion from infinite loops or exponential complexity in vulnerable code.

### Testing Infrastructure

The patchagent component lacks a dedicated test directory, relying instead on integration testing through the validation pipeline itself. The system tests patch correctness by executing real proof-of-concept inputs against sanitized binaries and checking for sanitizer output, providing end-to-end validation but limited unit test coverage for individual components.

Other components contain test files including primefuzz tests for fuzzing infrastructure and triage test_parser for sanitizer report parsing, but these do not directly exercise patchagent functionality.

The validation stages themselves serve as a comprehensive test suite, verifying patch format correctness, compilation success, and runtime behavior preservation. The ValidationResult enum captures distinct failure modes, enabling detailed diagnosis of patch quality issues.

### Unique and Interesting Techniques

The hybrid language server for C/C++ combines complementary indexing approaches, using ctags for fast symbol location across large codebases and clangd for precise definition lookup and type information. This hybrid design works around limitations of each tool: ctags lacks semantic understanding but provides fast regex-based search, while clangd offers precise analysis but requires compilation database setup and longer initialization.

Compile_commands.json generation employs Bear running inside OSS-Fuzz Docker containers, with pexpect scripting to interact with container shells and capture build commands. This infrastructure setup enables clangd to provide accurate hover information despite complex build systems.

The patch revision system implements automatic formatting correction for LLM-generated diffs, addressing common errors like incorrect context line counts, malformed hunk headers, and missing file path prefixes. The revise_clike_patch function even performs libclang parsing to expand abbreviated function signatures that LLMs sometimes generate.

Early termination through stop_indicator callbacks enables the system to halt ensemble exploration when another parallel process successfully generates a validated patch for the same bug profile. The is_available_bug_profile check prevents wasted computation on already-solved vulnerabilities.

Priority-based message queue management decrements priority on retry, ensuring that repeatedly failing tasks gradually yield queue position to fresh tasks. The separation of fast and generic patch modes through distinct queue messages with different priorities allows the system to balance thorough exploration against rapid iteration.

## Context Engineering Q&A

### What information is included in the LLM context?

The LLM context comprises several integrated components. The system prompt explains the patch generation task, describes available tools with their parameter schemas and return formats, provides examples of patch syntax, and emphasizes best practices like viewing code before modification and validating patches before claiming success.

The user prompt template injects the sanitizer report summary, which contains the raw sanitizer output, the identified CWE type, the CWE description explaining the vulnerability nature, and the CWE-specific repair advice with 3-4 actionable fixing steps. For example, use-after-free repair advice recommends setting pointers to NULL after freeing, ensuring single deallocation per block, systematic allocation tracking, and considering memory access reordering.

Counterexamples provide negative examples by showing previous failed patch attempts for the current bug profile, with random sampling selecting up to three examples to limit context length while maintaining diversity. The counterexample_num hyperparameter controls this quantity, taking values of 0 or 3 in the ensemble grid.

The project name helps ground the LLM in the specific codebase context, though prompts do not include broader project documentation or architectural descriptions.

### What are the inputs and expected output format?

Primary inputs include the bug profile identifier that specifies which vulnerability to patch, the sanitizer report containing error details and stack traces, the project name and source code location, and the list of configured sanitizers to test against.

The expected output format follows git diff conventions with strict requirements: file paths must use a/ and b/ prefixes, hunk headers must specify line numbers and line counts for both original and modified versions, additions must start with + at line beginning, deletions must start with - at line beginning, unchanged context lines must start with space, and C/C++ patches require at least 3 context lines at hunk boundaries while Java patches require at least 1 line.

The LLM agent must invoke the validate tool to test patches before considering the task complete. Successful validation triggers a PatchFoundException that terminates the agent loop and stores the patch, while failed validation returns error reports that the agent can use to refine its approach.

### What feedback mechanisms guide the LLM?

Validation feedback provides the primary guidance mechanism. When the LLM invokes validate with a candidate patch, the tool returns detailed failure reports for non-bug-detection failures including compilation errors with specific error messages, build timeouts, replay failures with sanitizer output showing continued vulnerability triggering, and replay timeouts. The agent can iteratively refine patches based on this concrete feedback, though the system limits each agent context to three validation attempts.

Counterexample feedback shows the LLM previous failed patch attempts from earlier agent contexts working on the same bug profile, helping the agent avoid repeating ineffective strategies. The system randomly samples these counterexamples to provide diverse negative examples without overwhelming the context window.

Tool invocation feedback occurs when locate fails to find symbol definitions or viewcode cannot locate requested files, prompting the agent to adjust its exploration strategy with alternative symbol names or different file paths.

The system does not employ SAST tools, coverage-guided patch refinement, root cause analysis beyond sanitizer reports, or fine-tuning based on patch success rates. Feedback comes exclusively from the validation pipeline executing patches against real proof-of-concept inputs and the tool APIs returning success or failure for exploration requests.

## Autonomous Agent vs. Agentic Workflow

Patch generation implements a fully autonomous agent architecture where the LLM independently decides tool invocations, exploration sequences, and reasoning steps through LangChain's AgentExecutor framework. The agent receives a task description and tool specifications, then autonomously generates a solution without predetermined workflow steps.

Non-autonomous components include the patch submission selector which implements rule-based coverage analysis and dominance filtering without LLM involvement, the patch validation pipeline which executes a fixed sequence of format checking, building, and replay testing, and the ensembling system which explores a predefined hyperparameter grid rather than using LLM-directed configuration selection.

## Technique Differences Between C and Java Challenges

C/C++ challenges use a hybrid LSP combining clangd for semantic analysis and ctags for fast symbol lookup, requiring compile_commands.json generation through Bear. Java challenges use tree-sitter for parsing without requiring compilation databases.

C/C++ patches test against AddressSanitizer, MemorySanitizer, UndefinedBehaviorSanitizer, and LeakSanitizer, detecting memory corruption, uninitialized reads, undefined behavior, and memory leaks. Java patches test against Jazzer which detects injection vulnerabilities, path traversal, remote code execution, and other application-level security issues.

C/C++ prompts require at least 3 context lines at hunk boundaries and undergo extensive patch revision including function signature expansion via libclang. Java prompts require at least 1 context line, prohibit comments in patches, mandate explicit import statements for new packages, and undergo only hunk header revision.

C/C++ projects receive auto-hint support through clangd LSP hover information on stack trace lines. Java projects do not have auto-hint implementation despite the parameter existing in agent configuration.

The CWE repair advice differs between languages, with C/C++ focusing on memory safety issues and Java emphasizing injection prevention and secure API usage.

## Techniques for Delta-Mode Challenges

Delta-mode challenges provide vendor-supplied diffs that modify the base source code before fuzzing begins. The AIXCCBuilder constructor detects delta-mode through the diff_path parameter, creates a pre-workspace directory, copies the focus directory to the pre-workspace, applies the vendor diff using the patch command with -p1 flag, then initializes the OSSFuzzBuilder with the pre-workspace path instead of the original source path.

This approach enables the patch generator to work with the modified source code while maintaining the same tool APIs and validation pipeline. The patch generator applies its fixes on top of the vendor-provided changes, and validation tests the combined patch against proof-of-concept inputs.

The system searches for .diff files in the provided diff_path directory and applies the first match, breaking after successful application. This single-diff assumption appears to match the competition infrastructure where each delta-mode challenge provides exactly one vendor diff.

## Disabled Components

The codebase contains several implemented-but-disabled features that reveal the team's original plans and subsequent strategic decisions to optimize for competition performance.

### Functional Test Validation

The validation pipeline includes a function_test stage that would verify patches preserve intended program functionality by running project-specific test suites. However, the implementation is a stub that always returns success without executing any tests. The builder.function_test() method contains only a pass statement, effectively disabling regression testing. This decision likely prioritized patch generation speed over quality assurance, accepting the risk that patches might fix vulnerabilities while breaking unrelated functionality. The ValidationResult enum still includes FunctionTestFailed and FunctionTestTimeout states, indicating the infrastructure was designed to support this feature.

### Cross-Profile Validation Filtering

A separate reproducer component continuously performs comprehensive cross-profile validation, testing all generated patches against all bug profiles within each task. The reproducer runs in an infinite loop with 20-second polling intervals, builds patches in Docker containers using hash-based workspaces for caching, replays proof-of-concept inputs against sanitized binaries, and populates the PatchBug database table with repaired status indicating whether each patch fixes each bug. Despite this substantial computational investment, the patch submitter's filtering logic that would exclude patches failing cross-profile validation is commented out. The submitter ignores PatchBug.repaired values and selects patches based only on coverage analysis. This "ghost mode" operation suggests the team found strict cross-profile filtering too restrictive, opting instead to maximize submission volume while keeping the validation infrastructure ready for potential reactivation. The reproducer represents significant engineering effort including Docker integration, build optimization, and race condition handling, all deployed in production but having no influence on submission decisions.

### Java Auto-Hint Support

The auto-hint mechanism that provides LSP hover information for symbols on stack trace lines is fully implemented for C/C++ projects but completely absent for Java. The Java agent accepts the auto_hint parameter and passes it through the configuration chain, but the Java LSP implementation does not include hover information retrieval or injection into viewcode responses. This creates an asymmetry where C/C++ agents receive automatic type definitions and declarations for vulnerable code locations while Java agents must explicitly invoke locate for the same information. The parameter exists in Java agent configurations purely for interface consistency with C/C++ agents.

### Report Purification and Chain Compression

The academic PatchAgent paper describes two optimizations not present in the competition implementation. Report purification would transform raw sanitizer output into LLM-friendly formats by removing noise and highlighting relevant information. Chain compression would optimize tool call sequences by identifying dominator actions that make subsequent calls redundant. The competition implementation uses raw sanitizer reports without preprocessing and does not analyze or compress the agent's tool invocation sequences. These omissions suggest the team prioritized implementation simplicity and development speed over the incremental improvements these optimizations might provide.

### POV-less Patch Generation

The patch generator includes a PatchMode.none case in patch_generator/utils.py that handles bugs without proof-of-concept inputs. However, this code path only logs a "fixme" event and returns None without attempting patch generation. The comment labels this as "Mock mode only!!!" indicating it serves testing or development purposes rather than production functionality. The validation pipeline fundamentally requires proof-of-concept inputs for the replay stage, making POV-less patching incompatible with the current architecture without significant redesign.

### Strategic Implications

These disabled features reveal a consistent pattern: the team built comprehensive quality assurance infrastructure including functional testing, cross-profile validation, and optimization techniques from academic research, then strategically disabled these components to maximize patch generation throughput and submission volume. The competition time pressure and scoring mechanics apparently favored quantity over quality, leading to architectural compromises where safety nets were left in place but deactivated. The substantial engineering investment in disabled features suggests these were not abandoned experiments but deliberate production decisions to tune the system for competition performance while maintaining the option to re-enable stricter validation if needed.

## Supporting Evidence

### Prompts and Context Engineering

- [C/C++ system prompt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L1-L70): Explains task, tools (viewcode, locate, validate), and patch format requirements
- [C/C++ user prompt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py#L72-L80): Injects sanitizer report and counterexamples with psychological persuasion
- [Java system prompt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/prompt.py#L1-L80): Adapted for Java with stricter formatting rules
- [Java user prompt](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/prompt.py#L82-L90): Similar structure with Jazzer report reference

### CWE-Based Repair Advice

- [CWE enumeration](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py#L1-L57): Defines 40+ vulnerability types across sanitizers
- [CWE descriptions](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py#L59-L105): Explains each vulnerability's nature
- [CWE repair advice](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/parser/cwe.py#L107-L370): Provides 3-4 concrete fixing steps per CWE type

### Agent Implementation and Tools

- [Agent generator](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/generator.py#L12-L55): Implements ensembling with generic mode (16 configs) and fast mode (1 random config)
- [CommonCLikeAgent](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/common.py#L97-L115): LangChain AgentExecutor setup with tool binding
- [Counterexample sampling](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/common.py#L117-L130): Random sampling of failed patches from agent contexts
- [viewcode tool](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/internal.py#L24-L70): Code retrieval with optional auto-hint via LSP hover
- [locate tool](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/internal.py#L73-L139): Hybrid symbol lookup using ctags and clangd
- [validate tool](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/internal.py#L142-L164): Patch validation with 3-attempt limit

### Validation Pipeline

- [ValidationResult enum](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L13-L23): Defines 9 distinct validation outcome states
- [Validation pipeline](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/task.py#L83-L113): Three-stage checking (format, build, replay)
- [Patch revision](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/proxy/utils.py#L11-L110): Auto-formats LLM-generated diffs before validation

### Deduplication and Submission

- [Patch reuse query](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/aixcc/utils.py#L12-L47): Searches for existing validated patches to test against new bug profiles
- [Coverage map building](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_submitter/main.py#L92-L147): Associates patches with bug profiles they completely fix
- [Dominated patch filtering](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_submitter/main.py#L172-L186): Removes patches whose coverage is proper subset of others
- [Incremental coverage selection](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_submitter/main.py#L201-L212): Only submits patches covering new bug profiles

### Language-Specific Components

- [HybridCServer](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/lsp/hybridc.py): Combines ctags and clangd for C/C++ analysis
- [JavaLanguageServer](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/lsp/java.py): Tree-sitter-based parsing for Java
- [Sanitizer mapping](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/ossfuzz.py#L36-L47): Maps C/C++ to ASAN/MSAN/UBSAN/Leak, Java to Jazzer

### Delta-Mode and Optimizations

- [AIXCCBuilder delta-mode](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_generator/builder/builder.py#L20-L42): Applies vendor diff to pre-workspace before building
- [Builder pool caching](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_generator/builder/pool.py#L17-L21): Reuses expensive builder objects per task
- [Build indicator files](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/ossfuzz.py#L77-L97): Content-addressed caching via MD5 hash
- [Tar-based NFS copy](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/primefuzz/tests/benchmark_copy_cifs.py): Optimizes network filesystem performance

### Disabled Components

- [Functional test stub](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/builder/builder.py#L104): Empty implementation that always passes
- [Reproducer cross-profile validation](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/reproducer/reproduce.py#L69-L154): Active validation with disabled filtering
- [Submitter filtering logic](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/submitter/workers.py#L106-L150): Commented-out cross-profile validation filter
- [Java auto-hint parameter](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/common.py): Accepted but not implemented
- [POV-less mock mode](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patch_generator/utils.py#L189-L192): Returns None without generating patches
