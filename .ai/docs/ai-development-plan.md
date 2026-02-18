# AI-Assisted and Agentic Development Plan

This document outlines a strategic plan for integrating AI-assisted and agentic development practices into the `scratch` repository, focusing on enhancing efficiency, code quality, and security.

## Current AI/LLM Usage

The repository currently utilizes AI for a critical pre-push review stage, as detailed in `AGENTS.md` and `README.md`.

### Existing AI Review Hook: `ai-review`

*   **Trigger**: Executed as a `pre-push` Git hook.
*   **Mechanism**: Calls the `Gemini CLI`, providing it with the branch diff and commit log.
*   **Context Discovery**: Dynamically identifies project context, including tech stack, `AGENTS.md` content, and active hooks, to inform its review.
*   **Focus Areas**: The AI specifically focuses on aspects that static analysis tools cannot readily catch, such as:
    *   Intent versus actual implementation.
    *   Potential flaws in IAM logic.
    *   Architectural drift from established patterns.
    *   Identification of operational gaps.
    *   Unforeseen cost implications.
*   **Output & Enforcement**: Review results are saved to `.ai/review-log/`. If the AI identifies serious findings, it responds with a `BLOCK:` line, preventing the push. Developers can override this with `git push --no-verify`.

This existing integration demonstrates a foundational understanding of leveraging AI for code quality and adherence to project conventions.

## Opportunities to Expand AI Assistance

Expanding AI assistance can significantly impact various stages of the development lifecycle.

### 1. Code Generation
*   **Terraform Modules**: Automate the scaffolding of new Terraform resources or modules (e.g., VPC, EC2, CloudFront configurations) based on high-level descriptions or common patterns.
*   **Configuration Files**: Generate boilerplate for `docker-compose.yml` or `user-data.sh.tftpl` based on application requirements.

### 2. Enhanced Review & Analysis
*   **Continuous Code Review**: Provide more granular, context-aware feedback earlier in the development process, potentially on a per-commit or per-file basis, beyond the current pre-push gate.
*   **Security Policy Integration**: Assist in identifying deviations from security policies defined in `.checkov.yml` or `.trivyignore` justifications, and propose fixes.
*   **Cost Optimization Analysis**: Offer more proactive suggestions for cost reduction based on Terraform plans and Infracost data, integrating with the `infracost` hook.

### 3. Testing
*   **Terraform Test Generation**: Automatically generate `*.tftest.hcl` files for new or modified Terraform modules, ensuring comprehensive test coverage.
*   **Script Unit Tests**: Create unit tests for utility scripts found in `scripts/` (e.g., `ai-review.sh`, `generate-docs.sh`).

### 4. Documentation & Knowledge Management
*   **Automated Documentation Updates**: Automatically generate or update sections within `AGENTS.md`, `README.md`, and `.ai/docs/` (e.g., `architecture.md`, `features.md`, `developer-guide.md`) following code changes.
*   **Bug List Augmentation**: Assist in enriching entries in `bug-list.md` by suggesting `Recommended Fix` implementations or providing deeper analysis.

### 5. Proactive Remediation
*   **Bug Fixing Suggestions**: Offer concrete code snippets and strategies to address identified bugs (e.g., those listed in `bug-list.md`).
*   **Refactoring Proposals**: Suggest and even implement small, self-contained refactorings to improve code readability, maintainability, or adherence to best practices.

## Recommended Tooling

The current setup provides a strong foundation. The primary recommendation is to deepen the integration with the existing AI platform.

*   **Gemini CLI**: This is the current backbone for agentic review. Further development should leverage its capabilities for:
    *   More interactive and granular code analysis.
    *   Programmatic code generation and modification.
    *   Orchestration of complex, multi-step agentic workflows.
*   **Pre-commit**: Crucial for integrating new AI-powered hooks into the development workflow, ensuring consistency and early feedback.
*   **Other LLMs (e.g., Claude Code)**: While Gemini CLI is established, exploring other code-specific LLMs like Claude Code could offer alternative perspectives or specialized capabilities for certain tasks (e.g., different programming language support, alternative reasoning styles). Any integration would need careful evaluation and potential wrapper scripts to fit the existing hook infrastructure.

