///|
let moonbit_language : @tree_sitter.Language = @tree_sitter_moonbit.language()

///|
priv enum MoonBitType {
  Unit
  Bool
  Int
  UInt
  Int64
  UInt64
  Float
  Double
  Error
  FixedArray(MoonBitType)
  Tuple(Array[MoonBitType])
  Typedef(String)
  Typeapp(String, Array[MoonBitType])
  Closure(Array[MoonBitType], MoonBitReturnType)
} derive(Eq, Hash)

///|
priv enum MoonBitReturnType {
  Void
  Type(MoonBitType)
  Error(MoonBitType, MoonBitType)
} derive(Eq, Hash)

///|
impl Show for MoonBitReturnType with output(self, logger) {
  match self {
    Void => logger.write_string("Void")
    Type(type_) => logger.write_object(type_)
    Error(value_type, error_type) => {
      logger.write_object(value_type)
      logger.write_char('!')
      if not(error_type is Error) {
        logger.write_object(error_type)
      }
    }
  }
}

///|
impl ToJson for MoonBitReturnType with to_json(self) {
  match self {
    Void => Json::null()
    Type(type_) => type_.to_json()
    Error(value_type, error_type) =>
      Json::object({
        "value": value_type.to_json(),
        "error": error_type.to_json(),
      })
  }
}

///|
impl Show for MoonBitType with output(self, logger) {
  match self {
    Unit => logger.write_string("Unit")
    Bool => logger.write_string("Bool")
    Int => logger.write_string("Int")
    UInt => logger.write_string("UInt")
    Int64 => logger.write_string("Int64")
    UInt64 => logger.write_string("UInt64")
    Float => logger.write_string("Float")
    Double => logger.write_string("Double")
    Error => logger.write_string("Error")
    FixedArray(type_) => logger.write_string("FixedArray[\{type_}]")
    Tuple(types) => {
      logger.write_string("(")
      for i, type_ in types {
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string("\{type_}")
      }
      logger.write_string(")")
    }
    Typedef(name) => logger.write_string("\{name}")
    Typeapp(name, type_arguments) => {
      logger.write_string("\{name}[")
      for i, type_argument in type_arguments {
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string("\{type_argument}")
      }
      logger.write_string("]")
    }
    Closure(parameter_types, Void) =>
      logger.write_string("(\{parameter_types})")
    Closure(parameter_types, return_type) =>
      logger.write_string("(\{parameter_types}) -> \{return_type}")
  }
}

///|
impl ToJson for MoonBitType with to_json(self) {
  self.to_string().to_json()
}

///|
fn MoonBitReturnType::parse(
  source : String,
  node : @tree_sitter.Node?
) -> MoonBitReturnType! {
  guard node is Some(node) else { return MoonBitReturnType::Void }
  for child in node.children() {
    if child.type_() is "type" {
      let type_ = MoonBitType::parse!(source, child)
      return MoonBitReturnType::Type(type_)
    }
    if child.type_() is "type_with_error" {
      let mut value_node = None
      let mut error_node = None
      for grandchild in child.children() {
        if grandchild.type_() is "type" {
          if value_node is None {
            value_node = Some(grandchild)
          } else {
            error_node = Some(grandchild)
          }
        }
      }
      guard value_node is Some(value_node) else {
        raise MoonBitParseError::Missing(
          source~,
          node=child,
          "type in type_with_error",
        )
      }
      let value_type = MoonBitType::parse!(source, value_node)
      let error_type = match error_node {
        None => MoonBitType::Error
        Some(error_node) => MoonBitType::parse!(source, error_node)
      }
      return MoonBitReturnType::Error(value_type, error_type)
    }
  }
  raise MoonBitParseError::Unrecognized(
    source~,
    node~,
    expect="type/type_with_error",
  )
}

