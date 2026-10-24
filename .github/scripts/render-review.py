#!/usr/bin/env python3
"""Render the blast-radius review comment from the agent's answer. Deterministic, no LLM.

render: result.json + gather.json + previous comment -> comment.md
        Checks every evidence entry, runs the risk checks, writes a one-line change note on re-runs.
        Exit 0 = fine, 3 = posted but the check must go red (evidence mostly unverified or a
        risk check failed).
stale:  previous comment -> the same comment with one "latest run failed" line on top.
"""
import argparse
import json
import os
import re
import sys

MARKER = "<!-- tf-blast-radius "
LEVELS = ["low", "medium", "high"]
EVIDENCE = re.compile(r"(?P<path>[^\s:,;]+):(?P<start>\d+)(?:-(?P<end>\d+))?")
STALE_PREFIX = "> ⚠ Latest run"


def clean(text):
    """Agent text is data: one line, no HTML (no fake markers), no @mention pings."""
    text = " ".join(str(text).split())
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
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
        return False, f"⚠ {code(entry)} (not path:line)"
    path, start = m["path"], int(m["start"])
    end = int(m["end"]) if m["end"] else start
    root = os.path.realpath(repo_root)
    full = os.path.realpath(os.path.join(root, path))
    if os.path.isabs(path) or not full.startswith(root + os.sep) or not os.path.isfile(full):
        return False, f"⚠ {code(entry)} (file not found)"
    with open(full, errors="replace") as f:
        lines = f.read().splitlines()
    if not (1 <= start <= end <= len(lines)):
        return False, f"⚠ {code(entry)} (line out of range)"
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


def render(a):
    result = json.load(open(a.result))
    out = result["structured_output"]
    gather = json.load(open(a.gather))
    prev = previous_marker(open(a.prev).read() if a.prev and os.path.exists(a.prev) else "")

    verdict = out["verdict"]
    findings = out["findings"]
    planned = gather.get("planned", [])
    hard_gate = sum(p.get("deletes_or_replaces", 0) for p in planned)

    # Header: what was reviewed, how, and the no-LLM hard gate.
    if planned:
        mode = "planned: " + ", ".join(p["root"] for p in planned)
    else:
        mode = "diff-only" + (" (dev is torn down)" if gather.get("dev_state") == "torn_down" else "")
    header = f"### Blast radius: **{verdict.upper()}** · {code(a.sha[:7])} · {mode}"
    if hard_gate:
        header += f" · hard gate: {hard_gate} deletes/replaces"
    lines = [header]

    note = change_line(prev, a.sha, verdict, counts(findings))
    if note:
        lines.append(note)

    # Evidence check, rendered per impact.
    total = verified = 0
    body = []
    for f in findings:
        title = f"**[{f['risk']}] {clean(f['resource'])}** · {clean(f['action'])}"
        if f["risk"] == "low" and not f["impacts"]:
            body.append(f"- [low] {clean(f['resource'])} · {clean(f['action'])}, no consumers")
            continue
        body.append("")
        body.append(title)
        body.append(clean(f["why"]))
        for imp in f["impacts"]:
            body.append(f"- **{clean(imp['affected'])}**: {clean(imp['how'])}")
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
            if shown:
                body.append("  - " + " · ".join(shown))

    # Deterministic risk checks on the agent's answer. They flag, never override.
    warnings = []
    worst = max((LEVELS.index(f["risk"]) for f in findings), default=0)
    if LEVELS.index(verdict) < worst:
        warnings.append(f"⚠ Verdict {verdict} is lower than its highest finding ({LEVELS[worst]}).")
    if hard_gate and verdict == "low":
        warnings.append(f"⚠ Verdict low, but the plan deletes or replaces {hard_gate} resource(s).")
    if verdict == "low" and any(r.startswith("prod/") for r in gather.get("changed_roots", [])):
        warnings.append("⚠ Verdict low, but a prod root changed (prod is at least medium).")
    unverified = total - verified
    if total and unverified * 3 > total:
        warnings.append(f"⚠ Most evidence could not be verified ({unverified}/{total}). Don't rely on this review.")

    lines.extend(warnings)
    lines.append(clean(out["summary"]))
    if total:
        lines.append(f"Evidence: {verified}/{total} verified" + (f" · {unverified} ⚠ unverified" if unverified else ""))
    lines.extend(body)

    untraced, not_planned = out.get("untraced", []), out.get("not_planned_roots", [])
    if untraced or not_planned:
        lines.append("")
        lines.append(f"<details><summary>Not traced ({len(untraced)}) · Not planned ({len(not_planned)})</summary>\n")
        lines += [f"- Not traced: {clean(u['item'])}: {clean(u['reason'])}" for u in untraced]
        lines += [f"- Not planned: {code(n['root'])}: {clean(n['reason'])}" for n in not_planned]
        lines.append("\n</details>")

    meta = f"[run]({a.run_url})"
    if result.get("num_turns") is not None:
        meta += f" · {result['num_turns']} turns"
    if result.get("total_cost_usd") is not None:
        meta += f" · ${result['total_cost_usd']:.2f}"
    lines.append("")
    lines.append(f"<sub>{meta}</sub>")
    marker = {"sha": a.sha, "verdict": verdict, "counts": counts(findings)}
    lines.append(f"{MARKER}{json.dumps(marker)} -->")

    open(a.out, "w").write("\n".join(lines) + "\n")
    return 3 if warnings else 0


def stale(a):
    body = open(a.prev).read()
    prev = previous_marker(body) or {}
    kept = [l for l in body.splitlines() if not l.startswith(STALE_PREFIX)]
    line = (f"{STALE_PREFIX} on {code(a.sha[:7])} failed ([run]({a.run_url})); "
            f"the review below is for {code(prev.get('sha', '?')[:7])}.")
    open(a.out, "w").write("\n".join([line] + kept) + "\n")
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
