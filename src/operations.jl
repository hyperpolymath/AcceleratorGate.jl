# SPDX-License-Identifier: MPL-2.0
# Operation-first admission and execution evidence for estate coprocessors.

const _SUPPORT_RANK = Dict(
    :declared => 1, :discoverable => 2, :loadable => 3, :runnable => 4,
    :conformant => 5, :resilient => 6, :deterministic => 7,
    :benchmarked => 8, :production_supported => 9,
)
const _DETERMINISM_RANK = Dict(:advisory_only => 1, :tolerance_bounded => 2, :canonical_exact => 3)
const _LANES = (:authoritative, :advisory, :remote_job)
const _FALLBACKS = (:require_named_backend, :require_deterministic_equivalent, :allow_reference, :prefer_accelerated)
const _IMPLEMENTATIONS = (:reference, :native, :hardware, :simulation, :remote)

"""A backend-neutral, versioned operation request admitted by AcceleratorGate."""
struct OperationRequest
    operation::String
    version::VersionNumber
    layout::NamedTuple
    lane::Symbol
    minimum_support::Symbol
    minimum_determinism::Symbol
    fallback::Symbol
    named_provider::Union{Nothing,String}
    allow_simulation::Bool
    function OperationRequest(operation::AbstractString;
            version=v"1.0.0", layout=(;), lane=:advisory,
            minimum_support=:conformant, minimum_determinism=:tolerance_bounded,
            fallback=:prefer_accelerated, named_provider=nothing,
            allow_simulation=false)
        isempty(operation) && throw(ArgumentError("operation id must not be empty"))
        lane in _LANES || throw(ArgumentError("invalid execution lane: $lane"))
        haskey(_SUPPORT_RANK, minimum_support) || throw(ArgumentError("invalid support level: $minimum_support"))
        haskey(_DETERMINISM_RANK, minimum_determinism) || throw(ArgumentError("invalid determinism: $minimum_determinism"))
        fallback in _FALLBACKS || throw(ArgumentError("invalid fallback policy: $fallback"))
        fallback === :require_named_backend && named_provider === nothing &&
            throw(ArgumentError("require_named_backend needs named_provider"))
        new(String(operation), VersionNumber(version), layout, lane, minimum_support,
            minimum_determinism, fallback,
            named_provider === nothing ? nothing : String(named_provider), allow_simulation)
    end
end

"""Auditable support claim for one provider/operation pair."""
struct CapabilityEvidence
    provider_id::String
    provider_version::VersionNumber
    operation::String
    operation_version::VersionNumber
    lanes::Tuple{Vararg{Symbol}}
    support::Symbol
    determinism::Symbol
    implementation::Symbol
    device_class::Symbol
    conformance_digest::Union{Nothing,String}
    function CapabilityEvidence(provider_id, provider_version, operation, operation_version;
            lanes=(:advisory,), support=:declared, determinism=:advisory_only,
            implementation=:simulation, device_class=:cpu, conformance_digest=nothing)
        isempty(provider_id) && throw(ArgumentError("provider id must not be empty"))
        isempty(operation) && throw(ArgumentError("operation id must not be empty"))
        isempty(lanes) && throw(ArgumentError("at least one execution lane is required"))
        all(lane -> lane in _LANES, lanes) || throw(ArgumentError("invalid execution lane"))
        haskey(_SUPPORT_RANK, support) || throw(ArgumentError("invalid support level: $support"))
        haskey(_DETERMINISM_RANK, determinism) || throw(ArgumentError("invalid determinism: $determinism"))
        implementation in _IMPLEMENTATIONS || throw(ArgumentError("invalid implementation kind: $implementation"))
        implementation === :remote && !all(==(:remote_job), lanes) &&
            throw(ArgumentError("remote providers may claim only the remote_job lane"))
        implementation !== :remote && :remote_job in lanes &&
            throw(ArgumentError("only remote providers may claim remote_job"))
        :authoritative in lanes && determinism !== :canonical_exact &&
            throw(ArgumentError("authoritative capability must be canonical_exact"))
        new(String(provider_id), VersionNumber(provider_version), String(operation),
            VersionNumber(operation_version), Tuple(lanes), support, determinism,
            implementation, device_class,
            conformance_digest === nothing ? nothing : String(conformance_digest))
    end