## Proposed Workflow Changes

The introduction of new AI capabilities will evolve the development workflow from purely human-driven to an AI-augmented model.

### 1. Code Generation Assist
Developers utilize AI to generate initial drafts of Terraform modules or other code artifacts, accelerating the start of new features or deployments. The developer then refines these drafts.

### 2. Continuous Feedback Loop
Beyond the pre-push review, AI provides continuous, real-time feedback during coding sessions or as part of smaller, localized Git hooks. This could include linting suggestions, security best practice reminders, or architectural adherence checks.

### 3. Automated Documentation
As code changes are committed, AI agents automatically update relevant documentation files, reducing manual overhead and ensuring documentation remains current with the codebase.

### 4. Assisted Debugging and Refactoring
When issues are identified (either manually or by static analysis tools), AI provides suggestions for debugging, potential fixes, or refactoring opportunities.

### 5. Agentic "Fix-it" Cycles
For well-defined, low-risk tasks (e.g., minor security fixes, cost optimizations identified by Infracost), AI agents propose and implement changes, with human oversight for approval.

### Workflow Diagram (ASCII Art)

```
+----------------+        +--------------------------+        +-------------------+
| Developer Code |------->| AI Code Generation       |------->| Developer Refines |
+----------------+        | (e.g., Terraform Boilerplate)  |        +-------------------+
        |                                       |                     ^
        | Git Commit                            |                     |
        v                                       v                     |
+----------------+        +--------------------------+        +-------------------+
| Pre-commit Hooks |------>| AI Continuous Review     |------->| Developer Fixes   |
| (Static Analysis +)    | (e.g., Security, Best Practices) |        | (Assisted by AI)  |
+----------------+        +--------------------------+        +-------------------+
        |                                       |                     ^
        | Git Push (Pre-push hook)              |                     |
        v                                       v                     |
+----------------+        +--------------------------+        +-------------------+
| AI Agentic Review|------>| AI Automated Documentation |------>| AI Proactive Fixes|
| (Architectural, IAM, Cost)|                     | (Low-Risk, Human Approved) |
+----------------+        +--------------------------+        +-------------------+
```

## Risks and Mitigations

The adoption of AI-assisted practices introduces new risks that require careful management.

### 1. Risk: Hallucinations and Inaccuracies
*   **Description**: AI models can generate incorrect code, illogical architectural suggestions, or misleading documentation.
*   **Mitigation**:
    *   **Human-in-the-Loop**: All AI-generated code or significant suggestions must undergo mandatory human review and approval.
    *   **Validation Tools**: Integrate AI output with existing static analysis tools (tflint, checkov, trivy) for automatic validation.
    *   **Testing**: Maintain a strong culture of testing, including AI-generated tests, to verify correctness.

### 2. Risk: Introduction of Security Vulnerabilities
*   **Description**: AI might inadvertently propose or implement code that introduces new security flaws or bypasses existing controls.
*   **Mitigation**:
    *   **Security Review Gate**: Implement an additional security review gate for AI-generated changes, especially those touching IAM or network configurations.
    *   **Principle of Least Privilege**: Train AI and configure agentic workflows to strictly adhere to the principle of least privilege in IAM and network rules.
    *   **Integration with Security Tools**: Ensure AI output is always piped through existing security scanning tools (Gitleaks, Trivy, Checkov).

### 3. Risk: Over-reliance and Loss of Developer Expertise
*   **Description**: Developers may become overly dependent on AI, leading to a degradation of their own problem-solving skills and domain knowledge.
*   **Mitigation**:
    *   **Assistive vs. Autonomous**: Position AI primarily as an assistant that augments developer capabilities, rather than a fully autonomous entity.
    *   **Educational Focus**: Encourage developers to understand *why* the AI made a suggestion or generated specific code, fostering learning.
    *   **Critical Thinking**: Emphasize critical thinking and validation of AI output.

