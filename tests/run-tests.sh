#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin/goal"
HOOK="$ROOT/goal-hook"

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

make_project() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/goal-test.XXXXXX")"
  mkdir -p "$dir/.goal/logs"
  printf "%s\n" "$dir"
}

make_fake_codex() {
  local bin_dir="$1"
  local mode="$2"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

mode="${GOAL_FAKE_MODE:-complete}"
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-last-message)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$mode" in
  complete)
    mkdir -p "$(dirname "$out")"
    if [[ "$out" == *worker-* ]]; then
      printf "worker complete\n" > "$out"
    elif [[ "$out" == *review-* ]]; then
      printf "REVIEW: pass\n" > "$out"
    elif [[ "$out" == *eval-* ]]; then
      printf "DONE: yes\n" > "$out"
    else
      printf "READY: yes\n" > "$out"
    fi
    ;;
  clarify-no)
    mkdir -p "$(dirname "$out")"
    if [[ "$out" == *worker-* ]]; then
      printf "worker complete\n" > "$out"
    elif [[ "$out" == *review-* ]]; then
      printf "REVIEW: pass\n" > "$out"
    elif [[ "$out" == *eval-* ]]; then
      printf "DONE: yes\n" > "$out"
    else
      printf "READY: no\n\nStatus: needs-clarification\n\nBlocking Question:\nWhat observable result proves this is complete?\n\nRecommended Default:\nThe requested behavior is covered by tests and documented in the README.\n" > "$out"
    fi
    ;;
  clarify-ready)
    mkdir -p "$(dirname "$out")"
    if [[ "$out" == *worker-* ]]; then
      printf "worker complete\n" > "$out"
    elif [[ "$out" == *review-* ]]; then
      printf "REVIEW: pass\n" > "$out"
    elif [[ "$out" == *eval-* ]]; then
      printf "DONE: yes\n" > "$out"
    else
      printf "READY: yes\n\nGoal: Improve goal clarification flow.\nDefinition of Done: The CLI supports clarify, answer, and start-clarified commands.\nAcceptance Criteria: start-clarified starts only after a ready handoff exists.\nVerification Plan: Run bash tests/run-tests.sh.\nOut of Scope: Do not install skills silently.\n" > "$out"
    fi
    ;;
  stall-worker)
    if [[ "$out" == *worker-* ]]; then
      sleep 30
    else
      mkdir -p "$(dirname "$out")"
      printf "unexpected non-worker call\n" > "$out"
    fi
    ;;
  *)
    printf "unknown fake mode: %s\n" "$mode" >&2
    exit 64
    ;;
esac
FAKE
  chmod +x "$bin_dir/codex"
  printf "%s\n" "$mode" > "$bin_dir/mode"
}

make_skill() {
  local root="$1"
  local name="$2"
  local description="${3:-Use when tests need the $name skill}"
  mkdir -p "$root/$name"
  cat > "$root/$name/SKILL.md" <<EOF
---
name: $name
description: $description
---

# $name
EOF
}

test_start_ready_defaults_to_ten_iterations() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" complete

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete "$BIN" start-ready "Goal: test. Definition of Done: status becomes complete. Acceptance Criteria: fake worker runs. Verification Plan: inspect status. Out of Scope: no real repository changes."
  ) >/dev/null

  assert_eq "10" "$(cat "$project/.goal/max-iterations")" "start-ready max iterations"
  assert_eq "complete" "$(cat "$project/.goal/status")" "start-ready completes with fake codex"
}

test_start_ready_rejects_incomplete_handoff() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" complete

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete "$BIN" start-ready "Goal: make it better"
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "start-ready should reject incomplete handoff"
  assert_eq "needs-clarification" "$(cat "$project/.goal/status")" "incomplete start-ready status"
  rg -q 'Definition of Done' "$project/.goal/clarify.md" || fail "missing fields should be written to clarify.md"
  [[ ! -f "$project/.goal/logs/worker-1.md" ]] || fail "worker ran despite incomplete handoff"
}

test_start_promotes_ready_clarity_check_to_goal_contract() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" clarify-ready

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=clarify-ready "$BIN" start "improve goal clarification"
  ) >/dev/null

  assert_eq "complete" "$(cat "$project/.goal/status")" "raw start with ready clarity status"
  rg -q '^Definition of Done:' "$project/.goal/goal.md" || fail "ready clarity output was not promoted to goal contract"
  rg -q '^Skill Plan:' "$project/.goal/goal.md" || fail "promoted goal contract missing skill plan"
}

