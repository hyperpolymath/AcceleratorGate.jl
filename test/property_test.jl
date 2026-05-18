# SPDX-License-Identifier: MPL-2.0
# Property-based tests for AcceleratorGate.jl
# Verifies invariants hold across random inputs and backend configurations.

using Test
using AcceleratorGate

@testset "Property-Based Tests" begin

    @testset "Invariant: memory usage never goes below zero" begin
        for _ in 1:50
            empty!(AcceleratorGate._MEMORY_USAGE)
            b = JuliaBackend()
            alloc = Int64(rand(1:1_000_000))
            dealloc = Int64(rand(1:2_000_000))  # may exceed alloc

            track_allocation!(b, alloc)
            track_deallocation!(b, dealloc)
            @test memory_usage(b) >= Int64(0)
        end
        empty!(AcceleratorGate._MEMORY_USAGE)
    end

    @testset "Invariant: memory usage accumulates correctly" begin
        for _ in 1:50
            empty!(AcceleratorGate._MEMORY_USAGE)
            b = JuliaBackend()
            n = rand(2:10)
            allocs = [Int64(rand(1:100_000)) for _ in 1:n]
            for a in allocs
                track_allocation!(b, a)
            end
            @test memory_usage(b) == sum(allocs)
        end
        empty!(AcceleratorGate._MEMORY_USAGE)
    end

    @testset "Invariant: diagnostic counters are non-negative" begin
        for _ in 1:50
            reset_diagnostics!()
            n = rand(1:20)
            for _ in 1:n
                _record_diagnostic!("cuda", "runtime_fallbacks")
            end
            diag = runtime_diagnostics()
            @test diag["backends"]["cuda"]["runtime_fallbacks"] == n
            @test diag["backends"]["cuda"]["runtime_fallbacks"] >= 0
        end
        reset_diagnostics!()
    end

    @testset "Invariant: select_backend always returns an AbstractBackend" begin
        ops = [:matmul, :fft, :conv, :einsum, :gemm, :inference]
        for _ in 1:50
            op = rand(ops)
            data_size = rand(100:100_000)
            b = select_backend(op, data_size)
            @test b isa AbstractBackend
        end
    end

    @testset "Invariant: @with_backend always restores previous backend" begin
        for _ in 1:50
            set_backend!(JuliaBackend())
            device = rand(0:3)
            @with_backend CUDABackend(device) begin
                @test current_backend() isa CUDABackend
            end
            @test current_backend() isa JuliaBackend
        end
        set_backend!(JuliaBackend())
    end

    @testset "Invariant: capability report has required keys" begin
        required_keys = ["generated_at", "strategy_order", "backends", "platform", "selected_backend"]
        for _ in 1:50
            report = capability_report()
            for k in required_keys
                @test haskey(report, k)
            end
            @test length(report["strategy_order"]) == 12
        end
    end

end
