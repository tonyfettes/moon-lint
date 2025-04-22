///|
let c_language : @tree_sitter.Language = @tree_sitter_c.language()

///|
priv enum CPointer {
  Own(CType)
  Ref(CType)
} derive(Show, Eq, Hash)

///|
impl ToJson for CPointer with to_json(self) {
  match self {
    Own(name) => "\{name} own *"
    Ref(name) => "\{name} ref *"
  }
}

///|
priv enum CType {
  Void
  Int32
  UInt32
  Int64
  UInt64
  Float
  Double
  Typedef(String)
  Pointer(CPointer)
} derive(Eq, Hash)

///|
impl Show for CType with output(self, logger) {
  match self {
    Void => logger.write_string("void")
    Int32 => logger.write_string("int32_t")
    UInt32 => logger.write_string("uint32_t")
    Int64 => logger.write_string("int64_t")
    UInt64 => logger.write_string("uint64_t")
    Float => logger.write_string("float")
    Double => logger.write_string("double")
    Typedef(string) => logger.write_string(string)
    Pointer(pointer) => logger.write_object(pointer)
  }
}

///|
impl ToJson for CType with to_json(self) {
  match self {
    Void => "void".to_json()
    Int32 => "int32_t".to_json()
    UInt32 => "uint32_t".to_json()
    Int64 => "int64_t".to_json()
    UInt64 => "uint64_t".to_json()
    Float => "float".to_json()
    Double => "double".to_json()
    Typedef(string) => string.to_json()
    Pointer(pointer) => pointer.to_json()
  }
}

///|
priv struct CParameter {
  name : String?
  type_ : CType
} derive(Show)

///|
impl ToJson for CParameter with to_json(self) {
  let object = Map::new()
  if self.name is Some(name) {
    object["name"] = name.to_json()
  }
  object["type"] = self.type_.to_json()
  Object(object)
}

///|
priv struct CFunction {
  static_ : Bool
  name : String
  type_ : CType
  parameters : Array[CParameter]
  body : @tree_sitter.Node
} derive(Show)

///|
impl ToJson for CFunction with to_json(self) {
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
priv type! CParseError {
  MissingType
  MissingDeclarator
  MissingParameters
  MissingBody
} derive(Show)

///|
fn CFunction::parse(source : String, node : @tree_sitter.Node) -> CFunction! {
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
  let type_node = node
    .child_by_field_name("type")
    .or_error!(CParseError::MissingType)
  let type_ = source.view(
    start_offset=type_node.start_byte(),
    end_offset=type_node.end_byte(),
  )
  let type_ = type_.to_string()
  let mut type_ = match type_ {
    "void" => CType::Void
    "int32_t" => CType::Int32
    "uint32_t" => CType::UInt32
    "int64_t" => CType::Int64
    "uint64_t" => CType::UInt64
    "float" => CType::Float
    "double" => CType::Double
    type_ => CType::Typedef(type_)
  }
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
      type_ = Pointer(CPointer::Ref(type_))
    } else {
      type_ = Pointer(CPointer::Own(type_))
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
    let type_node = parameter_node
      .child_by_field_name("type")
      .or_error!(CParseError::MissingType)
    let type_ = source.view(
      start_offset=type_node.start_byte(),
      end_offset=type_node.end_byte(),
    )
    let type_ = type_.to_string()
    let mut type_ = match type_ {
      "void" => CType::Void
      "int32_t" => CType::Int32
      "uint32_t" => CType::UInt32
      "int64_t" => CType::Int64
      "uint64_t" => CType::UInt64
      "float" => CType::Float
      "double" => CType::Double
      type_ => CType::Typedef(type_)
    }
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
    let name = if declarator_node is Some(declarator_node) {
      if declarator_node.type_() is "pointer_declarator" {
        if is_const {
          type_ = Pointer(CPointer::Ref(type_))
        } else {
          type_ = Pointer(CPointer::Own(type_))
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
    parameters.push(CParameter::{ name, type_ })
  }
  let body = node
    .child_by_field_name("body")
    .or_error!(CParseError::MissingBody)
  { static_, name: [..name], type_, parameters, body }
}

///|
priv struct CTranslationUnit {
  functions : Array[CFunction]
} derive(Show, ToJson)

///|
fn CTranslationUnit::parse(
  source : String,
  node : @tree_sitter.Node
) -> CTranslationUnit! {
  let functions = []
  for child in node.children() {
    if child.type_() is "function_definition" {
      functions.push(CFunction::parse!(source, child))
    }
  }
  CTranslationUnit::{ functions, }
}

///|
test "c" {
  let parser = @tree_sitter.Parser::new()
  parser.set_language(c_language)
  let source =
    #|int32_t
    #|moonbit_uv_is_closing(uv_handle_t *handle) {
    #|  int32_t is_closing = uv_is_closing(handle);
    #|  moonbit_decref(handle);
    #|  return is_closing;
    #|}
  let tree = parser.parse_string(None, source).unwrap()
  let root_node = tree.root_node()
  let translation_unit = CTranslationUnit::parse!(source, root_node)
  @json.inspect!(translation_unit, content={
    "functions": [
      {
        "name": "moonbit_uv_is_closing",
        "type": "int32_t",
        "parameters": [{ "name": "handle", "type": "uv_handle_t own *" }],
      },
    ],
  })
}