test_custom_agent_command_can_replace_codex_exec() {
  local project agent_command
  project="$(make_project)"
  agent_command='case "$GOAL_OUTPUT" in *worker-*) printf "worker complete\n" > "$GOAL_OUTPUT";; *review-*) printf "REVIEW: pass\n" > "$GOAL_OUTPUT";; *eval-*) printf "DONE: yes\n" > "$GOAL_OUTPUT";; *) printf "READY: yes\n\nGoal: Run with a custom agent command.\nDefinition of Done: The configured command drives the loop.\nAcceptance Criteria: status becomes complete.\nVerification Plan: inspect status.\nOut of Scope: no codex binary dependency.\n" > "$GOAL_OUTPUT";; esac'

  (
    cd "$project"
    GOAL_AGENT_COMMAND="$agent_command" "$BIN" start "run with custom agent"
  ) >/dev/null

  assert_eq "complete" "$(cat "$project/.goal/status")" "custom agent command status"
}

test_legacy_codex_goal_wrapper_still_runs() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" complete

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete "$ROOT/bin/codex-goal" start-ready "Goal: wrapper test. Definition of Done: status becomes complete. Acceptance Criteria: fake worker runs through the wrapper. Verification Plan: inspect status. Out of Scope: no source changes."
  ) >/dev/null

  assert_eq "complete" "$(cat "$project/.goal/status")" "legacy wrapper status"
}

test_legacy_codex_goal_env_still_runs_custom_agent() {
  local project agent_command
  project="$(make_project)"
  agent_command='case "$CODEX_GOAL_OUTPUT" in *worker-*) printf "worker complete\n" > "$CODEX_GOAL_OUTPUT";; *review-*) printf "REVIEW: pass\n" > "$CODEX_GOAL_OUTPUT";; *eval-*) printf "DONE: yes\n" > "$CODEX_GOAL_OUTPUT";; *) printf "READY: yes\n\nGoal: Run with the legacy custom agent env.\nDefinition of Done: The legacy command env drives the loop.\nAcceptance Criteria: status becomes complete.\nVerification Plan: inspect status.\nOut of Scope: no codex binary dependency.\n" > "$CODEX_GOAL_OUTPUT";; esac'

  (
    cd "$project"
    CODEX_GOAL_AGENT_COMMAND="$agent_command" "$BIN" start "run with legacy custom agent env"
  ) >/dev/null

  assert_eq "complete" "$(cat "$project/.goal/status")" "legacy custom agent env status"
}

test_hook_retries_stalled_worker_three_times_then_blocks() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" stall-worker
  printf "active\n" > "$project/.goal/status"
  printf "Goal: stall test. Definition of Done: stalled workers are retried. Acceptance Criteria: status becomes blocked-stalled-worker. Verification Plan: inspect stalled logs. Out of Scope: no source changes.\n" > "$project/.goal/goal.md"
  printf "10\n" > "$project/.goal/max-iterations"

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=stall-worker GOAL_STALL_TIMEOUT_SECONDS=1 "$HOOK" --project "$project" --loop
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "stalled hook should exit non-zero"
  assert_eq "blocked-stalled-worker" "$(cat "$project/.goal/status")" "stalled hook status"
  assert_eq "3" "$(find "$project/.goal/logs" -name 'worker-*.stalled' | wc -l | tr -d ' ')" "stalled worker retry count"
}

test_hook_uses_current_codex_approval_flag() {
  ! rg -q -- ' -a never|\\n[[:space:]]*-a never' "$BIN" "$HOOK" || fail "obsolete codex exec -a never flag remains"
  rg -q -- '--dangerously-bypass-approvals-and-sandbox' "$HOOK" || fail "hook does not use current bypass flag"
}

test_runtime_files_do_not_hardcode_local_home() {
  ! rg -q '/Users/macbook' "$BIN" "$HOOK" "$ROOT/README.md" "$ROOT/skills/goal/SKILL.md" || fail "runtime files should not hardcode a local home path"
  [[ ! -L "$ROOT/skills/grill-with-docs" ]] || fail "bundled grill-with-docs skill should not be an absolute symlink"
}

