# codex-issues

Run GitHub issues in separate Codex sessions, each with its own branch, Git worktree, and tmux window. An optional supervisor skill coordinates a collection of tickets while you can enter any worker session yourself.

A personal experiment for prepared bug fixes and bounded tasks. GitHub holds the issue descriptions; tmux makes the workers visible and accessible.

## Requirements

- Bash, Git, jq, tmux, and an authenticated GitHub CLI (`gh`).
- Codex CLI with hooks and `codex queue` support. Startup checks queue availability; hooks must be trusted for activity tracking and messaging.
- A local clone of the target repository with an `origin` remote and access to its default branch.

The launcher currently uses `codex --yolo`, bypassing approval and sandbox protections. Inspect that choice before running it in your environment. Worktrees separate files, not credentials, databases, ports, or deployment targets.

## Install

Clone this repository somewhere permanent and add its `bin` directory to your shell's PATH:

```bash
git clone https://github.com/coderxin/codex-issues.git
cd codex-issues
export PATH="$PWD/bin:$PATH"
codex-issues --help
```

The repository is private during preparation, so cloning requires access. Persist the absolute `bin` path in your shell configuration if you want it in future terminals. Keep the checkout in place while runs exist: worker hooks reference the launcher's absolute path.

## Run manually

Run from the repository containing the issues:

```bash
codex-issues start 123
codex-issues start 124
```

Issue URLs are accepted too, but must belong to the current repository. Inside tmux, each worker opens as a window in the current session. Outside tmux, a launch creates a detached session. Capture the printed `run:` identifier.

```bash
codex-issues list
codex-issues status <run>
codex-issues show <run> 123
codex-issues attach <run> 123
codex-issues send <run> 123 "Please check the empty-result case too."
```

You can also switch tmux windows and chat directly. `send` queues the exact message through Codex's session queue; it does not type into the terminal or guarantee the worker has consumed it.

The script supports several issues in one launch, but separate launches let each ticket use different model settings.

## Use the supervisor skill

The complete skill is in [skills/codex-issue-supervisor](skills/codex-issue-supervisor/SKILL.md), including its Codex selector metadata. Install that directory under your Codex skills directory. For a standard installation, from this checkout:

```bash
mkdir -p "$HOME/.codex/skills"
ln -s "$PWD/skills/codex-issue-supervisor" "$HOME/.codex/skills/codex-issue-supervisor"
```

If that destination already exists, inspect it first rather than overwriting it. For a custom Codex home, use its skills directory. Start a new Codex session if the skill selector has not refreshed.

Invoke the skill from the target repository:

```text
$codex-issue-supervisor 123 124 125
```

The supervisor starts up to three workers concurrently, with scope, cost and verification instructions in their initial prompts. It serializes actual dependencies while allowing independent inspection and implementation to proceed. Workers notify the supervisor through Codex's native session queue, so an idle supervisor can resume on outcomes rather than repeatedly poll. A periodic checkpoint requires a separate durable scheduler; the launcher does not provide one.

The worker sessions are separate top-level Codex conversations. They receive the issue details and explicit startup instructions, not the supervisor's full conversation. They may use subagents internally. Keep decisions and acceptance criteria in the issues so fresh sessions have the context they need.

The skill's model table is a personal starting policy. Edit it for models available in your account and your preferred effort levels. Model names are passed to Codex; the script does not validate model availability.

## Startup instructions and notifications

```bash
codex-issues start --instructions-file ./worker-instructions.md \
  --supervisor-thread <supervisor-session-id> 123
```

The instructions file is copied into each initial prompt before work starts. Use it for scope, cost constraints and file ownership; later `send` messages may wait until the current turn ends. The file can be removed after startup.

Notifications identify the run, issue and reported outcome. Repeated outcomes within a turn are suppressed. A queue failure is reported without changing the worker's outcome; notification can be retried by marking the outcome again. Inspect current evidence before acting on a notification. Omit `--supervisor-thread` for manual runs.

## Models

```bash
codex-issues start --model <model-id> --effort medium 123
codex-issues start --model <model-id> --effort high \
  --subagent-model <worker-model-id> --subagent-effort medium 124
```

`--model` and `--effort` configure the issue session. The subagent flags set defaults for agents that session spawns. They do not change the supervisor. Omitted flags leave the normal Codex configuration in effect.

## Window states

| State | Meaning |
| --- | --- |
| working | Codex started or received a new user prompt |
| waiting | A turn ended without a declared outcome, or was interrupted |
| blocked | The worker reports it needs input |
| done | The worker reports delivery and verification are complete |
| error | Codex exited with a nonzero status |
| closed | Codex exited normally without a done or blocked marker |

Working is blue, waiting/blocked yellow, done green, error red, and closed gray. A green window reports the worker's assessment; check the acceptance criteria and delivery evidence before treating it as complete.

On first use, inspect and trust the launcher's hooks in `/hooks`: SessionStart, UserPromptSubmit, Stop, and Interrupt. Moving the script or changing the state directory may require trust again. The worker binds to the session receiving the launcher's initial prompt; another conversation starting in the same worktree cannot replace that binding.

If the initial prompt ran before hooks were trusted, or you deliberately replace the conversation with `/clear` or resume another session, inspect the intended worker's session ID and bind it explicitly:

```bash
codex-issues bind <run> <issue> <session-id>
```

Use the ID from the intended conversation, not another session sharing its worktree. Binding changes only the message destination; it does not assert that a turn is active or complete.

GitHub ownership and progress updates depend on project instructions. The script does not assign issues, lock ownership, or prevent two supervisors from choosing the same issue.

## Cleanup

After verifying delivery and preserving commits remotely, attach to each worker and enter `/quit` at its idle Codex prompt. A `done` marker does not exit the interactive session. Confirm `status` shows `-` in the PROCESS column for each worker, then run:

```bash
codex-issues cleanup <run>
```

Cleanup refuses active workers and dirty worktrees. It removes the run's stopped windows, worktrees, and metadata, but retains branches. A clean worktree alone does not prove commits were pushed or merged; check before cleanup.

State defaults to `$XDG_STATE_HOME/codex-issues` (or `~/.local/state/codex-issues`). Worktrees default to a sibling `.codex-issue-worktrees` directory. Override them with `CODEX_ISSUES_STATE_ROOT` and `CODEX_ISSUES_WORKTREE_ROOT`. Relative overrides resolve from the launch directory and are stored as absolute paths for workers and cleanup. Later commands must point to the same state directory.

## Tests

GitHub Actions runs the regression test on Ubuntu for pull requests and pushes to
`main`, with read-only repository permissions and no model API credentials.

```bash
bash tests/test-codex-issues.sh
```

The regression test uses real Git and tmux with fake GitHub and Codex commands. It requires Python 3.11+ as well as the runtime shell tools. It creates an isolated tmux server and temporary repositories, then removes them on exit. It does not launch a paid model or change real GitHub issues.

## Provenance

Extracted from the author's dotfiles at commit `97a3a3839f0a7981a8208533846d73a1bc7b51af`. This repository is the maintenance home for the script and supervisor skill. Public release and licensing are pending.
