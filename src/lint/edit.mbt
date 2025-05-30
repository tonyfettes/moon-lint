///|
struct Edit {
  name : String
  search : String
  replace : String
} derive(Show, ToJson)

///|
priv type! EditParseError {
  Missing(String)
} derive(Show)

///|
pub fn parse_rules(source : Bytes) -> Array[Edit]! {
  let parser = @tree_sitter.Parser::new()
  let yaml = @tree_sitter_yaml.language()
  parser.set_language(yaml)
  let source_tree = parser
    .parse_bytes(None, source, encoding=@encoding.Encoding::UTF8)
    .or_error!(Failure("Parse error"))
  let source_root = source_tree.root_node()
  let query_source =
    #|(block_mapping_pair
    #| key: (_) @name
    #| value:
    #| (block_node
    #|  (block_mapping
    #|   (block_mapping_pair
    #|    key: (_) @_search
    #|    value: (_) @search)
    #|   (#eq? @_search "search")
    #|   (block_mapping_pair
    #|    key: (_) @_replace
    #|    value: (_) @replace)
    #|   (#eq? @_replace "replace"))))
  let query = @tree_sitter.Query::new!(yaml, query_source)
  let query_cursor = @tree_sitter.QueryCursor::new()
  query_cursor.exec(query, source_root)
  let edits : Array[Edit] = []
  while true {
    guard query_cursor.next_match() is Some(match_) else { break }
    let captures_nodes = {}
    let captures_texts = {}
    for capture in match_.captures {
      let node = capture.node
      let bytes = source[node.start_byte():node.end_byte()]
      let text = @encoding.decoder(UTF8).decode!([..bytes])
      captures_nodes[query.capture_name_for_id(capture.index)] = node
      captures_texts[query.capture_name_for_id(capture.index)] = text
    }
    guard captures_texts["name"] is Some(name) else {
      raise EditParseError::Missing("name")
    }
    guard captures_texts["search"] is Some(search) else {
      raise EditParseError::Missing("search")
    }
    let search : String = match search.trim_space() {
      ['|', '\n', .. search] => [..search]
      search => search
    }
    guard captures_texts["replace"] is Some(replace) else {
      raise EditParseError::Missing("replace")
    }
    let replace : String = match replace.trim_space() {
      ['|', '\n', .. replace] => [..replace]
      replace => replace
    }
    edits.push(Edit::{
      name,
      search: search.trim_space(),
      replace: replace.trim_space(),
    })
  }
  return edits
}

///|
priv type! EditError {
  UnknownCapture(String)
  MultipleCapture(String)
  UnableToMergeCaptures(Int, Int)
  NoChange
  UnknownFileType(String)
} derive(Show)

///|
fn handle_predicates(
  captures : Map[String, String],
  predicates : Array[Array[@tree_sitter.QueryPredicateStep]],
  properties : Map[String, Map[String, String?]]
) -> Bool! {
  let mut result = true
  loop predicates[:] {
    [predicate, .. predicates] =>
      match predicate {
        [String("match?"), Capture(capture), String(matcher)] => {
          guard captures[capture] is Some(text) else {
            raise UnknownCapture(capture.to_string())
          }
          let matcher = @regexp.compile!(matcher)
          let regexp_result = matcher.matches(text)
          if not(regexp_result.success()) {
            result = false
            continue predicates
          }
          let regexp_named_captures = regexp_result.named_captures()
          for name, value in regexp_named_captures {
            captures[name] = value
          }
          continue predicates
        }
        [String("eq?"), Capture(left), right] => {
          guard captures[left] is Some(left) else {
            raise UnknownCapture(left.to_string())
          }
          let right = match right {
            Capture(right) => {
              guard captures[right] is Some(right) else {
                raise UnknownCapture(right.to_string())
              }
              right
            }
            String(right) => right
          }
          if left != right {
            result = false
          }
          continue predicates
        }
        [String("set!"), Capture(capture), String(name)] => {
          guard captures[capture] is Some(value) else {
            raise UnknownCapture(capture.to_string())
          }
          println("Info: Tagging \{name}")
          match properties[value] {
            None => {
              let property = {}
              property[name] = None
              properties[value] = property
            }
            Some(property) => property[name] = None
          }
          continue predicates
        }
        [String("is?"), Capture(capture), String(name)] => {
          guard captures[capture] is Some(value) else {
            raise UnknownCapture(capture.to_string())
          }
          match properties[value] {
            Some(property) =>
              match property[name] {
                Some(_) => continue predicates
                None => {
                  result = false
                  continue predicates
                }
              }
            None => {
              result = false
              continue predicates
            }
          }
        }
        [String("is-not?"), Capture(capture), String(name)] => {
          guard captures[capture] is Some(value) else {
            raise UnknownCapture(capture.to_string())
          }
          match properties[value] {
            Some(property) =>
              match property[name] {
                Some(_) => continue predicates
                None => {
                  result = false
                  continue predicates
                }
              }
            None => continue predicates
          }
        }
        predicate => {
          println("Warning: unknown predicate, ignoring: \{predicate}")
          continue predicates
        }
      }
    [] => ()
  }
  result
}

