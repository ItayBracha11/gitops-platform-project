# Agentic CI: progress log

What we've built, why, and what comes next. Full spec: [agentic-ci.md](agentic-ci.md).

## ⏭ Next to be done: Agent A, step 2, the skill
- **What:** three files that tell the agent how to work:
  - `SKILL.md`: the step-by-step procedure.
  - `trace-guide.md`: where connections hide in this repo.
  - `risk-checklist.md`: what counts as low, medium or high.
- **Why:** the gather job (step 1) gives the agent evidence. The skill tells it what to do with that evidence: find what else breaks, and prove it.
- **Done when:** the three files exist, follow the design doc, and contain no answers to the eval cases. They're tested for real in step 3.

---

## Groundwork

### 1. Provider lock files ✅ Done
- **What:** `.terraform.lock.hcl` committed in all 9 roots. CI runs `init -lockfile=readonly`, and a workflow, run by hand, opens PRs that upgrade providers.
- **Why:** the plan that gets reviewed and the apply that follows use the same provider versions. Upgrades become reviewable PRs.
- **Proof:** PR #1. The bot opened it, the plan passed, the review was posted, and it was merged into `agentic-pipeline`.

### 2. Foundation (Phase 0) ✅ Done
- **What:** the design doc was added, and CLAUDE.md updated: agents may read AWS but never write (no kubectl/helm changes either).
- **What:** a local `readonly` AWS profile for my session. No S3 (state holds secrets), and no `ec2:Get*`.
- **Why:** I can investigate AWS without being able to change anything.

### 3. CI credentials ✅ Done
- **AWS:** role `tf-plan-reader`, read-only, usable only by the `tf-plan` environment, and it can't read prod state.
  - **Why:** the plan job needs to read dev; nothing else gets the role.
- **Claude:** federation set up and tested; it's trusted only for the `agent-review` environment.
  - For now the job uses your subscription token, because there's no API credit.
  - Guards: the agent can't read `/proc`, and output containing `sk-ant-` is blocked.
  - **Why:** no stored API key. One environment = one identity.
- **The v1 reviewer runs end to end:** plan → Claude review → PR comment.

---

## Agent A ("what else breaks?")

### 1. Gather job ✅ Done
- **What:** the first job of `tf-blast-radius.yml`. No AI.
  - It finds which roots a PR changed.
  - It plans the dev network and cluster roots.
  - It counts deletes.
  - It packages the evidence: `gather.json`, `pr.diff`, plan text files.
- **Why:** the agent gets evidence, never AWS credentials.
- **Safety:** plan files with full values are deleted right after use; only the masked text is kept.
- **Proof:** test PR #2 (closed, not merged). Dev was down, so nothing was planned, and the correct reason was recorded for each root.
- **Not proven yet:** the path with real plans. It needs dev up and is covered in step 6.

### 2. Skill ⏭ Next to be done
See the top of this file.

### 3. Local iteration ⬜ To do
- Run the agent on my machine against real gather outputs until the doc's example trace works.

### 4. Output schema ⬜ To do
- The JSON shape of the answer: findings, impacts, evidence, what wasn't traced.

### 5. Full workflow ⬜ To do
- gather → agent → publish, with publish checking every cited file exists. v1 is removed.

### 6. Evals ⬜ To do
- 7 test PRs, 3 runs each, in one batch with dev up, then dev destroyed.

### 7. Acceptance ⬜ To do
- Every eval gets the expected verdict. Then merging to `main` is your call.

---

## Branches
- `agentic-pipeline`: v1 reviewer, lock files, Claude access.
- `agentic-foundation`: Phase 0 + docs.
- `agent-a-blast-radius`: Agent A work. **Current branch.**
- Nothing merges to `main` until Agent A passes step 7. I ask before every merge.

## Decisions made
- One skill for all roots.
- Dev only; prod PRs get a diff-only review.
- One agent run per PR.
- v1 is replaced, not kept.
- The gather job diffs against the PR's own base, not `main`.

## Later
- Approval gate on the prod apply workflow.
- Tighten `tf-plan-reader` further, to only what a dev plan reads.
- Move off the subscription token once there's API credit.
- Agent runs longer than ~9 min need a refreshed token for federation.
- Decide on `[skip ci]` for the final merge to `main`, which otherwise triggers the dev and prod applies.
