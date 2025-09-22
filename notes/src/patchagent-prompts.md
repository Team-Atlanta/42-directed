# PatchAgent Prompts: LLM Engineering for Vulnerability Patching

## Overview

The PatchAgent system uses carefully crafted prompts to guide LLMs in automated vulnerability patching. The prompts are language-specific and include both system-level instructions and user-specific task descriptions with various psychological and technical persuasion techniques.

## Prompt Architecture

### Language-Specific Prompt Structure

The system uses separate prompt templates for different target languages:

**C/C++ Prompts** ([`clike/prompt.py`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/clike/prompt.py)):
- `CLIKE_SYSTEM_PROMPT_TEMPLATE`: Core instructions for C/C++ vulnerability patching
- `CLIKE_USER_PROMPT_TEMPLATE`: Task-specific user message with AddressSanitizer reports

**Java Prompts** ([`java/prompt.py`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/java/prompt.py)):
- `JAVA_SYSTEM_PROMPT_TEMPLATE`: Core instructions for Java vulnerability patching
- `JAVA_USER_PROMPT_TEMPLATE`: Task-specific user message with Jazzer reports

### Prompt Integration via LangChain

```python
# From common.py implementations
self.prompt = ChatPromptTemplate.from_messages([
    ("system", SYSTEM_PROMPT_TEMPLATE),
    ("user", USER_PROMPT_TEMPLATE),
    MessagesPlaceholder(variable_name="agent_scratchpad"),
])
```

## Detailed Prompt Analysis

### System Prompts: Technical Architecture Instructions

#### C/C++ System Prompt Structure

**Core Task Definition**:
```
Your task is to patch the bug in the program as identified by the sanitizer report.
Access the buggy C/C++ codebase and the corresponding sanitizer report highlighting various issues.
```

**Tool Instruction Framework**:
The system prompt defines three core tools with precise usage instructions:

1. **`viewcode` Tool**:
   - **Purpose**: Code snippet viewing with line numbers
   - **Arguments**: `path`, `start_line`, `end_line`
   - **Output Format**: Line-numbered code snippets
   - **Example Output**:
   ```c++
   10| int check (char *string) {
   11|    if (string == NULL) {
   12|        return 0;
   13|    }
   14|    return !strcmp(string, "hello");
   15| }
   ```

2. **`locate` Tool**:
   - **Purpose**: Symbol definition location
   - **Arguments**: `symbol` (function name, struct name, variable name)
   - **Integration**: "Using `locate` in conjunction with `viewcode` can significantly enhance your code navigation efficiency"

3. **`validate` Tool**:
   - **Purpose**: Patch validation via PoC replay
   - **Format**: Git diff format with precise requirements
   - **Validation**: Security test + functional test compliance

**Patch Format Specification**:
Extremely detailed git diff format requirements:
```diff
--- a/foo.c
+++ b/foo.c
@@ -11,7 +11,9 @@
 int check (char *string) {
+   if (string == NULL) {
+       return 0;
+   }
-   return !strcmp(string, "hello");
+   return !strcmp(string, "hello world");
 }
```

**Critical Requirements**:
- At least 3 lines of context at beginning and end of hunks
- No shortcuts like `...` or useless comments
- Precise line number calculations
- Mandatory use of `validate` tool after patch generation

#### Java System Prompt Differences

