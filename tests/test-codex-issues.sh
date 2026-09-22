#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="${CODEX_ISSUES_TEST_SCRIPT:-$repo_root/bin/codex-issues}"
bash -n "$script"
"$script" --help | grep 'codex-issues start' >/dev/null

# All artifacts, worktrees, and the private tmux socket belong to this test.
TEST_ROOT="$(mktemp -d /tmp/codex-issues-regression-test-XXXXXX)"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
REAL_TMUX="$(command -v tmux)"
export TEST_ROOT REAL_TMUX
cleanup() {
  "$REAL_TMUX" -S "$TEST_ROOT/tmux.sock" kill-server 2>/dev/null || true
  rm -r "$TEST_ROOT"
}
trap cleanup EXIT
export CODEX_ISSUES_STATE_ROOT="$TEST_ROOT/state"
export CODEX_ISSUES_WORKTREE_ROOT="$TEST_ROOT/worktrees"
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/tmux" <<'STUB'
#!/usr/bin/env bash
exec "$REAL_TMUX" -S "$TEST_ROOT/tmux.sock" -f /dev/null "$@"
STUB
cat > "$TEST_ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  'repo view')
    if [[ "$*" == *nameWithOwner* ]]; then printf 'owner/repo\n'; else printf 'main\n'; fi ;;
  'issue view')
    printf '{"number":%s,"title":"Test issue","body":"Do the work","url":"https://github.com/owner/repo/issues/%s"}\n' "$3" "$3" ;;
esac
STUB
cat > "$TEST_ROOT/bin/codex" <<'STUB'
#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, time, tomllib
root = pathlib.Path(os.environ['TEST_ROOT'])
args = sys.argv[1:]
if args[0] == 'queue':
    if '--help' in args:
        sys.exit(0)
    (root / 'queue.json').write_text(json.dumps(args))
    sys.exit(1 if (root / 'reject-queue').exists() else 0)
assert args[0] == '--yolo'
assert '--dangerously-bypass-hook-trust' not in args
configs = [tomllib.loads(args[i+1]) for i, arg in enumerate(args) if arg == '-c']
hooks = {k: v for config in configs for k, v in config.get('hooks', {}).items()}
assert set(hooks) == {'SessionStart', 'UserPromptSubmit', 'Stop', 'Interrupt'}
issue = pathlib.Path.cwd().name.removeprefix('issue-')
(root / ('args-' + issue + '.json')).write_text(json.dumps(args))
for event in ('SessionStart', 'UserPromptSubmit'):
    command = hooks[event][0]['hooks'][0]['command']
    payload = {'cwd': os.getcwd(), 'session_id': 'thread-' + issue, 'hook_event_name': event, 'prompt': args[-1]}
    if event == 'SessionStart':
        # Another conversation arrives first, in the same worktree.
        foreign = dict(payload, session_id='unrelated-thread')
        subprocess.run(command, input=json.dumps(foreign), text=True, shell=True, check=True)
        foreign.update(hook_event_name='UserPromptSubmit', prompt='Unrelated work')
        subprocess.run(command, input=json.dumps(foreign), text=True, shell=True, check=True)
    subprocess.run(command, input=json.dumps(payload), text=True, shell=True, check=True)
(root / ('ready-' + issue)).touch()
print('Codex chat ready', flush=True)
while not (root / ('exit-' + issue)).exists():
    time.sleep(.05)
sys.exit(int((root / ('exit-' + issue)).read_text()))
STUB
chmod +x "$TEST_ROOT/bin/gh" "$TEST_ROOT/bin/codex" "$TEST_ROOT/bin/tmux"
export PATH="$TEST_ROOT/bin:$PATH"

git init --bare -q "$TEST_ROOT/origin.git"
git init -q -b main "$TEST_ROOT/repo"
git -C "$TEST_ROOT/repo" config user.name Test
git -C "$TEST_ROOT/repo" config user.email codex-issues-test.invalid
touch "$TEST_ROOT/repo/README.md"
git -C "$TEST_ROOT/repo" add README.md
git -C "$TEST_ROOT/repo" commit -qm init
git -C "$TEST_ROOT/repo" remote add origin "$TEST_ROOT/origin.git"
git -C "$TEST_ROOT/repo" push -qu origin main

wait_for() {
  local n
  for ((n=0; n<100; n++)); do if "$@"; then return 0; fi; sleep .1; done
  printf 'timed out: %s\n' "$*" >&2
  tmux list-panes -a -F '#{pane_id} #{pane_dead} #{pane_dead_status}' >&2 || true
  tmux capture-pane -p -t "$pane" >&2 || true
  return 1
}
if "$script" status '../bad' >/dev/null 2>&1; then exit 1; fi
output="$(cd "$TEST_ROOT/repo" && env -u TMUX "$script" start \
  --model gpt-6-astra --effort medium \
  --subagent-model 'openai/gpt-5.6-"luna"' --subagent-effort low 12 34)"