test_hook_rejects_incomplete_goal_contract() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" complete
  printf "active\n" > "$project/.goal/status"
  printf "Goal: make it better\n" > "$project/.goal/goal.md"
  printf "10\n" > "$project/.goal/max-iterations"

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete "$HOOK" --project "$project" --loop
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "hook should reject incomplete active goal"
  assert_eq "needs-clarification" "$(cat "$project/.goal/status")" "incomplete hook goal status"
  rg -q 'Verification Plan' "$project/.goal/clarify.md" || fail "hook clarify file should name missing verification"
  [[ ! -f "$project/.goal/logs/worker-1.md" ]] || fail "hook ran worker despite incomplete contract"
}

test_start_ready_appends_installed_skill_plan() {
  local project fake_bin skill_dir
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  skill_dir="$project/skills"
  mkdir -p "$skill_dir"
  make_skill "$skill_dir" frontend-app-builder
  make_skill "$skill_dir" frontend-testing-debugging
  make_skill "$skill_dir" frontend-skill
  make_skill "$skill_dir" playwright
  make_skill "$skill_dir" verification-before-completion
  make_fake_codex "$fake_bin" complete

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$skill_dir" "$BIN" start-ready "Goal: Build a landing page prototype for a web app. Definition of Done: responsive page exists. Acceptance Criteria: browser verification passes. Verification Plan: inspect desktop and mobile. Out of Scope: no deployment."
  ) >/dev/null

  rg -q '^Skill Plan:' "$project/.goal/goal.md" || fail "goal is missing Skill Plan section"
  rg -q 'Task Type:.*frontend' "$project/.goal/goal.md" || fail "frontend task type was not detected"
  rg -q 'Required Installed Skills:' "$project/.goal/goal.md" || fail "installed skill list missing"
  rg -q 'frontend|playwright|verification' "$project/.goal/goal.md" || fail "expected frontend/browser/verification skill was not routed"
  rg -q '^- none$' "$project/.goal/goal.md" || fail "fully installed frontend route should not list missing candidates"
  rg -q 'Missing Skill Approval: not required; no missing candidates' "$project/.goal/goal.md" || fail "approval should not be required when no candidates are missing"
}

test_hook_prompts_enforce_skill_plan() {
  rg -q 'Skill Plan' "$HOOK" || fail "hook prompts do not mention Skill Plan"
  rg -q 'Fail.*required skill|required skill.*skipped|skill.*skipped' "$HOOK" || fail "reviewer/evaluator does not enforce required skill use"
}

test_missing_task_skill_stops_for_approval() {
  local project fake_bin empty_skills
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  empty_skills="$project/empty-skills"
  mkdir -p "$empty_skills"
  make_fake_codex "$fake_bin" complete

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$empty_skills" "$BIN" start-ready "Goal: Generate a polished product image. Definition of Done: image exists. Acceptance Criteria: image is inspected. Verification Plan: inspect output. Out of Scope: no unrelated files."
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "missing task skill should stop before worker"
  assert_eq "needs-skill-approval" "$(cat "$project/.goal/status")" "missing task skill status"
  rg -q 'imagegen' "$project/.goal/clarify.md" || fail "clarify file does not name missing imagegen skill"
  rg -q 'search/install.*imagegen|Search Recommendations|cannot be done to a high-quality standard' "$project/.goal/clarify.md" || fail "clarify file should recommend skill search/install and block high-quality execution"
  [[ ! -f "$project/.goal/logs/worker-1.md" ]] || fail "worker ran despite missing required task skill"
}

test_missing_skill_uses_search_command_recommendation() {
  local project fake_bin empty_skills
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  empty_skills="$project/empty-skills"
  mkdir -p "$empty_skills"
  make_fake_codex "$fake_bin" complete

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$empty_skills" GOAL_SKILL_SEARCH_COMMAND='printf "marketplace result for %s" "$GOAL_SKILL_CAPABILITY"' "$BIN" start-ready "Goal: Generate a polished product image. Definition of Done: image exists. Acceptance Criteria: image is inspected. Verification Plan: inspect output. Out of Scope: no unrelated files."
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "missing task skill should stop before worker"
  rg -q 'marketplace result for imagegen' "$project/.goal/clarify.md" || fail "clarify file should include search command recommendation"
}

test_missing_skill_searches_skills_sh_api() {
  local project fake_bin empty_skills curl_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  empty_skills="$project/empty-skills"
  curl_bin="$project/fake-bin/curl"
  mkdir -p "$empty_skills" "$fake_bin"
  make_fake_codex "$fake_bin" complete
  cat > "$curl_bin" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
url=""
for arg in "$@"; do
  case "$arg" in
    http*) url="$arg" ;;
  esac
