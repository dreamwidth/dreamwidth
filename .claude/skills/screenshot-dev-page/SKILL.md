---
name: screenshot-dev-page
description: Capture a screenshot of a page rendered by the local Dreamwidth dev server, to visually check how a change looks. Use when asked to screenshot, "show me", or visually verify how a page/view/.tt renders (e.g. after a BML→TT migration or a CSS/template change). Runs headless Chrome inside the devcontainer via bin/dev/screenshot.
---

# Screenshot a dev-server page

`bin/dev/screenshot` renders a page from the local Starman dev server (port 8080)
to a PNG using headless Google Chrome. Use it to *see* how a change looks rather
than only reading the HTML.

## Prerequisites

- The page's devcontainer must be running (`docker ps --filter
  label=devcontainer.local_folder=<worktree-path>`). The script runs **inside**
  the container (as root) and talks to Starman on `127.0.0.1:8080`.
- First run installs Google Chrome (Google's signed apt repo) and `puppeteer-core`
  into `/opt/dw-screenshot` — ~1–2 min once per container, then cached.

## Run it

```bash
CID=$(docker ps --filter label=devcontainer.local_folder=<worktree-path> --format '{{.ID}}')

# public page
docker exec -w /workspaces/dreamwidth $CID bin/dev/screenshot /login

# logged-in page (most pages): pass a user + password
docker exec -w /workspaces/dreamwidth $CID \
  bin/dev/screenshot --user someuser --password somepass /manage/tags
```

Options: `--user`/`--password` (log in first), `--out FILE`, `--size WxH`
(default `1280x1400`), `--restart`. See `bin/dev/screenshot --help`.

The PNG is written **inside the container** (default `/tmp/dw-screenshot.png`).
Copy it out, then look at it and/or send it to the user:

```bash
docker cp $CID:/tmp/dw-screenshot.png /tmp/shot.png
```

Then `Read` `/tmp/shot.png` to inspect it yourself, and/or `SendUserFile` it.

## Gotchas

- **A running Starman does not pick up a new controller/route** (it globs the FS
  at startup). After adding or changing a route, pass `--restart`, or you'll get
  a 404 for the new page.
- **Auth:** logged-in pages need `--user`/`--password`. If you don't already have
  a usable account in the container's DB, make a throwaway one:
  ```bash
  docker exec -w /workspaces/dreamwidth $CID perl -e '
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
    my $u = LJ::load_user("shotuser") || LJ::User->create_personal(
      user=>"shotuser", email=>"shot\@example.com", password=>"Testpass123", name=>"Shot User");
    $u->update_self({status=>"A", statusvis=>"V"});
    LJ::update_user($u, { password=>"Testpass123" });'
  # then: bin/dev/screenshot --user shotuser --password Testpass123 <path>
  ```
- It captures the **full page** (`fullPage: true`); pass `--size` to change the
  viewport width.
