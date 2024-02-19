struct ASTNode{VT}
    value::VT
    structure_type::Int
    children::Vector{ASTNode{VT}}
    named_children::Dict{String, Int}
end

# ASTNode behaves like vector and dict
value(n::ASTNode) = n.value
value(n::ASTNode, k) = value(n[k])
value(n::ASTNode, k, def) = haskey(n, k) ? value(n[k]) : def
Base.getindex(n::ASTNode, i::Integer) = n.children[i]
Base.getindex(n::ASTNode, k::AbstractString) = n.children[n.named_children[k]]
Base.eachindex(n::ASTNode) = eachindex(n.children)
Base.keys(n::ASTNode) = keys(n.named_children)
Base.haskey(n::ASTNode, i::Integer) = i in eachindex(n.children)
Base.haskey(n::ASTNode, k::AbstractString) = haskey(n.named_children, k)

function transform_structure!(n::ASTNode{<:Vector}, c::ParserCache, index, d; dep=0)
    if index == 0
        return
    end
    rs = result(c, index)
    transform_structure!(n, c, rs.prev_node, d; dep=dep)
    if n.structure_type == 0
        if rs.last_child == 0# && isempty(rs.key)
            append!(n.value, d[rs.start_position:prevind(d, rs.next_position)])
        else
            transform_structure!(n, c, rs.last_child, d; dep=dep)
        end
        if !isempty(rs.key) && rs.key != "_"
            @warn "key $(rs.key) found in string"
        end
    elseif rs.structure_type >= 0
        n2 = ASTNode(typeof(n.value)(), rs.structure_type, typeof(n.children)(), typeof(n.named_children)())
        push!(n.children, n2)
        #println(' '^dep, "\"$(rs.key)\"=type $(rs.structure_type): ", d[rs.start_position:prevind(d, rs.next_position)])
        if n.structure_type == 2
            n.named_children[rs.key] = lastindex(n.children)
        elseif !isempty(rs.key)
            @warn "key $(rs.key) found in array"
        end
        #if rs.structure_type == 0
            #println("string value: ", d[rs.start_position:prevind(d, rs.next_position)])
        #end
        transform_structure!(n2, c, rs.last_child, d; dep=dep + 1)
    else
        transform_structure!(n, c, rs.last_child, d; dep=dep)
    end
end

transform_type_structure(n::ASTNode, out_type) =
        ASTNode{out_type}(out_type(n.value), n.structure_type,
        [transform_type_structure(c, out_type) for c in n.children], n.named_children)

function transform_structure(c::ParserCache, index, d, out_type)
    # root is dict
    n = ASTNode{Vector{eltype(d)}}([], 2, [], Dict())
    transform_structure!(n, c, index, d)
    return transform_type_structure(n, out_type)
end
