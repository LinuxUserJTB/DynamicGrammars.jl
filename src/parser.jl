struct State
    position::Int
    node::Int
    parameter::Int
end

Base.hash(s::State, u::UInt) = hash(s.parameter, hash(s.node, hash(s.position, u)))
(Base. ==)(s1::State, s2::State) = s1.position == s2.position && s1.node == s2.node && s1.parameter == s2.parameter

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

function parse_node_at!(c::ParserCache, r::RuleSet, n::Reference, s::State, rs_link::Int, d)
    s2 = State(s.position, n.node, n.parameter(s.parameter))
    cache_index = request_key!(c, s2)
    if first(result_range(c, cache_index)) == 0
        if n.node == 0
            set_result_range!(c, cache_index, empty_end_range(c))
            push_result!(c, cache_index, StateResult("", -1, s.position, s.position, 0, 0))
        else
            sub_i = parse_node_at!(c, r, r.nodes[n.node], s2, 0, d)
            set_result_range!(c, cache_index, empty_end_range(c))
            for rnode in result_range(c, sub_i)
                rso = result(c, rnode)
                push_result!(c, cache_index, StateResult("", -1, s.position, rso.next_position, 0, rnode))
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
        push_result!(c, rs_index, StateResult("", -1, s.position, rso.next_position, rs_link, rnode))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Structure, s::State, rs_link::Int, d)
    s2 = State(s.position, 0, s.parameter)
    sub_i = parse_node_at!(c, r, n.definition_node, s2, 0, d)
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for rnode in result_range(c, sub_i)
        rso = result(c, rnode)
        push_result!(c, rs_index, StateResult(n.key, n.structure_type, s.position, rso.next_position, rs_link, rnode))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Terminal, s::State, rs_link::Int, d)
    node, next_position = terminal_match(n, n.root, d, s.position)
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    if node == 0
        push_result!(c, rs_index, StateResult("", -1, s.position, next_position, rs_link, 0))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Concatenation, s::State, rs_link::Int, d)
    # use local cache: position -> result node
    last = Dict{Int, Int}(s.position => 0)
    next = Dict{Int, Int}()
    for node in n.elements
        for (position, link) in last
            s2 = State(position, 0, s.parameter)
            sub_i = parse_node_at!(c, r, node, s2, link, d)
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
        push_result!(c, rs_index, StateResult("", -1, s.position, position, rs_link, link))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Repetition, s::State, rs_link::Int, d)
    min_count = n.min_count(s.parameter)
    max_count = n.max_count(s.parameter)
    if max_count == 0
        max_count = typemax(max_count)
    end
    # use local cache: position -> result node
    last = Dict{Int, Int}(s.position => 0)
    final = Dict{Int, Int}()
    reached = 0
    for count in 1:max_count
        lc = Dict{Int, Int}()
        for (position, link) in last
            s2 = State(position, 0, s.parameter)
            rs_index = parse_node_at!(c, r, n.element, s2, link, d)
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
        push_result!(c, rs_index, StateResult("", -1, s.position, position, rs_link, link))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Repetition{<:Any, <:Terminal}, s::State, rs_link::Int, d)
    min_count = n.min_count(s.parameter)
    max_count = n.max_count(s.parameter)
    if max_count == 0
        max_count = typemax(max_count)
    end
    position = s.position
    succ = n.greedy ? Int[min_count <= 0 ? s.position : 0] : Int[]
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
        push_result!(c, rs_index, StateResult("", -1, s.position, pos, rs_link, 0))
    end
    return rs_index
end

function parse_node_at!(c::ParserCache, r::RuleSet, n::Alternative, s::State, rs_link::Int, d)
    # use local cache: position -> result node
    lc = Dict{Int, Int}()
    # reverse: first elements have priority so their results overwrite others
    for node in reverse(n.elements)
        s2 = State(s.position, 0, s.parameter)
        sub_i = parse_node_at!(c, r, node, s2, 0, d)
        for rnode in result_range(c, sub_i)
            rso = result(c, rnode)
            lc[rso.next_position] = rnode
        end
    end
    rs_index = request_key!(c)
    set_result_range!(c, rs_index, empty_end_range(c))
    for (position, link) in sort!(collect(lc))
        push_result!(c, rs_index, StateResult("", -1, s.position, position, rs_link, link))
    end
    return rs_index
end
