# Roadmap of the CRS study

## Overview

The [local copy of blog](blog.md) provides the overview of the 42-b3yond-6ug team's CRS (in section "About 42-b3yond-6ug").
According to the blog, its main component is a traditional fuzzing pipeline, with LLMs assisting on the following components:

- [Seedgen Component](seedgen.md) - LLM-powered seed generation with multiple strategies
  - [Full Mode Deep Dive](seedgen-fullmode.md) - Compiler instrumentation and dynamic analysis for C/C++
  - [Mini Mode Deep Dive](seedgen-minimode.md) - Lightweight static analysis for all languages
  - [MCP Mode Deep Dive](seedgen-mcpmode.md) - Model Context Protocol for deep code analysis (currently enabled)
  - [Codex Mode Deep Dive](seedgen-codexmode.md) - Autonomous codebase exploration via external CLI tool (not used in competition)
- [Corpus Grabber Component](corpus_grabber.md)  
- [Patch Agent Component](patch_agent.md)
- [SARIF Component](sarif.md)


# references

- [blog](https://lkmidas.github.io/posts/20250808-aixcc-recap/), a good blog which summarizes their systems and their impressions of other systems
