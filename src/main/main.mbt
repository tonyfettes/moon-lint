///|
enum Arguments {
  C(pkg~ : String)
  Lint(ruleset~ : String, source~ : String, apply~ : Bool)
} derive(Show)

///|
type! ArgumentsError {
  MissingArgument(command~ : String)
  MissingCommand
  UnrecognizedCommand(String)
  UnrecognizedArgument(command~ : String, String)
  ExtraArgument(command~ : String, ArrayView[String])
}

///|
fn Arguments::parse_foreign(
  args : ArrayView[String]
) -> Arguments!ArgumentsError {
  match args {
    [] => raise ArgumentsError::MissingArgument(command="foreign")
    [pkg] => Arguments::C(pkg~)
    [_, .. args] => raise ArgumentsError::ExtraArgument(command="foreign", args)
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
    [] => raise ArgumentsError::MissingCommand
    ["foreign", .. args] => Arguments::parse_foreign!(args)
    ["lint", .. args] => Arguments::parse_lint!(args)
    [command, ..] => raise ArgumentsError::UnrecognizedCommand(command)
  }
}

///|
fn main {
  try {
    let args = @sys.get_cli_args()
    let args = Arguments::parse!(args)
    match args {
      C(pkg~) => @c.check_package!(pkg)
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
