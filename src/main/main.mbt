///|
enum Arguments {
  Abi(pkg~ : String)
  Lint(ruleset~ : String, source~ : String, apply~ : Bool)
} derive(Show)

///|
type! ArgumentsError {
  MissingExecName
  MissingArgument(command~ : String)
  MissingCommand
  UnrecognizedCommand(String)
  UnrecognizedArgument(command~ : String, String)
  ExtraArgument(command~ : String, ArrayView[String])
} derive(Show)

///|
fn Arguments::parse_c(args : ArrayView[String]) -> Arguments!ArgumentsError {
  let command = "abi"
  match args {
    [] => raise ArgumentsError::MissingArgument(command~)
    [pkg] => Arguments::Abi(pkg~)
    [_, .. args] => raise ArgumentsError::ExtraArgument(command~, args)
  }
}

///|
fn Arguments::parse_lint(args : ArrayView[String]) -> Arguments!ArgumentsError {
  struct Args {
    mut ruleset : String
    mut source : String
    mut apply : Bool
  } derive(Show)
  let parsed : Args = { ruleset: "", source: "", apply: false }
  loop args[:] {
    ["--fix", .. args] => {
      parsed.apply = true
      continue args
    }
    [ruleset, source, .. args] => {
      parsed.ruleset = ruleset
      parsed.source = source
      continue args
    }
    [] => break
    [argument, ..] =>
      raise ArgumentsError::UnrecognizedArgument(command="lint", argument)
  }
  Arguments::Lint(
    ruleset=parsed.ruleset,
    source=parsed.source,
    apply=parsed.apply,
  )
}

///|
fn Arguments::parse(args : Array[String]) -> Arguments!ArgumentsError {
  match args {
    [] => raise ArgumentsError::MissingExecName
    [_] => raise ArgumentsError::MissingCommand
    [_, "abi", .. args] => Arguments::parse_c!(args)
    [_, "lint", .. args] => Arguments::parse_lint!(args)
    [_, command, ..] => raise ArgumentsError::UnrecognizedCommand(command)
  }
}

///|
fn main {
  try {
    let args = @sys.get_cli_args()
    let args = Arguments::parse!(args)
    match args {
      Abi(pkg~) => @abi.check_package!(pkg)
      Lint(ruleset~, source~, apply~) => {
        let ruleset = @fs.read_file_to_bytes!(ruleset)
        let edits = @lint.parse_rules!(ruleset)
        @lint.apply_dir!(source, edits, apply~)
      }
    }
  } catch {
    error => println("Error: \{error}")
  }
}
