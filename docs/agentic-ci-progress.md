# Agentic CI: progress log

Where we are and why. Spec: [agentic-ci.md](agentic-ci.md).

## Now
- **Step:** Phase 1, step 1. Claude access via federation (no API key):
  - test ✅: the `agent-review` job got a Claude token.
  - rule needs tightening before the PR review can use it (see below).
- **Next:** tighten the rule → re-test → wire federation into the review job → PR #1 green → merge into `agentic-pipeline` → start the Agent A skill.

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
- **Claude access via Workload Identity Federation**, not an API key.
  - Why: no stored secret to leak or rotate, same idea as the AWS OIDC role.
  - Claude Console created an issuer (GitHub), service account `svac_017Q…`, rule `fdrl_013K…`, in workspace `wrkspc_019n…`.
  - Only jobs in the GitHub environment `agent-review` should get a token. Each job gets one identity: `tf-plan` = AWS, `agent-review` = Claude.
  - Temporary test workflow `anthropic-wif-test.yml` passed. **Delete it once the rule is final.**

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
