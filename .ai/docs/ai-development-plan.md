## AI-Assisted and Agentic Development Plan for `scratch`

This document outlines a strategic plan for adopting AI-assisted and agentic development practices within the `scratch` repository. The goal is to enhance developer productivity, improve code quality, and ensure adherence to best practices across the Terraform and GitHub Actions stack.

## Current AI/LLM Usage

The `scratch` repository currently integrates AI assistance primarily through a **pre-push AI review hook**. This hook is activated by the `scripts/ai-review.sh` script, which leverages the Gemini CLI to perform an agentic analysis of code changes before they are pushed to the remote repository.

Key aspects of current AI usage include:

*   **Gemini CLI Integration**: The `ai-review.sh` script invokes the Gemini CLI, providing the branch diff and commit log as input for analysis.
*   **Dynamic Context Discovery**: The AI dynamically identifies relevant project context (e.g., tech stack, `AGENTS.md`, active pre-commit hooks) at runtime to inform its review.
*   **Focus Areas of Review**: The AI review concentrates on detecting issues that static analysis tools typically miss, such as:
    *   Discrepancies between developer intent and implemented code.
    *   Flaws in IAM logic.
    *   Architectural drift from established patterns.
    *   Identification of operational gaps.
    *   Anticipation of potential cost surprises from infrastructure changes.
*   **Review Logging**: The outcomes of the AI review are systematically logged within the `.ai/review-log/` directory, providing an audit trail of agentic feedback.
*   **Push Blocking Capability**: The hook is configured to block a `git push` operation if it identifies critical findings (indicated by a `BLOCK:` line in its output), necessitating a manual override (`git push --no-verify`) if developers deem it appropriate.
*   **Structured Documentation**: The presence of the `.ai/docs/` directory, containing files like `architecture.md`, `bug-list.md`, and `developer-guide.md`, suggests an existing framework for structured documentation that can serve as context for AI or house AI-generated content.

## Opportunities to Expand AI Assistance

Expanding AI assistance can significantly enhance developer productivity, code quality, and consistency across the `scratch` project. Given its primary use of Terraform and GitHub Actions, several opportunities exist:

### Code Generation
*   **Terraform Module & Resource Scaffolding**: Generate boilerplate code for new Terraform resources (e.g., EC2 instances, S3 buckets, CloudFront distributions) or entire modules based on high-level natural language descriptions. This would include generating variables, outputs, and basic configuration blocks, adhering to the project's established conventions.
*   **GitHub Actions Workflow Creation**: Assist in generating or modifying CI/CD workflows (`.github/workflows/*.yml`) for new project subdirectories, deployment tasks, or specific testing phases.
*   **Container Orchestration Files**: Generate `docker-compose.yml` configurations for new services, drawing inspiration from existing patterns (e.g., the `wiki.js/docker-compose.yml` example).
*   **EC2 User Data Scripts**: Augment or generate `user-data.sh.tftpl` scripts for EC2 instances, incorporating common setup, installation, and configuration tasks.
*   **Terraform Test Case Structures**: Generate basic Terraform test (`.tftest.hcl`) structures to validate expected resource properties or behaviors.

### Code Review (Enhanced Capabilities)
*   **Proactive Cost Optimization**: Beyond flagging "cost surprises," AI can provide deeper analysis of `terraform plan` outputs, suggesting alternative, more cost-effective AWS services, configurations, or instance types.
*   **Advanced Security Policy Compliance**: Automated checks on Terraform code against specific security policies (e.g., CIS benchmarks, custom organizational policies) with actionable remediation steps, complementing existing Checkov and Trivy checks.
*   **Architectural Pattern Enforcement**: Verify that new Terraform deployments align with established architectural patterns and best practices documented in `AGENTS.md` or `.ai/docs/architecture.md`.
*   **IAM Policy Refinement**: Analyze IAM policies for overly broad permissions and recommend more granular alternatives, building on current `bug-list.md` findings.

### Automated Testing
*   **Terraform Test (`.tftest.hcl`) Generation**: Generate comprehensive `terraform test` definitions for resources and modules, asserting against key configurations, attributes, and desired behaviors.
*   **Pre-deployment Validation Scripts**: Generate scripts or checks to ensure all pre-requisites are met before executing `terraform apply` (e.g., AWS credentials validity, API key presence).

### Documentation Automation
*   **Dynamic README Maintenance**: Automatically generate or update sections of `README.md` files (e.g., Terraform module inputs/outputs, resource descriptions) using information extracted directly from Terraform code and variable definitions.
*   **Bug Report Summarization & Structuring**: Automate the summarization of new entries in `.ai/review-log/` or generate structured bug reports for `bug-list.md` based on AI review findings.
*   **Developer Guide Content Generation**: Propose and generate new sections for `developer-guide.md` or other internal documentation based on newly implemented features or evolving project patterns.
*   **ASCII Architectural Diagrams**: Generate simple ASCII diagrams to visualize infrastructure components or data flow directly from Terraform configurations.

    *Example ASCII Diagram:*
    ```
    +-----------------+        +-----------------+
    |   CloudFront    |------->|      EC2        |
    | (TLS, Security) |        | (Wiki.js, PgSQL)|
    +-----------------+        +-----------------+
             ^                        ^
             |                        |
             | HTTPS                  | HTTP (3000)
             |                        |
    +--------+--------+        +------+----------+
    |   User Browser  |        |    AWS VPC      |
    +-----------------+        +-----------------+
    ```

