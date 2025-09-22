# Summary

[Introduction](./readme.md)

## System Overview

- [System Architecture](./message-flow-architecture.md)
- [Blog Overview](./blog.md)

## Core Components

- [Bug Finding](./bug-finding.md)
  - [Fuzzing Components](./fuzzing.md)
    - [BandFuzz](./bandfuzz.md)
    - [PrimeFuzz](./primefuzz.md)
    - [Prime Build](./prime-build.md)
    - [Directed Fuzzing](./directed.md)
  - [Seed Generation](./seedgen.md)
    - [Full Mode Deep Dive](./seedgen-fullmode.md)
    - [Mini Mode Deep Dive](./seedgen-minimode.md)
    - [MCP Mode Deep Dive](./seedgen-mcpmode.md)
    - [Codex Mode Deep Dive](./seedgen-codexmode.md)
    - [How Seeds Are Used](./how-seeds-used.md)
  - [Analysis Components](./analysis.md)
    - [Triage Component](./triage.md)
    - [Slice Analysis](./slice.md)
    - [JavaSlicer](./javaslicer.md)
    - [Cmin++ (Corpus Minimization)](./cminplusplus.md)
  - [Corpus Management](./corpus_grabber.md)

- [Patch Generation](./patch_agent.md)
  - [PatchAgent Prompts](./patchagent-prompts.md)
  - [PatchAgent Reproducer](./patchagent-reproducer.md)

- [SARIF Processing](./sarif.md)

- [Infrastructure](./infrastructure.md)
  - [Gateway](./gateway.md)
  - [Scheduler](./scheduler.md)
  - [Submitter](./submitter.md)
  - [Database](./db.md)

## Reference Materials
- [Yu-Fu's Notes](./yufu.md)
