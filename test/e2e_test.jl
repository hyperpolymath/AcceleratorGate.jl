# SPDX-License-Identifier: MPL-2.0
# (PMPL-1.0-or-later preferred; MPL-2.0 required for Julia ecosystem)
# E2E pipeline tests for AcceleratorGate.jl
# Tests full backend selection, memory tracking, and operation registry workflows.

using Test
using AcceleratorGate

@testset "E2E Pipeline Tests" begin

    @testset "Full pipeline: backend selection and dispatch" begin
        # Start from a clean state with JuliaBackend as default
        set_backend!(JuliaBackend())
        @test current_backend() isa JuliaBackend

        # Register operations on a simulated GPU backend
        empty!(AcceleratorGate._BACKEND_OPS)
        register_operation!(CUDABackend, :matmul)
        register_operation!(CUDABackend, :fft)
        register_operation!(TPUBackend, :einsum)

        # Verify specialties are accessible before selection
        @test is_specialized(CUDABackend(0), :matmul)
        @test is_specialized(TPUBackend(0), :einsum)

        # Without hardware, selection always falls back to Julia
        b = select_backend(:matmul, 2048)
        @test b isa JuliaBackend

        # Use @with_backend macro for a scoped override
        @with_backend CUDABackend(0) begin
            @test current_backend() isa CUDABackend
            @test current_backend().device == 0
        end
        # Scope restored after block
        @test current_backend() isa JuliaBackend

        empty!(AcceleratorGate._BACKEND_OPS)
    end

    @testset "Full pipeline: memory tracking lifecycle" begin
        empty!(AcceleratorGate._MEMORY_USAGE)

        julia_b = JuliaBackend()
        tpu_b   = TPUBackend(0)

        # Allocate across two backends
        track_allocation!(julia_b, Int64(4096))
        track_allocation!(julia_b, Int64(8192))
        track_allocation!(tpu_b, Int64(1_000_000))

        @test memory_usage(julia_b) == Int64(12288)
        @test memory_usage(tpu_b)   == Int64(1_000_000)

        # Partial deallocations
        track_deallocation!(julia_b, Int64(4096))
        @test memory_usage(julia_b) == Int64(8192)

        # Full memory report
        report = memory_report()
        @test report isa Dict{String, Int64}
        @test report["JuliaBackend"] == Int64(8192)
        @test report["TPUBackend"]   == Int64(1_000_000)

        empty!(AcceleratorGate._MEMORY_USAGE)
    end

    @testset "Full pipeline: capability report and diagnostics" begin
        reset_diagnostics!()

        # Record several diagnostic events
        _record_diagnostic!("cuda", "runtime_fallbacks")
        _record_diagnostic!("tpu",  "runtime_fallbacks")
        _record_diagnostic!("cuda", "runtime_fallbacks")

        diag = runtime_diagnostics()
        @test diag["backends"]["cuda"]["runtime_fallbacks"] == 2
        @test diag["backends"]["tpu"]["runtime_fallbacks"]  == 1

        # Full capability report structure
        report = capability_report()
        @test haskey(report, "generated_at")
        @test haskey(report, "strategy_order")
        @test haskey(report, "backends")
        @test haskey(report, "platform")
        @test length(report["strategy_order"]) == 12

        reset_diagnostics!()
        @test runtime_diagnostics()["backends"]["cuda"]["runtime_fallbacks"] == 0
    end

    @testset "Error handling: invalid backend operations" begin
        # Switching to a non-default backend and back should be safe
        set_backend!(NPUBackend(2))
        @test current_backend() isa NPUBackend
        @test current_backend().device == 2

        set_backend!(JuliaBackend())
        @test current_backend() isa JuliaBackend

        # select_backend with all standard types excluded still returns Julia
        b = select_backend(:fft, 512; exclude=[CUDABackend, ROCmBackend, MetalBackend])
        @test b isa JuliaBackend
    end

    @testset "Round-trip consistency: backend set/get" begin
        original = current_backend()

        for BackendType in [CUDABackend, ROCmBackend, MetalBackend, TPUBackend]
            b = BackendType(0)
            set_backend!(b)
            got = current_backend()
            @test got isa BackendType
            @test got.device == 0
        end

        # Restore original
        set_backend!(JuliaBackend())
        @test current_backend() isa JuliaBackend
    end

end
