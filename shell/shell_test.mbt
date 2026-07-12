///|
async test "run_capture captures stdout from an external command" {
  let result = @shell.run_capture("powershell", [
    "-NoProfile", "-Command", "Write-Output 'hello-from-moonforge'",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.contains("hello-from-moonforge"))
}

///|
async test "run_capture reports non-zero exit code" {
  let result = @shell.run_capture("powershell", [
    "-NoProfile", "-Command", "exit 3",
  ])
  assert_eq(result.exit_code, 3)
}

///|
async test "run_capture separates stderr from stdout" {
  let result = @shell.run_capture("powershell", [
    "-NoProfile", "-Command", "[Console]::Error.WriteLine('err-line'); Write-Output 'out-line'",
  ])
  assert_true(result.stdout.contains("out-line"))
  assert_true(result.stderr.contains("err-line"))
}

///|
async test "run_capture_merged combines stdout and stderr" {
  let result = @shell.run_capture_merged("powershell", [
    "-NoProfile", "-Command", "Write-Output 'merged-out'",
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.contains("merged-out"))
}

///|
async test "run_capture_to_file writes stdout to disk instead of returning it" {
  let log_path = @fs.tmpdir(prefix="moonforge_shell_test_") + "/activity.log"
  let (exit_code, stderr) = @shell.run_capture_to_file(
    "powershell",
    ["-NoProfile", "-Command", "Write-Output 'to-file-out'"],
    log_path,
  )
  assert_eq(exit_code, 0)
  assert_eq(stderr, "")
  assert_true(@fs.read_file(log_path).text().contains("to-file-out"))
}

///|
async test "run_capture_to_file captures stderr separately from the stdout file" {
  let log_path = @fs.tmpdir(prefix="moonforge_shell_test_") + "/activity.log"
  let (exit_code, stderr) = @shell.run_capture_to_file(
    "powershell",
    [
      "-NoProfile", "-Command", "[Console]::Error.WriteLine('to-file-err'); Write-Output 'to-file-out2'",
    ],
    log_path,
  )
  assert_eq(exit_code, 0)
  assert_true(stderr.contains("to-file-err"))
  let logged = @fs.read_file(log_path).text()
  assert_true(logged.contains("to-file-out2"))
  assert_true(!logged.contains("to-file-err"))
}

///|
async test "run_capture_to_file truncates a stale log from a previous call" {
  let log_path = @fs.tmpdir(prefix="moonforge_shell_test_") + "/activity.log"
  @fs.write_file(
    log_path,
    "stale content that must not survive",
    create_mode=CreateOrTruncate,
  )
  let (exit_code, _stderr) = @shell.run_capture_to_file(
    "powershell",
    ["-NoProfile", "-Command", "Write-Output 'fresh-content'"],
    log_path,
  )
  assert_eq(exit_code, 0)
  let logged = @fs.read_file(log_path).text()
  assert_true(logged.contains("fresh-content"))
  assert_true(!logged.contains("stale content"))
}

///|
/// `stdin_path` exists specifically so a caller never has to pass large
/// content as an `args` element (see `llm.build_exec_args`'s doc comment
/// for the real `codex exec` crash that motivated this on the `llm` side).
/// This test only proves the plumbing itself works with a generic
/// stdin-echoing command; it does not touch `codex`.
async test "run_capture with stdin_path redirects a file onto the child's stdin" {
  let input_path = @fs.tmpdir(prefix="moonforge_shell_test_") +
    "/stdin_input.txt"
  @fs.write_file(input_path, "piped-in-content", create_mode=CreateOrTruncate)
  let result = @shell.run_capture(
    "powershell",
    [
      "-NoProfile", "-Command", "$piped = [Console]::In.ReadToEnd(); Write-Output $piped",
    ],
    stdin_path=input_path,
  )
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.contains("piped-in-content"))
}

///|
async test "run_capture_to_file with stdin_path redirects a file onto the child's stdin" {
  let input_path = @fs.tmpdir(prefix="moonforge_shell_test_") +
    "/stdin_input.txt"
  @fs.write_file(input_path, "piped-in-content-2", create_mode=CreateOrTruncate)
  let log_path = @fs.tmpdir(prefix="moonforge_shell_test_") + "/activity.log"
  let (exit_code, _stderr) = @shell.run_capture_to_file(
    "powershell",
    [
      "-NoProfile", "-Command", "$piped = [Console]::In.ReadToEnd(); Write-Output $piped",
    ],
    log_path,
    stdin_path=input_path,
  )
  assert_eq(exit_code, 0)
  assert_true(@fs.read_file(log_path).text().contains("piped-in-content-2"))
}

///|
async test "run_capture tolerates non-UTF8 process diagnostics" {
  let result = @shell.run_capture("powershell", [
    "-NoProfile", "-Command", "$bytes = [byte[]](0xff,0xfe,0x00); [Console]::OpenStandardError().Write($bytes, 0, $bytes.Length); exit 7",
  ])
  assert_eq(result.exit_code, 7)
  assert_true(result.stderr.contains("non-UTF8 stderr omitted"))
}

///|
async test "run_capture recovers ascii from UTF16LE diagnostics" {
  let result = @shell.run_capture("powershell", [
    "-NoProfile", "-Command", "$text = 'Wsl/Service/E_ACCESSDENIED'; $bytes = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes($text); [Console]::OpenStandardError().Write($bytes, 0, $bytes.Length); exit 8",
  ])
  assert_eq(result.exit_code, 8)
  assert_true(result.stderr.contains("Wsl/Service/E_ACCESSDENIED"))
}