done

case "$url" in
  */api/v1/skills/search*)
    printf '{"data":[{"id":"acme/skills/imagegen","slug":"imagegen","name":"Imagegen","source":"acme/skills","installs":42,"sourceType":"github","installUrl":"https://github.com/acme/skills","url":"https://skills.sh/acme/skills/imagegen"}]}'
    ;;
  */api/v1/skills/audit/acme/skills/imagegen)
    printf '{"id":"acme/skills/imagegen","audits":[{"provider":"Socket","status":"pass","summary":"No alerts","riskLevel":"LOW"}]}'
    ;;
  */api/v1/skills/acme/skills/imagegen)
    printf '{"id":"acme/skills/imagegen","source":"acme/skills","slug":"imagegen","installs":42,"files":[{"path":"SKILL.md","contents":"---\nname: imagegen\ndescription: Generate or edit raster images and photos.\n---\n"}]}'
    ;;
  *)
    exit 22
    ;;
esac
FAKE_CURL
  chmod +x "$curl_bin"

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$empty_skills" SKILLS_API_KEY="sk_test" CURL_BIN="$curl_bin" "$BIN" start-ready "Goal: Generate a polished product image. Definition of Done: image exists. Acceptance Criteria: image is inspected. Verification Plan: inspect output. Out of Scope: no unrelated files."
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "missing task skill should stop before worker"
  rg -q 'Imagegen.*skills.sh/acme/skills/imagegen' "$project/.goal/clarify.md" || fail "clarify file should include skills.sh recommendation"
  rg -q 'npx skills add https://github.com/acme/skills' "$project/.goal/clarify.md" || fail "clarify file should include skills.sh install command"
}

test_missing_skill_searches_open_agent_skill_without_api_key() {
  local project fake_bin empty_skills curl_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  empty_skills="$project/empty-skills"
  curl_bin="$project/fake-bin/curl"
  mkdir -p "$empty_skills" "$fake_bin"
  make_fake_codex "$fake_bin" complete
  cat > "$curl_bin" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
url=""
for arg in "$@"; do
  case "$arg" in
    http*) url="$arg" ;;
  esac
done

case "$url" in
  */api/agent/skills\?q=client%20proposal%20outreach\&format=json)
    printf '{"query":"client proposal outreach","total":1,"skills":[{"slug":"client-outreach","name":"Client Outreach","description":"Write client outreach and sales messaging","verified":true,"stats":{"downloads":1200,"rating":4.8},"install":"npx skills add acme/client-outreach","repository":"https://github.com/acme/client-outreach","urls":{"detail":"https://openagentskill.com/skills/client-outreach"}}]}'
    ;;
  */api/agent/skills/client-outreach\?format=json)
    printf '{"slug":"client-outreach","name":"Client Outreach","description":"Write client outreach and sales messaging","long_description":"Helps write client proposals and outreach sequences.","verified":true,"repository":"https://github.com/acme/client-outreach","urls":{"web":"https://openagentskill.com/skills/client-outreach"}}'
    ;;
  *)
    printf '{"query":"","total":0,"skills":[]}'
    ;;
esac
FAKE_CURL
  chmod +x "$curl_bin"

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$empty_skills" CURL_BIN="$curl_bin" "$BIN" start-ready "Goal: Create an X/Twitter client acquisition playbook. Definition of Done: playbook exists. Acceptance Criteria: it includes outreach templates and lead scoring. Verification Plan: inspect the playbook. Out of Scope: no auto-DM spam."
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "missing specialist skills should stop before worker"
  rg -q 'Client Outreach.*Open Agent Skill' "$project/.goal/clarify.md" || fail "clarify file should include Open Agent Skill recommendation"
  rg -q 'npx skills add acme/client-outreach' "$project/.goal/clarify.md" || fail "clarify file should include Open Agent Skill install command"
}

