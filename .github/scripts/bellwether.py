#!/usr/bin/env python3
"""
bellwether.py

Acts on maintainer commands in pull request comments (/merge, /approve, /hold,
/unhold, /fix++) and on Bellwether's grace period, for PRs that Bellwether's
triage has already checked. A /fix that triage hasn't run yet holds the merge.
It also keeps the PR's `bw:` status label in step with what it decides.

Bellwether's triage runs elsewhere: it reviews and tests each PR, then keeps
one status comment on it. That comment carries a hidden state line saying
which commit it checked and whether that commit passed. This script trusts
only comments written by the Bellwether app, never checks out or runs PR code,
and re-checks CI, the head commit and main right before merging.

Usage: bellwether.py event        handle the GitHub event in $GITHUB_EVENT_PATH
       bellwether.py pr N         evaluate one PR
       bellwether.py sweep        evaluate every open PR (the grace period)
       add --dry-run to print what would happen without changing anything

Authors:
    Mark Smith <mark@dreamwidth.org>

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
"""

import http.client
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

API = "https://api.github.com"
REPO = os.environ.get("GITHUB_REPOSITORY", "dreamwidth/dreamwidth")
TOKEN = os.environ.get("GH_TOKEN", "")
BOT = "dw-bellwether[bot]"
MARKER = "<!-- bellwether:status -->"
STATE = re.compile(r"<!-- bellwether:state (\{.*?\}) -->")
NEXT_START, NEXT_END = "<!-- bellwether:next -->", "<!-- /bellwether:next -->"
NEXT = re.compile(re.escape(NEXT_START) + r".*?" + re.escape(NEXT_END), re.S)
# `/fix` asks triage to fix review items on the branch; `/fix++` also approves.
COMMAND = re.compile(r"^\s*/(approve|lgtm|merge|hold|unhold|fix\+\+|fix)(?!\w)", re.I | re.M)
FOOTER = "I keep this comment up to date. New commits start the checks over."
DRY_RUN = "--dry-run" in sys.argv
# GitHub's API sometimes answers 5xx or times out for a moment. Reads are retried with backoff;
# writes are not, since a write that timed out may have happened (merge checks for that itself).
RETRY_DELAYS = (2, 5, 15)
TIMEOUT = 30
# After a merge request that errored or timed out, how long to watch for the merge to show up.
MERGE_SETTLE = (3, 5, 10)
# What a request that never got a full answer raises: the request may or may not have happened.
NO_ANSWER = (urllib.error.URLError, TimeoutError, ConnectionError, ssl.SSLError,
             http.client.HTTPException)
# The sweep also finishes the status of PRs merged this recently, in case the run that merged one
# lost GitHub's answer.
RECENT_MERGES = timedelta(hours=6)


def transient(e):
    if isinstance(e, urllib.error.HTTPError):
        return e.code >= 500
    return isinstance(e, NO_ANSWER)


def error_detail(e):
    """GitHub's message for an HTTP error, or its status if the body can't be read."""
    try:
        return json.loads(e.read() or b"{}").get("message") or f"HTTP {e.code} {e.reason}"
    except Exception:
        return f"HTTP {e.code} {e.reason}"


# Repository variables. BELLWETHER_AUTO_MERGE turns on merging after the grace period with no
# maintainer's go-ahead; BELLWETHER_AUTO_PER_HOUR caps those merges so they don't all land at once.
# Merges a maintainer asked for aren't capped.
AUTO_MERGE = os.environ.get("BELLWETHER_AUTO_MERGE", "") == "true"
AUTO_PER_HOUR = int(os.environ.get("BELLWETHER_AUTO_PER_HOUR") or 2)

def api(method, path, data=None):
    for delay in (*RETRY_DELAYS, None):
        try:
            return request(method, path, data)
        except Exception as e:
            if method != "GET" or delay is None or not transient(e):
                raise
            print(f"  GitHub API {method} {path.split('?')[0]} failed ({e}); retrying in {delay}s")
            time.sleep(delay)


def request(method, path, data=None):
    req = urllib.request.Request(
        path if path.startswith("http") else API + path, method=method,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "dw-bellwether",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read() or b"null")


def paged(path, key=None):
    out, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        got = api("GET", f"{path}{sep}per_page=100&page={page}")
        items = got[key] if key else got
        out += items
        if len(items) < 100:
            return out
        page += 1


