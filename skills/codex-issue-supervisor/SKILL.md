---
name: codex-issue-supervisor
description: Supervise GitHub issue delivery through codex-issues. Invoke manually with issue IDs or GitHub issue URLs.
---

# Codex Issue Supervisor

Treat all text following the skill invocation as GitHub issue numbers or issue URLs. Act as the fleet supervisor until every supplied ticket has been delivered and verified.

## Establish the run

1. Work from the target repository. If an issue number could refer to more than one repository and the current repository does not resolve it, ask one concise question before launching anything.
2. Confirm `codex-issues` and `gh` are available. Read each issue with `gh issue view` before choosing its execution order or model.
3. If the client supports persistent goals, create one covering the supplied tickets. Otherwise retain the ticket-to-run map as the resumable record. Do not set a token budget unless the user supplied one.
4. Run independent work concurrently, up to three active tickets. File overlap calls for explicit ownership and final integration, not postponing an entire ticket. Start inspection and non-conflicting implementation immediately; serialize only edits or releases that actually depend on another ticket.
5. Keep one ticket-to-run map with issue, launch command, models, run/thread IDs, state, PR, current check/deployment handles, and evidence. Reuse it instead of adding parallel progress records.

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

Apply these rules to individual subagent overrides as well as launch defaults. Explicit spawn settings must satisfy the same evidence and authorization requirements; they are not an escape hatch. Include the user's cost constraints and this escalation policy in the initial worker instructions. `send` queues a later turn; it does not establish that a running worker has read the message.

## Launch each ticket

Prepare one short instructions file before launch. Include the user's scope and cost constraints, model escalation policy, overlapping-file ownership, and these execution rules:

- Use the smallest complete implementation and the repository's authoritative check selection. Inspect selection before launching checks. Broad regression needs a concrete changed-behavior reason or an automatic requirement; a sensitive label alone is insufficient.
- Reuse passing tests and review while relevant inputs are unchanged. Fix acceptance and safety blockers; leave optional polish out.
- Start each external command once and retain its handle. A queued job or watcher timeout is a waiting state, not a test failure or a request to restart work.
- Before marking blocked, inspect the current PR head and current run. A superseded failure does not block a passing current run. Preserve required gates and other sessions' jobs.
- Report milestones, decisions, failures and completion; omit unchanged heartbeat narration.

Use exactly one `codex-issues start` per issue. Pass the instructions and the current supervisor session ID at startup:

```bash
codex-issues start \
  --model <issue-model> --effort <issue-effort> \
  --subagent-model <subagent-model> --subagent-effort <subagent-effort> \
  --instructions-file <path> --supervisor-thread <current-session-id> \
  <issue-number-or-url>
```

Preserve the user’s configured approval and sandbox policy. Never add `--yolo` unless the user explicitly authorizes unrestricted workers for this run. If a worker cannot update launcher state under its permissions, inspect the outcome and mark it from the supervisor instead of broadening access.

Confirm these options with the installed launcher's help. A launcher without startup instructions or notifications needs a capability correction before supervised work begins; do not substitute a late queued policy message. Use the actual session ID, never a guessed ID. Record the instructions file as owned and remove it once all launches have copied it.

Before launch, state `#ISSUE — MODEL/EFFORT; subagents MODEL/EFFORT; evidence: actual difficulty; escalation: none or specific justification`. Capture the `run:` value, confirm the worker is running, and record its session ID. Start the next eligible ticket immediately.

## Supervise on events

The launcher queues a notification to the supervisor when a worker reports done, blocked, waiting, or exits. Verify notification support during launch. After dispatch, return control so queued notifications can resume an idle supervisor. An active goal records unfinished work; it does not require a model to remain in a wait loop.

Use `codex-issues status`, `show`, and `send` for the specific run and issue named in a notification. Treat notifications as prompts to inspect current state, not proof of completion. React to user input immediately. Use a 30-minute checkpoint only through an available durable scheduler; never approximate it with repeated one-minute model/tool waits. If automatic wakeup is unavailable, report that limitation and preserve a resumable handoff rather than claim unattended supervision.

- Initial constraints belong in the launch prompt. For later steering, `send` only confirms enqueueing. Check that the worker consumed a correction before relying on it. For an urgent correction, use a supported interrupt-and-steer mechanism after preserving live command handles; do not cancel deployments or tests blindly.
- One bounded external watcher owns an unresolved CI/deployment wait. Prefer its completion notification to both supervisor and worker polling the same job. If a worker hands off a pending run, transfer that watcher handle rather than start duplicate watchers.
- On a timeout, inspect the recorded run once. Distinguish real failures, an occupied required runner, and superseded work. Preserve healthy queued work. Cancel only verified owned superseded runs with safe teardown; never cancel another session's work or bypass required checks.
- Keep the issue's scope fixed once acceptance is met. Correct an unnecessary manual full-suite override using the authoritative selector; retain automatically required checks. Record unrelated reproduced baseline failures separately without adopting their repair.
- Integrate current main before final verification and preserve valid evidence. When several approved tickets are ready together, merge under repository rules and use one canonical deployment covering them where supported. Do not hold a ready release for an unfinished ticket.
- Steer the worker rather than take over because it is slow. Use direct intervention only to recover the supervision mechanism or resolve a concrete delivery blocker.

## Verify completion

Verify the issue's acceptance criteria against retained test/review evidence, required current-revision CI, merged default-branch state, and the canonical deployment result when applicable. A structured deployment pass supplies its production checks; rerun only missing or invalid evidence. Verify owned cleanup, exit completed worker sessions, and clean their launcher runs while preserving other sessions' resources.

## Exit workers and clean up

After verifying delivery and confirming commits are preserved remotely, inspect each worker's state. A `done` marker does not exit the interactive session. The launcher has no unattended shutdown command: `send` queues a model message and cannot execute `/quit` as a terminal command.

Ask the user to enter `/quit` at each idle worker prompt, supplying the exact `codex-issues attach <run> <issue>` command. Preserve the run map and worktree while exit is pending. When `status` shows `-` in the PROCESS column for every worker, run `codex-issues cleanup <run>`. If cleanup refuses, inspect the active process or dirty worktree and preserve it until resolved. Confirm the run and recorded worktree paths are gone; retained branches are intentional.

Keep the goal active, when supported, while any ticket remains queued, running, blocked but recoverable, unverified, unmerged, undeployed when deployment is required, or not cleaned up. Mark the goal complete only when every supplied ticket is verified and no managed session remains active.

Finish with a compact report listing each ticket, selected issue/subagent models, result, PR or commit, verification evidence, and any intentionally retained resource or unresolved blocker.
