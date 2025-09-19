# Questionnaire
My answer by digging the source code.

# System Architecture

## General Design Choice
**Q:** Is the CRS an LLM-centric system or a traditional toolchain with LLM
augmentation?

**A:** _[Your answer here]_

---

**Q:** How does LLM integration differ between bug finding and patching modules? Why?

**A:** _[Your answer here]_


## Infrastructure
**Q:** What framework manages compute resources? (Kubernetes, custom scheduler built on Azure API, etc.)

**A:** _[Your answer here]_

---

**Q:** How are CPU cores, memory, and nodes scheduled across tasks?

**A:** _[Your answer here]_

---

**Q:** Does LLM participate in resource scheduling?

**A:** _[Your answer here]_

---

**Q:** How does the system handle failures? (component crashes, VM node failures, network partitions)

**A:** _[Your answer here]_


# LLM

## LLM Component Design
**Q:** What LLM application frameworks or scaffolds are used? (e.g., LangChain, MCP, custom frameworks, Claude Code/Cursor/Gemini wrappers)

**A:** _[Your answer here]_

---

**Q:** How are agentic components designed?

**A:** _[Your answer here]_

- Tool selection and integration
- Prompt engineering strategies
- Iterative research loop design

---

**Q:** What prompting techniques are employed? (e.g., CoT, few-shot, context engineering, deep research loops, RAG, voting, ensembles)

**A:** _[Your answer here]_

---

## LLM Infrastructure
**Q:** Did you use any framework or implemented one? (e.g., LiteLLM Proxy)

**A:** _[Your answer here]_

---

**Q:** Did you use any observability tool? (OpenLIT, Traceloop, Phoenix, etc.)

**A:** _[Your answer here]_

---

**Q:** How did you handle LLM failure? (rate limit, timeout, …)

**A:** _[Your answer here]_


## LLM Model/Quota Usage
**Q:** How are LLM quotas and throughput managed?

**A:** _[Your answer here]_

---

**Q:** Token budget allocation per task/component

**A:** _[Your answer here]_

---

**Q:** Model selection strategy (reasoning vs non-reasoning models, price/performance, priority hierarchy)

**A:** _[Your answer here]_

---

**Q:** Downgrade strategy when quota exhausted

**A:** _[Your answer here]_

---

**Q:** What controls LLM usage across components? (LiteLLM, custom rate limiters, priority queues)

**A:** _[Your answer here]_


# Bug Finding

## Overall Bug Finding Strategy
**Q:** What is the overall bug finding strategy and pipeline?

**A:** _[Your answer here]_

---

**Q:** Are there bug-type-specific finding approaches or components?

**A:** _[Your answer here]_


## Static Analysis
**Q:** How is static analysis used to guide other components? (call graph, program slicing for LLM context)

**A:** _[Your answer here]_

---

**Q:** How do dynamic techniques and LLM enhance static analysis? (runtime feedback, LLM-guided patterns)

**A:** _[Your answer here]_


## Dynamic Analysis / Fuzzing
**Q:** What fuzzing strategies are implemented? (ensemble, concolic, directed, coverage-guided)

**A:** _[Your answer here]_

---

**Q:** How does LLM augment fuzzing? (seed/dictionary/oracle generation, mutator/generator synthesis, feedback mechanisms)

**A:** _[Your answer here]_

---

**Q:** Which sanitizers are deployed and what is the strategy considering performance/coverage trade-offs?

**A:** _[Your answer here]_

---

**Q:** How are fuzzing resources allocated across targets? (time-slicing, worker distribution, harness assignment)

**A:** _[Your answer here]_

---

**Q:** Does fuzzing provide feedback to other bug finding components? (program dynamics for LLM context, crash validation)

**A:** _[Your answer here]_

## Build-Time Configuration
**Q:** What custom instrumentation is added?

**A:** _[Your answer here]_

---

**Q:** How does the CRS prevent build breakage from custom instrumentation?

**A:** _[Your answer here]_


## Non-Memory Safety Bugs
**Q:** How does the CRS handle non-memory safety findings? (logic bugs, OOM, timeout, stack overflow, uncaught exceptions)

**A:** _[Your answer here]_


## Bug/Finding Processing
**Q:** How are duplicate findings detected and deduplicated? (stack-based, root cause, patch-based grouping)

**A:** _[Your answer here]_

---

**Q:** What criteria determine finding prioritization for submission?

**A:** _[Your answer here]_


## Fallback Mechanisms
**Q:** What fallback strategies exist when advanced techniques fail? (vanilla libFuzzer fallback, static-only mode)

**A:** _[Your answer here]_


# Patch Generation
**Q:** What patch generation strategies are employed?

**A:** _[Your answer here]_

---

**Q:** How are patches validated? (crash reproduction, regression tests, functional tests, post-patch fuzzing)

**A:** _[Your answer here]_

---

**Q:** Are build processes optimized for patching? (incremental builds, cached compilation artifacts)

**A:** _[Your answer here]_

---

**Q:** Are there bug-type-specific patching strategies?

**A:** _[Your answer here]_

---

**Q:** Does the CRS generate patches without proof-of-vulnerability (no-PoV patches)?

**A:** _[Your answer here]_


# SARIF
**Q:** How are SARIF reports validated? (PoV-based validation, static verification, no-PoV)

**A:** _[Your answer here]_

---

# Delta Mode
**Q:** What technical adaptations are made for delta mode? (harness prioritization, vulnerability candidate ranking, LLM context specialization)

**A:** _[Your answer here]_


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

**A:** _[Your answer here]_


# Corpus Preparation
**Q:** Corpus pre-operation pipeline?

**A:**: Similar to ours

- All POC seeds from OSS-Fuzz
- Classified using Magika
- Fallback: grouping by LLM
