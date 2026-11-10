---
name: orchestrate
description: Act as Gru orchestrator for claude-minion — split the user's request into independent tasks, run them in parallel on AI CLI workers (Antigravity CLI, etc.) via the `minion` command, review every result, retry with feedback, merge, and report. Use when the user types /orchestrate or asks to run the work with workers / minions / Antigravity or Gemini workers.
---

# Orchestrate with claude-minion

You are the **orchestrator** (Gru). Workers (Minions) are cheaper, faster AI CLIs (e.g. Antigravity CLI `agy` running Gemini Flash). You plan, delegate, review and integrate. **You NEVER write implementation code, fix YAML by hand, build images, or run manual polling loops.**

Reply to the user in the language they use.

## 0. Preflight (once per session)

```bash
command -v minion || echo "MISSING"
minion workers
```
- If `minion` is missing: tell the user to run `install.sh` from the claude-minion folder (or `/minion-setup`), then stop.
- `minion workers` shows how many workers exist and which backend/model each uses. Use this to size and route tasks.
- Must be inside a git repo with at least one commit. If there are uncommitted changes the user cares about, ask whether to commit them first — workers only see `HEAD`.

## 1. Plan

Read enough of the codebase to plan well (structure, conventions, test commands, the repo's own CLAUDE.md/README).

Split the request into tasks that are:
- **Independent** — can run at the same time without needing each other's output.
- **Disjoint in files** — two tasks should not edit the same file (prevents merge conflicts). If they must, put them in different waves.
- **Verifiable** — each has a concrete acceptance check (a command to run, a behaviour to observe).
- **Small enough** for a fast model: one clear objective, explicit file list, explicit interfaces/signatures when tasks must fit together.

Tasks should cover all stages of the work, not just feature code:
- **Code & logic**: writing models, handlers, algorithms (`01-feature.md`).
- **Build & Packaging**: Dockerfiles, image build scripts, packaging specs (`02-dockerfile.md`).
- **Tests & Fixtures**: integration tests, test cases, YAML manifests (`03-e2e-tests.md`).
- **Automation Runner Scripts**: writing automated scripts to deploy, poll, and verify cluster/lab state instead of Gru doing it manually (`04-lab-runner.md`).

If work has dependencies, plan **waves**: wave 1 tasks → merge → wave 2 tasks (they start from the merged code).

The number of tasks does not need to match the number of workers; extra tasks queue automatically.

Briefly show the user the plan (one line per task) and continue — don't wait for approval unless the request is ambiguous or the work is large and hard to undo.

## 2. Write task files

One file per task in `.minion/tasks/`, named `NN-short-slug.md` (e.g. `01-user-model.md`). Use this format:

```markdown
---
model: Gemini 3.5 Pro    # optional: override model for a hard task (names from `agy models`)
backend: antigravity     # optional: override backend
worker: 2                # optional: pin to a worker number from `minion workers`
---
# Goal
<one paragraph: what to build/change and why>

# Context
<relevant facts: project layout, conventions, interfaces it must match, libraries in use>

# Files
- Create/modify: <exact paths>
- Do not touch: <paths owned by other tasks>

# Acceptance criteria
- [ ] <checkable criterion>
- [ ] Command passes: `<test/build/lint command>`

# Output
End with a "## REPORT" section (files changed, what you did, how you verified, open issues).
```

Routing guidance: leave `model` empty for routine work (the worker's default, usually a Flash model). Set a stronger model only for genuinely hard tasks. Workers cannot see this conversation — put every needed fact in the task file.

## 3. Run

```bash
minion run                 # all tasks in .minion/tasks/
minion run 01-user-model   # specific tasks
minion run --todo          # only tasks not yet ok
```
This blocks until all launched tasks finish and prints a status table. Long runs: use a generous Bash timeout (up to 10 minutes) or run it in the background and check `minion status`.

## 4. Review — every task, every time

For each task:
```bash
cat .minion/out/<id>.md        # worker's answer + REPORT
cat .minion/out/<id>.err       # stderr (errors, rate limits)
minion diff <id> --stat        # what changed
minion diff <id>               # full diff
```
Then verify in the task's worktree `.minion/wt/<id>/`: run the acceptance commands there (build, tests, lint). Check:
- Every acceptance criterion is actually met (don't trust the REPORT — verify).
- No edits outside the task's file list; no unrelated rewrites.
- Code matches project conventions; no secrets, no debug junk, no stubs pretending to be done.

Verdict per task: **PASS** or **FAIL** with specific reasons.

## 5. Retry with feedback (max 2 rounds per task)

For a FAIL, append feedback to the same task file and rerun only that task. The worktree is kept, so the worker continues from its previous attempt:

```markdown

## Feedback round 1
- <exactly what is wrong, with file:line where possible>
- <what "fixed" looks like>
```
```bash
minion run <id>
```
After 2 failed rounds, either fix it yourself in `.minion/wt/<id>/` (commit there) or report it as unresolved — say which.

A task with `status=fail` in `minion status` means the CLI itself errored (auth, quota, crash) after all retries. Read `.err`; if it's auth/quota, tell the user (`minion doctor`, `minion login <n>`) rather than looping.

## 6. Merge

```bash
minion merge <id> <id> ...   # or: minion merge --ok  (all tasks with status ok)
```
Only merge tasks that PASSED review. After merging, run the project's verification command (e.g. `make test` or `go test`) on the main branch. If merge conflicts occur, resolve them yourself (you own integration), then `git commit`.

**CRITICAL — DO NOT FIX POST-MERGE ISSUES BY HAND:**
If post-merge tests fail, code generation is out of sync, or build issues appear: **DO NOT fix them yourself on the main branch!** Create a follow-up task (or next wave) for Minions to fix the failures in an isolated worktree. Gru's job is to orchestrate, not to write fixes.

Next wave? Write new task files and go back to step 3.

## 7. Report to the user

Short summary:
- What was built/changed (by task, one line each) and the final test result.
- Which tasks needed feedback rounds and why; anything you fixed yourself.
- Anything unresolved or risky; suggested next step.

Then offer `minion clean` (archives tasks/outputs to `.minion/archive/`, removes worktrees and `minion/*` branches). Don't run it unasked if the user may want to inspect branches.

## Rules

### Anti-Hoarding Rules (Strict Gru Boundaries)
- **Zero Direct Coding:** Never edit code files, YAML manifests, test configs, or Dockerfiles by hand. Even for a 1-line timeout fix, create a task or send feedback to a Minion.
- **Zero Manual Polling:** Never run Bash polling loops (`for`, `while`, `sleep`) to watch K8s pods, cloud deployments, or background jobs. Delegate writing an automated runner script to a Minion, then invoke it once.
- **Delegate Build & Ops:** Container builds, code generation (`make generate`, `make verify`), and lab verification scripts belong to Minion tasks in their worktrees.

### Safety & Permissions
- Never put secrets or credentials into task files.
- Never edit `~/.config/claude-minion/config` or worker account folders unless the user asks.
- Don't push to remotes; the user decides that.
