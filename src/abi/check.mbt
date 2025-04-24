///|
priv type! CheckError {
  MissingMoonPkgJson(String)
  MissingC(String)
  MismatchedArity(moonbit~ : MoonBitFunction, c~ : CFunction)
  MismatchedType(moonbit~ : MoonBitType, c~ : CType)
  MismatchedReturnType(String, moonbit~ : MoonBitReturnType, c~ : CType)
  MismatchedParameterType(String, moonbit~ : MoonBitParameter, c~ : CParameter)
  DuplicatedCFunction(String)
} derive(Show)

///|
priv struct FuncChecker {
  abi_to_c : Map[String, CFunction]
}

///|
fn FuncChecker::new() -> FuncChecker {
  FuncChecker::{ abi_to_c: Map::new() }
}

///|
priv struct TypeChecker {
  moonbit_to_c : Map[MoonBitType, CType]
  c_to_moonbit : Map[CType, MoonBitType]
}

///|
fn TypeChecker::new() -> TypeChecker {
  TypeChecker::{ moonbit_to_c: Map::new(), c_to_moonbit: Map::new() }
}

///|
priv struct Checker {
  func : FuncChecker
  type_ : TypeChecker
}

///|
fn Checker::new() -> Checker {
  Checker::{ func: FuncChecker::new(), type_: TypeChecker::new() }
}

///|
fn TypeChecker::check_type(
  self : TypeChecker,
  moonbit~ : MoonBitType,
  c~ : CType,
  borrow~ : Bool = false
) -> Unit! {
  match (moonbit, c, borrow) {
    (Unit, Int32, _) => ()
    (Bool, Int32, _) => ()
    (Int, Int32, _) => ()
    (UInt, UInt32, _) => ()
    (Int64, Int64, _) => ()
    (UInt64, UInt64, _) => ()
    (Float, Float, _) => ()
    (Double, Double, _) => ()
    (Unit | Bool | Int | UInt | Int64 | UInt64 | Float | Double, _, _) =>
      raise MismatchedType(c~, moonbit~)
    (Bytes, MoonBitBytes, _) => ()
    (Closure(_), Pointer(Own(_)), _) => ()
    (FixedArray(moonbit), Pointer(Own(c)), borrow) =>
      self.check_type!(moonbit~, c~, borrow~)
    (moonbit, c, _) => {
      println("check_type: moonbit = \{moonbit}, c = \{c}")
      if self.moonbit_to_c[moonbit] is Some(old_c_type) && old_c_type != c {
        println("check_type: old_c_type = \{old_c_type}")
        raise MismatchedType(c~, moonbit~)
      } else {
        self.moonbit_to_c[moonbit] = c
        self.c_to_moonbit[c] = moonbit
      }
    }
  }
}

///|
fn TypeChecker::check_return_type(
  self : TypeChecker,
  name : String,
  moonbit~ : MoonBitReturnType,
  c~ : CType,
  borrow~ : Bool = false
) -> Unit! {
  println("check_return_type: name = \{name}, moonbit = \{moonbit}, c = \{c}")
  match (moonbit, c, borrow) {
    (Void, Void, _) => ()
    (Type(moonbit), c, borrow) =>
      try {
        self.check_type!(moonbit~, c~, borrow~)
      } catch! {
        MismatchedType(c~, moonbit~) =>
          raise MismatchedReturnType(name, c~, moonbit=Type(moonbit))
      }
    _ => raise MismatchedReturnType(name, c~, moonbit~)
  }
}

///|
fn Checker::check(
  self : Checker,
  moonbit~ : MoonBitStructure,
  c~ : CTranslationUnit
) -> Unit! {
  for function in c.functions {
    let name = function.name
    if self.func.abi_to_c[name] is Some(_) {
      raise DuplicatedCFunction(name)
    } else {
      self.func.abi_to_c[name] = function
    }
  }
  for moonbit in moonbit.functions {
    guard moonbit.body is C(linkage) else { continue }
    guard self.func.abi_to_c[linkage] is Some(c) else {
      println("Missing C implementation for \{linkage}")
      continue
    }
    guard moonbit.parameters.length() == c.parameters.length() else {
      raise MismatchedArity(c~, moonbit~)
    }
    self.type_.check_return_type!(
      linkage,
      moonbit=moonbit.return_type,
      c=c.type_,
    )
    for i in 0..<moonbit.parameters.length() {
      let moonbit = moonbit.parameters[i]
      let c = c.parameters[i]
      try {
        self.type_.check_type!(
          moonbit=moonbit.type_,
          c=c.type_,
          borrow=moonbit.borrow,
        )
      } catch! {
        MismatchedType(..) =>
          raise MismatchedParameterType(linkage, c~, moonbit~)
      }
    }
  }
}

