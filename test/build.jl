using DynamicGrammars

include("primitive.jl")

function print_errors(source, pos, errors)
    println("could not parse:\n", source[pos:end])
    for (p, node) in errors
        println("tried to parse \"", source[p:min(lastindex(source), pos+20)], "\" as ", node)
    end
end

function read_and_test(grammar0, source)
    # parse source with grammar
    @time ast1, num, err = parse_string(grammar0, source, String)
    if num <= lastindex(source)
        print_errors(source, num, err)
        error("previous grammar could not parse source!")
    end
    @info "source parsed (1)"
    # build grammar
    @time grammar1 = RuleSet{Char}(ast1)
    @info "grammar created (1)"
    # parse source with grammar2 and compare
    @time ast2, num, err = parse_string(grammar1, source, String)
    if num <= lastindex(source)
        print_errors(source, num, err)
        error("grammar could not parse itself!")
    end
    @info "source parsed (2)"
    @time grammar2 = RuleSet{Char}(ast2)
    @info "grammar created (2)"
    if repr(grammar1) != repr(grammar2)
        @warn "grammar does not replicate itself!"
    end
    return grammar2
end

function test_pipeline(sources)
    @info "initial grammar file: $(sources[begin])"
    grammars = [generate_primitive_grammar(Char, read(sources[begin], String))]
    for s in sources
        @info "test grammar file: $s"
        push!(grammars, read_and_test(grammars[end], read(s, String)))
        @info "grammar generated!"
    end
    @info "all grammars generated successfully!"
    return grammars[end]
end

test_pipeline_dir(dir) = test_pipeline([dir * '/' * f for f in readdir(dir)])

test_pipeline_dir(ARGS[begin])
println(repr(test_pipeline_dir(ARGS[begin])))