end

"""Evidence returned only after successful execution by the planned provider."""
struct ExecutionEvidence
    provider_id::String
    provider_version::VersionNumber
    operation::String
    operation_version::VersionNumber
    lane::Symbol
    support::Symbol
    determinism::Symbol
    implementation::Symbol
end

abstract type AbstractOperationProvider end

"""Provider backed by a Julia callback; useful for real adapters and explicit simulators."""
struct FunctionProvider <: AbstractOperationProvider
    id::String
    version::VersionNumber
    claims::Vector{CapabilityEvidence}
    callback::Function
    function FunctionProvider(id, version, claims, callback)
        all(claim -> claim.provider_id == id && claim.provider_version == VersionNumber(version), claims) ||
            throw(ArgumentError("every capability must name the provider and version"))
        new(String(id), VersionNumber(version), collect(claims), callback)
    end
end

FunctionProvider(callback::Function, id, version, claims) = FunctionProvider(id, version, claims, callback)

provider_id(provider::FunctionProvider) = provider.id
provider_capabilities(provider::FunctionProvider) = copy(provider.claims)
_execute_provider(provider::FunctionProvider, request::OperationRequest, args...) = provider.callback(request, args...)

const _OPERATION_PROVIDERS = AbstractOperationProvider[]
const _OPERATION_PROVIDER_LOCK = ReentrantLock()

registered_providers() = lock(_OPERATION_PROVIDER_LOCK) do
    copy(_OPERATION_PROVIDERS)
end
clear_provider_registry!() = lock(_OPERATION_PROVIDER_LOCK) do
    empty!(_OPERATION_PROVIDERS)
end

function register_provider!(provider::AbstractOperationProvider)
    id = provider_id(provider)
    isempty(provider_capabilities(provider)) && throw(ArgumentError("provider must claim at least one operation"))
    lock(_OPERATION_PROVIDER_LOCK) do
        any(existing -> provider_id(existing) == id, _OPERATION_PROVIDERS) &&
            throw(ArgumentError("duplicate operation provider id: $id"))
        push!(_OPERATION_PROVIDERS, provider)
    end
    provider
end

function _compatible(claim::CapabilityEvidence, request::OperationRequest)
    claim.operation == request.operation || return false
    claim.operation_version.major == request.version.major || return false
    claim.operation_version.minor >= request.version.minor || return false
    request.lane in claim.lanes || return false
    _SUPPORT_RANK[claim.support] >= _SUPPORT_RANK[request.minimum_support] || return false
    _DETERMINISM_RANK[claim.determinism] >= _DETERMINISM_RANK[request.minimum_determinism] || return false
    request.lane === :authoritative && claim.determinism !== :canonical_exact && return false
    claim.implementation === :simulation && !request.allow_simulation && return false
    request.named_provider !== nothing && claim.provider_id != request.named_provider && return false
    request.fallback === :require_deterministic_equivalent && claim.determinism !== :canonical_exact && return false
    request.fallback === :allow_reference && claim.implementation !== :reference && return false
    true
end

function _preference(claim::CapabilityEvidence)
    kind = Dict(:hardware => 5, :native => 4, :remote => 3, :reference => 2, :simulation => 1)[claim.implementation]
    (kind, _SUPPORT_RANK[claim.support], _DETERMINISM_RANK[claim.determinism])
end

"""Select one provider deterministically. Registration order never breaks ties."""
function plan_operation(request::OperationRequest)
    candidates = Tuple{AbstractOperationProvider,CapabilityEvidence}[]
    lock(_OPERATION_PROVIDER_LOCK) do
        for provider in _OPERATION_PROVIDERS, claim in provider_capabilities(provider)
            _compatible(claim, request) && push!(candidates, (provider, claim))
        end
    end
    isempty(candidates) && throw(ErrorException("no compatible provider for $(request.operation)"))
    sort!(candidates; by=entry -> begin
        preference = _preference(entry[2])
        (-preference[1], -preference[2], -preference[3], entry[2].provider_id)
    end)
    candidates[1]
end

