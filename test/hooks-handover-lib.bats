#!/usr/bin/env bats
# claude/skills/handover/scripts/handover-lib.sh のテスト。
# ライブラリを source して関数を直接呼ぶ。

load "helpers/common"

LIB="${BATS_TEST_DIRNAME}/../claude/skills/handover/scripts/handover-lib.sh"

# Sourced per test, not at file level: a missing lib must fail every test
# rather than leave bats reporting zero tests and exit 0.
setup() {
  source "$LIB"
  make_tmpdir
}

teardown() {
  rm -rf "$TEST_TMPDIR" "${GIT_REPO:-/private/tmp/nonexistent-dotfiles-test}"
}

# A version-5 state file with one done task (T1) and one in_progress task (T2).
write_state() {  # $1=path
  cat > "$1" <<'JSON'
{
  "version": 5,
  "session_id": "test-session",
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "description": "task one", "status": "done", "commit_sha": "abc1234", "file_paths": ["a.sh"], "last_touched": "2026-07-01T00:00:00Z"},
    {"id": "T2", "description": "task two", "status": "in_progress", "file_paths": ["b.sh"], "next_action": "fix b.sh", "last_touched": "2026-07-01T00:00:00Z"}
  ],
  "recent_decisions": [],
  "architecture_changes": [],
  "known_issues": []
}
JSON
}

# One READY session plus one ALL_COMPLETE session under $TEST_TMPDIR.
seed_two_sessions() {
  mkdir -p "$TEST_TMPDIR/main/20260701-090000" "$TEST_TMPDIR/main/20260701-100000"
  cat > "$TEST_TMPDIR/main/20260701-090000/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "status": "done"},
    {"id": "T2", "status": "in_progress", "next_action": "fix bug"}
  ]
}
JSON
  cat > "$TEST_TMPDIR/main/20260701-100000/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "ALL_COMPLETE",
  "active_tasks": [
    {"id": "T1", "status": "done"}
  ]
}
JSON
}

scan_field() {  # $1=jq path -> field of the first scanned session
  scan_sessions "$TEST_TMPDIR" | jq -r "$1"
}

scan_branch_of() {  # $1=base dir (may carry a trailing slash)
  scan_sessions "$1" | jq -r '.[0].branch'
}

@test "_handover_log prefixes message with [handover]" {
  run _handover_log "hello"
  [ "$output" = "[handover] hello" ]
}

@test "validate_project_state accepts valid version-5 file" {
  write_state "$TEST_TMPDIR/project-state.json"
  run validate_project_state "$TEST_TMPDIR/project-state.json"
  [ "$status" -eq 0 ]
}

@test "validate_project_state rejects missing file" {
  run validate_project_state "$TEST_TMPDIR/does-not-exist.json"
  [ "$status" -eq 1 ]
}

@test "validate_project_state rejects invalid JSON" {
  echo "not json" > "$TEST_TMPDIR/project-state.json"
  run validate_project_state "$TEST_TMPDIR/project-state.json"
  [ "$status" -eq 1 ]
}

@test "validate_project_state rejects version 3" {
  echo '{"version": 3, "status": "READY", "active_tasks": []}' > "$TEST_TMPDIR/project-state.json"
  run validate_project_state "$TEST_TMPDIR/project-state.json"
  [ "$status" -eq 1 ]
}

@test "validate_project_state rejects missing active_tasks" {
  echo '{"version": 5, "status": "READY"}' > "$TEST_TMPDIR/project-state.json"
  run validate_project_state "$TEST_TMPDIR/project-state.json"
  [ "$status" -eq 1 ]
}

@test "scan_sessions excludes ALL_COMPLETE sessions" {
  seed_two_sessions
  run scan_field 'length'
  [ "$output" = "1" ]
}

@test "scan_sessions reports branch" {
  seed_two_sessions
  run scan_field '.[0].branch'
  [ "$output" = "main" ]
}

@test "scan_sessions reports fingerprint" {
  seed_two_sessions
  run scan_field '.[0].fingerprint'
  [ "$output" = "20260701-090000" ]
}

@test "scan_sessions reports done_tasks" {
  seed_two_sessions
  run scan_field '.[0].done_tasks'
  [ "$output" = "1" ]
}

@test "scan_sessions reports total_tasks" {
  seed_two_sessions
  run scan_field '.[0].total_tasks'
  [ "$output" = "2" ]
}

@test "scan_sessions reports next_action" {
  seed_two_sessions
  run scan_field '.[0].next_action'
  [ "$output" = "fix bug" ]
}

@test "scan_sessions returns empty array for empty base dir" {
  run scan_field 'length'
  [ "$output" = "0" ]
}

@test "scan_sessions preserves slash-containing branch names" {
  mkdir -p "$TEST_TMPDIR/feature/auth-refactor/20260701-090000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' \
    > "$TEST_TMPDIR/feature/auth-refactor/20260701-090000/project-state.json"
  run scan_field '.[0].branch'
  [ "$output" = "feature/auth-refactor" ]
}

@test "scan_sessions extracts fingerprint under nested branch path" {
  mkdir -p "$TEST_TMPDIR/feature/auth-refactor/20260701-090000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' \
    > "$TEST_TMPDIR/feature/auth-refactor/20260701-090000/project-state.json"
  run scan_field '.[0].fingerprint'
  [ "$output" = "20260701-090000" ]
}

