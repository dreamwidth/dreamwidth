# Test a page in an old browser

Some readers still use browsers built on old engines, such as Waterfox Classic (Firefox 56's Gecko), Pale Moon or
SeaMonkey. These lack features the site's JavaScript may assume (`<dialog>` arrived in Firefox 98) and have
defaults modern Firefox dropped (table resize handles and row/column buttons in editable areas, off since Firefox
63). This page sets one up in the devcontainer, next to the Chrome that `bin/dev/screenshot` uses (see
[SCREENSHOTS.md](SCREENSHOTS.md)).

From the checkout root on the host, open a shell in the devcontainer:

```bash
CID=$(docker ps --filter "label=devcontainer.local_folder=$(pwd)" --format '{{.ID}}')
docker exec -it -w /workspaces/dreamwidth $CID bash
```

Everything after this runs in that shell, inside the container. The JavaScript examples use top-level `await`:
save them as `.mjs` files (ES modules) and run them with `node`, or wrap them in `(async () => { ... })()` in a
`.js` file. An `.mjs` file needs `require` made first:
`import { createRequire } from "node:module"; const require = createRequire(import.meta.url);`.

## Current Firefox with old defaults

Often enough, and easier to drive: puppeteer controls current Firefox directly.

```bash
bin/dev/screenshot /login >/dev/null   # first run only: installs puppeteer-core in /opt/dw-screenshot
cd /tmp && npx -y @puppeteer/browsers install firefox@stable --path /opt/dw-firefox
```

```js
const puppeteer = require("/opt/dw-screenshot/node_modules/puppeteer-core");
const browser = await puppeteer.launch({
    browser: "firefox",
    executablePath: "/opt/dw-firefox/firefox/linux-stable_<version>/firefox/firefox",  // printed by the install
    extraPrefsFirefox: {
        // The old Gecko defaults: resize handles and row/column buttons on tables.
        "editor.resizing.enabled_by_default": true,
        "editor.inline_table_editing.enabled_by_default": true,
        "editor.positioning.enabled_by_default": true,
    },
});
```

To test a missing API, remove it before the page's scripts run:
`page.evaluateOnNewDocument(() => { delete HTMLDialogElement.prototype.showModal; })`.

**Log in through the login form** (`/mobile/login`, fields `user` and `password`), not with `page.setCookie`.
Cookies set through puppeteer don't reach Firefox's requests, so the page loads logged out.

## Waterfox Classic

The real old engine. Puppeteer can't drive it, so it runs under geckodriver 0.20.1, the last release that supports
Gecko 56.

```bash
apt-get update -q && apt-get install -y -q libdbus-glib-1-2 xvfb   # dbus-glib for Waterfox, Xvfb for a display

mkdir -p /opt/dw-waterfox && cd /opt/dw-waterfox
REL=https://github.com/WaterfoxCo/Waterfox-Classic/releases/download/2022.11-classic
curl -sSLO $REL/waterfox-classic-2022.11.en-US.linux-x86_64.tar.bz2
curl -sSLO $REL/waterfox-classic-2022.11.sha256
grep linux-x86_64.tar.bz2 waterfox-classic-2022.11.sha256 | sha256sum -c -
tar xjf waterfox-classic-2022.11.en-US.linux-x86_64.tar.bz2
curl -sSLO https://github.com/mozilla/geckodriver/releases/download/v0.20.1/geckodriver-v0.20.1-linux64.tar.gz
echo "b2388c4b6f0dbbdb38834912a3ffe2b11aa3c2c652a7d8d82a143ed792867328  geckodriver-v0.20.1-linux64.tar.gz" | sha256sum -c -
tar xzf geckodriver-v0.20.1-linux64.tar.gz
./waterfox-classic/waterfox --version     # Waterfox Classic 2022.11
```

Run it on a virtual display, not with `-headless`: a headless window never has the focus, so no focus events fire
and anything that depends on them (the editor's own focus handling) can't be tested. Start Xvfb and geckodriver:

```bash
Xvfb :99 -screen 0 1280x1024x24 &
DISPLAY=:99 /opt/dw-waterfox/geckodriver --port 4444 &
```

Then drive it over the W3C WebDriver HTTP API, for example with `fetch` from Node:

```js
const WD = "http://127.0.0.1:4444";
let sid;
async function wd(method, path, body) {
    const r = await fetch(WD + (sid ? "/session/" + sid : "/session") + path, {
        method,
        headers: { "content-type": "application/json" },
        body: body ? JSON.stringify(body) : undefined,
    });
    const j = await r.json();
    if (j.value && j.value.error) throw new Error(path + ": " + j.value.message);
    return j.value;
}

sid = (await wd("POST", "", { capabilities: { alwaysMatch: {
    pageLoadStrategy: "none",
    "moz:firefoxOptions": { binary: "/opt/dw-waterfox/waterfox-classic/waterfox" },
} } })).sessionId;

await wd("POST", "/url", { url: "http://127.0.0.1:8080/entry/new" });
const ok = await wd("POST", "/execute/sync", { script: "return document.readyState", args: [] });
// Elements: POST /element {using: "css selector", value}, then /element/<id>/click or
// /element/<id>/value {text, value: [...chars]} to type ("\uE007" is Enter).
// Real keys: POST /actions. Screenshots: GET /screenshot (base64 PNG).
await wd("DELETE", "");
```

### Gotchas

- **Use `pageLoadStrategy: "none"`** and poll `document.readyState` yourself. With the default strategy a page
  that's still loading blocks every command.
- **A `confirm()` that runs while the page loads hangs it.** geckodriver 0.20 can't see or answer the prompt, so
  the page stays at `readyState == "loading"` and nothing after the script runs. On `/entry/new` that is the
  "Restore from saved draft?" question. Clear the test account's draft before each load, after leaving the page
  so autosave can't write it back:
  ```bash
  perl -e 'require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
    my $u = LJ::load_user("shotuser"); $u->set_prop(entry_draft => ""); $u->clear_prop("draft_properties");'
  ```
- **Check `document.hasFocus()`** if focus behaviour looks wrong. It is false in a headless window.
- **Set form values from script** when a key sequence is awkward. Set the element's `value`, then dispatch a
  `change` event (for example the entry form's `#editor` select).
- **Stop it with `pkill geckodriver; pkill -f waterfox-classic/waterfox`.** Run each as its own command: a
  `bash -c` holding the pattern matches itself and gets killed.
