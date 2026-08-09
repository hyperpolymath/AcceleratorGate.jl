# Architecture

## Overview

AcceleratorGate is the Julia admission and compatibility layer for the estate's
operation-first coprocessor runtime. It does not own numerical kernels and a
backend type name is not a capability claim.

Enaction owns runtime semantics, authoritative/advisory/remote-job policy, and
the Idris2-defined native ABI. AcceleratorGate translates Julia requests into
that operation vocabulary, admits providers using explicit evidence, and
returns execution evidence to Julia consumers.

## Operation path

```text
Julia/domain value
       |
       v
OperationRequest (version, layout, lane, evidence floors)
       |
       v
deterministic provider planning
       |
       +-- pure-Zig Enaction native provider
       +-- real hardware/provider adapter
       +-- explicit reference provider
       `-- explicit simulation (only when allow_simulation=true)
       |
       v
result + ExecutionEvidence
```

Provider claims are per operation and include support, determinism, execution
lanes, implementation kind, device class, and optional conformance digest.
Simulations are refused by default. Authoritative claims must be
`canonical_exact`. Remote providers may claim only `remote_job` execution.
Once a provider has been planned, its runtime failure is returned to the
caller; the registry never silently retries another provider.

`EnactionZigProvider` loads the shared form of the same pure-Zig library used by
the Rust adapter. It validates ABI version, layouts, capability records, status
and execution evidence. There is no C implementation or Julia-owned copy of a
kernel.

The older device hierarchy and operation-specialty table remain as a legacy
compatibility surface while consumers migrate. Environment flags and a type
such as `TPUBackend` are discovery hints only and must not be presented as
runnable hardware evidence.

## Directory Structure

```
.
├── src/
│   ├── AcceleratorGate.jl # legacy compatibility and module surface
│   └── operations.jl      # central requests, evidence, planner, providers
├── tests/        # Test suites
├── docs/         # Documentation
├── scripts/      # Utility scripts
├── config/       # Configuration files
├── LICENSE       # License file
├── LICENSES/     # Full license texts
└── README.adoc   # Project documentation
```

## Design Principles

- **Separation of Concerns**: Each module has a single responsibility
- **Testability**: Code is written to be easily testable
- **Documentation**: All public APIs are documented
- **Configuration**: Environment-specific settings are externalized

## Dependencies

- External dependencies are minimized and clearly declared
- Version pinning is used for reproducibility

## Security Considerations

- Sensitive data is never committed to the repository
- Secrets are managed through environment variables or secure vaults
- Regular dependency audits are performed

## Maintainability

- Code follows consistent style guidelines
- Pull requests require review and CI checks
- Issues and discussions are tracked transparently

---

*Last updated: 2026-07-18*
