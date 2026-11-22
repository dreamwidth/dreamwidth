# Browser tests

These are manual checks that run real pages in headless Chrome. They catch what server-side tests can't:
whether something is visible, keyboard and label behaviour, and pages with and without JavaScript. **CI doesn't run
them.** Run them yourself when you change the page a test covers.

## Running

Run inside the devcontainer, with the dev server up, from `$LJHOME`:

```bash
bin/dev/screenshot /login >/dev/null   # first run only: installs Chrome and puppeteer-core
node t/browser/editicons-rename.js
node t/browser/message-length.js
```

Each test prints `PASS: ...` lines and exits non-zero on failure. Set `DW_BROWSER_BASE` to test a server other than
`http://127.0.0.1:8080`.

## Writing one

A test here must run with that single command and no other setup:

- Create its own data with a fixture in `fixtures/<name>.pl`. The fixture prints JSON (account name, password, ids)
  and accepts `--delete <user>` to clean up. Fixture accounts start with `tbrowser_`.
- Log in with `login()` from `lib/browser.js`. No hand-exported cookie files.
- Remove its fixture when it finishes, even if it fails.
- Change only what it needs and never touch an account it didn't create.
