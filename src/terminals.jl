substitute_node(n, shift, next_root) = n < 0 ? n : n == 0 ? next_root : n + shift
revert_node(n) = n == 0 ? -2 : n == -2 ? 0 : n

terminal_revert(t::Terminal) = Terminal([(r[1], r[2], revert_node(r[3])) for r in t.ranges], t.nodes, revert_node(t.root))

function terminal_concat(v)
    if isempty(v)
        return Terminal{terminal_type(eltype(v))}([], [], 0)
    end
    result = Terminal{terminal_type(eltype(v))}([], [], 0)
    next_root = 0
    for t in reverse(v)
        range_shift = lastindex(result.ranges)
        node_shift = lastindex(result.nodes)
        append!(result.ranges, ((r[1], r[2], substitute_node(r[3], node_shift, next_root)) for r in t.ranges))
        append!(result.nodes, ((first(n) + range_shift):(last(n) + range_shift) for n in t.nodes))
        next_root = node_shift + t.root
    end
    return typeof(result)(result.ranges, result.nodes, next_root)
end

function terminal_merge!(selection_stack, result, selection)
    destnode = selection[2]
    # last exclusive
    sourceranges = [r for (t, n) in selection[1] for r in t.ranges[t.nodes[n]]]
    symbolset = Set([[r[1] for r in sourceranges]; [r[2] + 1 for r in sourceranges]])
    symbols = sort!(collect(symbolset))
    firstrange = nextind(result.ranges, lastindex(result.ranges))
    revsel = reverse(selection[1])
    for i in firstindex(symbols):prevind(symbols, lastindex(symbols))
        start, stop = symbols[i], symbols[nextind(symbols, i)] - 1
        sourcesel = eltype(selection)[]
        # give first nodes priority
        dest = -1
        for sel in revsel
            node = terminal_match(sel[1], start, sel[2])
            if node == -1
                continue
            elseif node <= 0
                empty!(sourcesel)
                dest = node
            else
                push!(sourcesel, (sel[1], node))
            end
        end
        # don't create nodes for accepting/rejecting states
        if !isempty(sourcesel)
            push!(result.nodes, 1:0)
            dest = lastindex(result.nodes)
            push!(selection_stack, (sourcesel, dest))
        end
        if dest >= 0
            push!(result.ranges, (start, stop, dest))
        end
    end
    lastrange = lastindex(result.ranges)
    result.nodes[destnode] = firstrange:lastrange
    return nothing
end

function terminal_merge(v)
    TT = terminal_type(eltype(v))
    result = Terminal{TT}([], [1:0], 1)
    nodesource = [([(t, t.root) for t in v], 1)]
    while !isempty(nodesource)
        selection = pop!(nodesource)
        terminal_merge!(nodesource, result, selection)
    end
    return result
end
