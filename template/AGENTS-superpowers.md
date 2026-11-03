# Superpowers in a meta-repo workspace

<!-- Keep this section only if the agent uses the superpowers plugin (obra/superpowers).
     Append it below the "Meta-repo workspace" instructions in your CLAUDE.md or AGENTS.md, then delete this file.
     Without superpowers, delete the file. -->

The superpowers skills assume one repository and one session. This workspace is several repositories in a worktree
set, planned in one session and executed in another. Where a skill's own instructions differ from the rules below, the
rules below win; superpowers states that project instructions take precedence over its skills.

## Plans

- Save the plan written by `writing-plans` (or by `brainstorming` when it ends in a plan) as `worktrees/<branch>/PLAN.md`,
  next to the worktrees it describes, not under `docs/superpowers/plans/` in any repository. The file is untracked by the
  meta-repo and survives `just wt-rm`, which reports it as kept.
- Create the worktree set before writing the plan, so the plan can name real paths:
  `just wt-new <branch> <repo>...` from the meta-repo root, with the repositories the change touches. Ask the user for the
  branch name and the repositories if they were not given.
- Every task in the plan names the repository it changes as its worktree path, e.g. `worktrees/<branch>/repo-a/`.
  Order tasks across repositories as "Cross-repo changes" above prescribes (provider before consumers).
- The plan ends with the way the set is finished, chosen from "Finishing a task" above: pull requests per repository,
  or `just wt-merge` into a feature branch.

## Handoff to execution

- A plan is executed in a new session started in the worktree set: `cd worktrees/<branch> && claude`. When the plan is
  complete, tell the user that command and stop. Do not start executing in the planning session unless the user asks
  for inline execution there.
- `executing-plans` and `subagent-driven-development` read `worktrees/<branch>/PLAN.md` (`./PLAN.md` from the session's
  working directory). Keep their workspace and ledger under `worktrees/<branch>/.superpowers/`, not at the git toplevel,
  which is the meta-repo root here.

## Worktrees

- Isolation is provided by the worktree set, so `using-git-worktrees` creates nothing: inside `worktrees/<branch>/` you
  are already isolated. Never create `.worktrees/` or `worktrees/` inside a repository, and never run `git worktree add`
  yourself; `just wt-new` is the only way worktrees are created here.
- A session started outside `worktrees/` that needs isolation asks the user for the branch and repositories and runs
  `just wt-new`, then continues in `worktrees/<branch>/` (or tells the user to start a session there).

## Subagents

- A brief for an implementer, reviewer, or any other subagent names the worktree directory it works in,
  e.g. `worktrees/<branch>/repo-a/`, and says that it edits files only there, never under `repos/`.
- Subagents run a repository's build, tests, and lint from that worktree's root, following the repository's own
  instructions, and never create worktrees of their own.
- Reviews read the change with `just wt-diff-pr <repo>` (committed) or `just wt-diff <repo>` (uncommitted included) from
  inside `worktrees/<branch>/`, one repository at a time.

## Finishing

- `finishing-a-development-branch` offers to merge, open a pull request, or keep the branch. Do not take any of those
  through the skill: finish as "Finishing a task" above describes, which the plan already chose, and only when the user
  asks. Cleanup is `just wt-rm <branch>` from the meta-repo root, not a `git worktree remove` by the skill.
- `verification-before-completion` applies per repository: run each repository's checks from its own worktree root and
  report them per repository.