run="$(awk '/^run: / { print $2 }' <<< "$output")"
run_dir="$CODEX_ISSUES_STATE_ROOT/$run"
pane="$(awk -F '\t' '$1 == 12 {print $3}' "$run_dir/workers.tsv")"
wait_for test -f "$TEST_ROOT/ready-12"
wait_for test -f "$TEST_ROOT/ready-34"
python3 - "$TEST_ROOT/args-12.json" "$TEST_ROOT/args-34.json" <<'PY'
import json, sys, tomllib
for path in sys.argv[1:]:
    args = json.load(open(path))
    assert args[args.index('--model') + 1] == 'gpt-6-astra'
    configs = [tomllib.loads(args[i + 1]) for i, arg in enumerate(args) if arg == '-c']
    assert any(config.get('model_reasoning_effort') == 'medium' for config in configs)
    assert any(config.get('agents', {}).get('default_subagent_model') == 'openai/gpt-5.6-"luna"' for config in configs)
    assert any(config.get('agents', {}).get('default_subagent_reasoning_effort') == 'low' for config in configs)
PY
"$script" list | grep "$run" >/dev/null
"$script" status "$run" | grep -E '#12[[:space:]]+working' >/dev/null
"$script" show "$run" 12 | grep 'Codex chat ready' >/dev/null
[[ "$(tmux display-message -p -t "$pane" '#{window_name}')" == '#12 working' ]]
[[ "$(tmux show-options -wqv -t "$pane" remain-on-exit)" == on ]]

hook_event() {
  jq -n --arg event "$1" --arg cwd "$TEST_ROOT/worktrees/$run/issue-12" --arg thread "${2:-thread-12}" \
    --arg source "${3:-startup}" \
    '{cwd:$cwd,session_id:$thread,hook_event_name:$event,source:$source}' | "$script" hook >/dev/null
}
assert_state() {
  [[ "$(cat "$run_dir/prompts/issue-12.state")" == "$1" ]]
  [[ "$(tmux display-message -p -t "$pane" '#{window_name}')" == "#12 $1" ]]
}
hook_event Stop
assert_state waiting
"$script" mark "$run" 12 "done"
hook_event Stop
assert_state "done"
[[ "$(tmux show-options -wqv -t "$pane" window-status-style)" == fg=green ]]
"$script" mark "$run" 12 blocked
hook_event Stop
assert_state blocked
[[ "$(tmux show-options -wqv -t "$pane" window-status-current-style)" == fg=black,bg=yellow,bold ]]
hook_event UserPromptSubmit wrong-thread
assert_state blocked
# A second startup, clear, resume, or compaction cannot steal registration.
for source in startup clear resume compact; do
  hook_event SessionStart wrong-thread "$source"
  hook_event UserPromptSubmit wrong-thread
  assert_state blocked
  [[ "$(cat "$run_dir/prompts/issue-12.session")" == thread-12 ]]
done
# Native queue must preserve literal multiline text and must not claim consumption.
message=$'Please check $HOME and `uname` literally\nThen check "Windows".'
"$script" send "$run" 12 "$message" >/dev/null
python3 - "$TEST_ROOT/queue.json" "$message" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == ['queue', '--thread', 'thread-12', '--message', sys.argv[2]]
PY
assert_state blocked
hook_event UserPromptSubmit
assert_state working
hook_event Interrupt
assert_state waiting
hook_event SessionStart
assert_state waiting
# Rejected messages, unknown sessions, and recycled panes fail closed.
touch "$TEST_ROOT/reject-queue"
if "$script" send "$run" 12 nope >/dev/null 2>&1; then exit 1; fi
rm "$TEST_ROOT/reject-queue"
rm "$run_dir/prompts/issue-12.session"
if "$script" send "$run" 12 nope >/dev/null 2>&1; then exit 1; fi
hook_event SessionStart
[[ ! -e "$run_dir/prompts/issue-12.session" ]]
"$script" bind "$run" 12 replacement-thread >/dev/null
hook_event SessionStart
"$script" send "$run" 12 rebound >/dev/null
python3 - "$TEST_ROOT/queue.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == ['queue', '--thread', 'replacement-thread', '--message', 'rebound']
PY
if "$script" bind "$run" 12 '../bad' >/dev/null 2>&1; then exit 1; fi
"$script" bind "$run" 12 thread-12 >/dev/null
tmux set-option -w -t "$pane" @codex_issue unrelated
if "$script" send "$run" 12 nope >/dev/null 2>&1; then exit 1; fi
if "$script" bind "$run" 12 wrong-thread >/dev/null 2>&1; then exit 1; fi
if "$script" show "$run" 12 >/dev/null 2>&1; then exit 1; fi
if "$script" attach "$run" 12 >/dev/null 2>&1; then exit 1; fi
if "$script" attach "$run" >/dev/null 2>&1; then exit 1; fi
"$script" status "$run" | grep -E '#12[[:space:]]+waiting[[:space:]]+-' >/dev/null
"$script" mark "$run" 12 "done"
[[ "$(tmux display-message -p -t "$pane" '#{window_name}')" == '#12 waiting' ]]
tmux set-option -w -t "$pane" @codex_issue "$run_dir/12"
"$script" mark "$run" 12 "done"
if "$script" mark "$run" 12 invalid >/dev/null 2>&1; then exit 1; fi
if "$script" cleanup "$run" >/dev/null 2>&1; then exit 1; fi

