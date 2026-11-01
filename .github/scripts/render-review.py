#!/usr/bin/env python3
"""Render the blast-radius review comment from the agent's answer. Deterministic, no LLM.

render: result.json + gather.json + previous comment -> comment.md
        Checks every evidence entry, runs the risk checks, writes a one-line change note on re-runs.
        Exit 0 = fine, 3 = posted but the check must go red (evidence mostly unverified or a
        risk check failed).
stale:  previous comment -> the same comment with one "latest run failed" note on top.

Layout, for a skim: the verdict with the dangers in bold, one status line, the agent's summary,
details (findings with consumers, evidence in small print), a table of the other changes,
suggested next steps, then the review's limits, collapsed.
"""
import argparse
import json
import os
import re
import sys

MARKER = "<!-- tf-blast-radius "
LEVELS = ["low", "medium", "high"]
ICON = {"low": "🟢", "medium": "🟡", "high": "🔴"}
EVIDENCE = re.compile(r"(?P<path>[^\s:,;]+):(?P<start>\d+)(?:-(?P<end>\d+))?")
STALE_ALERT = "> [!CAUTION]"
STALE_PREFIX = "> Latest run"


def clean(text):
    """Agent text is data: one line, no HTML (no fake markers), no links, emphasis or
    @mention pings. Markdown punctuation is escaped, so `public[*]` renders as written."""
    text = " ".join(str(text).split())
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"([\\`*_\[\]~|])", r"\\\1", text)
    text = re.sub(r"^([#+-])", r"\\\1", text)  # no heading or list when it starts a line
    return re.sub(r"@(?=\w)", "@​", text)


def code(text):
    """Inline code span that survives backticks in the text."""
    text = str(text)
    fence = "``" if "`" in text else "`"
    pad = " " if fence == "``" else ""
    return f"{fence}{pad}{text}{pad}{fence}"


def short(path):
    parts = path.split("/")
    return "/".join(parts[-2:]) if len(parts) > 2 else path


def check_evidence(entry, repo_root, repo, sha):
    """Return (ok, rendered). A verified entry links to the exact lines the agent read."""
    m = EVIDENCE.fullmatch(entry.strip())
    if not m:
        return False, f"⚠️ {code(entry)} (not path:line)"
    path, start = m["path"], int(m["start"])
    end = int(m["end"]) if m["end"] else start
    root = os.path.realpath(repo_root)
    full = os.path.realpath(os.path.join(root, path))
    if os.path.isabs(path) or not full.startswith(root + os.sep) or not os.path.isfile(full):
        return False, f"⚠️ {code(entry)} (file not found)"
    with open(full, errors="replace") as f:
        lines = f.read().splitlines()
    if not (1 <= start <= end <= len(lines)):
        return False, f"⚠️ {code(entry)} (line out of range)"
    label = f"{short(path)}:{start}" + (f"-{end}" if end != start else "")
    if path.startswith("gather/"):
        link = code(label)  # artifact file, not in the repo
    else:
        anchor = f"#L{start}" + (f"-L{end}" if end != start else "")
        link = f"[{code(label)}](https://github.com/{repo}/blob/{sha}/{path}{anchor})"
    quote = " ".join(lines[start - 1].split())
    quote = quote[:80] + ("…" if len(quote) > 80 else "")
    return True, link, quote


def previous_marker(prev_body):
    if not prev_body:
        return None
    hits = re.findall(re.escape(MARKER) + r"(\{.*?\}) -->", prev_body)
    if not hits:
        return None
    try:
        return json.loads(hits[-1])
    except json.JSONDecodeError:
        return None


def counts(findings):
    return {lvl: sum(1 for f in findings if f["risk"] == lvl) for lvl in LEVELS}


