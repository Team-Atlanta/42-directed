# Two-year Recap: A Story of 42-b3yond-6ug and AIxCC

**Author**: Midas  
**Date**: 2025-08-07  
**Category**: AI  

## Table of Contents

- [Forewords](#forewords)
- [What is AIxCC?](#what-is-aixcc)
  - [Competition Overview](#competition-overview)
  - [AFC Technical Details](#afc-technical-details)
  - [Scoring Overview](#scoring-overview)
- [About 42-b3yond-6ug](#about-42-b3yond-6ug)
  - [Our Team](#our-team)
  - [ASC Quick Recap](#asc-quick-recap)
  - [Our Mindset](#our-mindset)
  - [Our CRS](#our-crs)
  - [The Experience](#the-experience)
  - [Testing](#testing)
- [Peeking into other Teams' CRSs](#peeking-into-other-teams-crss)
  - [Categories of CRSs](#categories-of-crss)
  - [Trail of Bits - ButterCup](#trail-of-bits---buttercup)
  - [Lacrosse](#lacrosse)
  - [Shellphish - Artiphishell](#shellphish---artiphishell)
  - [Team Atlanta - Atlantis](#team-atlanta---atlantis)
  - [Theori - RoboDuck](#theori---roboduck)
  - [All You Need Is A Fuzzing Brain](#all-you-need-is-a-fuzzing-brain)
- [Conclusion](#conclusion)

> *Note: Use the table of contents above to navigate to the section that you are interested in.*

## Forewords

Well, it's been 2 years since I last updated my blog. Time sure does fly. A few days ago, I couldn't even recall how to make a new post and update this blog!

Anyhow, regarding what I've been doing the last 2 years - you might've heard about a HUGE competition organized by DARPA and ARPA-H, called the [**AI Cyber Challenge**](https://aicyberchallenge.com/), or **AIxCC**. It's a 2-year-long competition that I participated in as a core member of my wonderful team, [**42-b3yond-6ug**](https://b3yond.org/). It was a great experience with ups and downs, challenges and triumphs. We pretty much abandoned many things - like CTFs, coursework, and even research projects - to focus all of our efforts on this competition. That said, now that the competition is officially over, I have the itch to start writing something again!

So with this post, I just want to write whatever comes to mind about my team's and my own journey in AIxCC, looking back. I'd probably only describe things at a very high-level 10,000-foot view here, but do expect full technical writeups about our team's system later on our team's blog.

With all that out of the way, let's get into it!

## What is AIxCC?

### Competition Overview

AIxCC is a large-scale competition organized by **DARPA** and **ARPA-H** that tries to bridge the gap between rapidly emerging AI technologies and cybersecurity. From the official site:

> "The Artificial Intelligence Cyber Challenge (AIxCC) is a two-year competition that brings together the best and brightest in AI and cybersecurity to safeguard the software critical to Americans. AIxCC competitors are designing, testing, and improving novel AI systems to automatically secure this critical code. Cumulative prizes total $29.5 million to teams with the best systems."

So, in shorter and simpler terms, the competition is about embracing AI to build an autonomous system that can secure code - and win BIG money. "Securing code" here means finding vulnerabilities and fixing them.

The 2-year timeline of AIxCC was roughly this:

1. The competition was announced at Black Hat USA, August 2023.
2. Open Track and Small Business Track registration and proposal.
3. Small Business Track winners announced in March 2024 (7 teams).
4. Preliminary events leading to the AIxCC Semifinal Competition (ASC).
5. The ASC at DEFCON 32, August 2024, announcing 7 winning teams.
6. Three exhibition rounds leading to the AIxCC Final Competition (AFC).
7. The AFC announcement at DEFCON 33, August 2025, announcing the top 3 winners.

I'll mostly only talk about the AFC in this post, since I personally feel like I learned the most and had the best experiences during the second year of development leading to the Finals. I believe both our system and the competition infrastructure weren't mature enough at the time of the ASC and earlier, and the infrastructure was quite different.

That being said, our team 42-b3yond-6ug did win the Small Business Track prize and the ASC, which are great achievements in and of themselves.

### AFC Technical Details

In this competition, each team is expected to build a Cyber Reasoning System (CRS) that can autonomously identify vulnerabilities in real-world projects' codebases and fix them accordingly - **without** human intervention. During a competition round, there are **only two** entities interacting with each other: the competition API sending the tasks, and the CRS's API receiving and processing the tasks. Each team is given a large amount of budget per round (5 figures!) for compute resources and LLM usage to deploy their CRS.

In the AFC, there are three unscored exhibition rounds and one final scored round. For each round, the CRS must be running and handling tasks at all times for several days - up to 10 days in the final round. The tasks are called **Challenge Projects (CPs)**, which are real-world projects (such as libpng, libxml2, Apache, etc.), with or without synthetic vulnerabilities, that are compatible with the OSS-Fuzz infrastructure.

At the beginning of AIxCC in 2023, the organizers were very ambitious with the variety of CPs that teams were expected to deal with, including projects written in many different programming languages. However, after many considerations and rounds of feedback, the ASC narrowed the scope down to just C and Java user space projects, as well as the Linux kernel. In the AFC, the kernel was also removed, leaving only C and Java OSS-Fuzz-compatible projects. That's not to say the scope became small - in fact, the CRS had to handle a total of **60 tasks across 30 different projects** in the final round, with a budget of **$85,000 in Azure compute resources** and **$50,000 in LLM usage**.

There are two types of tasks that the CRS is expected to handle:

1. **Full-scan** tasks: The CRS receives two tarballs - one containing the CP's source codebase, and another containing the OSS-Fuzz tooling used to build and run that codebase. For a full-scan task, *any* vulnerability found in the codebase is eligible for scoring.
2. **Delta-scan** tasks: In addition to the codebase and fuzz tooling, the CRS also receives a DIFF file for the codebase. For a delta-scan task, only vulnerabilities introduced in the DIFF - or vulnerabilities that were already in the codebase but became *reachable* after the DIFF was applied - are eligible for scoring.
3. In addition, during the timeline of any given task, a **SARIF report** might be sent to the CRS. SARIF is a standardized format for representing static analysis results - e.g., which area of code contains a bug, what type of bug it is, etc. The CRS can respond with whether the SARIF report is a true positive to earn points.

One thing to note is that **all** challenge tasks and CRSs will be **open-sourced** at some point after the competition is over - which to me is super hyped. I can't wait to show the world what we've achieved, to learn in detail what other teams have cooked up, and the challenge tasks could be refactored into a really nice benchmark dataset as well.

### Scoring Overview

The scoring algorithm is quite complex - as it should be - to ensure that all scenarios are accounted for and scored appropriately. The official scoring guide that we received in the end was super long (40 pages!), but here, I'll just list the key points:

- There are 4 types of scorable submissions that the CRSs can submit to the competition API: Proofs-of-Vulnerability (PoVs), Patches, SARIF Assessments, and Bundles.
- For the purpose of this competition, any input that triggers a crash in the target project is considered a **PoV**. This includes sanitizer crashes (such as ASAN, MSAN, UBSAN, etc. for C projects, and JAZZER for Java), as well as libFuzzer crashes, such as timeouts and out-of-memory. (libFuzzer is the default fuzzer in OSS-Fuzz.) Each correct PoV is worth 2 points, or 0 points otherwise.
- A **Patch** is a DIFF file that can be applied to the CP's codebase to mitigate one or more vulnerabilities. Patches are assessed manually by the organizer using the ground truth PoV, and all variant PoVs of the same bug submitted by **all teams**. This means that even if a patch can prevent your team's PoV from crashing the CP, it might still not be a correct patch if other teams' submitted PoVs can still crash it. Each correct patch is worth 5 points, or 0 points otherwise.
- A **SARIF Assessment** is simply a binary answer - correct or incorrect - to assess whether the given SARIF report is a true positive or not. Each correct SARIF assessment is worth 1 point, or 0 points otherwise.
- A **Bundle** is an association between PoVs, Patches, and SARIF Assessments, to gain bonus points. For example, if Patch A can mitigate PoV 1, teams can submit a bundle of (Patch A, PoV 1). However, an incorrect bundle will result in a *deduction* in points, so it's a risky bonus submission.
- For each task, there is a global **Accuracy Multiplier (AM)** that affects the score of all types of submissions for that task. An unscorable submission (e.g., a PoV that doesn't crash, a patch that doesn't fix any vulns, etc.) will lower the AM. Interestingly, duplicated PoV submissions (e.g., 2 different PoVs that trigger the same bug) don't negatively affect the AM, but duplicated patch submissions (e.g., 2 patches that fix the same bug) do. This creates a **gamesmanship** element that caused us - and I believe many other teams as well - a whole lot of headaches to minimize AM penalty.
- There is a **Time Multiplier (TM)** element as well. This simply means that during the timeline of a task, earlier submissions score more - from 100% of the points at minute 0, down to 50% at the end. Notably, in the case of duplications, only the **final** duplicate is scored, which means we still prefer not to submit duplicates, in the interest of TM.

There are a bunch of other finer details about how the organizers do deduplication on PoVs and patches to prevent duplicated scoring and such. However, I won't dive into them here. To be honest, at this point, we aren't even 100% sure about their exact methods of doing so - but I believe the points I listed above are sufficient to understand the gist of the competition.

## About 42-b3yond-6ug

### Our Team

[**42-b3yond-6ug**](https://b3yond.org/) is a collaborative team of students and professors from five universities, led by Northwestern University in partnership with the University of Waterloo, University of Utah, University of Colorado Boulder, and University of New Hampshire.

Our team's name pays homage to Douglas Adams's "The Hitchhiker's Guide to the Galaxy," reflecting our mission to move beyond mere bug identification toward developing robust, practical solutions.

In the AFC, our team has about 15 members who worked full-time on our CRS. In addition, we also hire a few programmers in the industry with specific engineering experience to help us with some finer details.

As a core member of the team, during the ASC, I was responsible for performing static analysis on the Linux kernel fuzzing harnesses to generate structured input formats that could aid kernel fuzzing. However, in the AFC, since the kernel challenge was removed, I shifted focus to become a co-author of our seed generation component, the primary author of our triage and corpus grabber components (more about them later), the main tester of our CRS, and helped make decisions related to the structure and scaling of our CRS infrastructure.

### ASC Quick Recap

The ASC didn't have exhibition rounds leading up to the main event. All the CRSs were officially executed only once, with **much lower** budgets than the AFC (hundreds of times lower), live for 1 day at DEFCON 32. The ASC challenges consisted of 5 entire codebases from 2 userspace C projects (Nginx & SQLite3), 2 Java projects (Jenkins & Tika), and the Linux kernel. If I remember correctly, the challenges were given one after another and lasted for 4 hours each. According to the official writeups, there were a total of 59 synthetic vulnerabilities across the 5 projects, and collectively, all teams found 22 of them, patched 15, and one team (Team Atlanta) found a 0-day.

As for our CRS, it was a simple fixed 3-node system deployed as a Kubernetes cluster. The system consists of static analysis components, multiple fuzzers (AFL, Jazzer, Syzkaller), and an LLM Patch Agent. I don't have the exact number of bugs and patches that we found during the ASC anymore, but according to [the official summary](https://dashboard.aicyberchallenge.com/ascsummary), by vulnerability class, our team discovered bugs in 4 out of 8 different classes and patched bugs in 2 of them. Interestingly, we were the only team who found a bug in the Linux kernel challenge, which we're quite proud of, especially for the kernel fuzzing team, which I was a part of. However, on the flip side, our CRS completely failed to do anything on 1 or 2 challenges, which was the crucial factor that guided our mindset in the AFC.

### Our Mindset

Stepping into the AFC from the ASC, the biggest lesson we learned is that we need more testing - **a LOT** more. From triaging the logs from ASC, we realized that we didn't score at all in some challenges not because our CRS lacked efficacy, but simply because there were errors during the building process of CPs that we hadn't tested before. Those errors caused the CRS to fall over and stop working altogether on those targets, which is a really scary situation. The ASC only had 5 CPs across 1 day - we didn't know the exact scale of the AFC final round back then, but we expected it to be much larger, which meant the risk of the CRS falling over was even greater.

Therefore, since the beginning of development for the AFC, our mentor - Dr. Xinyu Xing - had been advocating for testing and stability above all. His philosophy was not to try coming up with fancy new things, but to stick to things that we *know* would work, and make them as stable as possible. There were obviously disagreements along the way - we are a team of researchers, and many of us wanted to do stuff that was new and special. However, in the end, we chose to stick with the principle of *Keep It Simple & Stable*. I can't say for sure whether this was the correct choice, but it was a logical decision given the format of the competition. To keep a system running autonomously over 10 days without human intervention at all - the worst thing that could happen is that our CRS falls over 2-3 days into the final round, and we definitely didn't want that.

That being said, at the end of development, the CRS didn't end up *that* simple. There were so many finer details and features we needed to implement, and performance issues we had to handle, which bloated the size of our CRS by a significant amount. It makes me feel that even with the amount of testing we did, there's no guarantee our CRS won't fall over - which is terrifying to think about!

### Our CRS

Now let's get a bit technical and talk about our CRS in more detail. Our CRS is called **BugBuster**. It is a system of many interconnected components, each component performing a *specific job*, deployed as a **Kubernetes** cluster. The CRS is designed to scale up and down, with many crucial components being *scalable both vertically and horizontally*. We deploy our system on 32-core nodes on Azure. Components can scale vertically with parallel threads to make full use of these CPU cores, or horizontally by launching many replicas, depending on the number of concurrent tasks at any point in time.

The pipeline of how the components work together is quite complicated, with many parallelizations and dependencies, but I'll try to explain it as clearly as possible at a high-level view. When our CRS receives a new task, the following things happen:

1. The **gateway** receives the task and stores the task information and tarballs in our **PostgreSQL database**.
2. The **scheduler** acknowledges the existence of new tasks in the database and prepares jobs to send to other components through **RabbitMQ message queues**.
3. The **fuzzers** are among the first components to receive a job. We have 3 different kinds of fuzzers in our CRS:
   - The **b3fuzz** fuzzers, which are C-specific fuzzers that use customized and optimized strategies for fuzzing. This is our largest-scale fuzzer.
   - The **prime** fuzzers, which run OSS-Fuzz's libFuzzer to handle both C and Java targets.
   - The **directed** fuzzers, which handle delta-scan tasks by guiding the fuzzers to the functions presented in the delta diffs.
4. The **seedgen** component receives a job in parallel to the fuzzers. This is the first component in our CRS that makes use of LLM. It is an LLM agent that analyzes the CPs' entrypoints and codebases to write Python scripts that can generate fuzzing seeds. The seeds are generated with the goal of maximizing coverage, using 3 different seedgen strategies (Full, Mini, MCP) to ensure efficacy in both time and diversity.
5. The **corpus grabber** component also receives a job at this stage. This component doesn't generate seeds but instead *grabs* seeds from a set of *pre-built corpora* that we've created by collecting PoCs of public vulnerabilities in the past for OSS-Fuzz-compatible projects. To take it a step further, we also divided these collected corpora by file types or data types. In cases where a project is brand new and we have no corpus for it, a lightweight LLM agent will analyze the project's entry points and determine which file types or data types of corpus we should grab for it.
6. During fuzzing, the massive scale of our fuzzer system can generate an overwhelming number of seeds. Therefore, our **cmin** component runs in parallel with fuzzing and periodically minimizes the set of seeds based on coverage. The fuzzers grab the minimized seeds from the **shared storage** whenever they're available.
7. In order to guide directed fuzzing, our directed fuzzers send a job to our **slicing** component, which utilizes static analysis techniques to generate slices of call paths from entrypoints to target functions. The directed fuzzers use these slices for targeted instrumentation.
8. Whenever a crash is found, the fuzzers save the PoCs in shared storage and their related information in the database. The **triage** component receives these PoCs and tries to reproduce them. This serves two purposes: to remove FP crashes introduced by fuzzers and to deduplicate PoCs of the same bug into **bug profiles**. We use a naive and conservative deduplication strategy here, based only on crash sites and sanitizer bug types. Because our fuzzers are massively scaled, the number of PoCs generated is enormous. Therefore, our triage replicas are executed massively in parallel as well.
9. Whenever a bug profile is found, the **patch agent** component kicks in and attempts to fix it. This is the second place where we utilize LLM. We run multiple replicas of the patch agent at a time, each looking at a single crash report for a single bug profile and attempting to fix it. When a patch is found, a DIFF patch will be saved to the database.
10. Since duplicated patch submissions are penalized for accuracy, we have 2 extra patch-related components, namely **patch reproducer** and **patch submitter**, to perform deduplication. Our deduplication strategy is to test a patch of each bug profile against the PoCs of *other* bug profiles. The details are complicated for certain edge cases, but basically, if two patches of two different profiles can fix the PoCs of each other, we consider these two bug profiles as duplicates, and these two patches as duplicates, and only choose to submit one of them.
11. When a SARIF report is received, the gateway saves it into the database, and the scheduler sends a job to the **sarif** component. This component first checks if the bug described in the SARIF report is one we already found. If it isn't, the component does some sanity checks about the validity and reachability of the code area shown in the report, then asks LLM about the correctness of it.
12. Finally, the **submitter** component periodically looks at the bug profiles, chosen patches, and SARIF assessments in the database in order to submit them and bundle them accordingly.

### The Experience

The shape of our CRS at the start of development was definitely not identical to the one I describe above. It was a lot simpler, but every time an issue showed up or a change in the rule set was made, we had to adjust accordingly and add in new features to accommodate. As far as I can recall, these are the most significant changes we needed to make.

**Exhibition round 1** was our first opportunity to test the CRS at a scale way larger than our test setup, and with that, a lot of issues arose:

- Our **b3fuzz** fuzzers stopped working halfway because the seed set became too large, and it took forever just to compress and decompress them. That's why we had to implement the seed minimizer **cmin** component.
- Our **triage** replicas couldn't keep up with the pace at which fuzzers produced crashes. Therefore, we needed to implement many performance optimization strategies for triaging.
- Our **slicing** component for C projects didn't work on a specific case because there was some code written in a newer C standard (C23) in the delta diff. Our slicing was written in LLVM 14, which couldn't compile such code. As a result, we needed to re-implement slicing in LLVM 18 - which sounds simple, but is actually a huge can of worms in itself. The introduction of *opaque pointers* since LLVM 16 directly affected our technique of creating call graphs, which required coming up with a whole new technique to do so.

**Exhibition round 2** was another step up in scaling, which unfortunately created more issues:

- Our **cmin** was originally based on `afl-cmin`, which was no longer fast enough and failed to minimize the seeds within the given time interval. We needed to come up with our own seed minimizing algorithm to solve it.
- We started to hit LLM rate limits within **patch agent** and **seedgen**, which required us to be more mindful of how we allocate LLM usage across components and the number of replicas that could be run in parallel at a time.
- We found many duplicated bug profiles of the same root cause this time around, so we started to have discussions about doing PoV deduplication. We tried using the organizer's call stack matching deduplication and an LLM based deduplicator agent. Both methods yielded FPs (putting 2 bug profiles of 2 different root causes as the same bug), so at the end, we kept the naive and conservative deduplication for PoVs and focus on deduplication for patches instead.
- At this point, our CRS was still *statically* scaled, which we realized was no longer a good idea. Therefore, we had to learn how to do dynamic scaling with Azure's infrastructure, and decide which components should be dynamically scaled and the metrics to scale them with.
- We started to question our choice of using **RabbitMQ** as our piping system, since we observed some crashes on the RabbitMQ side due to overloaded usage, which caused interruptions in some components. We discussed different architectures to potentially switch to. Ultimately, we decided to still stick with RabbitMQ and made each component handle queue-based errors more gracefully instead.

We managed to have an *almost* complete system after **exhibition round 3** that we could be happy with. However, this was when the final rulings about duplications and AM were announced. To handle the gamesmanship of it, we came up with the **patch reproducer** and **patch submitter** to optimize our scoring strategies. These were implemented very close to the final round submission deadline, which was a nightmare for testing.

Aside from all of that, there were multiple hiccups throughout the 3 rounds as well. Every time the organizers modified things such as the rules, the competition/CRS APIs, the base Docker image they used for OSS-Fuzz, the way they built the CPs' Docker images, etc., it would certainly cause some problems in our pipeline that required a day or two to fix. These were especially frustrating, since they had nothing to do with the main features of the CRS and just wasted our development and testing time and budget.

### Testing

As I've mentioned before, our principle for the AFC was to keep everything stable. To do so, we started testing our systems very early on - as soon as possible. Even before the organizer gave us the integration test repo and a test API, we had already begun building our own test dataset based on the single exemplar challenge they provided for `libpng`.

Our dataset was prepared using real-world Open Source Vulnerabilities (OSVs) for OSS-Fuzz-compatible projects. We initially collected a large number of them and gathered around 200+ bugs across 80+ projects. However, not all of them were usable for various reasons:

- Some projects were actually C++, even though their `project.yaml` file in OSS-Fuzz listed C.
- Some projects could only be built using the source code shipped with OSS-Fuzz, not local ones - which we needed to do for AIxCC.
- Some failed to build using the AIxCC-customized OSS-Fuzz base images.
- Some delta diff files made changes only in build scripts instead of source code.

As a result, our final dataset included around 40 projects and 80 bugs, in addition to the official challenges from the exhibition rounds. We continuously ran tests in parallel with development to catch any breaking bugs that could occur at any time.

Since I was the main tester, I can definitely share more about the challenges we faced during testing:

- Because we were running tests in parallel with development, every time a new feature was pushed, we had to decide whether to restart testing. Most of the time, we chose to restart - which caused testing to be very fragmented. Our CRS was rarely tested continuously for a long duration.
- We didn't have good logging or debugging early on, so I had to manually inspect each component's output and notify the authors whenever something looked off.
- Since each component had its own author(s), I often couldn't tell if something was a bug unless there was a clear error message. Bugs without obvious symptoms (e.g., misconfigurations that caused a component to underperform) could go unnoticed for a long time.
- In the earlier stages, integrity bugs showed up so frequently that we barely had time to evaluate efficacy. Every time I tried to run an efficacy test, a breaking bug would appear, forcing us to fix and re-test - just for another one to appear...

Fortunately, in the later stages, we managed to get every component author on board with testing. Along with a better logging system, this allowed us to conduct more thorough testing - albeit a little later than I would have liked.

## Peeking into other Teams' CRSs

After the final submission was over and before the winner announcement, thanks to the efforts of Dr. Adam Doupé ([@adamdoupe](https://x.com/adamdoupe)) and Dr. Yan Shoshitaishvili ([@Zardus](https://x.com/Zardus)) at [CTF Radiooo](https://x.com/ctfradiooo), every team had a chance to join a podcast interview and share their experiences as well as some details of their CRSs. Watching the interviews was a fascinating and eye-opening experience for me. Truthfully, there are so many more ideas I want to explore further now after watching them than when I was developing our CRS. Again, kudos to CTF Radiooo and the participating teams for such insightful discussions!

In this section, I'd like to discuss what other teams have achieved that I find interesting, similarly or differently to us, based on their sharings. Please go watch the interviews themselves to get the full context!

**VERY IMPORTANT: Keep in mind that these are MY OWN takeaways from watching the podcasts. I might be completely off the mark on some of it, so please don't take what I say at face value. If any other teams have read this and found any errors, please let me know so that I can correct them.** I'd love to see how many of these points I got right or wrong after the CRSs are open-sourced.

### Categories of CRSs

Overall, I would categorize the CRSs based on their usage of LLM:

1. Some CRSs follow the traditional fuzzing pipeline, with the assistance of LLMs on certain tasks - this category fits our BugBuster CRS.
2. Some CRSs still follow the fuzzing pipeline but make heavier use of LLM in specific components.
3. Some CRSs follow an LLM-first approach, with their system mainly running on LLM agents, while fuzzing plays a more supportive role.

The variety of approaches to this competition is surprising to me and my team. We originally thought that all CRSs would follow the same shape and didn't believe that an LLM-first approach would be effective. However, it seems we were proven very wrong on this.

### Trail of Bits - ButterCup

The CRS that I think is closest to ours is **Trail of Bits's ButterCup**. The similarities here are twofold. Firstly, about the overall **architecture**: ButterCup is also a system of multiple components that handle specific jobs, connected with message queues and a database. The jobs are distributed by an *orchestrator* component, similar to our *scheduler*. Secondly, there is a similarity in the **mindset**: based on their long-time research and engineering knowledge and experience, Trail of Bits also decided to use LLMs only on tasks they believed LLMs are good at, namely seed generation and patching. This aligns with the belief we had when developing our CRS as well.

That is not to say our CRSs are *identical*. There are distinct differences where I think Trail of Bits have done things differently and possibly superior to us:

- Their orchestrator performs both task distribution and submission; we have two separate components for this.
- Their seedgen component generates seeds not only based on coverage, but also based on the grammar of commonly seen vulnerabilities.
- Their approach to fuzzing, SARIF assessment, and deduplication seems simpler than ours.
- Most importantly, they have **much better engineering discipline and experience than us**. The way they have a CI that runs an end-to-end task every time a change is made, and cross-check each other's code before merging, is what I dreamed of as the tester of our team.

### Lacrosse

Personally, I think the architecture of **Lacrosse**'s CRS is the most unique among the teams, but it still fits in category 1 because of their LLM usage.

They also have a single central node (scheduler/orchestrator) that distributes tasks to others. However, the other nodes here are not specialized task handlers. They all run the same piece of code that can handle any task but choose which task to handle based on a priority system decided by the central node. The worker nodes only communicate with the central node, not with each other. I think this is a very interesting strategy since it saves the headache of maintaining a complex piping interconnectivity system between components, although I can definitely see it introduces more headache in synchronization.

Lacrosse uses LLM mainly for three tasks: vulnerability characterization, patching, and SARIF assessment. The vulnerability characterization is the interesting bit for me. This agent generates a natural language description, assigns a CWE, and suggests which files the root cause of the bug could be in. This information is used as context for patching, and as a way to do PoV deduplication.

Moreover, they have a vertical fallback system between different LLM models in case a model fails or hits rate limits, and a horizontal consensus system to make decisions based on answers from multiple different LLMs. In our team, we thought of these strategies but never implemented them. However, I think they could be valuable to improve stability and accuracy.

### Shellphish - Artiphishell

The next CRS I'd like to discuss falls into category 2 in my definition, which are CRSs that still follow the traditional pipeline but have heavy usage of LLM in a very specific task.

Architecturally, **Artiphishell** has WAY more specialized components than us, and it's actually pretty intimidating to look at. However, one specific component was emphasized in their podcast as their main secret sauce: the **GrammarGuy**. This is an LLM agent that consumes a huge amount of LLM budget to incrementally scan the entire codebase, accumulating more and more context along the way, to generate grammar for fuzzers.

I'm not a fuzzing expert - in fact, I don't know much about fuzzing beyond just running default fuzzers. However, according to my teammates who have done much fuzzing research, traditional grammar-based fuzzing historically proved to be not so effective. I wonder if, with massive LLM usage, grammar-based fuzzing could break through and become the new state-of-the-art? That said, after looking at the official challenges from the exhibition rounds, there are a few vulnerabilities that only trigger if the payload contains certain strings such as `"verysimpleprotocol"`, `"crashycrashy"`, or `"eMezilaireseD"`, etc., which would be likely to work in favor of grammar-based techniques.

### Team Atlanta - Atlantis

If Shellphish uses LLM heavily to aid fuzzing, then Team Atlanta does so to aid patching. **Atlantis** is the only CRS consisting of a fine-tuned LLM model.

They used *instruction tuning* to fine-tune a Llama model to learn from existing codebases how to decide which appropriate context should be given to patching (e.g., symbols, etc.). This model is then used in a *contextualizer* agent for their patching component. I don't know much about fine-tuning, but from my recent experiments, having a contextualizer improves patching success rate significantly. For our patch agent in the final round, we only gave it tools to view code at certain lines and locate symbols, which I think could be lacking compared to other teams who used more advanced static analysis or LLM sub-agents as contextualizers for patching. It's definitely interesting to see how effective this fine-tuned LLM contextualizer agent would turn out to be.

Aside from fine-tuning LLM, Team Atlanta also put a lot of efforts in improving and fail-proofing the fuzzing pipeline. Their system has 3 separate sub-CRSs running individually in parallel for C, Java, and Multi-language. Each of the fuzzers in these sub-CRSs are enhanced with *customized extensions and instrumentations* to the original fuzzers such as libFuzzer, AFL, and JAZZER. This way, each sub-CRS has its own strength, but in case one of them falls over, the others might still be able to finish the job, which is great for stability and reliability.

### Theori - RoboDuck

The final two CRSs in the list adopted an LLM-first approach, with **RoboDuck** being my favorite of all among the CRSs in terms of innovation. I was amazed listening to Theori's team members describe their system, because before that, I wouldn't have thought any of their approach would be possible or effective at all. As a team, we played it safe with our system and focused on stability instead of innovative research, but I personally think that an LLM-first system is what DARPA is really looking for.

Architecturally, their system consists of a single Python process that distributes tasks to other nodes, which spawn Docker containers to handle the tasks. Most importantly, these task handlers are almost entirely **LLM agents**, with lots of hand-crafted tools, sub-agents, and guardrails. The philosophy behind the design of these agents is to try not to give them access to terminals or the ability to read code line-by-line, but to provide information through hand-coded tools instead.

There are various "sub-agents" in the system, which act as tools for the main agents to use, such as:

- **Source code question**: has access to the codebase and answers any source code related questions. To my understanding, this is effectively RoboDuck's contextualizer.
- **Debugger question**: has access to gdb/jdb and answers any questions that require the CP to be dynamically executed.
- **Harness input encoder**: analyzes the harness and generates a Python function that takes semantically meaningful arguments and encodes them into the binary format that the fuzzing harness expects.
- **Harness input decoder**: the opposite of the encoder - generates a Python function to decode a blob of binary input into structured Python objects.
- etc.

When a challenge task is received, their pipeline is as follows:

- It starts from **static analyzers** (e.g., Infer), together with an **LLM diff analyzer** for delta tasks, to identify candidate vulnerabilities. There are a lot of false positives at this stage.
- They reduce false positives using a lightweight **LLM binary classifier**, which answers with a single token output and bases its decision on the probability of the next YES/NO token to reduce the number of candidate vulnerabilities.
- Next is a **Vuln Analyzer agent**, which assesses if a bug is real and reachable, and annotates it with additional information, such as root cause and conditions required to trigger it. As they claim, after this stage, there is a very low false positive rate coming out of this agent (roughly 50% compared to 99.99% from static analyzers).
- The **PoV producer agent** and the **Patching agent** are next in line and run in parallel. The PoV producer agent does NOT have access to the codebase and makes use of information retrieved from three sub-agents: source code question, debugger question, and harness input encoder. It generates a Python script to generate PoVs. During the lifetime of a PoV producer agent session, any *failed PoVs are used as seeds for the fuzzers*. Observably, LLM might just miss a crash by a byte or two that fuzzers can mutate and trigger.
- The Patching agent is not very complex and makes use of the harness input decoder agent to make small diff patches. Erroneous diffs are fixed and sanity checked by sequence alignment and dynamic programming approaches.

Overall, I find it very fascinating how their system works, and I can't wait to learn all the details from its source code and see it in action!

### All You Need Is A Fuzzing Brain

Despite their name, this is the second team to adopt an LLM-first approach. According to their explanations, the **"fuzzing brain"** is an LLM!

Overall, I believe this CRS has many similarities to RoboDuck, with some identical ideas such as using an LLM agent to generate a PoV generator script and using the failed PoVs as seeds for fuzzers. However, they didn't go as in-depth into the agents within their system as Theori did in their interview. On the other hand, similar to Lacrosse, this team also implemented a vertical fallback and horizontal consensus between LLM models.

In addition to LLM, there are two points that they emphasized: advanced static analysis and parallelization. As far as I understand, CodeQL is extensively used in their CRS for reachability analysis. This is how they reduce false positives in candidate vulnerabilities. With an LLM agent, they rank the candidates, and only the top five ranked candidates are fed into other LLM agents for further analysis. They also optimized their CodeQL queries so that this static analysis phase must finish within five minutes.

During the early stages of the ASC, our team also dipped our toes into writing CodeQL. The results, however, were nowhere near as good as we expected - the false positive rate was too high, the analyses were too restricted, and the performance was quite slow. Therefore, I'm very interested to see how this team wrote their queries and how well they work.

## Conclusion

As I write this, it's about 12 hours until the final results are announced. No matter the outcome, huge thanks to **DARPA** and **ARPA-H** for organizing the AIxCC competition, to my team **42-b3yond-6ug** for the incredible journey, and to **CTF Radiooo** and all the other participating teams for the insightful discussions and knowledge sharing. We've learned so much together as a team - and I've grown a lot personally too. These are lessons I never would've gained just from taking courses or doing research.

When we were asked on the podcast what we would've done differently, I remember saying that nothing really came to mind. But after some reflection - and after listening to other teams - I've realized where we can improve. Stability is important, but there's definitely room for us to explore more innovative ideas. And when it comes to engineering discipline, we've got a long way to go. That's something I want to work on not just as a team member, but individually too.

And finally, to you readers - if you've made it this far, thank you so much! It feels great to be writing again after two long years.