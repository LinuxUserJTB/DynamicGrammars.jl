# DynamicGrammars.jl

`DynamicGrammars.jl` is a package for string parsing with context-free grammars in pure julia.

Grammars are represented as `RuleSet`s with specified terminal symbol type. Each rule in a ruleset has a
name, an index and a definition. The definition is a node which can have following types:

- `Reference`: resolves the definition of another rule
- `Structure`: used to create nodes in the abstract syntax tree
- `Terminal`: matches a string part using deterministic automata
- `Concatenation`: matches multiple nodes in order
- `Repetition`: explicit "array" of nodes, can specify minimal/maximal count
- `Alternative`: matches one of multiple alternative nodes
