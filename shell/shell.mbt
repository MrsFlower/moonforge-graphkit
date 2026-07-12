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
/// When `stdin_path` is given, the file at that path is redirected onto
/// the child's stdin (see `run_capture_to_file`'s doc comment for why this
/// matters — a large prompt passed as an `args` element instead can crash
/// some child processes on Windows).
///
/// This is a thin wrapper over `moonbitlang/async/process.collect_output`,
/// used for cases where the caller needs to distinguish stdout from stderr
/// (for example, classifying `moon prove` failures).
pub async fn run_capture(
  cmd : String,
  args : Array[String],
  cwd? : String,
  stdin_path? : String,
) -> CommandResult {
  let stdin = match stdin_path {
    Some(path) => Some(@process.redirect_from_file(path))
    None => None
  }
  let (exit_code, stdout_data, stderr_data) = match (cwd, stdin) {
    (Some(cwd), Some(stdin)) =>
      @process.collect_output(cmd, args, cwd=cwd[:], stdin~)
    (Some(cwd), None) => @process.collect_output(cmd, args, cwd=cwd[:])
    (None, Some(stdin)) => @process.collect_output(cmd, args, stdin~)
    (None, None) => @process.collect_output(cmd, args)
  }
  let stdout = decode_process_output(stdout_data, "stdout")
  let stderr = decode_process_output(stderr_data, "stderr")
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
  let output = decode_process_output(output_data, "merged output")
  { exit_code, stdout: output, stderr: "" }
}

///|
/// Run `cmd` with `args` to completion, but unlike `run_capture*`, stdout
/// is never buffered in this process's memory: it is redirected straight
/// to the file at `log_path` at the OS level via `@process.redirect_to_file`.
/// stderr is *not* included in `log_path` (see below) — it is captured
/// separately, in-memory, and returned once the child exits.
///
/// This exists so a caller can watch a long-running child process's
/// stdout *while it is still running*, by re-reading `log_path` from a
/// second, independent read (e.g. a background task's polling loop) —
/// `run_capture*` cannot support that, since their `CommandResult` is only
/// ever produced once the child has already exited. `log_path` is
/// truncated (`CreateOrTruncate`) at the start of every call, so a stale
/// log from a previous run is never mistaken for this one's output.
///
/// stdout and stderr are deliberately *not* merged into one file here:
/// `@process.redirect_to_file`'s handle has no double-close guard (unlike
/// the in-memory pipe `run_capture_merged` uses), so the same handle
/// cannot safely be passed to both `stdout` and `stderr`, and two
/// independently-opened handles pointed at the same path would race on
/// the file's byte offset. This is a real constraint for merging, not a
/// simplification of convenience — callers whose child writes everything
/// of interest to stdout (e.g. `codex exec --json`, which puts its entire
/// JSONL event stream on stdout) are unaffected; callers who need
/// interleaved stdout+stderr should use `run_capture_merged` instead and
/// accept its all-at-once-on-exit tradeoff.
///
/// When `stdin_path` is given, the file at that path is redirected onto
/// the child's stdin — see `run_capture`'s doc comment for why a large
/// prompt should go through stdin rather than `args` (a real crash on
/// Windows, not a style preference: see `docs/LESSONS.md`).
pub async fn run_capture_to_file(
  cmd : String,
  args : Array[String],
  log_path : String,
  cwd? : String,
  stdin_path? : String,
) -> (Int, String) {
  let stdout_sink = @process.redirect_to_file(
    log_path,
    create_mode=CreateOrTruncate,
  )
  let (r_err, w_err) = @process.read_from_process()
  let stdin = match stdin_path {
    Some(path) => Some(@process.redirect_from_file(path))
    None => None
  }
  @async.with_task_group() <| group => {
    let exit_code = group.spawn(() => {
      match (cwd, stdin) {
        (Some(cwd), Some(stdin)) =>
          @process.run(
            cmd,
            args[:],
            stdout=stdout_sink,
            stderr=w_err,
            stdin~,
            cwd=cwd[:],
          )
        (Some(cwd), None) =>
          @process.run(
            cmd,
            args[:],
            stdout=stdout_sink,
            stderr=w_err,
            cwd=cwd[:],
          )
        (None, Some(stdin)) =>
          @process.run(cmd, args[:], stdout=stdout_sink, stderr=w_err, stdin~)
        (None, None) =>
          @process.run(cmd, args[:], stdout=stdout_sink, stderr=w_err)
      }
    })
    let stderr = group.spawn(() => {
      defer r_err.close()
      decode_process_output(r_err.read_all(), "stderr")
    })
    (exit_code.wait(), stderr.wait())
  }
}

///|
/// External tools on Windows can emit diagnostics in encodings other than
/// UTF-8 (notably `wsl.exe` service errors). Do not let that crash the
/// framework; callers need a textual failure record they can classify or
/// surface.
fn decode_process_output(data : &@io.Data, stream_name : String) -> String {
  data.text() catch {
    _ => {
      let bytes = data.binary()
      let recovered = recover_ascii_utf16le(bytes)
      if recovered != "" {
        recovered
      } else {
        "<non-UTF8 \{stream_name} omitted; \{bytes.length()} byte(s)>"
      }
    }
  }
}

///|
/// Best-effort recovery for Windows diagnostics that arrive as UTF-16LE
/// bytes inside an otherwise non-UTF8 stream. This intentionally keeps
/// only printable ASCII plus CR/LF/TAB; it is for preserving machine
/// error codes such as `Wsl/Service/E_ACCESSDENIED`, not for general text
/// transcoding.
fn recover_ascii_utf16le(bytes : Bytes) -> String {
  let out = StringBuilder()
  let mut recovered = 0
  for i = 0; i + 1 < bytes.length(); i = i + 2 {
    if bytes[i + 1] == (0 : Int).to_byte() {
      let value = bytes[i].to_int()
      if value == 9 ||
        value == 10 ||
        value == 13 ||
        (32 <= value && value <= 126) {
        match value.to_char() {
          Some(ch) => {
            out.write_char(ch)
            recovered += 1
          }
          None => ()
        }
      }
    }
  }
  if recovered >= 4 {
    out.to_string()
  } else {
    ""
  }
}
