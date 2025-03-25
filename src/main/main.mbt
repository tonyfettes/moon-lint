///|
fn main {
  try {
    let args = @sys.get_cli_args()
    let args = @lib.Arguments::parse(args)
    let ruleset = @fs.read_file_to_bytes!(args.ruleset_path)
    let edits = @lib.parse_rules!(ruleset)
    @lib.apply_dir!(args.source_path, edits, apply=args.apply)
  } catch {
    error => println("Error: \{error}")
  }
}
