///|
/// Result of running an external command to completion, with stdout and
/// stderr captured separately.
pub struct CommandResult {
  exit_code : Int
  stdout : String
  stderr : String
} derive(Debug, Eq)

///|
/// Run `cmd` with `args` to completion, capturing stdout and stderr
/// separately. `cwd` sets the working directory for the child process when
/// provided; otherwise the current process's working directory is used.
///
/// This is a thin wrapper over `moonbitlang/async/process.collect_output`,
/// used for cases where the caller needs to distinguish stdout from stderr
/// (for example, classifying `moon prove` failures).
pub async fn run_capture(
  cmd : String,
  args : Array[String],
  cwd? : String,
) -> CommandResult {
  let (exit_code, stdout_data, stderr_data) = match cwd {
    Some(cwd) => @process.collect_output(cmd, args, cwd=cwd[:])
    None => @process.collect_output(cmd, args)
  }
  let stdout = stdout_data.text()
  let stderr = stderr_data.text()
  { exit_code, stdout, stderr }
}

///|
/// Run `cmd` with `args` to completion, capturing stdout and stderr merged
/// into a single stream (matching the order the child process produced
/// them). Cheaper than `run_capture` when the caller does not need to
/// distinguish the two streams.
pub async fn run_capture_merged(
  cmd : String,
  args : Array[String],
  cwd? : String,
) -> CommandResult {
  let (exit_code, output_data) = match cwd {
    Some(cwd) => @process.collect_output_merged(cmd, args, cwd=cwd[:])
    None => @process.collect_output_merged(cmd, args)
  }
  let output = output_data.text()
  { exit_code, stdout: output, stderr: "" }
}
