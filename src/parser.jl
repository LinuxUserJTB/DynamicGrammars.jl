struct State
    position::Int
    node::Int
end

Base.hash(s::State, u::UInt) = hash(hash(s.node, hash(s.position, u)))
(Base. ==)(s1::State, s2::State) = s1.position == s2.position && s1.node == s2.node

struct StateResult
    key::String
    structure_type::Int
    start_position::Int
    next_position::Int
    prev_node::Int
    last_child::Int
end

Base.isless(s1::StateResult, s2::StateResult) = isless(s1.next_position, s2.next_position)

struct ParserCache
    # data structure maintaining already known states
    # TODO multi-root avl-tree. one root for each input position -> each tree is small
    cache::Dict{State, Int}
    result_ranges::Vector{UnitRange{Int}}
    results::Vector{StateResult}
end

function request_key!(c::ParserCache, s::State)
    if haskey(c.cache, s)
        return c.cache[s]
    else
        return c.cache[s] = request_key!(c)
    end
end

function request_key!(c::ParserCache)
    push!(c.result_ranges, 0:-1)
    return lastindex(c.result_ranges)
end

result_range(c::ParserCache, i) = c.result_ranges[i]
result(c::ParserCache, i) = c.results[i]
empty_end_range(c::ParserCache) = (lastindex(c.results) + 1):0
set_result_range!(c::ParserCache, i, r) = c.result_ranges[i] = r

function push_result!(c::ParserCache, i, r::StateResult)
    range = result_range(c, i)
    @assert last(range) == lastindex(c.results)
    push!(c.results, r)
    c.result_ranges[i] = first(range):lastindex(c.results)
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Reference, p, rs_link::Int, d)
    s = State(p, n.node)
    cache_index = request_key!(c, s)
    if first(result_range(c, cache_index)) == 0
        if n.node == 0
            set_result_range!(c, cache_index, empty_end_range(c))
            push_result!(c, cache_index, StateResult("", -1, p, p, 0, 0))
        else
            sub_i = parse_node_at!(c, r, r.nodes[n.node], p, 0, d)
            set_result_range!(c, cache_index, empty_end_range(c))
            for rnode in result_range(c, sub_i)
                rso = result(c, rnode)
                push_result!(c, cache_index, StateResult("", -1, p, rso.next_position, 0, rnode))
            end
        end
    end
    if rs_link == 0
        return cache_index
    end
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for rnode in result_range(c, cache_index)
        rso = result(c, rnode)
        push_result!(c, rs_index, StateResult("", -1, p, rso.next_position, rs_link, rnode))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Structure, p, rs_link::Int, d)
    sub_i = parse_node_at!(c, r, n.definition_node, p, 0, d)
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for rnode in result_range(c, sub_i)
        rso = result(c, rnode)
        push_result!(c, rs_index, StateResult(n.key, n.structure_type, p, rso.next_position, rs_link, rnode))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Terminal, p, rs_link::Int, d)
    node, next_position = terminal_match(n, n.root, d, p)
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    if node == 0
        push_result!(c, rs_index, StateResult("", -1, p, next_position, rs_link, 0))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Concatenation, p, rs_link::Int, d)
    # use local cache: position -> result node
    last = Dict{Int, Int}(p => 0)
    next = Dict{Int, Int}()
    for node in n.elements
        for (position, link) in last
            sub_i = parse_node_at!(c, r, node, position, link, d)
            for rnode in result_range(c, sub_i)
                rso = result(c, rnode)
                next[rso.next_position] = rnode
            end
        end
        empty!(last)
        # use current results for next iteration
        last, next = next, last
        if isempty(last)
            break
        end
    end
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for (position, link) in sort!(collect(last))
        push_result!(c, rs_index, StateResult("", -1, p, position, rs_link, link))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Repetition, p, rs_link::Int, d)
    min_count = n.min_count
    max_count = n.max_count
    if max_count == 0
        max_count = typemax(max_count)
    end
    # use local cache: position -> result node
    last = Dict{Int, Int}(p => 0)
    final = Dict{Int, Int}()
    reached = 0
    for count in 1:max_count
        lc = Dict{Int, Int}()
        for (position, link) in last
            rs_index = parse_node_at!(c, r, n.element, position, link, d)
            if n.greedy && count > min_count && isempty(result_range(c, rs_index))
                final[position] = link
            end
            for rnode in result_range(c, rs_index)
                rso = result(c, rnode)
                lc[rso.next_position] = rnode
            end
        end
        # use current results for next iteration
        last = lc
        reached = count
        if isempty(last)
            break
        elseif count >= min_count && !n.greedy
            for entry in last
                push!(final, entry)
            end
        end
    end
    if reached >= min_count && n.greedy
        for entry in last
            push!(final, entry)
        end
    end
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for (position, link) in sort!(collect(final))
        push_result!(c, rs_index, StateResult("", -1, p, position, rs_link, link))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Repetition{<:Any, <:Terminal}, p, rs_link::Int, d)
    min_count = n.min_count
    max_count = n.max_count
    if max_count == 0
        max_count = typemax(max_count)
    end
    position = p
    succ = n.greedy ? Int[min_count <= 0 ? p : 0] : Int[]
    for count in 1:max_count
        node, position = terminal_match(n.element, n.element.root, d, position)
        if node < 0
            break
        elseif count < min_count
            continue
        elseif n.greedy
            succ[begin] = position
        else
            push!(succ, position)
        end
    end
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for pos in sort!(succ)
        if pos == 0
            continue
        end
        push_result!(c, rs_index, StateResult("", -1, p, pos, rs_link, 0))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Alternative, p, rs_link::Int, d)
    # use local cache: position -> result node
    lc = Dict{Int, Int}()
    # reverse: first elements have priority so their results overwrite others
    for node in reverse(n.elements)
        sub_i = parse_node_at!(c, r, node, p, 0, d)
        for rnode in result_range(c, sub_i)
            rso = result(c, rnode)
            lc[rso.next_position] = rnode
        end
    end
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for (position, link) in sort!(collect(lc))
        push_result!(c, rs_index, StateResult("", -1, p, position, rs_link, link))
    end
    return rs_index
end