def change_line(prev, sha, verdict, now_counts):
    if not prev:
        return None
    parts = []
    if prev.get("verdict") != verdict:
        parts.append(f"verdict {prev.get('verdict')} → {verdict}")
    for lvl in reversed(LEVELS):
        before = prev.get("counts", {}).get(lvl, 0)
        if before != now_counts[lvl]:
            parts.append(f"{lvl} {before}→{now_counts[lvl]}")
    same = prev.get("sha") == sha
    lead = f"Re-run on the same commit {code(sha[:7])}" if same else f"Changed since {code(prev.get('sha', '')[:7])}"
    if not parts:
        return f"{lead}: no change." if same else f"No change since {code(prev.get('sha', '')[:7])}."
    tail = " (same code, so the difference comes from the agent)" if same else ""
    return f"{lead}: " + " · ".join(parts) + tail + "."


def basis(gather):
    """What the review is based on, in plain words."""
    planned = [code(p["root"]) for p in gather.get("planned", [])]
    unplanned = [code(n["root"]) for n in gather.get("not_planned", [])]
    if planned:
        text = "Based on the Terraform plan for " + ", ".join(planned)
        return text + (" and the code change for " + ", ".join(unplanned) if unplanned else "")
    if gather.get("dev_state") == "torn_down":
        return "Based on the code change only (dev is torn down, so Terraform couldn't plan it)"
    if unplanned:
        return "Based on the code change only (no Terraform plan for " + ", ".join(unplanned) + ")"
    return "Based on the code change only"