"""Execute exactly the planned provider. A runtime failure is never a fallback signal."""
function execute_operation(request::OperationRequest, args...)
    provider, claim = plan_operation(request)
    value = _execute_provider(provider, request, args...)
    evidence = ExecutionEvidence(claim.provider_id, claim.provider_version,
        claim.operation, request.version, request.lane, claim.support,
        claim.determinism, claim.implementation)
    value, evidence
end

# Enaction v1 C-compatible structs. Idris2 remains their authority; these
# assertions make drift fail at Julia load rather than corrupting a call.
struct _EnactionRequest
    abi_major::UInt16; abi_minor::UInt16; operation_major::UInt16; operation_minor::UInt16
    operation::UInt32; lane::UInt32; minimum_support::UInt32; minimum_determinism::UInt32
    layout::UInt32; reserved::UInt32; dim0::UInt64; dim1::UInt64; dim2::UInt64
end
struct _EnactionBufferIn
    data::Ptr{Float32}; len::UInt64
end
struct _EnactionBufferOut
    data::Ptr{Float32}; len::UInt64
end
struct _EnactionCapability
    abi_major::UInt16; abi_minor::UInt16; operation_major::UInt16; operation_minor::UInt16
    operation::UInt32; support::UInt32; determinism::UInt32; backend_id::UInt32
    device_class::UInt32; flags::UInt32
end
struct _EnactionEvidence
    abi_major::UInt16; abi_minor::UInt16; operation_major::UInt16; operation_minor::UInt16
    operation::UInt32; backend_id::UInt32; support::UInt32; determinism::UInt32
end

sizeof(_EnactionRequest) == 56 || error("Enaction Request ABI drift")
sizeof(_EnactionBufferIn) == 16 || error("Enaction buffer ABI drift")
sizeof(_EnactionCapability) == 32 || error("Enaction Capability ABI drift")
sizeof(_EnactionEvidence) == 24 || error("Enaction Evidence ABI drift")

const _OP_CODE = Dict(
    "enaction.tensor.f32.relu" => UInt32(3), "enaction.tensor.f32.relu6" => UInt32(4),
    "enaction.tensor.f32.matmul" => UInt32(5), "enaction.tensor.f32.add" => UInt32(6),
    "enaction.tensor.f32.mul" => UInt32(7),
)
const _CODE_OP = Dict(value => key for (key, value) in _OP_CODE)
const _SUPPORT_CODE = Dict(key => UInt32(value) for (key, value) in _SUPPORT_RANK)
const _DETERMINISM_CODE = Dict(key => UInt32(value) for (key, value) in _DETERMINISM_RANK)

mutable struct EnactionZigProvider <: AbstractOperationProvider
    id::String
    version::VersionNumber
    path::String
    handle::Ptr{Cvoid}
    claims::Vector{CapabilityEvidence}
    unary::Ptr{Cvoid}
    binary::Ptr{Cvoid}
end

provider_id(provider::EnactionZigProvider) = provider.id
provider_capabilities(provider::EnactionZigProvider) = copy(provider.claims)

function EnactionZigProvider(path::AbstractString)
    isfile(path) || throw(ArgumentError("Enaction Zig library not found: $path"))
    handle = Libdl.dlopen(path)
    abi_version = ccall(Libdl.dlsym(handle, :enaction_accel_abi_version), UInt32, ())
    abi_version == 0x00010000 || throw(ErrorException("unsupported Enaction accelerator ABI: $abi_version"))
    count = ccall(Libdl.dlsym(handle, :enaction_accel_capability_count), UInt32, ())
    at = Libdl.dlsym(handle, :enaction_accel_capability_at)
    claims = CapabilityEvidence[]
    for index in UInt32(0):(count - UInt32(1))
        raw = Ref{_EnactionCapability}()
        status = ccall(at, UInt32, (UInt32, Ref{_EnactionCapability}), index, raw)
        status == 0 || throw(ErrorException("capability query failed with status $status"))
        raw[].abi_major == 1 && raw[].abi_minor == 0 &&
            raw[].operation_major == 1 && raw[].operation_minor == 0 &&
            raw[].backend_id == 1 && raw[].device_class == 1 ||
            throw(ErrorException("invalid Enaction capability evidence at index $index"))
        operation = get(_CODE_OP, raw[].operation, nothing)
        operation === nothing && continue # fixed-i32 uses a different Julia buffer surface
        support = Symbol(first(key for (key, value) in _SUPPORT_CODE if value == raw[].support))
        determinism = Symbol(first(key for (key, value) in _DETERMINISM_CODE if value == raw[].determinism))
        push!(claims, CapabilityEvidence("enaction.cpu.zig.scalar", v"1.0.0", operation, v"1.0.0";
            lanes=(:advisory,), support, determinism, implementation=:native,
            device_class=:cpu, conformance_digest=nothing))
    end
    EnactionZigProvider("enaction.cpu.zig.scalar", v"1.0.0", String(path), handle, claims,
        Libdl.dlsym(handle, :enaction_accel_execute_f32),
        Libdl.dlsym(handle, :enaction_accel_execute_f32_binary))