# Successful exit retains the explicit outcome; crash retains a red, readable tab.
printf '0\n' > "$TEST_ROOT/exit-12"
printf '7\n' > "$TEST_ROOT/exit-34"
wait_for grep -qx error "$run_dir/prompts/issue-34.state"
pane_dead() { [[ "$(tmux display-message -p -t "$pane" '#{pane_dead}')" == 1 ]]; }
wait_for pane_dead
assert_state "done"
"$script" show "$run" 34 | grep 'Codex chat ready' >/dev/null
if "$script" send "$run" 12 nope >/dev/null 2>&1; then exit 1; fi
touch "$TEST_ROOT/worktrees/$run/issue-12/uncommitted.txt"
if "$script" cleanup "$run" >/dev/null 2>&1; then exit 1; fi
rm "$TEST_ROOT/worktrees/$run/issue-12/uncommitted.txt"
"$script" cleanup "$run" >/dev/null
[[ ! -e "$run_dir" && ! -e "$TEST_ROOT/worktrees/$run" ]]
git -C "$TEST_ROOT/repo" show-ref --verify --quiet "refs/heads/codex/issue-12-${run#repo-}"

# Inside-tmux startup keeps the containing session and its unrelated window.
tmux new-session -d -s container 'sleep 60'
output="$(cd "$TEST_ROOT/repo" && TMUX=fake "$script" start 56)"
run="$(awk '/^run: / {print $2}' <<< "$output")"
wait_for test -f "$TEST_ROOT/ready-56"
python3 - "$TEST_ROOT/args-56.json" <<'PY'
import json, sys, tomllib
args = json.load(open(sys.argv[1]))
assert '--model' not in args
configs = [tomllib.loads(args[i + 1]) for i, arg in enumerate(args) if arg == '-c']
assert all('model_reasoning_effort' not in config and 'agents' not in config for config in configs)
PY
printf '0\n' > "$TEST_ROOT/exit-56"
wait_for grep -qx closed "$CODEX_ISSUES_STATE_ROOT/$run/prompts/issue-56.state"
# Simulate a server restart reusing the pane ID for an unrelated live process.
pane="$(awk -F '\t' '$1 == 56 {print $3}' "$CODEX_ISSUES_STATE_ROOT/$run/workers.tsv")"
wait_for pane_dead
tmux set-option -w -t "$pane" @codex_issue unrelated
tmux respawn-pane -t "$pane" 'sleep 60'
"$script" status "$run" | grep -E '#56[[:space:]]+closed[[:space:]]+-' >/dev/null
"$script" cleanup "$run" >/dev/null
[[ "$(tmux display-message -p -t "$pane" '#{pane_dead}')" == 0 ]]
tmux kill-pane -t "$pane"
tmux has-session -t container
# Relative roots (including spaces) are resolved before changing into worktrees.
output="$(cd "$TEST_ROOT/repo" && env -u TMUX CODEX_ISSUES_STATE_ROOT='../relative state' \
  CODEX_ISSUES_WORKTREE_ROOT='../relative worktrees' "$script" start 78)"
run="$(awk '/^run: / {print $2}' <<< "$output")"
wait_for test -f "$TEST_ROOT/ready-78"
relative_run="$TEST_ROOT/relative state/$run"
[[ "$(cat "$relative_run/prompts/issue-78.session")" == thread-78 ]]
CODEX_ISSUES_STATE_ROOT="$TEST_ROOT/relative state" "$script" send "$run" 78 relative >/dev/null
printf '0\n' > "$TEST_ROOT/exit-78"
pane="$(awk -F '\t' '{print $3}' "$relative_run/workers.tsv")"
wait_for pane_dead
(cd "$TEST_ROOT" && CODEX_ISSUES_STATE_ROOT='relative state' "$script" cleanup "$run" >/dev/null)
[[ ! -e "$relative_run" && ! -e "$TEST_ROOT/relative worktrees/$run" ]]
if (cd "$TEST_ROOT/repo" && "$script" start --effort enormous 57) >/dev/null 2>&1; then exit 1; fi
if (cd "$TEST_ROOT/repo" && "$script" start --subagent-effort enormous 57) >/dev/null 2>&1; then exit 1; fi
if (cd "$TEST_ROOT/repo" && "$script" start --model) >/dev/null 2>&1; then exit 1; fi
if (cd "$TEST_ROOT/repo" && "$script" start --unknown 57) >/dev/null 2>&1; then exit 1; fi
printf 'codex-issues integration test passed\n'