def render(a):
    result = json.load(open(a.result))
    out = result["structured_output"]
    gather = json.load(open(a.gather))
    prev = previous_marker(open(a.prev).read() if a.prev and os.path.exists(a.prev) else "")

    verdict = out["verdict"]
    # Highest risk first; the agent's order is kept within a level.
    findings = sorted(out["findings"], key=lambda f: -LEVELS.index(f["risk"]))
    dangers = sorted(out.get("dangers", []), key=lambda d: -LEVELS.index(d["risk"]))
    planned = gather.get("planned", [])
    hard_gate = sum(p.get("deletes_or_replaces", 0) for p in planned)

    # What else breaks: findings with consumers. Evidence is checked here, in small print under each impact.
    total = verified = 0
    breaks = []
    for f in (f for f in findings if f["impacts"]):
        breaks.append("")
        breaks.append(f"**{ICON[f['risk']]} {clean(f['resource'])}** · {clean(f['action'])}<br>")
        breaks.append(clean(f["why"]))
        breaks.append("")
        for imp in f["impacts"]:
            shown, quoted = [], False
            for entry in imp["evidence"]:
                total += 1
                res = check_evidence(entry, a.repo_root, a.repo, a.sha)
                if res[0]:
                    verified += 1
                    _, link, quote = res
                    if not quoted and quote:
                        shown.append(f"{link} {code(quote)}")
                        quoted = True  # one quote per impact keeps the comment short
                    else:
                        shown.append(link)
                else:
                    shown.append(res[1])
            line = f"- **{clean(imp['affected'])}**: {clean(imp['how'])}"
            breaks.append(line + (f"<br>\n  <sub>📎 {' · '.join(shown)}</sub>" if shown else ""))

    # Deterministic risk checks on the agent's answer. They flag, never override.
    warnings = []
    worst = max((LEVELS.index(x["risk"]) for x in findings + dangers), default=0)
    if LEVELS.index(verdict) < worst:
        warnings.append(f"Verdict {verdict} is lower than its highest finding or danger ({LEVELS[worst]}).")
    if verdict != "low" and not dangers:
        warnings.append(f"Verdict {verdict}, but no danger is listed.")
    if hard_gate and verdict == "low":
        warnings.append(f"Verdict low, but the plan deletes or replaces {hard_gate} resource(s).")
    if verdict == "low" and any(r.startswith("prod/") for r in gather.get("changed_roots", [])):
        warnings.append("Verdict low, but a prod root changed (prod is at least medium).")
    unverified = total - verified
    if total and unverified * 3 > total:
        warnings.append(f"Most evidence could not be verified ({unverified}/{total}). Don't rely on this review.")

    # Header: the verdict and the dangers in bold, then one status line: what the review is based
    # on, the no-LLM hard gate, evidence, commit.
    lines = [f"### {ICON[verdict]} Blast radius: {verdict.upper()}", ""]
    if dangers:
        lines += [f"- {ICON[d['risk']]} **{clean(d['text'])}**" for d in dangers]
    elif verdict == "low":
        lines.append("✅ **Nothing else breaks.**")
    status = [basis(gather)]
    if hard_gate:
        status.append(f"**{hard_gate} resource{'s' if hard_gate > 1 else ''} deleted or replaced**")
    if total:
        status.append(f"evidence {verified}/{total} verified " + ("✅" if not unverified else "⚠️"))
    status.append(f"commit {code(a.sha[:7])}")
    lines += ["", " · ".join(status)]

    note = change_line(prev, a.sha, verdict, counts(findings))
    if note:
        lines += ["", f"🔁 {note}"]
    if warnings:
        lines += ["", "> [!WARNING]"] + [f"> {w}" for w in warnings]
    lines += ["", clean(out["summary"])]

    if breaks:
        lines += ["", "#### Details and evidence"] + breaks

    others = [f for f in findings if not f["impacts"]]
    if others:
        heading = "Other changes" if breaks else "Changes"
        lines += ["", f"#### {heading} (nothing else depends on them)", "",
                  "| | Resource | Change | Why |", "|:-:|---|---|---|"]
        lines += [f"| {ICON[f['risk']]} | {clean(f['resource'])} | {clean(f['action'])} | {clean(f['why'])} |"
                  for f in others]

    steps = out.get("next_steps", [])
    if steps:
        lines += ["", "#### Suggested next steps", ""] + [f"{i}. {clean(s)}" for i, s in enumerate(steps, 1)]

    untraced, not_planned = out.get("untraced", []), out.get("not_planned_roots", [])
    if untraced or not_planned:
        lines += ["", f"<details><summary>Limits of this review ({len(untraced) + len(not_planned)})</summary>", ""]
        lines += [f"- Not checked: **{clean(u['item'])}**: {clean(u['reason'])}" for u in untraced]
        lines += [f"- No Terraform plan for {code(n['root'])}: {clean(n['reason'])}" for n in not_planned]
        lines += ["", "</details>"]

    meta = [f"[Run]({a.run_url})" if a.run_url else "Run"]
    if result.get("num_turns") is not None:
        meta.append(f"{result['num_turns']} turns")
    if result.get("total_cost_usd") is not None:
        meta.append(f"${result['total_cost_usd']:.2f}")
    lines += ["", f"<sub>🤖 tf-blast-radius · {' · '.join(meta)}</sub>"]
    marker = {"sha": a.sha, "verdict": verdict, "counts": counts(findings)}
    lines.append(f"{MARKER}{json.dumps(marker)} -->")

    open(a.out, "w").write("\n".join(lines) + "\n")
    return 3 if warnings else 0


def stale(a):
    body = open(a.prev).read()
    prev = previous_marker(body) or {}
    kept = [l for l in body.splitlines() if l != STALE_ALERT and not l.startswith(STALE_PREFIX)]
    while kept and not kept[0].strip():
        kept.pop(0)
    note = [STALE_ALERT, f"{STALE_PREFIX} on {code(a.sha[:7])} failed ([run]({a.run_url})); "
                         f"the review below is for {code(prev.get('sha', '?')[:7])}.", ""]
    open(a.out, "w").write("\n".join(note + kept) + "\n")
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["render", "stale"])
    p.add_argument("--result")
    p.add_argument("--gather")
    p.add_argument("--prev")
    p.add_argument("--repo-root", default=".")
    p.add_argument("--repo", default="")
    p.add_argument("--sha", required=True)
    p.add_argument("--run-url", default="")
    p.add_argument("--out", required=True)
    a = p.parse_args()
    sys.exit(render(a) if a.mode == "render" else stale(a))


if __name__ == "__main__":
    main()