///|
fn MoonBitType::parse(
  source : String,
  node : @tree_sitter.Node
) -> MoonBitType! {
  if node.type_() is "type" {
    return MoonBitType::parse!(
      source,
      node
      .named_child(0)
      .or_error!(MoonBitParseError::Missing(source~, node~, "type")),
    )
  }
  if node.type_() is "apply_type" {
    let mut qualified_type_identifier_node = None
    let mut type_arguments_node = None
    for child in node.children() {
      if child.type_() is "qualified_type_identifier" {
        qualified_type_identifier_node = Some(child)
        continue
      }
      if child.type_() is "type_arguments" {
        type_arguments_node = Some(child)
        continue
      }
    }
    guard qualified_type_identifier_node is Some(qualified_type_identifier_node) else {
      raise MoonBitParseError::Missing(
        source~,
        node~,
        "qualified_type_identifier",
      )
    }
    let identifier_node = qualified_type_identifier_node
      .child(0)
      .or_error!(
        MoonBitParseError::Missing(
          source~,
          node=qualified_type_identifier_node,
          "identifier",
        ),
      )
    let identifier = source.view(
      start_offset=identifier_node.start_byte(),
      end_offset=identifier_node.end_byte(),
    )
    let identifier = identifier.to_string()
    return match (identifier, type_arguments_node) {
      ("Unit", None) => MoonBitType::Unit
      ("Bool", None) => MoonBitType::Bool
      ("Int", None) => MoonBitType::Int
      ("UInt", None) => MoonBitType::UInt
      ("Int64", None) => MoonBitType::Int64
      ("UInt64", None) => MoonBitType::UInt64
      ("Float", None) => MoonBitType::Float
      ("Double", None) => MoonBitType::Double
      ("FixedArray", Some(type_arguments_node)) => {
        let type_arguments = []
        for type_argument_node in type_arguments_node.children() {
          if type_argument_node.type_() is "type" {
            type_arguments.push(MoonBitType::parse!(source, type_argument_node))
          }
        }
        if type_arguments is [type_] {
          return MoonBitType::FixedArray(type_)
        } else {
          raise MoonBitParseError::MismatchedTypeArity(
            expect=1,
            actual=type_arguments.length(),
          )
        }
      }
      (identifier, None) => MoonBitType::Typedef(identifier)
      (identifier, Some(type_arguments_node)) => {
        let type_arguments = []
        for type_argument_node in type_arguments_node.children() {
          if type_argument_node.type_() is "type" {
            type_arguments.push(MoonBitType::parse!(source, type_argument_node))
          }
        }
        return MoonBitType::Typeapp(identifier, type_arguments)
      }
    }
  }
  if node.type_() is "function_type" {
    let parameter_type_nodes = []
    let mut return_type_node = None
    for child in node.children() {
      if child.type_() is "type" {
        parameter_type_nodes.push(child)
        continue
      }
      if child.type_() is "return_type" {
        return_type_node = Some(child)
        continue
      }
    }
    let parameter_types = []
    for parameter_type_node in parameter_type_nodes {
      parameter_types.push(MoonBitType::parse!(source, parameter_type_node))
    }
    let return_type = MoonBitReturnType::parse!(source, return_type_node)
    return MoonBitType::Closure(parameter_types, return_type)
  }
  if node.type_() is "option_type" {
    let type_node = node
      .child(0)
      .or_error!(MoonBitParseError::Missing(source~, node~, "type"))
    let type_ = MoonBitType::parse!(source, type_node)
    return MoonBitType::Typeapp("Option", [type_])
  }
  if node.type_() is "tuple_type" {
    let type_nodes = []
    for child in node.children() {
      if child.type_() is "type" {
        type_nodes.push(child)
      }
    }
    let types = []
    for type_node in type_nodes {
      types.push(MoonBitType::parse!(source, type_node))
    }
    return MoonBitType::Tuple(types)
  }
  raise MoonBitParseError::Unrecognized(
    source~,
    node~,
    expect="type/apply_type/function_type",
  )
}

///|
priv struct MoonBitParameter {
  borrow : Bool
  labeled : Bool
  name : String
  type_ : MoonBitType
} derive(Show)

///|
impl ToJson for MoonBitParameter with to_json(self) {
  Json::object({
    "borrow": self.borrow.to_json(),
    "name": self.name.to_json(),
    "type": self.type_.to_json(),
  })
}

///|
priv enum MoonBitFunctionBody {
  C(String)
  Primitive(String)
  MoonBit(@tree_sitter.Node)
} derive(Show)

///|
impl ToJson for MoonBitFunctionBody with to_json(self) {
  match self {
    C(linkage_identifier) => Json::object({ "c": linkage_identifier.to_json() })
    Primitive(linkage_identifier) =>
      Json::object({ "primitive": linkage_identifier.to_json() })
    MoonBit(body) => Json::object({ "moonbit": body.string().to_json() })
  }
}

///|
priv struct MoonBitFunction {
  name : String
  return_type : MoonBitReturnType
  parameters : Array[MoonBitParameter]
  body : MoonBitFunctionBody
} derive(Show, ToJson)

///|
priv type! MoonBitParseError {
  Missing(source~ : String, node~ : @tree_sitter.Node, String)
  Unrecognized(source~ : String, node~ : @tree_sitter.Node, expect~ : String)
  MismatchedTypeArity(expect~ : Int, actual~ : Int)
}

