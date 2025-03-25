///|
struct Arguments {
  ruleset_path : String
  source_path : String
  apply : Bool
} derive(Show)

///|
fn Arguments::parse(args : Array[String]) -> Arguments {
  struct Args {
    mut ruleset : String
    mut source : String
    mut apply : Bool
  } derive(Show)
  let parsed : Args = { ruleset: "", source: "", apply: false }
  loop args[1:] {
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
    _ => {
      println("Usage: \{args[0]} <ruleset_path> <source_path> [--fix]")
      @sys.exit(1)
    }
  }
  Arguments::{
    ruleset_path: parsed.ruleset,
    source_path: parsed.source,
    apply: parsed.apply,
  }
}

///|
fn main {
  try {
    let args = @sys.get_cli_args()
    let args = Arguments::parse(args)
    let ruleset = @fs.read_file_to_bytes!(args.ruleset_path)
    let edits = @lib.parse_rules!(ruleset)
    @lib.apply_dir!(args.source_path, edits, apply=args.apply)
  } catch {
    error => println("Error: \{error}")
  }
}
