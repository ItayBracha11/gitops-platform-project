# Agentic CI: progress log

Where we are and why. Spec: [agentic-ci.md](agentic-ci.md).

## Now
- **Step:** Agent A, step 1 (gather job) built and tested on the torn-down path.
- **Next:** step 2, the skill (`SKILL.md`, `trace-guide.md`, `risk-checklist.md`).

## Agent A steps
1. ✅ Gather job (no LLM): find the changed roots, plan the dev network/cluster roots, package the evidence.
2. Skill: how to trace, where coupling lives, risk rules.
3. Local iteration: `claude -p` on real gather outputs.
4. Schema: adds impacts, evidence, untraced, not-planned.
5. Workflow: gather → agent → publish (evidence check). v1 removed.
6. Evals: 7 PRs × 3 runs, in one batch with dev up.
7. Acceptance; merge to `main` is the user's call.

## Branches
- `agentic-pipeline`: v1 reviewer, lock files, Claude access.
- `agentic-foundation`: Phase 0 + docs (includes everything from `agentic-pipeline`).
- `agent-a-blast-radius`: Agent A work (cut from `agentic-foundation`).
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

### Agent A, step 1: gather job (`agent-a-blast-radius`)
- **What:** the first job of `tf-blast-radius.yml`. No LLM, and the only job with AWS access (`tf-plan`).
  - Why: the agent should get evidence, not credentials.
- **Diffs against the PR's own base**, not `main`.
  - Why: our PRs target work branches. Diffing against `main` would pull in unrelated changes.
- **`changed-roots.sh` maps files → roots.** A module change maps to every root whose `source =` points at it.
  - Why: read from the code, so it can't go stale. Tested locally with 7 cases.
- **Checks whether dev is up** (network state has outputs?). If it's down, nothing is planned and the reason is recorded.
  - A state read error now fails the job instead of looking like "torn down" (found in review, fixed).
- **Plans only dev network/cluster.**
  - Platform/bootstrap need cluster API access; prod is out of scope (dev only).
  - Cluster: `public_access_cidrs` comes from the live cluster, or the runner IP when there's no cluster.
- **Hard gate:** counts deletes/replaces with `jq`. The JSON plan (plain-text secrets) never leaves the job.
- **Output:** artifact `gather` = plan text files, `pr.diff`, `changed-files.txt`, `gather.json`.
- **Plan files with full values are deleted right after use** (`/tmp/plan.json` and the binary `tfplan`).
  - Why: the JSON/binary plan shows sensitive values in plain text. Only the masked text plan is kept and shared.
- **`tf-plan-reader` can't read prod state** (inline policy `tf-no-prod-state`, explicit deny on `prod/*`).
  - Why: the repo is public, and anyone with write access could edit the workflow in a PR and use this role. With the deny, prod state files (which can hold secrets) stay out of reach. Dev is all the gather job needs.
- **Tested:** PR #2 (test, not merged) changed a dev cluster tag and a prod network tag. Result: `torn_down`, nothing planned, the correct reason per root. v1 didn't run.
  - Not tested yet: the path with real plans. That needs dev up, so it's covered in the eval batch (step 6).

## Decisions
- **One skill for all roots.** Root-specific knowledge goes in `risk-checklist.md`.
- **Dev only.** Prod PRs get a diff-only review marked "not planned".
- **One agent run per PR**, even when it touches 3+ roots, so coupling across roots isn't missed.
- **v1 reviewer is replaced, not kept alongside.** That avoids double cost and conflicting comments.
- **Gather job is built before local agent testing.**
  - Why: the `readonly` profile can't read state, so the plans come from CI artifacts.

## Later
- Add an approval gate on the **prod apply** workflow.
- Tighten `tf-plan-reader` further (prod state is already blocked; next would be scoping it to only what a dev plan reads).
- Decide on `[skip ci]` for the final merge to `main`, which otherwise triggers the dev and prod applies.
- Move off the subscription token once there's API credit.
- Agent runs longer than ~9 min need a refreshed GitHub token for federation (matters for Agent A's 25 turns).
