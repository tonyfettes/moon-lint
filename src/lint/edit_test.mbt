///|
test "parse_rules" {
  let rules =
    #|suggested-for-in:
    #|  search: |
    #|    ((for_expression
    #|      (for_binder
    #|       (lowercase_identifier) @binderDefinition
    #|        (expression
    #|         (pipeline_expression
    #|          (compound_expression
    #|           (simple_expression
    #|            (atomic_expression
    #|             (literal
    #|              (integer_literal) @rangeLower)))))))
    #|        .
    #|        (semicolon)
    #|        (compound_expression
    #|         (binary_expression
    #|         (_) @binderConditional
    #|         "<"
    #|         (_) @rangeUpper))
    #|        (semicolon)
    #|        (for_binder
    #|         (lowercase_identifier) @binderAssignment
    #|         (expression
    #|         (pipeline_expression
    #|          (compound_expression
    #|           (binary_expression
    #|              (_) @binderUpdate
    #|              "+"
    #|              (_) @rangeStep)))))
    #|        (block_expression) @forBody
    #|        (else_clause)? @forBody)
    #|     (#eq? @binderDefinition @binderConditional)
    #|     (#eq? @binderDefinition @binderAssignment)
    #|     (#eq? @binderDefinition @binderUpdate)
    #|     (#eq? @rangeStep "1"))
    #|  replace: |
    #|    for $binderDefinition in $rangeLower..<($rangeUpper) $forBody
    #|
  let rules = @lint.parse_rules!(@encoding.encode(UTF8, rules))
  @json.inspect!(rules, content=[
    {
      "name": "suggested-for-in",
      "search": "((for_expression\n      (for_binder\n       (lowercase_identifier) @binderDefinition\n        (expression\n         (pipeline_expression\n          (compound_expression\n           (simple_expression\n            (atomic_expression\n             (literal\n              (integer_literal) @rangeLower)))))))\n        .\n        (semicolon)\n        (compound_expression\n         (binary_expression\n         (_) @binderConditional\n         \"<\"\n         (_) @rangeUpper))\n        (semicolon)\n        (for_binder\n         (lowercase_identifier) @binderAssignment\n         (expression\n         (pipeline_expression\n          (compound_expression\n           (binary_expression\n              (_) @binderUpdate\n              \"+\"\n              (_) @rangeStep)))))\n        (block_expression) @forBody\n        (else_clause)? @forBody)\n     (#eq? @binderDefinition @binderConditional)\n     (#eq? @binderDefinition @binderAssignment)\n     (#eq? @binderDefinition @binderUpdate)\n     (#eq? @rangeStep \"1\"))",
      "replace": "for $binderDefinition in $rangeLower..<($rangeUpper) $forBody",
    },
  ])
}

///|
test "apply_edit" {
  let rules =
    #|if-true:
    #|  search: |
    #|    (if_expression
    #|     (_) @cond
    #|     (block_expression (_)* @body)
    #|     (#eq? @cond "true"))
    #|  replace: |
    #|    $body
  let rules = @lint.parse_rules!(@encoding.encode(UTF8, rules))
  let source =
    #|fn main {
    #|  if true {
    #|    println!("Hello, world!")
    #|  }
    #|}
  let source : Bytes = [..@encoding.encode(UTF8, source)]
  let parser = @tree_sitter.Parser::new()
  let language = @tree_sitter_moonbit.language()
  parser.set_language(language)
  let source = @lint.apply_edit!(
    parser,
    language,
    rules[0],
    source,
    diagnostics=[],
    apply=true,
  )
  let source = @encoding.decoder(UTF8).decode!(source)
  inspect!(
    source,
    content=
      #|fn main {
      #|  println!("Hello, world!")
      #|
      #|}
    ,
  )
}