///|
fn fill_captures(
  replacement : String,
  captures_texts : Map[String, String]
) -> String!EditError {
  let buffer = StringBuilder::new()
  replace~: loop replacement.view() {
    ['$', .. replace] => {
      let name = StringBuilder::new()
      name~: loop replace {
        [char, .. replace] =>
          if char.is_ascii_alphabetic() {
            name.write_char(char)
            continue name~ replace
          } else {
            match captures_texts[name.to_string()] {
              Some(value) => {
                buffer.write_string(value)
                buffer.write_char(char)
                continue replace~ replace
              }
              None => raise UnknownCapture(name.to_string())
            }
          }
        replace => {
          match captures_texts[name.to_string()] {
            Some(value) => {
              buffer.write_string(value)
              continue replace~ replace
            }
            None => raise UnknownCapture(name.to_string())
          }
          continue replace~ replace
        }
      }
    }
    [char, .. replace] => {
      buffer.write_char(char)
      continue replace~ replace
    }
    [] => break
  }
  return buffer.to_string()
}

///|
test "fill_captures" {
  let replacement =
    #|for $binderDefinition in $rangeLower..<($rangeUpper) $forBody
  let captures = {
    "binderDefinition": "i",
    "rangeLower": "0",
    "rangeUpper": "10",
    "forBody": "{\n  println!(\"Hello, world!\")\n}",
  }
  let filled = fill_captures!(replacement, captures)
  inspect!(
    filled,
    content=
      #|for i in 0..<(10) {
      #|  println!("Hello, world!")
      #|}
    ,
  )
}

///|
struct Match {
  node : @tree_sitter.Node
  captures : Map[String, String]
  predicates : Array[Array[@tree_sitter.QueryPredicateStep]]
} derive(Show)

///|
fn merge_captures(
  captures : Map[String, Array[@tree_sitter.Node]],
  source : Bytes
) -> Map[String, String]! {
  let merged_captures = {}
  for name, nodes in captures {
    nodes.sort_by(fn(a, b) { a.start_byte().compare(b.start_byte()) })
    let mut range = None
    for node in nodes {
      let node_start = node.start_byte()
      let node_end = node.end_byte()
      match range {
        None => range = Some((node_start, node_end))
        Some((range_start, range_end)) => {
          if node_start > range_end {
            let bytes = source[range_end:node_start]
            let text = @encoding.decoder(UTF8).decode!([..bytes])
            if not(text.iter().all(fn(c) { c.is_whitespace() })) {
              raise UnableToMergeCaptures(range_end, node_start)
            }
          }
          let range_end = @math.maximum(range_end, node_end)
          range = Some((range_start, range_end))
        }
      }
    }
    match range {
      None => continue
      Some((range_start, range_end)) => {
        let bytes = source[range_start:range_end]
        let text = @encoding.decoder(UTF8).decode!([..bytes])
        merged_captures[name] = text
      }
    }
  }
  merged_captures
}

///|
pub fn schedule(
  edit : Edit,
  query : @tree_sitter.Query,
  query_cursor : @tree_sitter.QueryCursor,
  source : Bytes
) -> Array[Match]! {
  let matches : Array[@tree_sitter.QueryMatch] = []
  while true {
    guard query_cursor.next_match() is Some(match_) else { break }
    matches.push(match_)
  }
  matches.sort_by(fn(a, b) { a.pattern_index.compare(b.pattern_index) })
  let filtered : Array[Match] = []
  let properties = {}
  for match_ in matches {
    let captures = {}
    for capture in match_.captures {
      let node = capture.node
      let name = query.capture_name_for_id(capture.index)
      let quantifier = query.capture_quantifier_for_id(
        match_.pattern_index,
        capture.index,
      )
      match captures[name] {
        None => captures[name] = [node]
        Some(nodes) =>
          match quantifier {
            One => captures[name] = [node]
            _ => nodes.push(node)
          }
      }
    }
    let merged_captures = merge_captures!(captures, source)
    let predicates = query.predicates_for_pattern(match_.pattern_index)
    if not(handle_predicates!(merged_captures, predicates, properties)) {
      // println("Info: skipping match")
      continue
    }
    match captures[edit.name] {
      Some([node]) =>
        filtered.push({ node, captures: merged_captures, predicates })
      Some(_) => raise MultipleCapture(edit.name)
      None => continue
    }
  }
  filtered.sort_by(fn(a, b) { a.node.start_byte().compare(b.node.start_byte()) })
  filtered
}

///|
struct Diagnostic {
  name : String
  range : (@tree_sitter.Point, @tree_sitter.Point)
  replace : String
}

