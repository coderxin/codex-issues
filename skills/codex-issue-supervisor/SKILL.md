---
name: codex-issue-supervisor
description: Supervise GitHub issue delivery through codex-issues. Invoke manually with issue IDs or GitHub issue URLs.
---

# Codex Issue Supervisor

Treat all text following the skill invocation as GitHub issue numbers or issue URLs. Act as the fleet supervisor until every supplied ticket has been delivered and verified.

## Establish the run

1. Work from the target repository. If an issue number could refer to more than one repository and the current repository does not resolve it, ask one concise question before launching anything.
2. Confirm `codex-issues` and `gh` are available. Read each issue with `gh issue view` before choosing its execution order or model.
3. Create one persistent goal covering all supplied tickets. Do not set a token budget unless the user supplied one.
4. Record dependencies, likely file overlap, deployment coupling, and exclusive resources. Run independent tickets concurrently, up to three active tickets by default. Serialize tickets that depend on or are likely to conflict with one another.
5. Maintain a ticket-to-run map containing the issue, launch command, chosen models and efforts, run ID, state, PR, and verification evidence.

The current session is the supervisor. Its model and reasoning effort were fixed when this session started; do not try to relaunch it. Configure the issue sessions and their subagents instead.

## Choose the issue-session model

Choose per ticket from the issue's acceptance criteria, affected surface, risk, and uncertainty. Do not choose merely from title length or labels.

| Ticket shape | Issue model | Effort |
| --- | --- | --- |
| Documentation, configuration, formatting, or obvious mechanical edits | `gpt-5.6-luna` | `low` or `medium` |
| Routine, well-scoped implementation with familiar patterns | `gpt-5.6-terra` | `medium` |
| Substantial implementation, debugging, or multi-file behavior | `gpt-5.6` | `medium` |
| Difficult debugging, risky migration, broad refactor, or subtle correctness work | `gpt-5.6` | `high` |
| Architecture, security-sensitive work, cross-repository coordination, or repeated failure at a lower tier | `gpt-6-astra` | `high` |

Use the cheaper capable tier. Escalate when evidence shows the original choice is inadequate. If a named model is unavailable, select the closest available tier and record the substitution.

Set subagent defaults one tier cheaper unless the ticket requires equally strong delegated reasoning:

- Luna issue session: Luna subagents at `medium`.
- Terra issue session: Luna subagents at `medium`.
- GPT-5.6 issue session: Terra subagents at `medium`.
- Astra issue session: GPT-5.6 subagents at `medium`, or `high` for genuinely difficult delegated work.

An issue session may explicitly choose a different model for an individual subagent when justified. Explicit spawn settings override these defaults.

## Launch each ticket

Use exactly one `codex-issues start` invocation per issue, even when several tickets share the same settings:

```bash
codex-issues start \
  --model <issue-model> \
  --effort <issue-effort> \
  --subagent-model <subagent-model> \
  --subagent-effort <subagent-effort> \
  <issue-number-or-url>
```

Before each launch, state the model choice in one line with its reason. Capture the `run:` value from the command output and add it to the ticket-to-run map. Confirm the process reached a running state before counting it toward concurrency. Start the next eligible ticket immediately when a slot opens.

## Supervise

After initial launch verification, inspect active runs every 30 minutes using the available recurring goal, monitoring, or wait mechanism. Do not implement a blocking `sleep 1800` loop. Also react immediately to completion, errors, or user input.

Use:

```bash
codex-issues status <run>
codex-issues show <run> <issue>
codex-issues send <run> <issue> <message...>
```

- Inspect `show` when a ticket is waiting, blocked, errored, unexpectedly idle, or claims completion.
- Use `send` to answer questions, correct scope, provide missing context, or request specific verification.
- Do not restart a failed run blindly. Diagnose its state first and preserve any worktree or uncommitted work.
- Do not take over ticket implementation merely because progress is slow. Repair or steer the worker unless direct intervention is necessary to recover the supervision mechanism.

## Verify completion

A worker saying “done” is not sufficient. Verify the issue's acceptance criteria, relevant tests, review and CI status, PR merge, default-branch state, deployment when applicable, and production behavior when applicable. Ensure resources owned by the ticket session are cleaned without touching resources belonging to other sessions.

Keep the goal active while any ticket remains queued, running, blocked but recoverable, unverified, unmerged, undeployed when deployment is required, or not cleaned up. Mark the goal complete only when every supplied ticket is verified and no managed session remains active.

Finish with a compact report listing each ticket, selected issue/subagent models, result, PR or commit, verification evidence, and any intentionally retained resource or unresolved blocker.