test_missing_specialist_skill_blocks_even_with_some_installed() {
  local project fake_bin skill_dir
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  skill_dir="$project/skills"
  mkdir -p "$skill_dir"
  make_skill "$skill_dir" notion-research-documentation
  make_fake_codex "$fake_bin" complete

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$skill_dir" "$BIN" start-ready "Goal: Create an X/Twitter client acquisition playbook. Definition of Done: playbook exists. Acceptance Criteria: it includes outreach templates and lead scoring. Verification Plan: inspect the playbook. Out of Scope: no auto-DM spam."
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "missing specialist skills should block even when one related skill is installed"
  assert_eq "needs-skill-approval" "$(cat "$project/.goal/status")" "missing specialist skill status"
  rg -q 'client-lead-scoring-skill|proposal-outreach-skill|headline-copywriting-skill|prompt-engineering-skill' "$project/.goal/clarify.md" || fail "clarify file does not name missing specialist capabilities"
  rg -q 'Recommended skill search/install targets' "$project/.goal/clarify.md" || fail "clarify file should include skill search/install recommendations"
  rg -q 'cannot be done to a high-quality standard with the current skill set' "$project/.goal/clarify.md" || fail "clarify file should state high-quality work is blocked without skills"
  ! rg -q 'bensigo-upwork-proposal|upwork-job-scoring' "$project/.goal/clarify.md" || fail "clarify file should not expose local user-specific skill names as required candidates"
  [[ ! -f "$project/.goal/logs/worker-1.md" ]] || fail "worker ran despite missing specialist skill candidates"
}

test_skill_candidate_must_match_description() {
  local project fake_bin skill_dir
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  skill_dir="$project/skills"
  mkdir -p "$skill_dir"
  make_skill "$skill_dir" notion-research-documentation "Use when tasks need research documentation and source synthesis"
  make_skill "$skill_dir" lead-scoring "Use when scoring client leads for fit and urgency"
  make_skill "$skill_dir" proposal "Use when managing unrelated project proposals for internal planning only"
  make_skill "$skill_dir" headline-formulas "Use when writing headlines and copywriting variants"
  make_skill "$skill_dir" prompt-engineering-patterns "Use when applying prompt engineering patterns"
  make_fake_codex "$fake_bin" complete

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$skill_dir" "$BIN" start-ready "Goal: Create an X/Twitter client acquisition playbook. Definition of Done: playbook exists. Acceptance Criteria: it includes outreach templates and lead scoring. Verification Plan: inspect the playbook. Out of Scope: no auto-DM spam."
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "candidate with unrelated description should not satisfy outreach capability"
  assert_eq "needs-skill-approval" "$(cat "$project/.goal/status")" "description mismatch status"
  rg -q 'proposal-outreach-skill' "$project/.goal/clarify.md" || fail "description mismatch should leave proposal outreach capability missing"
}

test_missing_specialist_skill_can_be_explicitly_approved_to_skip() {
  local project fake_bin skill_dir
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  skill_dir="$project/skills"
  mkdir -p "$skill_dir"
  make_skill "$skill_dir" notion-research-documentation
  make_skill "$skill_dir" lead-scoring
  make_skill "$skill_dir" proposal "Use when writing client outreach proposals"
  make_skill "$skill_dir" headline-formulas
  make_skill "$skill_dir" prompt-engineering-patterns
  make_fake_codex "$fake_bin" complete

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$skill_dir" "$BIN" start-ready "Goal: Create an X/Twitter client acquisition playbook. Definition of Done: playbook exists. Acceptance Criteria: it includes outreach templates and lead scoring. Verification Plan: inspect the playbook. Out of Scope: no auto-DM spam. Missing Skill Approval: approved."
  ) >/dev/null

  assert_eq "complete" "$(cat "$project/.goal/status")" "explicit missing skill skip approval status"
  rg -q 'Missing Skill Approval: approved' "$project/.goal/goal.md" || fail "approval marker was not preserved"
}

test_client_acquisition_not_misclassified_by_quality_test_language() {
  local project fake_bin skill_dir
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  skill_dir="$project/skills"
  mkdir -p "$skill_dir"
  make_skill "$skill_dir" notion-research-documentation
  make_skill "$skill_dir" lead-scoring
  make_skill "$skill_dir" proposal "Use when writing client outreach proposals"
  make_skill "$skill_dir" headline-formulas
  make_skill "$skill_dir" prompt-engineering-patterns
  make_fake_codex "$fake_bin" complete

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete GOAL_SKILL_SCAN_DIRS="$skill_dir" "$BIN" start-ready "Goal: Re-run the X/Twitter client acquisition playbook to test whether the skill-discovery gate improves quality. Definition of Done: rerun playbook exists. Acceptance Criteria: comparison includes outreach, lead scoring, and proposal quality. Verification Plan: inspect both outputs and compare quality. Out of Scope: no code changes."
  ) >/dev/null

  rg -q 'Task Type: client-acquisition' "$project/.goal/goal.md" || fail "client acquisition task was misclassified by quality test language"
  rg -q 'proposal' "$project/.goal/goal.md" || fail "client acquisition route did not include an installed proposal skill"
  rg -q 'Missing Skill Approval: not required; no missing candidates' "$project/.goal/goal.md" || fail "fully covered client acquisition route should not require approval"
  ! rg -q 'Task Type: coding' "$project/.goal/goal.md" || fail "client acquisition route fell through to coding"
}