///|
pub fn apply_edit(
  parser : @tree_sitter.Parser,
  language : @tree_sitter.Language,
  edit : Edit,
  source : Bytes,
  diagnostics~ : Array[Diagnostic],
  apply~ : Bool = false
) -> Bytes! {
  let old_source = Set::new()
  let mut source = source
  let mut offset = 0
  while true {
    let source_tree = parser
      .parse_bytes(None, source, encoding=@encoding.UTF8)
      .or_error!(Failure("Parse error"))
    let source_root = source_tree.root_node()
    let search = if edit.search.contains("@\{edit.name}") {
      edit.search
    } else {
      edit.search + " @\{edit.name}"
    }
    let query = @tree_sitter.Query::new!(language, search)
    let query_cursor = @tree_sitter.QueryCursor::new()
    query_cursor.exec(query, source_root)
    let matches = schedule!(edit, query, query_cursor, source)
    if matches.length() == 0 {
      break
    }
    for match_ in matches {
      let buffer = fill_captures!(edit.replace, match_.captures)
      let start = offset + match_.node.start_byte()
      let end = offset + match_.node.end_byte()
      let replace = @encoding.encode(UTF8, buffer)
      if apply {
        source = [..source[:start], ..replace, ..source[end:]]
        let source_hash = source.hash()
        if old_source.contains(source_hash) {
          raise NoChange
        }
        offset += replace.length() - (end - start)
        old_source.add(source.hash())
      } else {
        let start = match_.node.start_point()
        let end = match_.node.end_point()
        diagnostics.push({
          name: edit.name,
          range: (start, end),
          replace: buffer,
        })
      }
    }
    if not(apply) {
      break
    }
  }
  source
}

///|
priv struct MoonModJson {
  target : String
}

///|
impl @json.FromJson for MoonModJson with from_json(
  json : Json,
  path : @json.JsonPath
) -> MoonModJson!@json.JsonDecodeError {
  match json {
    { "target": String(target), .. } => MoonModJson::{ target, }
    { "target": target, .. } =>
      raise @json.JsonDecodeError(
        (path, "expected target to be a string, got \{target}"),
      )
    _ => MoonModJson::{ target: "target" }
  }
}

///|
fn apply_file(
  path : String,
  edits : Array[Edit],
  apply~ : Bool = false
) -> Unit! {
  let mut source = @fs.read_file_to_bytes!(path)
  let language = @tree_sitter_moonbit.language()
  let parser = @tree_sitter.Parser::new()
  parser.set_language(language)
  let diagnostics = []
  for edit in edits {
    source = apply_edit!(parser, language, edit, source, diagnostics~, apply~)
  }
  if apply {
    @fs.write_bytes_to_file!(path, source)
  } else {
    let source = @encoding.decoder(UTF8).decode!(source)
    let lines = source.split("\n").collect()
    for diagnostic in diagnostics {
      let (start, end) = diagnostic.range
      let first_line_prefix = lines[start.row()].view(end_offset=start.column())
      let lines = [
          ..lines[start.row():end.row() + 1].map(fn(line) { "  │" + line }),
        ]
      let source_in_range = @string.concat(lines, separator="\n")
      let replace = ([..first_line_prefix, ..diagnostic.replace] : String)
        .split("\n")
        .map(fn(line) { "  │" + line })
        .collect()
        |> @string.concat(separator="\n")
      println(
        $|\{path}:\{start.row() + 1}:\{start.column() + 1}: error: \{diagnostic.name}
        $|\{source_in_range}
        $|  note: to fix, use
        $|\{replace}
        ,
      )
    }
  }
}

///|
pub fn apply_dir(
  path : String,
  edits : Array[Edit],
  apply~ : Bool = false
) -> Unit! {
  fn apply_dir(path : String, edits : Array[Edit], apply : Bool) -> Unit! {
    if @fs.is_dir!(path) {
      if path == ".mooncakes" || path.has_suffix("/.mooncakes") {
        return
      }
      for entry in @fs.read_dir!(path) {
        apply_dir!("\{path}/\{entry}", edits, apply)
      }
    } else if @fs.is_file!(path) {
      if not(path.has_suffix(".mbt")) {
        return
      }
      apply_file!(path, edits, apply~)
    } else {
      raise UnknownFileType(path)
    }
  }

  if @fs.is_file!(path) {
    apply_file!(path, edits, apply~)
  }
  let moon_mod_json_path = path + "/moon.mod.json"
  if @fs.path_exists(moon_mod_json_path) {
    let moon_mod_json : MoonModJson = @fs.read_file_to_string!(
        moon_mod_json_path,
      )
      |> @json.parse!()
      |> @json.from_json!()
    for entry in @fs.read_dir!(path) {
      if entry == moon_mod_json.target {
        continue
      }
      apply_dir!("\{path}/\{entry}", edits, apply)
    }
  } else {
    apply_dir!(path, edits, apply)
  }
}