def now():
    return datetime.now(timezone.utc)


def parse_time(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


_writers = {}


def can_write(user):
    """Maintainers are the people with write access to the repository."""
    if user not in _writers:
        # Only "not a collaborator" means no access. Any other error stops this PR, rather than
        # counting a maintainer's /hold or review as nobody's.
        try:
            perm = api("GET", f"/repos/{REPO}/collaborators/{user}/permission")["permission"]
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            perm = "none"
        _writers[user] = perm in ("admin", "maintain", "write")
    return _writers[user]


def status_comment(number):
    """Bellwether's status comment on a PR and the state it records, or (None, None)."""
    for c in reversed(paged(f"/repos/{REPO}/issues/{number}/comments")):
        if c["user"]["login"] == BOT and MARKER in (c["body"] or ""):
            m = STATE.search(c["body"])
            try:
                return c, json.loads(m.group(1)) if m else None
            except ValueError:
                return c, None
    return None, None


def commands(pr, since, fixes_done=(), go_since=None):
    """Maintainers' go-aheads on the current head, whether the PR is on hold, who has requested
    changes, and who has a `/fix` that triage hasn't dealt with yet.

    /approve, /lgtm, /merge and approving reviews count only after `since`, when Bellwether first
    saw this head, so a new push needs a new go-ahead. An edited comment counts from when it was
    edited. /hold and /unhold persist; the latest wins. Each reviewer's latest review is the one
    that counts. The PR's author and bots never count.

    A `/fix` posted after `since` that isn't in the state's `fixes_done` hasn't run yet. Merging
    then would merge the commit without the fix, so the PR waits for triage to push it.

    `go_since`, when later than `since`, is when a `/fix` on this head failed: go-aheads from before
    it asked for the fix, so only later ones count."""
    author = pr["user"]["login"]
    since = parse_time(since)
    go_since = max(since, parse_time(go_since)) if go_since else since
    go, hold, fixing = [], None, []
    comments = paged(f"/repos/{REPO}/issues/{pr['number']}/comments")
    for c in sorted(comments, key=lambda c: parse_time(c["updated_at"])):
        who = c["user"]["login"]
        found = [m.lower() for m in COMMAND.findall(c["body"] or "")]
        if not found or who == author or c["user"]["type"] == "Bot" or not can_write(who):
            continue
        for cmd in found:
            if cmd in ("approve", "lgtm", "merge", "fix++") and parse_time(c["updated_at"]) > go_since:
                go.append(who)
            if cmd in ("fix", "fix++") and parse_time(c["updated_at"]) > since \
                    and c["id"] not in fixes_done:
                fixing.append(who)
            elif cmd == "hold":
                hold = who
            elif cmd == "unhold":
                hold = None
    latest = {}
    for r in paged(f"/repos/{REPO}/pulls/{pr['number']}/reviews"):
        who = (r.get("user") or {}).get("login")
        if r["state"] in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED") and who != author:
            latest[who] = r  # the API lists reviews oldest first
    changes = []
    for who, r in latest.items():
        if not can_write(who):
            continue
        if r["state"] == "CHANGES_REQUESTED":
            changes.append(who)
        elif (r["state"] == "APPROVED" and r["commit_id"] == pr["head"]["sha"]
              and parse_time(r["submitted_at"]) > go_since):
            go.append(who)
    return list(dict.fromkeys(go)), hold, changes, list(dict.fromkeys(fixing))


def ci_state(sha, ignore, required):
    """passing, pending, failing, missing or awaiting approval for the commit.

    Each required workflow's latest run on the commit must have succeeded; a skipped or absent one
    blocks. Every other check must not be failing or still running."""
    runs = paged(f"/repos/{REPO}/actions/runs?head_sha={sha}", "workflow_runs")
    if any(r["status"] == "action_required" or r["conclusion"] == "action_required" for r in runs):
        return "awaiting approval"
    for name in required:
        mine = sorted((r for r in runs if r["name"] == name and r["event"] == "pull_request"),
                      key=lambda r: r["created_at"])
        if not mine:
            return f"missing {name}"
        if mine[-1]["status"] != "completed":
            return "pending"
        if mine[-1]["conclusion"] != "success":
            return "failing"
    states = set()
    for run in paged(f"/repos/{REPO}/commits/{sha}/check-runs", "check_runs"):
        if run["name"] in ignore:
            continue
        if run["status"] != "completed":
            states.add("pending")
        elif run["conclusion"] in ("success", "neutral", "skipped"):
            states.add("passing")
        else:
            states.add("failing")
    for s in paged(f"/repos/{REPO}/commits/{sha}/status", "statuses"):
        if s["context"] not in ignore:
            states.add({"success": "passing", "pending": "pending"}.get(s["state"], "failing"))
    for result in ("failing", "pending"):
        if result in states:
            return result
    return "passing"


def main_drift(state, base_ref):
    """Files the PR touches that main has changed since Bellwether's tests ran on it."""
    if not state.get("base"):
        return ["(no record of the tested base)"]
    cmp = api("GET", f"/repos/{REPO}/compare/{state['base']}...{base_ref}")
    files = ({f["filename"] for f in cmp.get("files") or []}
             | {f["previous_filename"] for f in cmp.get("files") or [] if f.get("previous_filename")})
    if len(files) >= 300:
        return ["(main has changed too much to compare)"]
    return sorted(set(state.get("files") or []) & files)


class StateChanged(Exception):
    """Triage updated the status comment while this run was deciding; start again."""


def current_state(comment):
    m = STATE.search(comment["body"] or "")
    return m.group(1) if m else None


def set_next(comment, text):
    """Replace the "what happens next" part of the status comment, if it changed.

    Triage owns the state line. This re-reads the comment first and only ever rewrites the next
    part of what it finds, so it can't put back a state that triage has since replaced. If the
    state has changed, the decision this run made is stale."""
    fresh = comment if DRY_RUN else api("GET", f"/repos/{REPO}/issues/comments/{comment['id']}")
    if current_state(fresh) != current_state(comment):
        raise StateChanged()
    # A recorded merge is final: another run may have merged it meanwhile.
    if says_merged(fresh):
        return print("  comment already records the merge")
    body = NEXT.sub(lambda _: f"{NEXT_START}\n{text}\n{NEXT_END}", fresh["body"])
    if body == fresh["body"]:
        return
    print(f"  comment -> {text.splitlines()[0]}")
    if not DRY_RUN:
        comment["body"] = api("PATCH", f"/repos/{REPO}/issues/comments/{comment['id']}",
                              {"body": body})["body"]


# Triage sets every status label on each pass. Between passes this keeps the label in step with
# what this script just decided. `risk:` labels and anyone else's labels are left alone.
STATUS_LABELS = ("bw: needs approval", "bw: blocking item", "bw: fix failed", "bw: merging",
                 "bw: waiting on author", "bw: in progress", "bw: on hold")


def set_label(pr, label):
    """Make `label` the PR's only status label; None removes them all (once it has merged)."""
    have = {x["name"] for x in pr.get("labels") or []}
    stale = sorted((have & set(STATUS_LABELS)) - {label})
    add = [label] if label and label not in have else []
    if not stale and not add:
        return
    print(f"  labels -> " + ", ".join([*(f"+{x}" for x in add), *(f"-{x}" for x in stale)]))
    if DRY_RUN:
        return
    for x in stale:
        try:
            api("DELETE", f"/repos/{REPO}/issues/{pr['number']}/labels/{urllib.parse.quote(x, safe='')}")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
    if add:
        api("POST", f"/repos/{REPO}/issues/{pr['number']}/labels", {"labels": add})
    # Later calls in this run see the labels as they now are.
    pr["labels"] = [{"name": x} for x in sorted((have - set(stale)) | set(add))]


def evaluate(number):
    for _ in range(3):
        try:
            return decide(number)
        except StateChanged:
            print("  triage updated the comment meanwhile; re-evaluating")
    raise RuntimeError("triage kept updating the comment; gave up for this run")


def says_merged(comment):
    m = NEXT.search(comment["body"] or "")
    return bool(m) and m.group(0)[len(NEXT_START):].lstrip().startswith("**Merged**")


def finish_merge(number, comment, sha, reason=None):
    """Record a merge on the status comment and clear the status labels. `reason` is left out
    when the merge wasn't this run's (another run, or a person)."""
    text = f"**Merged** as {sha[:11]}" + (f" after {reason}." if reason else ".")
    for _ in range(3):
        try:
            set_next(comment, text)
            break
        except StateChanged:
            comment, _ = status_comment(number)
    else:
        raise RuntimeError("triage kept updating the comment while recording the merge")
    set_label(api("GET", f"/repos/{REPO}/pulls/{number}"), None)


def merge_commit(number, waits=()):
    """The merge commit if the PR has merged, waiting `waits` seconds between looks, else None."""
    for wait in (0, *waits):
        time.sleep(wait)
        pr = api("GET", f"/repos/{REPO}/pulls/{number}")
        if pr["merged"]:
            return pr.get("merge_commit_sha") or ""
    return None


def decide(number, final_check=False):
    """Evaluate one PR. With `final_check`, only report whether it may still merge right now."""
    pr = api("GET", f"/repos/{REPO}/pulls/{number}")
    print(f"#{number}:")
    if pr["state"] != "open":
        print("  closed")
        # A merge recorded nowhere (an earlier run lost GitHub's answer, or a person merged it)
        # gets its comment finished now, and its status labels cleared even if the comment was.
        if not pr.get("merged") or DRY_RUN:
            return
        comment, _ = status_comment(number)
        if comment and NEXT.search(comment["body"] or "") and not says_merged(comment):
            return finish_merge(number, comment, pr.get("merge_commit_sha") or "")
        return set_label(pr, None)
    comment, state = status_comment(number)
    if not comment or not state or state.get("v") != 1:
        return print("  no Bellwether status")
    if pr["head"]["sha"] != state["head"]:
        # New commits since triage checked it. Triage re-checks and updates the comment.
        return print("  head has moved on since triage")
    if pr["base"]["ref"] != pr["base"]["repo"]["default_branch"]:
        # Triage tests PRs merged onto the default branch only.
        return print(f"  targets {pr['base']['ref']}, not the default branch")
    go, hold, changes, fixing = commands(pr, state["head_seen_at"], state.get("fixes_done") or [],
                                         state.get("fix_failed_at"))

    def label(name):
        # The final check re-runs this function; label once. A state from before triage sent its
        # label has none, and then triage's own labels stand.
        if not final_check and name:
            set_label(pr, name)
    print(f"  gates_ok={state['gates_ok']} needs_approval={state['needs_approval']} "
          f"ready={state['ready']} go={go} hold={hold} changes_requested={changes} fixing={fixing}")
    if changes:
        label("bw: waiting on author")
        return set_next(comment, f"**Changes requested by {', '.join(changes)}.** I won't merge "
                                 f"it until they approve.\n\n{FOOTER}")
    if hold:
        label("bw: on hold")
        return set_next(comment, f"**On hold: {hold} replied `/hold`.**\n\n"
                                 "Maintainers: reply `/unhold` to let it merge.")
    if fixing:
        label("bw: in progress")
        return set_next(comment, f"**Waiting on the `/fix` from {', '.join(fixing)}.** I'll push "
                                 f"it, check it and re-test before anything merges.\n\n{FOOTER}")
    if not state["gates_ok"] or (state["needs_approval"] and not go):
        label(state.get("label"))
        return set_next(comment, state["next"])
    if go:
        label("bw: merging")
        reason = f"{', '.join(go)} approved it"
    elif state["ready"] and state.get("ready_since") and AUTO_MERGE:
        label(state.get("label"))
        hours = state["grace_hours"]
        if now() < parse_time(state["ready_since"]) + timedelta(hours=hours):
            return set_next(comment, state["next"])
        if recent_merges() >= AUTO_PER_HOUR:
            return print(f"  due, but {AUTO_PER_HOUR} merges already this hour; next sweep")
        reason = f"{hours} hours passed with no `/hold`"
    else:
        label(state.get("label"))
        return set_next(comment, state["next"])

    # Everything triage checked has passed. Re-check what can have changed since.
    problems = []
    if pr["draft"]:
        problems.append("it's a draft")
    ci = ci_state(state["head"], set(state.get("ignore_checks") or []),
                  state.get("required_workflows") or ["CI (fast)"])
    if ci != "passing":
        problems.append(f"CI is {ci}")
    drift = main_drift(state, pr["base"]["ref"])
    if drift:
        problems.append("main has changed files it touches since its tests ran ("
                        + ", ".join(drift[:4]) + (" …" if len(drift) > 4 else "")
                        + "), so it needs a re-test")
    if pr.get("mergeable") is False:
        problems.append("it has merge conflicts")
    if problems:
        return set_next(comment, f"**Not merged yet: {'; '.join(problems)}.** "
                                 f"I'll merge it once that's sorted.\n\n{FOOTER}")
    if final_check:
        return "ok"

    # Everything above took a while. Re-read the PR, the state, the commands and main once more,
    # right before merging, so a /hold or a triage update in the meantime is respected.
    if decide(number, final_check=True) != "ok":
        return
    set_next(comment, f"**Merging: {reason}.**")
    if DRY_RUN:
        return print("  would merge")
    try:
        sha = api("PUT", f"/repos/{REPO}/pulls/{number}/merge",
                  {"merge_method": "squash", "sha": state["head"],
                   "commit_title": f"{pr['title']} (#{number})"})["sha"]
    except urllib.error.HTTPError as e:
        if e.code < 500:
            # GitHub refused. Someone else may have merged it first.
            other = merge_commit(number)
            if other is not None:
                return finish_merge(number, comment, other)
            return set_next(comment, f"**Merge failed.** GitHub said: {error_detail(e)}\n\n{FOOTER}")
        sha = None
        print(f"  merge answered {e.code}; checking whether it merged")
    except (*NO_ANSWER, ValueError, KeyError, TypeError) as e:
        sha = None
        print(f"  merge got no usable answer ({e!r}); checking whether it merged")
    if sha is None:
        # The merge may have happened, or may still be happening. Watch for it; if it doesn't show,
        # leave the comment on "Merging" and fail this PR, and a later run sorts it out either way.
        sha = merge_commit(number, MERGE_SETTLE)
        if sha is None:
            raise RuntimeError("merge request got no clear answer and the PR hasn't merged")
    finish_merge(number, comment, sha, reason)


def handle_event():
    name = os.environ.get("GITHUB_EVENT_NAME")
    event = json.loads(open(os.environ["GITHUB_EVENT_PATH"]).read())
    if name == "issue_comment":
        if event["issue"].get("pull_request"):
            evaluate(event["issue"]["number"])
    elif name == "workflow_run":
        sha = event["workflow_run"]["head_sha"]
        evaluate_each(pr["number"] for pr in paged(f"/repos/{REPO}/pulls?state=open")
                      if pr["head"]["sha"] == sha)
    elif name == "workflow_dispatch" and (event.get("inputs") or {}).get("pr"):
        evaluate(int(event["inputs"]["pr"]))
    else:
        sweep()


def recent_merges():
    """How many PRs Bellwether merged in the last hour."""
    cutoff = now() - timedelta(hours=1)
    count = 0
    for pr in api("GET", f"/repos/{REPO}/pulls?state=closed&sort=updated&direction=desc&per_page=30"):
        if pr.get("merged_at") and parse_time(pr["merged_at"]) > cutoff:
            merged_by = (api("GET", f"/repos/{REPO}/pulls/{pr['number']}").get("merged_by") or {})
            count += merged_by.get("login") == BOT
    return count


def sweep():
    """Evaluate every open PR, and every recently merged one whose status may be unfinished."""
    recent = api("GET", f"/repos/{REPO}/pulls?state=closed&sort=updated&direction=desc&per_page=50")
    merged = [pr["number"] for pr in recent
              if pr.get("merged_at") and now() - parse_time(pr["merged_at"]) < RECENT_MERGES]
    evaluate_each([*(pr["number"] for pr in paged(f"/repos/{REPO}/pulls?state=open")), *merged])


def evaluate_each(numbers):
    """Evaluate several PRs. One PR's error doesn't stop the others; the run still fails at the
    end, so the error shows."""
    failed = []
    for number in numbers:
        try:
            evaluate(number)
        except Exception as e:
            print(f"#{number}: error: {e!r}")
            failed.append(number)
    if failed:
        sys.exit(f"errors on {', '.join(f'#{n}' for n in failed)}")


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    if args[:1] == ["event"]:
        handle_event()
    elif args[:1] == ["pr"] and len(args) == 2:
        evaluate(int(args[1]))
    elif args[:1] == ["sweep"]:
        sweep()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
