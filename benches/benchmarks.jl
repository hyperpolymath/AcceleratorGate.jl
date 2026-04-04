# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 required for Julia ecosystem)
# BenchmarkTools benchmarks for AcceleratorGate.jl
# Measures backend selection, memory tracking, and capability report throughput.

using BenchmarkTools
using AcceleratorGate

# ── Setup ─────────────────────────────────────────────────────────────────────

# Ensure clean state before benchmarking
empty!(AcceleratorGate._MEMORY_USAGE)
empty!(AcceleratorGate._BACKEND_OPS)
reset_diagnostics!()

# ── Backend selection benchmarks ──────────────────────────────────────────────

# Small workload selection (100 element vector)
println("=== select_backend :matmul (small, n=100) ===")
@benchmark select_backend(:matmul, 100)

# Medium workload selection (10_000 elements)
println("=== select_backend :fft (medium, n=10_000) ===")
@benchmark select_backend(:fft, 10_000)

# Large workload selection with exclusions (1_000_000 elements)
println("=== select_backend :conv (large, n=1_000_000, with exclusions) ===")
@benchmark select_backend(:conv, 1_000_000; exclude=[CUDABackend, ROCmBackend])

# ── Memory tracking benchmarks ────────────────────────────────────────────────

# Small: single allocation + deallocation
let b = JuliaBackend()
    println("=== memory tracking (small: 1 alloc/dealloc) ===")
    @benchmark begin
        track_allocation!($b, Int64(4096))
        track_deallocation!($b, Int64(4096))
    end
end

# Medium: batch allocations across multiple backends
println("=== memory tracking (medium: 10 allocs, 2 backends) ===")
let julia_b = JuliaBackend(), tpu_b = TPUBackend(0)
    @benchmark begin
        for _ in 1:5
            track_allocation!($julia_b, Int64(1024))
            track_allocation!($tpu_b,   Int64(2048))
        end
        empty!(AcceleratorGate._MEMORY_USAGE)
    end
end

# Large: memory report over many backends
println("=== memory_report() (large: all backends populated) ===")
let backends = [JuliaBackend(), CUDABackend(0), ROCmBackend(0), TPUBackend(0), NPUBackend(0)]
    for (i, b) in enumerate(backends)
        track_allocation!(b, Int64(i * 1024))
    end
    @benchmark memory_report()
end
empty!(AcceleratorGate._MEMORY_USAGE)

# ── Capability report benchmark ───────────────────────────────────────────────

println("=== capability_report() ===")
@benchmark capability_report()

# ── Operation registry benchmarks ─────────────────────────────────────────────

println("=== supports_operation (small: 1 op registered) ===")
let
    empty!(AcceleratorGate._BACKEND_OPS)
    register_operation!(CUDABackend, :matmul)
    @benchmark supports_operation(CUDABackend(0), :matmul)
end

println("=== supports_operation (large: 10 ops registered) ===")
let ops = [:matmul, :fft, :conv, :gemm, :einsum, :pooling, :norm, :softmax, :relu, :dropout]
    empty!(AcceleratorGate._BACKEND_OPS)
    for op in ops
        register_operation!(CUDABackend, op)
    end
    @benchmark supports_operation(CUDABackend(0), :matmul)
end
empty!(AcceleratorGate._BACKEND_OPS)