## Recommended Tooling

To effectively expand AI assistance within the `scratch` project, the following tooling recommendations are made:

*   **Gemini CLI (Expanded Use)**: The existing `ai-review.sh` hook already leverages Gemini CLI. Its capabilities can be further utilized for:
    *   Generating more sophisticated code review insights and actionable feedback.
    *   Context-aware documentation generation.
    *   Producing Terraform configuration snippets and GitHub Actions workflow outlines.
    *   Integration into additional pre-commit or CI/CD stages.
*   **Claude Code (for Code Generation & Refinement)**: Given its proficiency in code understanding, generation, and summarization, Claude Code can be integrated for:
    *   Generating initial drafts of Terraform resources, modules, and GitHub Actions workflows based on natural language prompts.
    *   Assisting in refactoring existing code to improve readability, security posture, or cost efficiency.
    *   Helping with complex bug identification and suggesting potential fixes.
*   **Emerging Terraform-native AI Integrations**: Actively explore and integrate any new AI tools specifically designed for Terraform that offer direct integration with HCL, providing enhanced validation, cost analysis, or security checks beyond current capabilities.

## Proposed Workflow Changes

Integrating expanded AI assistance will introduce several changes to the existing development workflow, aiming for a more streamlined and intelligent process.

### Local Development
*   **Interactive AI-Assisted Scaffolding**: Developers will utilize CLI commands or IDE integrations to prompt AI models (via Gemini CLI or Claude Code) to generate initial Terraform code, Docker Compose files, or user data scripts. This shifts the initial development phase from manual authoring to reviewing and refining AI-generated code.
*   **Augmented Pre-commit Hooks**: New pre-commit hooks can be introduced for more granular AI checks, such as:
    *   AI-powered suggestions for `terraform fmt` and `tflint` that automatically propose fixes.
    *   AI checks for common security misconfigurations prior to committing.
*   **AI-Driven Documentation Drafts**: Developers can leverage AI to generate initial `README.md` content, update variable descriptions, or create preliminary `bug-list.md` entries based on their code changes.

### Pull Request Workflow
*   **Enhanced AI Review Comments**: The current pre-push `ai-review` hook will be enhanced to provide more detailed, actionable comments directly within pull requests, highlighting specific lines of code related to security, cost, or architectural concerns.
*   **Automated Test Plan Suggestions**: For complex changes, AI could analyze the modifications and suggest relevant test cases or modifications to existing `tftest.hcl` files, promoting comprehensive test coverage.
*   **Auto-generated Documentation Updates**: Upon merging a pull request, an automated process (potentially AI-driven) could trigger updates to relevant documentation pages in `.ai/docs/` or project `README.md`s based on the integrated changes.

### Continuous Integration/Continuous Deployment (CI/CD)
*   **Intelligent Anomaly Detection**: AI can be employed to monitor CI/CD pipeline runs, identifying patterns indicative of potential issues (e.g., flaky tests, unexpected build times, uncharacteristic resource provisioning in `terraform plan` outputs) and providing early warnings.
*   **Advanced Cost Impact Analysis**: Beyond the basic Infracost integration, AI could provide a more nuanced analysis of cost implications for `terraform plan` outputs, comparing against historical data, usage patterns, or best practices.

## Risks and Mitigations

The adoption of AI in development introduces both significant opportunities and inherent risks that must be actively identified and managed.

### Risks
*   **Hallucinations and Inaccuracies**: AI models can generate incorrect, non-idiomatic code, misleading documentation, or inaccurate review findings.
*   **Over-reliance on AI**: Developers might become excessively dependent on AI tools, potentially leading to a decline in critical thinking and fundamental engineering skills.
*   **Security Vulnerabilities**: AI-generated code might inadvertently introduce new security flaws, or the AI models themselves could be susceptible to prompt injection attacks if not properly secured.
*   **Bias and Fairness**: AI models can inadvertently perpetuate biases present in their training data, leading to suboptimal or unfair suggestions.
*   **Cost Implications**: Extensive use of commercial AI APIs can lead to significant operational costs if not carefully managed.
*   **Data Privacy and Intellectual Property (IP) Concerns**: Sending proprietary code or sensitive project details to external AI services raises valid concerns about data privacy and potential intellectual property leakage.
*   **"Black Box" Problem**: The reasoning behind some AI suggestions might be opaque, making it difficult for developers to understand, trust, or debug the recommendations.

