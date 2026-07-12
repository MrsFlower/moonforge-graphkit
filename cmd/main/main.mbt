///|
/// Entry point for the MoonForge CLI. Parses argv into one of three
/// subcommands (`fill`, `scaffold`, `scaffold-and-fill`), builds the
/// matching pipeline config, resolves a backend/prove-runner from the
/// shared flags, calls the corresponding library pipeline function
/// (`orchestrator.run` / `scaffolder.generate` / `scaffolder.generate_and_fill`),
/// and reports the result. All pipeline/config logic lives in
/// `cli_spec.mbt`/`cli_config.mbt`/`cli_report.mbt`; this file is dispatch
/// only.
///
/// Run with `moon run cmd/main -- <subcommand> [flags...]`.

///|
#cfg(target="native")
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  let exit_code = try {
    let matches = build_root_command().parse()
    guard matches.subcommand is Some((name, sub_matches)) else {
      @stdio.stderr.write("no subcommand selected\n")
      2
    }
    match name {
      "fill" => run_fill(sub_matches)
      "fill-sequence" => run_fill_sequence(sub_matches)
      "scaffold" => run_scaffold(sub_matches)
      "scaffold-and-fill" => run_scaffold_and_fill(sub_matches)
      other => {
        @stdio.stderr.write("unknown subcommand: \{other}\n")
        2
      }
    }
  } catch {
    err => {
      @stdio.stderr.write("error: \{err}\n")
      2
    }
  }
  exit(exit_code)
}

///|
async fn run_fill(matches : @argparse.Matches) -> Int {
  let config = build_run_config(matches)
  let backend = resolve_backend(matches)
  let runner = resolve_prove_runner(matches)
  let result = @orchestrator.run(
    backend,
    @prover_loop.RealCheckGate::{  },
    runner,
    config,
  )
  report_run_result(result)
}

///|
async fn run_fill_sequence(matches : @argparse.Matches) -> Int {
  let config = build_sequence_run_config(matches)
  let backend = resolve_backend(matches)
  let runner = resolve_prove_runner(matches)
  let result = @orchestrator.run_sequence(
    backend,
    @prover_loop.RealCheckGate::{  },
    runner,
    config,
  )
  report_sequence_run_result(result)
}

///|
async fn run_scaffold(matches : @argparse.Matches) -> Int {
  let config = build_scaffold_config(matches, with_tags=false)
  let backend = resolve_backend(matches)
  let result = @scaffolder.generate(
    backend,
    @prover_loop.RealCheckGate::{  },
    config,
  )
  report_scaffold_result(result)
}

///|
async fn run_scaffold_and_fill(matches : @argparse.Matches) -> Int {
  let config = build_scaffold_and_fill_config(matches)
  let backend = resolve_backend(matches)
  let runner = resolve_prove_runner(matches)
  let result = @scaffolder.generate_and_fill(
    backend,
    @prover_loop.RealCheckGate::{  },
    runner,
    config,
  )
  report_scaffold_and_fill_result(result)
}
