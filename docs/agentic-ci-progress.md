# Agentic CI: progress log

Where we are and why. Spec: [agentic-ci.md](agentic-ci.md).

## Now
- **Step:** Phase 1, step 1 done. The v1 pipeline works end to end: plan → review → PR comment.
- **Next:** create branch `agent-a-blast-radius` → build the gather job (plans every changed root) → write the Agent A skill.

## Branches
- `agentic-pipeline`: v1 reviewer, lock files, Claude access.
- `agentic-foundation`: Phase 0 + docs (includes everything from `agentic-pipeline`).
- `agent-a-blast-radius`: Phase 1, not created yet.
- Nothing merges to `main` until Agent A passes its acceptance criteria.

## Done

### Provider lock files (`agentic-pipeline`)
- **Committed `.terraform.lock.hcl` files** instead of gitignoring them.
  - Why: the reviewed plan and the applied plan use the same provider versions.
- **`-lockfile=readonly` on every `terraform init`** in CI.
  - Why: CI never silently changes provider versions.
- **New workflow `[Terraform] Update Lock Files`** (run it by hand from the Actions tab).
  - Regenerates the lock files and opens a PR.
  - Why: provider upgrades become reviewable PRs, not surprises at apply time.
- **GitHub App `itay-tf-lock-bot` opens those PRs.**
  - Why: PRs opened with `GITHUB_TOKEN` don't trigger other workflows, so the plan review would never run.
- **Proven on PR #1** (9 lock files):
  - opened by the app, plan passed with `-lockfile=readonly`, review posted;
  - merged into `agentic-pipeline`;
  - every root also passes the readonly init on the Mac.
  - The temporary test trigger is removed.

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
- **Claude access via Workload Identity Federation** (Claude Console: issuer, service account, rule).
  - Why: no stored API key, same idea as the AWS role.
  - The rule trusts only the GitHub environment `agent-review`. Tested both ways: inside it gets a token, outside it is refused.
  - IDs are variables on `agent-review`. One environment = one identity: `tf-plan` = AWS, `agent-review` = Claude.
- **Subscription token for now** (`CLAUDE_CODE_OAUTH_TOKEN`, secret on `agent-review`).
  - Why: federation works, but the account has no API credit.
  - Known gap: a long-lived secret. Guards: the agent can't read `/proc`, and the job fails if output contains `sk-ant-`.
  - Switch back: add API credit → delete the secret.
- **Failure output:** when `claude` fails, the step prints its output. That's how the credit problem was found.

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
- Move off the subscription token once there's API credit.
- Agent runs longer than ~9 min need a refreshed GitHub token for federation (matters for Agent A's 25 turns).