///|
pub fn check(moonbit~ : String, c~ : String) -> Unit! {
  let parser = @tree_sitter.Parser::new()
  parser.set_language(c_language)
  let c_tree = parser.parse_string(None, c).unwrap()
  let c_root_node = c_tree.root_node()
  parser.set_language(moonbit_language)
  let moonbit_tree = parser.parse_string(None, moonbit).unwrap()
  let moonbit_root_node = moonbit_tree.root_node()
  let c = CTranslationUnit::parse!(c, c_root_node)
  let moonbit = MoonBitStructure::parse!(moonbit, moonbit_root_node)
  let checker = Checker::new()
  checker.check!(moonbit~, c~)
}

///|
priv struct MoonBitPackage {
  native_stub : Array[String]
}

///|
impl @json.FromJson for MoonBitPackage with from_json(json, path) {
  guard json is Object(object) else {
    raise @json.JsonDecodeError(
      (path, "MoonBitPackage::from_json: expected object"),
    )
  }
  let native_stub = match object.get("native-stub") {
    Some(native_stub) => {
      let path = path.add_key("native-stub")
      guard native_stub is Array(native_stub) else {
        raise @json.JsonDecodeError(
          (path, "MoonBitPackage::from_json: expected array"),
        )
      }
      let result = []
      for i, stub in native_stub {
        match stub {
          String(stub_name) => result.push(stub_name)
          _ =>
            raise @json.JsonDecodeError(
              (path.add_index(i), "MoonBitPackage::from_json: expected string"),
            )
        }
      }
      result
    }
    None => []
  }
  { native_stub, }
}

///|
#borrow(command)
extern "c" fn system(command : Bytes) -> Int = "system"

///|
pub fn check_package(pkg : String) -> Unit! {
  println("Checking package: \{pkg}")
  let moon_pkg_path = pkg + "/moon.pkg.json"
  try {
    if not(@fs.is_file!(moon_pkg_path)) {
      raise MissingMoonPkgJson(moon_pkg_path)
    }
  } catch {
    _ => raise MissingMoonPkgJson(moon_pkg_path)
  }
  let moon_pkg : MoonBitPackage = moon_pkg_path
    |> @fs.read_file_to_string!()
    |> @json.parse!()
    |> @json.from_json!()
  let c_source = StringBuilder::new()
  for stub in moon_pkg.native_stub {
    let stub_path = pkg + "/" + stub
    let stub_text = @fs.read_file_to_string!(stub_path)
    if stub_text.contains("MOONBIT_FFI_EXPORT") {
      let lines = stub_text.split("\n").collect().map(fn(x) { x.to_string() })
      let mut first_ffi_line = 0
      for i in 0..<lines.length() {
        let line = lines[i]
        if line.contains("MOONBIT_FFI_EXPORT") {
          first_ffi_line = i
          break
        }
      }
      let separator = "/* moon-lint */"
      let lines = [
          ..lines[:first_ffi_line],
          separator,
          ..lines[first_ffi_line:],
        ]
      @fs.create_dir?("/tmp/moon-lint/abi") |> ignore()
      let commented_path = "/tmp/moon-lint/abi/\{stub}.comment.c"
      @fs.write_string_to_file!(commented_path, lines.join("\n"))
      let preprocessed_path = "/tmp/moon-lint/abi/\{stub}.preprocessed"
      let command = "gcc -E -CC \{commented_path} -I /Users/haoxiang/Library/MoonBit/include -I \{pkg} -o \{preprocessed_path}"
      let _ = system([..@encoding.encode(UTF8, command), 0])
      let stub_text = @fs.read_file_to_string!(preprocessed_path)
      let stub_text = stub_text.split(separator).drop(1).collect()[0].to_string()
      c_source.write_string(stub_text)
    }
  }
  let c_source = c_source.to_string()
  let moonbit_source = StringBuilder::new()
  for entry in @fs.read_dir!(pkg) {
    if not(entry.has_suffix(".mbt")) {
      continue
    }
    let entry_path = pkg + "/" + entry
    let entry_text = @fs.read_file_to_string!(entry_path)
    println("Collecting MoonBit source: \{entry_path}")
    moonbit_source.write_string(entry_text)
  }
  let moonbit_source = moonbit_source.to_string()
  check!(c=c_source, moonbit=moonbit_source)
}

///|
test "check" {
  let parser = @tree_sitter.Parser::new()
  parser.set_language(c_language)
  let c_source =
    #|int32_t
    #|moonbit_uv_is_closing(uv_handle_t *handle) {
    #|  int32_t is_closing = uv_is_closing(handle);
    #|  moonbit_decref(handle);
    #|  return is_closing;
    #|}
  let c_tree = parser.parse_string(None, c_source).unwrap()
  parser.set_language(moonbit_language)
  let moonbit_source =
    #|extern "c" fn uv_is_closing(self : Handle) -> Bool = "moonbit_uv_is_closing"
  let moonbit_tree = parser.parse_string(None, moonbit_source).unwrap()
  let c_root_node = c_tree.root_node()
  let moonbit_root_node = moonbit_tree.root_node()
  let c = CTranslationUnit::parse!(c_source, c_root_node)
  let moonbit = MoonBitStructure::parse!(moonbit_source, moonbit_root_node)
  let checker = Checker::new()
  checker.check!(moonbit~, c~)
}
