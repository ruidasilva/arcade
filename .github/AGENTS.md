# AGENTS.md

## 🎯 Purpose & Scope

This file defines the **baseline standards, workflows, and structure** for *all contributors and AI agents* operating within this repository. It serves as the root authority for engineering conduct, coding conventions, and collaborative norms.

It is designed to help AI assistants (e.g., Codex, Claude, Gemini) and human developers alike understand our practices, contribute clean and idiomatic code, and navigate the codebase confidently and effectively.

> Whether reading, writing, testing, or committing code, **you must adhere to the rules in this document.**

Additional `AGENTS.md` files **may exist in subdirectories** to provide more contextual or specialized guidance. These local agent files are allowed to **extend or override** the root rules to fit the needs of specific packages, services, or engineering domains—while still respecting the spirit of consistency and quality defined here.

<br><br>

## 📚 Technical Conventions

Our technical standards are organized into focused, portable documents in the `.github/tech-conventions/` directory:

### Core Development
* **[Go Essentials](tech-conventions/go-essentials.md)** - Context-first design, interfaces, goroutines, error handling
* **[Testing Standards](tech-conventions/testing-standards.md)** - Unit tests, coverage requirements, best practices
* **[Commenting & Documentation](tech-conventions/commenting-documentation.md)** - Code comments, package docs, markdown

### Version Control & Collaboration
* **[Commit & Branch Conventions](tech-conventions/commit-branch-conventions.md)** - Git workflow standards
* **[Pull Request Guidelines](tech-conventions/pull-request-guidelines.md)** - PR structure and review process
* **[Release Workflow & Versioning](tech-conventions/release-versioning.md)** - Semantic versioning and releases

### Project Management & Infrastructure
* **[Labeling Conventions](tech-conventions/labeling-conventions.md)** - GitHub label system
* **[Dependency Management](tech-conventions/dependency-management.md)** - Go modules and security
* **[Security Practices](tech-conventions/security-practices.md)** - Vulnerability reporting and secure coding
* **[GitHub Workflows Development](tech-conventions/github-workflows.md)** - Actions workflow best practices

> 💡 **Start with [tech-conventions/README.md](tech-conventions/README.md)** for a complete index with descriptions.

<br><br>

## 📁 Directory Structure

| Directory                   | Description                                             |
|-----------------------------|---------------------------------------------------------|
| `.github/`                  | Issue templates, workflows, and community documentation |
| `.github/actions/`          | GitHub composite actions for CI/CD and automation       |
| `.github/ISSUE_TEMPLATE/`   | Issue and pull request templates                        |
| `.github/tech-conventions/` | Technical conventions and standards for development     |
| `.github/workflows/`        | GitHub Actions workflows for CI/CD                      |
| `.vscode/`                  | VS Code settings and extensions for development         |
| `.` (root)                  | Source files and tests for the local package            |

## Votari terminology and responsibility boundaries

Clarification dated 2026-11-05. This supplements existing guidance; it grants no implementation, deployment, protocol-adoption or gate-promotion authority.

- **VEST — Votari Election Simulation & Scale Testing:** simulator, workload generator and correctness oracle. Its internal verifier checks its own scenarios; it is not a production service, independent election auditor, service owner or source of normative protocol rules. Cite test evidence with run ID, revision, environment and limitations. `QUALIFIED` means a scenario passed against the then-deployed services; `fully_qualified` describes a local mock election meeting VEST's bar. Neither certifies a service or production capacity.
- **VCES — Votari Core Election Services:** GoBA (Ballot Allocator), GoFD (Fee Delegator), JungleBus middleware (index/query support) and Arcade (broadcast/status). Name the specific service and contract in requirements and owner questions; VCES is not one verifier, owner or eligibility authority. A repository README or VEST run alone does not attest the deployed revision; record deployment provenance or mark it **REQUIRES_REVALIDATION**.
- **VEAT — Votari Election Audit Toolbox:** independent election-audit R&D for evidence reconstruction and protocol-conformance checking. Its `main` baseline is G0 documentation; this is not a universal statement about research progress. [Research snapshot `58aefb7`](https://github.com/ruidasilva/VEAT-Votari-Election-Audit-Toolbox/blob/58aefb7123455a28fe9a80ec5449c2b6176a5a10/README.md) records later bounded offline synthetic acceptance, including G5 with gzip qualifications. Always state branch, revision, gate and limits. Unapproved capabilities remain **DESIGN ONLY**; research acceptance is not production readiness or real-election assurance. VEAT does not certify legal eligibility, legality or voter intent.
- **VERS — Votari Eligibility & Registration Services:** eligibility/registration support, distinct from VCES execution. Separate current attestation/device-rule evaluation from authority-backed entitlement R&D; do not silently promote research into the current protocol or make VCES an eligibility authority.
- **Protocol owners:** normative rules (including M08 supply, M09 finality and M10 traversal) belong to the applicable versioned specifications and their adoption process. VEST implementation choices and service behavior are evidence, not protocol adoption. Never combine VEST and VEAT as one owner. If the responsible individual or normative authority is not established, write **TO CONFIRM** rather than infer ownership.

Reference: [VEO PR #24 terminology audit](https://github.com/ruidasilva/VEO/blob/b739f6a189b7317cc80013942cc92e14b7999a6c/docs/integration/TERMINOLOGY-AUDIT-VEST-VCES-VEAT.md). Its G0/G1-not-started statements reflect its historical source pin and must not override later VEAT branch evidence. The [whitepaper v1.0, November 2025, §8](https://github.com/ruidasilva/VERS-Votari-Eligibility-Registration-Services-R-D/blob/60dbc684554c260a718c306312956fd59395a68f/source-material/votari/Votari%20A%20Digital%20Voting%20System%20%E2%80%94%20Whitepaper.md) describes public, self-contained audit; it names none of VEST, VCES or VEAT and does not appoint an auditing authority. Preserve historical evidence and report conflicts rather than rewriting it as current fact.

### Application in this repository

This guidance applies to Votari integration in the ruidasilva fork; it does not redefine upstream Arcade governance. Arcade supplies broadcast/status evidence, not a Votari election verdict. Votari operational ownership versus upstream maintenance responsibility is TO CONFIRM; do not assign either by inference.