### 4. Risk: Cost Implications
*   **Description**: Increased usage of AI models (especially powerful ones) can lead to higher operational costs.
*   **Mitigation**:
    *   **Cost Monitoring**: Implement robust monitoring of API calls and token usage for AI services.
    *   **Optimized Prompts**: Develop efficient prompting strategies to minimize input/output tokens.
    *   **Tiered Model Usage**: Use smaller, less expensive models for simpler tasks where possible, reserving larger models for complex problem-solving.

### 5. Risk: Context Drift and Scalability
*   **Description**: AI models may struggle to maintain context across large, complex codebases or over extended development periods.
*   **Mitigation**:
    *   **Modular Context Feeding**: Develop strategies to feed highly relevant, localized context to the AI for specific tasks.
    *   **Project-Specific Fine-tuning**: Explore fine-tuning AI models on the repository's codebase and documentation for improved domain understanding.
    *   **Iterative Design**: Break down complex tasks for AI into smaller, manageable sub-tasks to maintain focus.

## Phased Roadmap

This roadmap outlines a progression from the current state to a mature AI-augmented development practice.

### Phase 1: Augmentation (0-3 Months) - Current State & Immediate Enhancements

*   **Objective**: Solidify current AI usage and introduce basic AI assistance for common development tasks.
*   **Key Activities**:
    *   **Ensure `ai-review` adoption**: Verify all developers are using and benefiting from the pre-push `ai-review` hook.
    *   **Interactive Code Explanation**: Encourage developers to use Gemini CLI for interactive questions about code sections, explaining logic, or providing usage examples for existing Terraform resources.
    *   **Basic Documentation Drafting**: Pilot AI-assisted drafting of initial `README.md` or `.ai/docs/` sections for newly created Terraform modules or scripts.
    *   **Infracost Insights**: Develop a workflow where AI provides enhanced interpretation or recommendations based on `infracost` reports.

### Phase 2: Assisted Creation & Enhancement (3-9 Months)

*   **Objective**: Integrate AI for more active participation in code generation, testing, and proactive issue identification.
*   **Key Activities**:
    *   **Terraform Module Scaffolding**: Implement AI agents to generate boilerplate for new Terraform modules (e.g., a new EC2 instance, a basic S3 bucket with common configurations) based on developer input.
    *   **Automated Test Generation (Initial)**: Develop AI to generate basic `*.tftest.hcl` files for new or modified Terraform resources.
    *   **Pull Request Description Generation**: Implement AI to draft clear and concise pull request descriptions based on the changes in the branch.
    *   **Static Analysis Fix Suggestions**: Integrate AI to provide concrete code suggestions for issues flagged by `tflint`, `trivy`, or `checkov`. This would be an opt-in feature.
    *   **IAM Policy Refinement Suggestions**: Use AI to suggest more granular IAM policies based on resource usage patterns, adhering to the principle of least privilege.

### Phase 3: Agentic Workflows & Continuous Improvement (9-18 Months)

*   **Objective**: Deploy more autonomous AI agents for well-defined, low-risk tasks, and establish a cycle of continuous AI improvement.
*   **Key Activities**:
    *   **Proactive Bug Remediation (Low/Medium Severity)**: Develop AI agents to automatically propose and, with human approval, apply fixes for "Low" and "Medium" severity bugs identified in `bug-list.md`.
    *   **Automated Refactoring**: Implement agents to perform small, self-contained code refactorings (e.g., updating variable names, consolidating similar blocks of code) based on predefined rules or patterns.
    *   **Architectural Drift Detection & Correction**: Advanced AI agents analyze new changes against established architectural patterns (e.g., from `architecture.md`) and suggest corrective actions or refactorings to prevent drift.
    *   **Self-Updating Documentation**: Fully automate the updating of specific documentation sections based on detected code changes, with built-in validation.
    *   **AI Agent Monitoring & Evaluation**: Establish metrics and processes to monitor the performance, accuracy, and efficiency of AI agents, with continuous feedback loops for model improvement.
