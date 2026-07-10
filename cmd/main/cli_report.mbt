///|
/// Map each pipeline result enum to a human-readable message (stdout on
/// success, stderr on failure) and an exit code. Exit codes are chosen to
/// be scriptable: 0 success, 2 usage/config error, 3 needs human review, 4
/// rounds exhausted. Exit code 1 is deliberately left unused here, so an
/// uncaught error falling through to the async runtime's own generic
/// fallback (which always exits 1) stays visibly distinct from any of
/// these explicitly-handled outcomes.
async fn report_run_result(result : @orchestrator.RunResult) -> Int {
  match result {
    VerificationSuccess(rounds_used~) => {
      println("verification succeeded after \{rounds_used} round(s)")
      0
    }
    NeedsHumanReview(reason~) => {
      @stdio.stderr.write("needs human review: \{reason}\n")
      3
    }
    RoundsExhausted(last_kind~, last_outcome~) => {
      @stdio.stderr.write(
        "rounds exhausted without a successful proof; last failure: \{last_kind}\n",
      )
      @stdio.stderr.write("last stdout:\n\{last_outcome.stdout}\n")
      @stdio.stderr.write("last stderr:\n\{last_outcome.stderr}\n")
      4
    }
  }
}

///|
async fn report_scaffold_result(result : @scaffolder.ScaffoldResult) -> Int {
  match result {
    ScaffoldSuccess(package_dir~, files_written~) => {
      println("scaffold succeeded: \{package_dir}")
      for file in files_written {
        println("  wrote \{file}")
      }
      0
    }
    NeedsHumanReview(reason~) => {
      @stdio.stderr.write("needs human review: \{reason}\n")
      3
    }
    RoundsExhausted(last_kind~, raw_output~) => {
      @stdio.stderr.write(
        "rounds exhausted without moon check accepting the package; last failure: \{last_kind}\n",
      )
      @stdio.stderr.write("last output:\n\{raw_output}\n")
      4
    }
  }
}

///|
async fn report_scaffold_and_fill_result(
  result : @scaffolder.ScaffoldAndFillResult,
) -> Int {
  match result {
    FullSuccess(package_dir~, fill_rounds_used~) => {
      println(
        "scaffold-and-fill succeeded: \{package_dir} (fill stage used \{fill_rounds_used} round(s))",
      )
      0
    }
    ScaffoldStageFailed(result~) => {
      @stdio.stderr.write("scaffold stage failed:\n")
      report_scaffold_result(result)
    }
    FillStageFailed(result~) => {
      @stdio.stderr.write("fill stage failed:\n")
      report_run_result(result)
    }
  }
}