///|
impl Show for MoonBitParseError with output(self, logger) {
  match self {
    Unrecognized(source~, node~, expect~) => {
      let view = source.view(
        start_offset=node.start_byte(),
        end_offset=node.end_byte(),
      )
      logger.write_string(
        "Invalid node: expected \{expect}, got \{node.type_()}: \{view}",
      )
    }
    Missing(source~, node~, type_) => {
      let view = source.view(
        start_offset=node.start_byte(),
        end_offset=node.end_byte(),
      )
      logger.write_string("Missing \{type_}: \{view}")
    }
    MismatchedTypeArity(expect~, actual~) =>
      logger.write_string(
        "Mismatched type arity: expected \{expect}, got \{actual}",
      )
  }
}

///|
fn tree_sitter_get_child_by_type(
  source~ : String,
  node : @tree_sitter.Node,
  type_ : String
) -> @tree_sitter.Node! {
  for child in node.children() {
    if child.type_() == type_ {
      return child
    }
  }
  raise MoonBitParseError::Missing(source~, node~, type_)
}

///|
fn MoonBitFunction::parse(
  source : String,
  node : @tree_sitter.Node
) -> MoonBitFunction! {
  guard node.type_() is "function_definition" else {
    raise MoonBitParseError::Unrecognized(
      source~,
      node~,
      expect="function_definition",
    )
  }
  let mut attributes_node = None
  let mut external_linkage_node = None
  let mut function_identifier_node = None
  let mut parameters_node = None
  let mut return_type_node = None
  let mut external_source_node = None
  let mut block_expression_node = None
  for child in node.children() {
    if child.type_() is "attributes" {
      attributes_node = Some(child)
    } else if child.type_() is "external_linkage" {
      external_linkage_node = Some(child)
    } else if child.type_() is "function_identifier" {
      function_identifier_node = Some(child)
    } else if child.type_() is "parameters" {
      parameters_node = Some(child)
    } else if child.type_() is "return_type" {
      return_type_node = Some(child)
    } else if child.type_() is "external_source" {
      external_source_node = Some(child)
    } else if child.type_() is "block_expression" {
      block_expression_node = Some(child)
    }
  }
  let borrowed_parameters = Set::new()
  if attributes_node is Some(attributes_node) {
    for attribute_node in attributes_node.children() {
      if not(attribute_node.type_() is "attribute") {
        continue
      }
      let expression_node = tree_sitter_get_child_by_type!(
        source~,
        attribute_node,
        "attribute_expression",
      )
      let identifier_node = tree_sitter_get_child_by_type!(
        source~,
        expression_node,
        "lowercase_identifier",
      )
      let identifier = source.view(
        start_offset=identifier_node.start_byte(),
        end_offset=identifier_node.end_byte(),
      )
      let properties_node = tree_sitter_get_child_by_type?(
        source~,
        expression_node,
        "attribute_properties",
      ).to_option()
      if identifier is [.. "borrow"] && properties_node is Some(properties_node) {
        for property_node in properties_node.children() {
          if property_node.type_() is "attribute_property" &&
            property_node.named_child(0) is Some(property_node) &&
            property_node.type_() is "attribute_expression" &&
            property_node.named_child(0) is Some(identifier_node) {
            let identifier = source.view(
              start_offset=identifier_node.start_byte(),
              end_offset=identifier_node.end_byte(),
            )
            borrowed_parameters.add(identifier.to_string())
          }
        }
      }
    }
  }
  guard function_identifier_node is Some(function_identifier_node) else {
    raise Missing(source~, node~, "function identifier")
  }
  let function_identifier_node = function_identifier_node
    .child(0)
    .or_error!(Missing(source~, node=function_identifier_node, "identifier"))
  let name = source
    .view(
      start_offset=function_identifier_node.start_byte(),
      end_offset=function_identifier_node.end_byte(),
    )
    .to_string()
  let parameters = []
  if parameters_node is Some(parameters_node) {
    for parameter_node in parameters_node.children() {
      if parameter_node.type_() == "parameter" {
        let mut identifier_node = None
        let mut label_node = None
        let mut option_node = None
        let mut type_node = None
        for child in parameter_node.children() {
          if child.type_() is "lowercase_identifier" {
            identifier_node = Some(child)
          } else if child.type_() is "type_annotation" {
            type_node = Some(
              tree_sitter_get_child_by_type!(source~, child, "type"),
            )
          } else if child.type_() is "parameter_label" &&
            child.named_child(0) is Some(child) {
            label_node = Some(child)
          } else if child.type_() is "optional_parameter_label" &&
            child.named_child(0) is Some(child) {
            option_node = Some(child)
          }
        }
        let labeled = label_node is Some(_)
        let optional = option_node is Some(_)
        guard (identifier_node, label_node, option_node)
          is ((Some(identifier_node), None, None)
          | (None, Some(identifier_node), None)
          | (None, None, Some(identifier_node))) else {
          raise MoonBitParseError::Missing(
            source~,
            node=parameter_node,
            "parameter label or parameter identifier",
          )
        }
        guard type_node is Some(parameter_type_node) else {
          raise MoonBitParseError::Missing(
            source~,
            node=parameter_node,
            "parameter type",
          )
        }
        let identifier = source.view(
          start_offset=identifier_node.start_byte(),
          end_offset=identifier_node.end_byte(),
        )
        let identifier = identifier.to_string()
        let type_ = MoonBitType::parse!(source, parameter_type_node)
        let type_ = if optional {
          MoonBitType::Typeapp("Option", [type_])
        } else {
          type_
        }
        let parameter = MoonBitParameter::{
          borrow: borrowed_parameters.contains(identifier),
          labeled,
          name: identifier,
          type_,
        }
        parameters.push(parameter)
      }
    }
  }
  let type_ = MoonBitReturnType::parse!(source, return_type_node)
  let body = if external_linkage_node is Some(external_linkage_node) {
    let linkage_string_node = external_linkage_node
      .named_child(0)
      .or_error!(Missing(source~, node=external_linkage_node, "linkage_string"))
    let linkage_string = source.view(
      start_offset=linkage_string_node.start_byte(),
      end_offset=linkage_string_node.end_byte(),
    )
    let linkage_string = linkage_string.to_string()
    if linkage_string is ("\"C\"" | "\"c\"") {
      guard external_source_node is Some(external_source_node) else {
        raise Missing(source~, node~, "external source")
      }
      let external_source_node = external_source_node
        .child(0)
        .or_error!(
          Missing(source~, node=external_source_node, "external source"),
        )
      let external_source = source.view(
        start_offset=external_source_node.start_byte() + 1,
        end_offset=external_source_node.end_byte() - 1,
      )
      let external_source = external_source.to_string()
      MoonBitFunctionBody::C(external_source)
    } else {
      raise Unrecognized(
        source~,
        node=linkage_string_node,
        expect="\"C\"/\"c\"",
      )
    }
  } else if block_expression_node is Some(block_expression_node) {
    MoonBitFunctionBody::MoonBit(block_expression_node)
  } else if external_source_node is Some(external_source_node) {
    let external_source_node = external_source_node
      .child(0)
      .or_error!(Missing(source~, node=external_source_node, "external source"))
    let external_source = source.view(
      start_offset=external_source_node.start_byte() + 1,
      end_offset=external_source_node.end_byte() - 1,
    )
    let external_source = external_source.to_string()
    MoonBitFunctionBody::Primitive(external_source)
  } else {
    raise MoonBitParseError::Missing(source~, node~, "function body")
  }
  { name, return_type: type_, body, parameters }
}

