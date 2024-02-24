terminal_type(::Type{<:Node{TT}}) where TT = TT
terminal_type(::Node{TT}) where TT = TT

struct Reference{TT} <: Node{TT}
    node::Int
    name::String
end

struct Structure{TT, NT} <: Node{TT}
    key::String # if dict key
    structure_type::Int # 0 = string, 1 = array, 2 = dict
    definition_node::NT
end

Structure(key, structure_type, definition_node) =
        Structure{terminal_type(definition_node), typeof(definition_node)}(key, structure_type, definition_node)

struct Terminal{TT} <: Node{TT}
    # encodes a trie with character ranges to match string classes
    ranges::Vector{Tuple{TT, TT, Int}} # (min, max, next_node)
    nodes::Vector{UnitRange{Int}}
    root::Int
end

rangemin(x) = rangemin(typeof(x))
rangemax(x) = rangemax(typeof(x))
rangemin(t::Type) = typemin(t)
rangemax(t::Type) = typemax(t)
rangemax(::Type{Char}) = Char(0x1ffffe)

Terminal{TT}(min::TT, max::TT, neg::Bool) where TT = Terminal([(min, max, neg ? -2 : 0)], [1:1], 1)
Terminal{TT}(sym::TT, neg::Bool) where TT = Terminal{TT}(sym, sym, neg)
Terminal{TT}() where TT = Terminal{TT}(rangemin(TT), rangemax(TT), false)

Terminal(str::AbstractString, neg::Bool) = Terminal(collect(str), neg)

function Terminal(str::AbstractVector{TT}, neg::Bool) where TT
    ranges = [(str[i], str[i], i + 1) for i in eachindex(str)]
    ranges[end] = (ranges[end][1], ranges[end][2], neg ? -2 : 0)
    nodes = [i:i for i in eachindex(str)]
    return Terminal(ranges, nodes, 1)
end

function terminal_match(t::Terminal{TT}, s::TT, node) where TT
    a, b = first(t.nodes[node]), last(t.nodes[node])
    while a < b
        m = (a + b) >> 1
        if s <= t.ranges[m][2]
            b = m
        else
            a = m + 1
        end
    end
    if t.ranges[a][1] <= s && s <= t.ranges[a][2]
        return t.ranges[a][3]
    end
    return -1
end

function terminal_match(t::Terminal, node, d, index)
    while node > 0 && index <= lastindex(d)
        sym = d[index]
        node = terminal_match(t, sym, node)
        index = nextind(d, index)
    end
    if node > 0
        node = -1
    end
    return node, index
end

struct Concatenation{TT, NT} <: Node{TT}
    elements::Vector{NT}
end

Concatenation(elements) = Concatenation{terminal_type(eltype(elements)), eltype(elements)}(elements)

struct Repetition{TT, NT} <: Node{TT}
    element::NT
    min_count::Int
    max_count::Int # 0 means ∞
    greedy::Bool
end

Repetition(element, min_count, max_count, greedy) =
        Repetition{terminal_type(element), typeof(element)}(element, min_count, max_count, greedy)

struct Alternative{TT, NT} <: Node{TT}
    elements::Vector{NT}
end

Alternative(elements) = Alternative{terminal_type(eltype(elements)), eltype(elements)}(elements)
