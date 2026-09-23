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

## Choose models critically

Treat model recommendations in issues, plans, and this skill as starting hypotheses. Honor the user's explicit model choices and cost constraints across all tickets and delegated work.

Use these defaults unless the user specifies otherwise:

| Responsibility | Model | Effort |
| --- | --- | --- |
| Mechanical edits and bounded supporting tasks | `gpt-6-luna` | `low` or `medium` |
| Implementation | `gpt-6-sol` | `medium` |
| Subagents | `gpt-6-luna` | `medium` |

Confirm the selected model IDs are available before launching. If a default is unavailable, choose an available alternative within the user's cost constraints and record the substitution. Availability alone does not establish relative cost; verify cost information before claiming an alternative is cheaper. If no suitable alternative is established, ask rather than silently upgrading.

Before choosing above a default model or effort, record:

1. The concrete reasoning difficulty, supported by the issue or inspected code.
2. Why the default is likely inadequate.
3. The smallest task that needs stronger reasoning.

Security labels, private data, migrations, file count, UI work, and cross-repository coordination do not independently justify escalation. Determine whether the work introduces difficult decisions or follows established patterns. Preserve required review, testing, and safety checks regardless of model choice.

Escalate on evidence. Distinguish reasoning failures from missing context, unclear requirements, environment failures, and failing tools; correct those causes first. Consider stronger effort on the current model or a bounded stronger-model task before upgrading an entire issue. Reassess each new ticket independently.

`gpt-6-astra` is an exception: identify a concrete unresolved reasoning problem, explain why Sol is insufficient, and obtain explicit user authorization unless already authorized for that scope. Routine delivery authorization does not authorize Astra.

Apply these rules to individual subagent overrides as well as launch defaults. Explicit spawn settings must satisfy the same evidence and authorization requirements; they are not an escape hatch. Pass the user's cost constraints and this escalation policy to each worker through `codex-issues send` once its session is bound, before directing delegated work. Record that handoff in the ticket-to-run map.

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

Before each launch, state `#ISSUE — MODEL/EFFORT; subagents MODEL/EFFORT; evidence: actual difficulty; escalation: none or specific justification`. Record any required authorization in the ticket-to-run map. Capture the `run:` value from the command output and add it to the ticket-to-run map. Confirm the process reached a running state before counting it toward concurrency. Start the next eligible ticket immediately when a slot opens.

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

## Exit workers and clean up

After verifying delivery and confirming commits are preserved remotely:

1. Inspect `status` and `show` for each worker. `done` is an outcome marker; its interactive Codex process may still be running.
2. For each live worker, hand off to the user with the exact `codex-issues attach <run> <issue>` command and ask them to enter `/quit` at the idle Codex prompt. Keep the run map and verification evidence while awaiting their return. The launcher has no unattended shutdown command; `send` queues a model message and cannot execute `/quit` as a terminal command. Preserve the worktree and report cleanup as pending until exit is confirmed.
3. Recheck `codex-issues status <run>`. When every worker's PROCESS column is `-`, run `codex-issues cleanup <run>`. If cleanup refuses, inspect the reported active process or dirty worktree and preserve it until resolved.
4. Confirm the run is absent from `codex-issues list` and its recorded worktree paths no longer exist. Retained branches are intentional.

Keep the goal active while any ticket remains queued, running, blocked but recoverable, unverified, unmerged, undeployed when deployment is required, or not cleaned up. Mark the goal complete only when every supplied ticket is verified and no managed session remains active.

Finish with a compact report listing each ticket, selected issue/subagent models, result, PR or commit, verification evidence, and any intentionally retained resource or unresolved blocker.