end

function _native_layout(request::OperationRequest)
    if request.operation == "enaction.tensor.f32.matmul"
        all(key -> haskey(request.layout, key), (:m, :k, :n)) || throw(ArgumentError("matmul layout needs m, k and n"))
        UInt32(2), UInt64(request.layout.m), UInt64(request.layout.k), UInt64(request.layout.n)
    else
        haskey(request.layout, :len) || throw(ArgumentError("vector layout needs len"))
        UInt32(3), UInt64(request.layout.len), UInt64(0), UInt64(0)
    end
end

function _execute_provider(provider::EnactionZigProvider, request::OperationRequest, args...)
    code = get(_OP_CODE, request.operation, nothing)
    code === nothing && throw(ArgumentError("unsupported native operation: $(request.operation)"))
    layout, dim0, dim1, dim2 = _native_layout(request)
    raw_request = Ref(_EnactionRequest(1, 0, UInt16(request.version.major), UInt16(request.version.minor),
        code, 2, _SUPPORT_CODE[request.minimum_support], _DETERMINISM_CODE[request.minimum_determinism],
        layout, 0, dim0, dim1, dim2))
    evidence = Ref{_EnactionEvidence}()
    inputs = if request.operation == "enaction.tensor.f32.matmul"
        map(value -> vec(permutedims(Float32.(value))), args)
    else
        map(value -> vec(Float32.(value)), args)
    end
    expected = request.operation == "enaction.tensor.f32.matmul" ? Int(dim0 * dim2) : Int(dim0)
    output = Vector{Float32}(undef, expected)
    output_buffer = Ref(_EnactionBufferOut(pointer(output), UInt64(length(output))))
    status = GC.@preserve inputs output begin
        buffers = map(value -> Ref(_EnactionBufferIn(pointer(value), UInt64(length(value)))), inputs)
        if length(buffers) == 1
            ccall(provider.unary, UInt32,
                (Ref{_EnactionRequest}, Ref{_EnactionBufferIn}, Ref{_EnactionBufferOut}, Ref{_EnactionEvidence}),
                raw_request, buffers[1], output_buffer, evidence)
        elseif length(buffers) == 2
            ccall(provider.binary, UInt32,
                (Ref{_EnactionRequest}, Ref{_EnactionBufferIn}, Ref{_EnactionBufferIn}, Ref{_EnactionBufferOut}, Ref{_EnactionEvidence}),
                raw_request, buffers[1], buffers[2], output_buffer, evidence)
        else
            throw(ArgumentError("native tensor operations take one or two inputs"))
        end
    end
    status == 0 || throw(ErrorException("Enaction Zig operation failed with ABI status $status"))
    raw_evidence = evidence[]
    raw_evidence.abi_major == 1 && raw_evidence.abi_minor == 0 &&
        raw_evidence.operation_major == request.version.major &&
        raw_evidence.operation_minor == request.version.minor &&
        raw_evidence.operation == code && raw_evidence.backend_id == 1 &&
        raw_evidence.support >= _SUPPORT_CODE[request.minimum_support] &&
        raw_evidence.determinism >= _DETERMINISM_CODE[request.minimum_determinism] ||
        throw(ErrorException("invalid Enaction execution evidence"))
    request.operation == "enaction.tensor.f32.matmul" ? reshape(output, Int(dim2), Int(dim0))' |> Matrix : output
end
