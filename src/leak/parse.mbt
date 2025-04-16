///|
let c : @tree_sitter.Language = @tree_sitter_c.language()

///|
enum Pointer {
  Own(Type)
  Ref(Type)
  Plain(Type)
} derive(Show)

///|
impl ToJson for Pointer with to_json(self) {
  match self {
    Own(name) => "\{name} own *"
    Ref(name) => "\{name} ref *"
    Plain(name) => "\{name} *"
  }
}

///|
enum Type {
  Typedef(String)
  Pointer(Pointer)
}

///|
impl Show for Type with output(self, logger) {
  match self {
    Typedef(string) => logger.write_string(string)
    Pointer(pointer) => logger.write_object(pointer)
  }
}

///|
impl ToJson for Type with to_json(self) {
  match self {
    Typedef(string) => string.to_json()
    Pointer(pointer) => pointer.to_json()
  }
}

///|
struct Parameter {
  name : String?
  type_ : Type
} derive(Show)

///|
impl ToJson for Parameter with to_json(self) {
  let object = Map::new()
  if self.name is Some(name) {
    object["name"] = name.to_json()
  }
  object["type"] = self.type_.to_json()
  Object(object)
}

///|
struct Function {
  static_ : Bool
  name : String
  type_ : Type
  parameters : Array[Parameter]
} derive(Show)

///|
impl ToJson for Function with to_json(self) {
  let object = Map::new()
  if self.static_ {
    object["static"] = True
  }
  object["name"] = self.name.to_json()
  object["type"] = self.type_.to_json()
  let parameters = Array::new()
  for parameter in self.parameters {
    parameters.push(parameter.to_json())
  }
  object["parameters"] = parameters.to_json()
  Object(object)
}

///|
type! ParseError {
  MissingType
  MissingDeclarator
  UnrecognizedDeclarator(String)
  MissingParameters
  MissingBody
} derive(Show)

///|
fn Function::parse(
  source : String,
  node : @tree_sitter.Node
) -> Function! {
  let mut static_ = false
  for child in node.children() {
    if child.type_() is "storage_class_specifier" {
      let storage_class = source.view(
        start_offset=child.start_byte(),
        end_offset=child.end_byte(),
      )
      if storage_class is [.. "static"] {
        static_ = true
      }
    }
  }
  let type_node = node.child_by_field_name("type").or_error!(MissingType)
  let type_ = source.view(
    start_offset=type_node.start_byte(),
    end_offset=type_node.end_byte(),
  )
  let mut type_ = Typedef(type_.to_string())
  let mut is_const = false
  if type_node.prev_sibling() is Some(prev_sibling) &&
    prev_sibling.type_() == "type_qualifier" {
    let type_qualifier = source.view(
      start_offset=prev_sibling.start_byte(),
      end_offset=prev_sibling.end_byte(),
    )
    if type_qualifier is [.. "const"] {
      is_const = true
    }
  }
  if is_const is false &&
    type_node.next_sibling() is Some(next_sibling) &&
    next_sibling.type_() == "type_qualifier" {
    let type_qualifier = source.view(
      start_offset=next_sibling.start_byte(),
      end_offset=next_sibling.end_byte(),
    )
    if type_qualifier is [.. "const"] {
      is_const = true
    }
  }
  let declarator_node = node
    .child_by_field_name("declarator")
    .or_error!(MissingDeclarator)
  let declarator_node = if declarator_node.type_() is "pointer_declarator" {
    if is_const {
      type_ = Pointer(Pointer::Ref(type_))
    } else {
      type_ = Pointer(Pointer::Own(type_))
    }
    declarator_node
    .child_by_field_name("declarator")
    .or_error!(MissingDeclarator)
  } else {
    declarator_node
  }
  let declarator_node = declarator_node
    .child_by_field_name("declarator")
    .or_error!(MissingDeclarator)
  let name = source.view(
    start_offset=declarator_node.start_byte(),
    end_offset=declarator_node.end_byte(),
  )
  let parameters = []
  let parameters_node = declarator_node
    .next_named_sibling()
    .or_error!(MissingParameters)
  for parameter_node in parameters_node.named_children() {
    println("parameter_node: \{parameter_node}")
    let type_node = parameter_node
      .child_by_field_name("type")
      .or_error!(MissingType)
    let type_ = source.view(
      start_offset=type_node.start_byte(),
      end_offset=type_node.end_byte(),
    )
    let mut type_ = Typedef(type_.to_string())
    let mut is_const = false
    if type_node.prev_sibling() is Some(prev_sibling) &&
      prev_sibling.type_() == "type_qualifier" {
      let type_qualifier = source.view(
        start_offset=prev_sibling.start_byte(),
        end_offset=prev_sibling.end_byte(),
      )
      if type_qualifier is [.. "const"] {
        is_const = true
      }
    }
    if is_const is false &&
      type_node.next_sibling() is Some(next_sibling) &&
      next_sibling.type_() == "type_qualifier" {
      let type_qualifier = source.view(
        start_offset=next_sibling.start_byte(),
        end_offset=next_sibling.end_byte(),
      )
      if type_qualifier is [.. "const"] {
        is_const = true
      }
    }
    let declarator_node = parameter_node.child_by_field_name("declarator")
    println("declarator_node: \{declarator_node}")
    let name = if declarator_node is Some(declarator_node) {
      if declarator_node.type_() is "pointer_declarator" {
        if is_const {
          type_ = Pointer(Pointer::Ref(type_))
        } else {
          type_ = Pointer(Pointer::Own(type_))
        }
        let declarator_node = declarator_node
          .child_by_field_name("declarator")
          .or_error!(MissingDeclarator)
        let name = source.view(
          start_offset=declarator_node.start_byte(),
          end_offset=declarator_node.end_byte(),
        )
        Some(name.to_string())
      } else if declarator_node.type_() is "abstract_pointer_declarator" {
        None
      } else {
        let name = source.view(
          start_offset=declarator_node.start_byte(),
          end_offset=declarator_node.end_byte(),
        )
        Some(name.to_string())
      }
    } else {
      None
    }
    println("name: \{name}")
    parameters.push(Parameter::{ name, type_ })
  }
  println("parameters: \{parameters}")
  let body = node.child_by_field_name("body").or_error!(MissingBody)
  let query_source =
    #|(call_expression
    #| function: (identifier) @function
    #| arguments: (argument_list (identifier) @argument))
  let query = @tree_sitter.Query::new!(c, query_source)
  let query_cursor = @tree_sitter.QueryCursor::new()
  query_cursor.exec(query, body)
  while query_cursor.next_match() is Some(matches) {
    for capture in matches.captures {
      let capture_name = query.capture_name_for_id(capture.index)
      println("capture_name: \{capture_name}")
      let capture_node = capture.node
      let capture_source = source.view(
        start_offset=capture_node.start_byte(),
        end_offset=capture_node.end_byte(),
      )
      println("capture_source: \{capture_source}")
    }
  }
  for body_child in body.children() {
    println("body_child: \{body_child}")
  }
  { static_, name: [..name], type_, parameters }
}