///|
priv struct MoonBitStructure {
  functions : Array[MoonBitFunction]
} derive(Show, ToJson)

///|
fn MoonBitStructure::parse(
  source : String,
  node : @tree_sitter.Node
) -> MoonBitStructure! {
  let functions = []
  for child in node.children() {
    if child.type_() is "structure_item" &&
      child.child(0) is Some(child) &&
      child.type_() is "function_definition" {
      functions.push(MoonBitFunction::parse!(source, child))
    }
  }
  MoonBitStructure::{ functions, }
}

///|
test "moonbit" {
  let parser = @tree_sitter.Parser::new()
  parser.set_language(moonbit_language)
  let source =
    #|#borrow(self)
    #|extern "c" fn uv_is_closing(self : Handle) -> Bool = "moonbit_uv_is_closing"
    #|
    #|extern "c" fn a(b : FixedArray[Int]) = "moonbit_a"
  let tree = parser.parse_string(None, source).unwrap()
  let root_node = tree.root_node()
  let structure = MoonBitStructure::parse!(source, root_node)
  @json.inspect!(structure, content={
    "functions": [
      {
        "name": "uv_is_closing",
        "return_type": "Bool",
        "parameters": [{ "borrow": true, "name": "self", "type_": "Handle" }],
        "body": { "c": "moonbit_uv_is_closing" },
      },
      {
        "name": "a",
        "return_type": Null,
        "parameters": [
          { "borrow": false, "name": "b", "type_": "FixedArray[Int]" },
        ],
        "body": { "c": "moonbit_a" },
      },
    ],
  })
}