test_coding_task_not_misclassified_by_no_docs_scope() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" complete

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete "$BIN" start-ready "Goal: Implement a tiny coding task by creating done.txt. Definition of Done: done.txt exists. Acceptance Criteria: done.txt contains expected text. Verification Plan: cat done.txt. Out of Scope: no app, no docs."
  ) >/dev/null

  rg -q 'Task Type: coding' "$project/.goal/goal.md" || fail "coding task was misclassified when Out of Scope mentioned no docs"
  rg -q 'test-driven-development' "$project/.goal/goal.md" || fail "coding task did not route to TDD"
  rg -q 'verification-before-completion' "$project/.goal/goal.md" || fail "coding task did not route to verification"
  ! rg -q 'systematic-debugging|diagnose|requesting-code-review' "$project/.goal/goal.md" || fail "simple coding task routed to heavyweight debug/review skills"
}

test_clarify_writes_blocking_question_without_starting_worker() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" clarify-no

  set +e
  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=clarify-no "$BIN" clarify "make goal routing better"
  ) >/dev/null 2>&1
  local code=$?
  set -e

  [[ "$code" -ne 0 ]] || fail "clarify should exit non-zero when more answers are needed"
  assert_eq "needs-clarification" "$(cat "$project/.goal/status")" "clarify status"
  rg -q 'Blocking Question:' "$project/.goal/clarify.md" || fail "clarify.md should contain a blocking question"
  [[ ! -f "$project/.goal/logs/worker-1.md" ]] || fail "clarify should not start worker"
}

test_answer_can_produce_ready_handoff_and_start_clarified() {
  local project fake_bin
  project="$(make_project)"
  fake_bin="$project/fake-bin"
  make_fake_codex "$fake_bin" clarify-ready

  (
    cd "$project"
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=clarify-ready "$BIN" clarify "improve goal clarification" >/dev/null
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=clarify-ready "$BIN" answer "Done means tests cover the behavior." >/dev/null
    PATH="$fake_bin:$PATH" GOAL_FAKE_MODE=complete "$BIN" start-clarified >/dev/null
  )

  assert_eq "complete" "$(cat "$project/.goal/status")" "start-clarified status"
  rg -q 'Done means tests cover the behavior' "$project/.goal/clarify-answers.md" || fail "answer was not persisted"
  rg -q '^Skill Plan:' "$project/.goal/goal.md" || fail "start-clarified goal missing skill plan"
}

test_start_ready_defaults_to_ten_iterations
test_start_ready_rejects_incomplete_handoff
test_start_promotes_ready_clarity_check_to_goal_contract
test_custom_agent_command_can_replace_codex_exec
test_legacy_codex_goal_wrapper_still_runs
test_legacy_codex_goal_env_still_runs_custom_agent
test_hook_retries_stalled_worker_three_times_then_blocks
test_hook_uses_current_codex_approval_flag
test_runtime_files_do_not_hardcode_local_home
test_hook_rejects_incomplete_goal_contract
test_start_ready_appends_installed_skill_plan
test_hook_prompts_enforce_skill_plan
test_missing_task_skill_stops_for_approval
test_missing_skill_uses_search_command_recommendation
test_missing_skill_searches_skills_sh_api
test_missing_skill_searches_open_agent_skill_without_api_key
test_missing_specialist_skill_blocks_even_with_some_installed
test_skill_candidate_must_match_description
test_missing_specialist_skill_can_be_explicitly_approved_to_skip
test_client_acquisition_not_misclassified_by_quality_test_language
test_coding_task_not_misclassified_by_no_docs_scope
test_clarify_writes_blocking_question_without_starting_worker
test_answer_can_produce_ready_handoff_and_start_clarified

printf "All goal tests passed.\n"
