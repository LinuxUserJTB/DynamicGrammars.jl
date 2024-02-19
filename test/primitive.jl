using DynamicGrammars

terminal_value(s, def) = s == "." ? def : typeof(def)(parse(Int, s))

function terminal_range(s, TT)
    start, stop = DynamicGrammars.rangemin(TT), DynamicGrammars.rangemax(TT)
    if contains(s, '-')
        s1, s2 = split(s, '-'; limit=2)
        start, stop = terminal_value(s1, start), terminal_value(s2, stop)
    elseif s != "."
        start = stop = terminal_value(s, start)
    end
    return Terminal{TT}(start, stop, false)
end

function parse_node(ruleset::RuleSet, str)
    TT = terminal_type(ruleset)
    if str == "()"
        # empty node
        return Reference{TT}(0, str)
    elseif isdigit(str[begin]) || str[begin] == '.' || str[begin] == '-'
        # string node
        parts = Terminal{TT}[]
        for part in split(str, ';')
            revert, rem = if part[begin] == '-'
                true, part[nextind(part, firstindex(part)):end]
            else
                false, part
            end
            str = terminal_concat([terminal_range(s, TT) for s in split(rem, '*')])
            push!(parts, revert ? terminal_revert(str) : str)
        end
        return terminal_merge(parts)
    else
        # reference
        return Reference{TT}(ruleset.indices[str], str)
    end
end

function parse_concat(ruleset, line)
    TT = terminal_type(ruleset)
    children = DynamicGrammars.Node{TT}[]
    for part in split(line, ' ')
        if isempty(part)
            continue
        end
        if contains(part, '=')
            name, node = strip.(split(part, '='; limit=2))
            structure_type, key = if endswith(name, "[*]")
                0, name[begin:prevind(name, lastindex(name), 3)]
            elseif endswith(name, "[]")
                1, name[begin:prevind(name, lastindex(name), 2)]
            elseif name == "*"
                2, ""
            elseif name == "_"
                -1, name
            else
                2, name
            end
            push!(children, Structure(key, structure_type, parse_node(ruleset, node)))
        else
            push!(children, parse_node(ruleset, part))
        end
    end
    if length(children) == 1
        return children[1]
    end
    return Concatenation(children)
end

function generate_primitive_grammar(terminaltype, spec)
    lines = filter!(!isempty, [split(s, '#'; limit=2)[begin] for s in split(spec, '\n')])
    rules = [strip.(split(line, "=>"; limit=2)) for line in lines]
    indices = Dict{String, Int}()
    nodes = DynamicGrammars.Node{terminaltype}[]
    names = String[]
    for r in rules
        if !haskey(indices, r[1])
            push!(names, r[1])
            indices[names[end]] = lastindex(names)
            push!(nodes, Alternative(DynamicGrammars.Node{terminaltype}[]))
        end
    end
    ruleset = RuleSet{terminaltype}(nodes, names, indices, indices["root"])
    for r in rules
        push!(nodes[indices[r[1]]].elements, parse_concat(ruleset, r[2]))
    end
    return ruleset
end
