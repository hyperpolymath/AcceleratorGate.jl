<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# TOPOLOGY.md — AcceleratorGate.jl

## Purpose

Unified accelerator abstraction layer for Julia providing consistent interface to GPU, TPU, NPU, FPGA, QPU, DSP, and other accelerators. Enables transparent hardware acceleration across hyperpolymath Julia packages via pluggable backend system with compile-time and runtime device selection.

## Module Map

```
AcceleratorGate.jl/
├── src/                 # Julia package source
│   ├── backends/       # Accelerator backend implementations
│   ├── device/         # Device detection and management
│   ├── dispatch/       # Kernel dispatch system
│   └── memory/         # Memory management across accelerators
├── test/               # Test suite and backend verification
├── examples/           # Integration examples
├── docs/               # API documentation
└── Project.toml        # Julia package manifest
```

## Data Flow

```
[Julia Code] ──► [AcceleratorGate Dispatch] ──► [Backend Detection] ──► [Accelerator Kernel]
                                                       ↓
                                                [Device Memory] ──► [Result]
```

## Supported Accelerators

- **GPU**: NVIDIA CUDA, AMD ROCm, Intel oneAPI
- **TPU**: Google TPU via JAX integration
- **NPU**: Qualcomm Hexagon, MediaTek APU
- **FPGA**: Xilinx, Intel Altera
- **QPU**: Quantum accelerators (integration with QuantumCircuit.jl)
- **DSP**: Specialized signal processing units
