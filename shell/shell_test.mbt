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
