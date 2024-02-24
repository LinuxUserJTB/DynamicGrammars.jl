using DynamicGrammars

function parse_parameters(data::ASTNode)
    c0 = parse(Int, value(data, "c0", "0"))
    c1 = haskey(data, "c1")
    return c0, c1
end

function construct_node(r::RuleSet, data::ASTNode, ::Type{Reference})
    name = value(data, "reference")
    return Reference{terminal_type(r)}(r.indices[name], name)
end

function construct_node(r::RuleSet, data::ASTNode, ::Type{Structure})
    structure = data["structure"]
    key = value(structure, "key", "")
    structure_type = haskey(structure, "string") ? 0 : haskey(structure, "array") ? 1 : haskey(structure, "dict") ? 2 : -1
    if structure_type == -1
        error("unknown structure type")
    end
    definition = construct_node(r, data["definition"])
    return Structure(key, structure_type, definition)
end

function preparestring(str)
    out = eltype(str)[]
    i = firstindex(str)
    while i <= lastindex(str)
        ch = str[i]
        if ch == '\\'
            i = nextind(str, i)
            ch = str[i]
            if ch == 'n'
                ch = '\n'
            end
        end
        push!(out, ch)
        i = nextind(str, i)
    end
    return typeof(str)(out)
end

function charvalue(r::RuleSet, data::ASTNode)
    TT = terminal_type(r)
    if haskey(data, "char")
        TT(preparestring(value(data, "char"))[begin])
    elseif haskey(data, "codepoint")
        TT(parse(Int, value(data, "codepoint")))
    else
        error("unknown char value type")
    end
end

rangebound(r::RuleSet, data::ASTNode, def) = haskey(data, "wildcard") ? def : charvalue(r, data)

function construct_terminal_part(r::RuleSet, data::ASTNode)
    TT = terminal_type(r)
    if haskey(data, "string")
        return Terminal(preparestring(value(data, "string")), false)
    elseif haskey(data, "value")
        return Terminal{TT}(charvalue(r, data["value"]), false)
    elseif haskey(data, "range")
        rng = data["range"]
        if haskey(rng, "wildcard")
            return Terminal{TT}()
        end
        start = rangebound(r, rng["start"], DynamicGrammars.rangemin(TT))
        stop = rangebound(r, rng["stop"], DynamicGrammars.rangemax(TT))
        return Terminal{TT}(start, stop, false)
    end
end

function construct_terminal_string(r::RuleSet, data::ASTNode)
    sign = value(data, "sign", "")
    partdata = data["parts"]
    parts = [construct_terminal_part(r, partdata[i]) for i in eachindex(partdata)]
    conc = terminal_concat(parts)
    return sign == "-" ? terminal_revert(conc) : conc
end

function construct_node(r::RuleSet, data::ASTNode, ::Type{Terminal})
    altdata = data["terminal"]
    alts = [construct_terminal_string(r, altdata[i]) for i in eachindex(altdata)]
    return terminal_merge(alts)
end

function construct_node(r::RuleSet, data::ASTNode, ::Type{Concatenation})
    elementdata = data["concatenation"]
    elements = DynamicGrammars.Node{terminal_type(r)}[construct_node(r, elementdata[i]) for i in eachindex(elementdata)]
    return Concatenation(elements)
end

function construct_node(r::RuleSet, data::ASTNode, ::Type{Repetition})
    min_c = parse(Int, value(data, "min"))
    max_c = parse(Int, value(data, "max", "0"))
    greedy = haskey(data, "greedy")
    element = construct_node(r, data["repetition"])
    return Repetition(element, min_c, max_c, greedy)
end

function construct_node(r::RuleSet, data::ASTNode, ::Type{Alternative})
    elementdata = data["alternative"]
    elements = [construct_node(r, elementdata[i]) for i in eachindex(elementdata)]
    return Alternative(elements)
end

function construct_node(r::RuleSet, data::ASTNode)
    if haskey(data, "reference")
        construct_node(r, data, Reference)
    elseif haskey(data, "structure")
        construct_node(r, data, Structure)
    elseif haskey(data, "terminal")
        construct_node(r, data, Terminal)
    elseif haskey(data, "concatenation")
        construct_node(r, data, Concatenation)
    elseif haskey(data, "repetition")
        construct_node(r, data, Repetition)
    elseif haskey(data, "alternative")
        construct_node(r, data, Alternative)
    elseif haskey(data, "empty")
        return Reference{terminal_type(r)}(0, "()")
    else
        display(data.named_children)
        error("unknown node type")
    end
end

function construct_ruleset(TT, data::ASTNode)
    ruledata = data["rules"]
    nodes = DynamicGrammars.Node{TT}[]
    names = String[]
    indices = Dict{String, Int}()
    # pre-index the node names
    for i in eachindex(ruledata)
        rule = ruledata[i]
        name = value(rule, "left")
        if !haskey(indices, name)
            push!(names, name)
            push!(nodes, Alternative(DynamicGrammars.Node{TT}[]))
            indices[name] = lastindex(names)
        end
    end
    r = RuleSet(nodes, names, indices, indices["root"])
    # create nodes
    for i in eachindex(ruledata)
        rule = ruledata[i]
        name = value(rule, "left")
        definition = rule["right"]
        push!(nodes[indices[name]].elements, construct_node(r, definition))
    end
    return DynamicGrammars.simplify(r)
end