**Language-Specific Adaptations**:
- **File Path Examples**: `Main.java`, `src/Main.java` instead of `.c` files
- **Code Examples**: Java syntax with proper class structure
- **Import Requirements**: "If you use a new package, you must import it"
- **Context Rules**: "At least 1 lines of context" (reduced from C/C++'s 3 lines)
- **Comment Restrictions**: "Do not make change in the comments", "Do not add comments in the patch"

### User Prompts: Psychological Persuasion + Task Specifics

#### Emotional Manipulation Techniques

**Consistent Across Both Languages**:
```
I will give [ten/a ten] dollar tip for your assistance to create a patch for the identified issues.
Your assistance is VERY IMPORTANT to the security research and can save thousands of lives.
```

**Analysis**: This employs multiple persuasion techniques:
- **Financial Incentive**: Small monetary reward to trigger reciprocity
- **Importance Amplification**: "VERY IMPORTANT" with emphasis
- **Moral Stakes**: "save thousands of lives" creates urgency and responsibility
- **Social Proof**: "security research" implies credible, important work

#### Task-Specific Variations

**C/C++ User Prompt**:
```
Now I want to patch the {project} program, here is the asan report
{report}
```

**Java User Prompt**:
```
Now I want to patch the {project} program, here is the jazzer report
{report}
```

**Technical Instructions**:
- **Stack Trace Analysis**: "You can use the stack trace to identify a fix point for the bug"
- **Context Awareness**: "Do not forget the relationship between the stack trace and the [function/method] arguments"
- **Tool Usage Requirements**: "you MUST MUST use the `validate` tool to validate the patch"
- **Continuation Logic**: "Otherwise, you MUST continue to gather information using these tools"

#### Counterexample Integration

Both prompts include placeholder for counterexample feedback:
```
{counterexamples}
```

This enables the basic counterexample system where failed patches are included as examples of what NOT to do.

## Prompt Engineering Techniques

### 1. **Progressive Disclosure**
- **System Prompt**: Comprehensive tool documentation
- **User Prompt**: Specific task with emotional hooks
- **Counterexamples**: Dynamic failure-based learning

### 2. **Constraint Specification**
- **Explicit Format Requirements**: Detailed git diff specifications
- **Mandatory Validation**: "MUST MUST use the `validate` tool"
- **Quality Standards**: No shortcuts, proper context, no useless comments

### 3. **Multi-Modal Guidance**
- **Example-Based Learning**: Concrete code examples for each tool
- **Format Templates**: Exact patch format with line number explanations
- **Error Prevention**: Explicit rules about what NOT to do

### 4. **Language-Specific Optimization**
- **Syntax Adaptation**: Language-appropriate code examples
- **Tool Integration**: Different context requirements (3 vs 1 lines)
- **Security Focus**: Sanitizer-specific instructions (ASAN vs Jazzer)

## Comparison with Academic Paper

### ✅ **Implemented Prompt Features**
- **Tool Integration**: Clear API documentation for LLM tool usage
- **Validation Requirements**: Mandatory patch testing
- **Format Specification**: Precise git diff format requirements
- **Counterexample Integration**: Basic failed patch prevention

### ❌ **Missing Paper Optimizations**
- **No Report Purification**: Sanitizer reports used raw, not LLM-optimized
- **No Chain Compression**: No automatic multi-tool workflow optimization
- **No Auto-Correction Guidance**: No numerical error prevention instructions
- **Basic Counterexample Logic**: Simple "don't repeat this" vs. sophisticated failure analysis

### ⚠️ **Interesting Implementation Choices**

**Emotional Manipulation**: The "save thousands of lives" approach is not mentioned in the academic paper, suggesting practical experimentation with LLM motivation techniques.

**Language Specificity**: The dual-prompt system for C/C++ vs Java shows more sophisticated language adaptation than described in the research.

**Tool Documentation Detail**: The extensive tool usage examples exceed the paper's described approach, indicating practical lessons learned from LLM confusion.

## Prompt Evolution and Optimization

### Current Parameters Affecting Prompt Behavior

From [`generator.py`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/patchagent/patchagent/agent/generator.py):
- **Temperature**: `[0, 0.3, 0.7, 1]` - Controls response randomness
- **Auto-hint**: `[True, False]` - Enables automatic symbol resolution hints
- **Counterexample Number**: `[0, 3]` - Number of failed patches to include
- **Max Iterations**: `30` (generic) / `15` (fast) - Attempt limits per configuration

### Potential Improvements Based on Paper

1. **Add Report Purification Instructions**: Guide LLM to interpret sanitizer reports systematically
2. **Include Chain Compression Prompts**: Instructions for efficient multi-tool workflows
3. **Auto-Correction Guidelines**: Help LLM self-correct numerical and formatting errors
4. **Enhanced Counterexample Analysis**: Prompt LLM to analyze WHY patches failed

## Integration in CRS Workflow

### Template Variables

**System Prompts**: Static technical instructions
**User Prompts**: Dynamic with variables:
- `{project}`: Target project name
- `{report}`: Sanitizer report content
- `{counterexamples}`: Failed patch examples

### LangChain Integration

The prompts are integrated via LangChain's `ChatPromptTemplate` system, enabling:
- **Message History**: Persistent conversation context
- **Tool Integration**: Structured tool calling
- **Agent Scratchpad**: Intermediate reasoning preservation

This prompt system represents a **production-ready LLM engineering approach** that goes beyond the academic paper's descriptions, incorporating practical lessons learned from real-world LLM vulnerability patching attempts.