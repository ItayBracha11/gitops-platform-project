# Agentic CI: progress log

Where we are and why. Spec: [agentic-ci.md](agentic-ci.md).

## Now
- **Step:** Phase 1, step 1. On PR #1 (lock files):
  - plan job ✅: role, OIDC and `-lockfile=readonly` all work in CI.
  - review job ❌: the `ANTHROPIC_API_KEY` secret is missing.
- **Next:** add the secret → re-run → merge PR #1 into `agentic-pipeline` → start the Agent A skill.

## Branches
- `agentic-pipeline`: v1 reviewer + lock files work.
- `agentic-foundation`: Phase 0 (cut from `agentic-pipeline`).
- `agent-a-blast-radius`: Phase 1, not created yet.
- Nothing merges to `main` until Agent A passes its acceptance criteria.

## Done

### Provider lock files (`agentic-pipeline`)
- **Committed `.terraform.lock.hcl` files** instead of gitignoring them.
  - Why: the reviewed plan and the applied plan use the same provider versions.
- **`-lockfile=readonly` on every `terraform init`** in CI.
  - Why: CI never silently changes provider versions.
- **New workflow `[Terraform] Update Lock Files`.**
  - Regenerates the lock files and opens a PR.
  - Why: provider upgrades become reviewable PRs, not surprises at apply time.
- **GitHub App `itay-tf-lock-bot` opens those PRs.**
  - Why: PRs opened with `GITHUB_TOKEN` don't trigger other workflows, so the plan review would never run.
- **Temporary `push` trigger on the lock workflow.**
  - Why: lets us test it before it's on `main`.
  - **Remove before merging to `main`.**

### Phase 0: foundation (`agentic-foundation`)
- **Design doc** `docs/agentic-ci.md` added; CLAUDE.md points agents to it.
- **CLAUDE.md = Appendix A**, plus "mutating kubectl **or helm**".
  - Why: agents may read AWS but never write; every claim cites evidence.
- **GitHub OIDC provider confirmed** in the AWS account.
  - Why: CI gets short-lived AWS credentials, with no stored keys.
- **Local `readonly` profile** (permission set `ReadOnlyInvestigator`).
  - Why: my local session can query AWS but can't change anything.
  - Explicit `Deny s3:*`: state files hold secrets.
  - No `ec2:Get*`: it includes calls that can expose secrets.
  - Set via `.claude/settings.local.json`, not by launching VS Code from the terminal (no admin rights on this Mac).

### Phase 1: Agent A (in progress)
- **`tf-plan-reader` role**: `ReadOnlyAccess`, trusted only by the `tf-plan` environment.
  - Why: the plan job needs to read state and resources; nothing else can assume the role.
- **`TF_PLAN_ROLE_ARN` set** on the `tf-plan` environment.
  - Why: the plan job was failing without it.
- **Required reviewer removed** from `tf-plan`.
  - Why: plans run automatically, as most teams do; approval belongs on apply.

## Decisions
- **One skill for all roots.** Root-specific knowledge goes in `risk-checklist.md`.
- **Dev only.** Prod PRs get a diff-only review marked "not planned".
- **One agent run per PR**, even when it touches 3+ roots, so coupling across roots isn't missed.
- **v1 reviewer is replaced, not kept alongside.** That avoids double cost and conflicting comments.
- **Gather job is built before local agent testing.**
  - Why: the `readonly` profile can't read state, so the plans come from CI artifacts.

## Later
- Add an approval gate on the **prod apply** workflow.
- Tighten `tf-plan-reader` beyond `ReadOnlyAccess`.
- Decide on `[skip ci]` for the final merge to `main`, which otherwise triggers the dev and prod applies.