### Mitigations
*   **Mandatory Human Oversight**: All AI-generated content (code, documentation, review comments) *must* undergo thorough human review and validation. AI should function as an intelligent co-pilot, not an autonomous decision-maker.
*   **Phased and Gradual Adoption**: Implement AI assistance incrementally, beginning with low-risk tasks (e.g., boilerplate generation, documentation drafting) and progressively expanding to more critical areas as confidence and experience grow.
*   **Developer Education and Training**: Provide comprehensive training to developers on how to effectively utilize AI tools, understand their inherent limitations, and critically evaluate their outputs.
*   **Secure Integration Practices**: Implement strict access controls and secure API gateways for AI service integrations. Prioritize local or self-hosted models for processing highly sensitive code when feasible. Ensure robust input sanitization to prevent prompt injection attacks.
*   **Robust Feedback Mechanisms**: Establish clear and accessible channels for developers to provide feedback on AI performance, enabling continuous improvement and fine-tuning of models or prompts.
*   **Proactive Cost Monitoring**: Implement detailed monitoring for AI API usage to track and manage associated operational costs effectively.
*   **Clear AI Attribution**: Clearly mark AI-generated content to ensure transparency, accountability, and proper differentiation from human-authored content.
*   **Enhanced Contextual Awareness**: Ensure AI tools are provided with comprehensive project context (e.g., `AGENTS.md`, `.ai/docs/`) to generate more relevant, accurate, and contextually appropriate outputs.

## Phased Roadmap

A structured, phased roadmap will enable controlled adoption, continuous learning, and seamless integration of AI assistance into the `scratch` project's development lifecycle.

### Phase 0: Current State (Q1 2026)
*   **Focus**: Leverage existing pre-push AI code review capabilities.
*   **Activities**:
    *   Ongoing maintenance and incremental improvement of the `scripts/ai-review.sh` hook.
    *   Ensure `AGENTS.md` and `.ai/docs/` are consistently updated to reflect current project context, serving as vital input for AI agents.
    *   Monitor AI review outputs in `.ai/review-log/` to assess effectiveness and identify patterns for future automation.
*   **Tooling**: Gemini CLI.

### Phase 1: Basic AI Augmentation (Q2 2026)
*   **Focus**: Introduction of boilerplate generation, initial documentation assistance, and non-critical review enhancements.
*   **Activities**:
    *   **Terraform Boilerplate Generation**: Implement simple AI prompts for generating basic Terraform resource blocks (e.g., S3, EC2 skeleton configurations).
    *   **README & Docs Assistant**: Utilize AI-driven suggestions for updating `README.md` files (e.g., automatic generation of variable/output tables) and drafting initial documentation sections for `.ai/docs/`.
    *   **Enhanced Review Feedback**: Configure the existing AI review to provide more constructive suggestions for minor issues (e.g., code style improvements, minor refactoring).
*   **Workflow Impact**: Developers will interact with AI to generate initial code and documentation drafts, which they then review and refine. This phase will have a minor, positive impact on the PR workflow.
*   **Tooling**: Gemini CLI, Claude Code (for more advanced generation tasks).

### Phase 2: Advanced AI Integration (Q3-Q4 2026)
*   **Focus**: Automated test generation, deeper code analysis, and workflow automation.
*   **Activities**:
    *   **Terraform Test Generation**: Develop sophisticated AI prompts to generate `tftest.hcl` files based on Terraform resource definitions, asserting against key properties and behaviors.
    *   **Security Policy Augmentation**: Employ AI to analyze Terraform code against specific security best practices, offering direct and actionable remediation suggestions.
    *   **GitHub Actions Workflow Generation**: Introduce AI assistance for generating new GitHub Actions workflows or modifying existing ones for common CI/CD tasks.
    *   **Context-Aware Cost Optimization**: Integrate AI to provide more detailed, context-aware cost-saving recommendations based on `terraform plan` outputs, potentially comparing against historical spend.
*   **Workflow Impact**: AI becomes a more active participant in the coding process, generating tests and offering deeper, more critical insights during both local development and pull request reviews.
*   **Tooling**: Gemini CLI, Claude Code, potential custom Terraform AI integrations.

### Phase 3: Mature AI-Augmented Development (H1 2027 onwards)
*   **Focus**: Proactive bug detection, architectural pattern enforcement, and intelligent troubleshooting.
*   **Activities**:
    *   **Proactive Anomaly Detection**: AI monitors CI/CD pipelines and deployed infrastructure for deviations from baselines or unexpected behavior, flagging potential issues before they escalate.
    *   **Architectural Guardrails & Drift Detection**: AI actively identifies and suggests refactoring for Terraform code that deviates from established architectural patterns, providing "architectural drift" detection and remediation.
    *   **Intelligent Incident Response Support**: AI assists in diagnosing and suggesting solutions for production issues by analyzing logs, monitoring data, and correlating findings with recent code changes.
    *   **Advanced Refactoring Opportunities**: AI proactively proposes significant refactoring opportunities for improving modularity, scalability, or long-term maintainability of Terraform projects.
*   **Workflow Impact**: AI functions as an intelligent assistant throughout the entire software development lifecycle, from initial ideation to ongoing operations, fostering a highly efficient, secure, and resilient engineering practice.
*   **Tooling**: Fully integrated Gemini CLI, Claude Code, potentially custom fine-tuned models tailored for project-specific tasks.
