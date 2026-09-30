<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# Contributing to AcceleratorGate.jl

This document explains how to contribute to the project. We follow a
"Dual-Track" architecture where human-readable documentation lives in
the root and machine-readable policies live in `.machine_readable/`.

## How to Contribute

We welcome contributions in many forms:

- **Code:** Improving the core verified stack or extensions.

- **Documentation:** Enhancing AsciiDoc manuals or AI manifests.

- **Testing:** Adding property-based tests or formal proofs.

- **Bug reports:** Filing clear, reproducible issues.

## Getting Started

1.  **Read the AI Manifest:** Start with `0-AI-MANIFEST.a2ml` (if
    present) to understand the repository structure.

2.  **Environment:** Use `guix` `develop` or `direnv` `allow` to set up
    your tools.

3.  **Task Runner:** Use `just` to see available commands (`just`
    `--list`).

## Development Workflow

### Branch Naming

    docs/short-description       # Documentation
    test/what-added              # Test additions
    feat/short-description       # New features
    fix/issue-number-description # Bug fixes
    refactor/what-changed        # Code improvements
    security/what-fixed          # Security fixes

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

    <type>(<scope>): <description>

    [optional body]

    [optional footer]

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`,
`security`.

## Reporting Bugs

Before reporting:

1.  Search existing issues.

2.  Check if it is already fixed in `main`.

When reporting, include:

- Clear, descriptive title.

- Environment details (OS, versions, toolchain).

- Steps to reproduce.

- Expected vs actual behaviour.

## Code of Conduct

All contributors are expected to adhere to our ethical standards. See
[CODE_OF_CONDUCT](../CODE_OF_CONDUCT.adoc) for details.

## License

By contributing, you agree that your contributions will be licensed
under the same license as the project (see [LICENSE](../LICENSE)).

## Signed commits

Every commit that reaches the default branch must be signed; a ruleset refuses
unsigned pushes. Estate policy:
[SIGNING-POLICY](https://github.com/hyperpolymath/standards/blob/main/docs/SIGNING-POLICY.adoc).

- **People and interactive agents** sign with an SSH key registered on GitHub
  as a *signing* key (`gpg.format=ssh`, `commit.gpgsign=true`). The committer
  email must be verified on that account.
- **Apps, bots and workflows** never `git push` local commits. They write
  through the API (`createCommitOnBranch` or the estate `signed-push` action)
  so that GitHub signs each commit.
- Merge PRs with **squash**. The ruleset checks every commit on the PR branch,
  not just the result, so one unsigned commit blocks the merge. Re-create such a
  branch with signed commits (`git cherry-pick -S`) and open a new PR.
  Rebase-merge replays commits unsigned and is disabled.
