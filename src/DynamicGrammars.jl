module DynamicGrammars

export ASTNode, Reference, Structure, Terminal, Concatenation, Repetition, Alternative, RuleSet
export value, terminal_type, terminal_revert, terminal_concat, terminal_merge, parse_string

abstract type Node{TT} end

include("nodes.jl")

include("terminals.jl")

struct RuleSet{TT}
    nodes::Vector{Node{TT}}
    names::Vector{String}
    indices::Dict{String, Int}
    root::Int
end

simplify(r::RuleSet, n::Node) = n
simplify(r::RuleSet, n::Reference) = (n.node > 0 && r.nodes[n.node] isa Terminal) ? r.nodes[n.node] : n

simplify(r::RuleSet, n::Concatenation) =
        length(n.elements) == 1 ? simplify(r, n.elements[1]) :
        Concatenation(Node{terminal_type(r)}[simplify(r, c) for c in n.elements])
simplify(r::RuleSet, n::Repetition) = Repetition(simplify(r, n.element), n.min_count, n.max_count, n.greedy)
simplify(r::RuleSet, n::Alternative) =
        length(n.elements) == 1 ? simplify(r, n.elements[1]) :
        Alternative(Node{terminal_type(r)}[simplify(r, c) for c in n.elements])

simplify(r::RuleSet) = RuleSet([simplify(r, n) for n in r.nodes], r.names, r.indices, r.root)

terminal_type(::RuleSet{TT}) where TT = TT

include("parser.jl")

include("ast.jl")

include("grammarbuilder.jl")

RuleSet{TT}(ast::ASTNode) where TT = construct_ruleset(TT, ast)

function list_errors(r::RuleSet, cache::ParserCache, start_pos)
    list = Pair{Int, String}[]
    for (state, index) in cache.cache
        if isempty(result_range(cache, index)) && state.position >= start_pos
            push!(list, state.position => r.names[state.node])
        end
    end
    sort!(list)
    return list
end

function parse_string(r::RuleSet{TT}, d, out_type) where TT
    cache = ParserCache(Dict{State, Int}(), UnitRange{Int}[], StateResult[])
    result_root = parse_node_at!(cache, r, r.nodes[r.root], firstindex(d), 0, d)
    mxpos = 1
    mxi = 0
    for i in result_range(cache, result_root)
        if result(cache, i).next_position > mxpos
            mxi = i
            mxpos = result(cache, i).next_position
        end
    end
    return transform_structure(cache, mxi, d, out_type), mxpos, list_errors(r, cache, mxpos)
end

end