@test "scan_sessions strips a trailing slash from base_dir before deriving branch" {
  mkdir -p "$TEST_TMPDIR/main/20260701-090000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' \
    > "$TEST_TMPDIR/main/20260701-090000/project-state.json"
  run scan_branch_of "$TEST_TMPDIR/"
  [ "$output" = "main" ]
}

@test "find_active_session_dir skips newer ALL_COMPLETE and picks older READY" {
  GIT_REPO="$(make_tmp_git_repo)"
  mkdir -p "$GIT_REPO/.agents/handover/main/20260701-090000" \
           "$GIT_REPO/.agents/handover/main/20260701-100000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' \
    > "$GIT_REPO/.agents/handover/main/20260701-090000/project-state.json"
  echo '{"version":5,"status":"ALL_COMPLETE","active_tasks":[]}' \
    > "$GIT_REPO/.agents/handover/main/20260701-100000/project-state.json"
  run find_active_session_dir "$GIT_REPO"
  [ "$output" = "$GIT_REPO/.agents/handover/main/20260701-090000" ]
}

@test "find_active_session_dir returns 1 when no .agents/handover exists" {
  GIT_REPO="$(make_tmp_git_repo)"
  run find_active_session_dir "$GIT_REPO"
  [ "$status" -eq 1 ]
}

@test "find_active_session_dir returns 1 outside a git repo" {
  run find_active_session_dir "$TEST_TMPDIR"
  [ "$status" -eq 1 ]
}

@test "add_architecture_change appends one entry" {
  write_state "$TEST_TMPDIR/project-state.json"
  add_architecture_change "$TEST_TMPDIR/project-state.json" "abc1234" "test summary" \
    '["a.sh","b.sh"]' "2026-07-10T00:00:00Z"
  run jq '.architecture_changes | length' "$TEST_TMPDIR/project-state.json"
  [ "$output" = "1" ]
}

@test "add_architecture_change records commit_sha" {
  write_state "$TEST_TMPDIR/project-state.json"
  add_architecture_change "$TEST_TMPDIR/project-state.json" "abc1234" "test summary" \
    '["a.sh","b.sh"]' "2026-07-10T00:00:00Z"
  run jq -r '.architecture_changes[0].commit_sha' "$TEST_TMPDIR/project-state.json"
  [ "$output" = "abc1234" ]
}

@test "touch_related_tasks leaves non-matching task untouched" {
  write_state "$TEST_TMPDIR/project-state.json"
  touch_related_tasks "$TEST_TMPDIR/project-state.json" '["b.sh"]' "2026-07-10T12:00:00Z"
  run jq -r '.active_tasks[] | select(.id=="T1") | .last_touched' "$TEST_TMPDIR/project-state.json"
  [ "$output" = "2026-07-01T00:00:00Z" ]
}

@test "touch_related_tasks updates matching task" {
  write_state "$TEST_TMPDIR/project-state.json"
  touch_related_tasks "$TEST_TMPDIR/project-state.json" '["b.sh"]' "2026-07-10T12:00:00Z"
  run jq -r '.active_tasks[] | select(.id=="T2") | .last_touched' "$TEST_TMPDIR/project-state.json"
  [ "$output" = "2026-07-10T12:00:00Z" ]
}

@test "update_status_field marks ALL_COMPLETE when every task is done" {
  echo '{"version":5,"status":"READY","active_tasks":[{"id":"T1","status":"done"},{"id":"T2","status":"done"}]}' \
    > "$TEST_TMPDIR/project-state.json"
  update_status_field "$TEST_TMPDIR/project-state.json"
  run jq -r '.status' "$TEST_TMPDIR/project-state.json"
  [ "$output" = "ALL_COMPLETE" ]
}

@test "update_status_field keeps READY when a task is pending" {
  write_state "$TEST_TMPDIR/project-state.json"
  update_status_field "$TEST_TMPDIR/project-state.json"
  run jq -r '.status' "$TEST_TMPDIR/project-state.json"
  [ "$output" = "READY" ]
}

# The six generate_handover_md cases share this fixture.
gen_md() {
  write_state "$TEST_TMPDIR/project-state.json"
  add_architecture_change "$TEST_TMPDIR/project-state.json" "abc1234" "did a thing" \
    '["a.sh"]' "2026-07-10T00:00:00Z"
  generate_handover_md "$TEST_TMPDIR/project-state.json" "$TEST_TMPDIR/handover.md"
}

@test "generate_handover_md writes title line" {
  gen_md
  grep -q "^# Session Handover" "$TEST_TMPDIR/handover.md"
}

@test "generate_handover_md writes Completed section" {
  gen_md
  grep -qF "## Completed" "$TEST_TMPDIR/handover.md"
}

@test "generate_handover_md lists the done task" {
  gen_md
  grep -qF "T1" "$TEST_TMPDIR/handover.md"
}

@test "generate_handover_md writes Remaining section" {
  gen_md
  grep -qF "## Remaining" "$TEST_TMPDIR/handover.md"
}

@test "generate_handover_md lists next_action for in-progress task" {
  gen_md
  grep -qF "fix b.sh" "$TEST_TMPDIR/handover.md"
}

@test "generate_handover_md lists architecture change" {
  gen_md
  grep -qF "abc1234: did a thing" "$TEST_TMPDIR/handover.md"
}