///|
struct TranslationUnit {
  functions : Array[Function]
} derive(Show, ToJson)

///|
fn TranslationUnit::parse(
  source : String,
  node : @tree_sitter.Node
) -> TranslationUnit! {
  let functions = []
  for child in node.children() {
    if child.type_() is "function_definition" {
      functions.push(Function::parse!(source, child))
    }
  }
  TranslationUnit::{ functions, }
}

///|
test {
  let parser = @tree_sitter.Parser::new()
  parser.set_language(c)
  let source =
    #|int32_t
    #|moonbit_uv_loop_alive(uv_loop_t *loop) {
    #|  int alive = uv_loop_alive(loop);
    #|  moonbit_decref(loop);
    #|  return alive;
    #|}
    #|
    #|static inline void
    #|moonbit_uv_fs_finalize(void *object) {
    #|  moonbit_uv_fs_t *fs = (moonbit_uv_fs_t *)object;
    #|  if (fs->fs.data) {
    #|    moonbit_decref(fs->fs.data);
    #|  }
    #|  if (fs->bufs_base) {
    #|    moonbit_decref(fs->bufs_base);
    #|  }
    #|  uv_fs_req_cleanup(&fs->fs);
    #|}
    #|
    #|
    #|int32_t
    #|moonbit_uv_fs_write(
    #|  uv_loop_t *loop,
    #|  moonbit_uv_fs_t *fs,
    #|  uv_file file,
    #|  moonbit_bytes_t *bufs_base,
    #|  int32_t *bufs_offset,
    #|  int32_t *bufs_length,
    #|  int64_t offset,
    #|  moonbit_uv_fs_cb_t *cb
    #|) {
    #|  int bufs_size = (((struct moonbit_object*)(bufs_base) - 1)->meta & (((uint32_t)1 << 28) - 1));
    #|                                                 ;
    #|  uv_buf_t *bufs = malloc(sizeof(uv_buf_t) * bufs_size);
    #|  for (int i = 0; i < bufs_size; i++) {
    #|    bufs[i] =
    #|      uv_buf_init((char *)bufs_base[i] + bufs_offset[i], bufs_length[i]);
    #|  }
    #|  moonbit_uv_fs_set_data(fs, cb);
    #|  moonbit_uv_fs_set_bufs(fs, bufs_base);
    #|  int result =
    #|    uv_fs_write(loop, &fs->fs, file, bufs, bufs_size, offset, moonbit_uv_fs_cb);
    #|  free(bufs);
    #|  moonbit_decref(loop);
    #|  moonbit_decref(bufs_offset);
    #|  moonbit_decref(bufs_length);
    #|  return result;
    #|}
  let tree = parser.parse_string(None, source).unwrap()
  let root_node = tree.root_node()
  let translation_unit = TranslationUnit::parse!(source, root_node)
  @json.inspect!(translation_unit, content={
    "functions": [
      {
        "name": "moonbit_uv_loop_alive",
        "type": "int32_t",
        "parameters": [{ "name": "loop", "type": "uv_loop_t own *" }],
      },
      {
        "static": true,
        "name": "moonbit_uv_fs_finalize",
        "type": "void",
        "parameters": [{ "name": "object", "type": "void own *" }],
      },
      {
        "name": "moonbit_uv_fs_write",
        "type": "int32_t",
        "parameters": [
          { "name": "loop", "type": "uv_loop_t own *" },
          { "name": "fs", "type": "moonbit_uv_fs_t own *" },
          { "name": "file", "type": "uv_file" },
          { "name": "bufs_base", "type": "moonbit_bytes_t own *" },
          { "name": "bufs_offset", "type": "int32_t own *" },
          { "name": "bufs_length", "type": "int32_t own *" },
          { "name": "offset", "type": "int64_t" },
          { "name": "cb", "type": "moonbit_uv_fs_cb_t own *" },
        ],
      },
    ],
  })
}
