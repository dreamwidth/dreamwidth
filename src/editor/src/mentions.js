// @username autocomplete. Suggestions come exclusively from the logged-in
// user's own circle (one fetch of /__rpc_general?mode=list_circle, cached for
// the page lifetime) — deliberately NOT a global username search, so the
// username namespace stays non-enumerable. Anyone outside the circle can
// still be mentioned: the typed name itself is always offered as the last
// suggestion, and bad names simply render as "[Bad username]" on display.
//
// Typing "@user.site" (e.g. @jack.x.com) offers external-site links instead,
// matching Dreamwidth's @user.site markdown syntax; the part after the first
// dot is prefix-matched against the known external sites.
//
// Choosing a suggestion inserts a `user` node (serialized as
// <user name="..."> or <user name="..." site="...">). Plain @text left in the
// entry stays literal text: the rte1 format does not do server-side @mention
// conversion, which is exactly why the editor resolves mentions itself.

import { Plugin, PluginKey } from "prosemirror-state";

const key = new PluginKey("dwMentions");
const MAX_ITEMS = 8;

let circle = null; // [{username, journaltype}], fetched once per page
let circleFetch = null;

function loadCircle(url) {
    if (!circleFetch) {
        circleFetch = fetch(url)
            .then((res) => (res.ok ? res.json() : { circle: [] }))
            .then((data) => {
                circle = data.circle || [];
            })
            .catch(() => {
                circle = [];
            });
    }
    return circleFetch;
}

// Find an @mention being typed at the cursor: returns {from, to, query}.
function getMatch(state) {
    const sel = state.selection;
    if (!sel.empty || !sel.$cursor) return null;
    const $cursor = sel.$cursor;
    if ($cursor.parent.type.spec.code) return null;

    const textBefore = $cursor.parent.textBetween(
        Math.max(0, $cursor.parentOffset - 40),
        $cursor.parentOffset,
        "\0",
        "\0"
    );
    // A mention starts with a valid username character (the markdown parser's
    // username class is [\w-]); dots only appear as the @user.site separator.
    const match = /(?:^|[\s(])@([\w-][\w.-]{0,39})$/.exec(textBefore);
    if (!match) return null;

    const from = $cursor.pos - match[1].length - 1;
    return { from: from, to: $cursor.pos, query: match[1] };
}

// Local DW usernames fold to [a-z0-9_], with "-" treated as "_"
// (LJ::canonical_username). So @foo-bar and @Foo_Bar both mean foo_bar.
function canonicalLocal(name) {
    return name.toLowerCase().replace(/-/g, "_");
}

function suggestionsFor(query, sites) {
    // External form "user.sitedomain", mirroring Dreamwidth's @user.site
    // markdown syntax. The part after the first dot is matched as a prefix of a
    // known site domain (aliases included), so "@jack.x" offers jack@x.com and
    // "@jack." lists sites. When this matches, external suggestions are all we
    // offer. External usernames are kept verbatim (sites canonicalize their own).
    const ext = /^([\w-]+)\.([\w.-]*)$/.exec(query);
    if (ext && sites && sites.length) {
        const uname = ext[1];
        const prefix = ext[2].toLowerCase();
        const matched = sites
            .filter((d) => d.indexOf(prefix) == 0)
            .sort()
            .slice(0, MAX_ITEMS);
        if (matched.length)
            return matched.map((d) => ({ username: uname, site: d, external: true }));
    }

    // Local: compare against the circle using the canonical form, so "@foo-bar"
    // finds "foo_bar".
    const q = canonicalLocal(query);
    let items = [];
    if (circle && q.length) {
        const starts = [],
            contains = [];
        circle.forEach((u) => {
            const name = u.username.toLowerCase();
            if (name.indexOf(q) == 0) starts.push(u);
            else if (name.indexOf(q) > 0) contains.push(u);
        });
        items = starts.concat(contains).slice(0, MAX_ITEMS);
    }
    // Offer the typed name itself (canonicalized) so out-of-circle users can be
    // mentioned without a lookup -- but only when it's a valid local username.
    if (/^[a-z0-9_]+$/.test(q) && !items.some((u) => u.username.toLowerCase() == q))
        items.push({ username: q, literal: true });
    return items;
}

class MentionDropdown {
    constructor(view, options) {
        this.view = view;
        this.options = options;
        this.items = [];
        this.index = 0;
        this.match = null;

        this.dom = document.createElement("div");
        this.dom.className = "dw-editor-mentions";
        this.dom.setAttribute("role", "listbox");
        this.dom.style.display = "none";
        document.body.appendChild(this.dom);

        this.dom.addEventListener("mousedown", (e) => {
            const item = e.target.closest("[data-index]");
            if (!item) return;
            e.preventDefault();
            this.select(+item.getAttribute("data-index"));
        });

        view.dom.addEventListener("blur", () => this.hide());
    }

    update(view) {
        this.view = view;
        const match = getMatch(view.state);
        const suppressed = match && key.getState(view.state) == match.from;

        if (!match || suppressed || !view.hasFocus()) {
            this.hide();
            return;
        }

        if (!circle) {
            loadCircle(this.options.circleUrl).then(() => {
                if (this.view.hasFocus()) this.update(this.view);
            });
        }

        const prevQuery = this.match && this.match.query;
        this.match = match;
        this.items = suggestionsFor(match.query, this.options.sites);
        if (match.query != prevQuery) this.index = 0;
        if (this.index >= this.items.length) this.index = 0;

        if (!this.items.length) {
            this.hide();
            return;
        }
        this.render();
    }

    render() {
        this.dom.textContent = "";
        this.items.forEach((item, i) => {
            const row = document.createElement("div");
            row.className =
                "dw-editor-mention-item" + (i == this.index ? " dw-editor-mention-active" : "");
            row.setAttribute("role", "option");
            row.setAttribute("aria-selected", i == this.index ? "true" : "false");
            row.setAttribute("data-index", String(i));

            const name = document.createElement("span");
            name.textContent = item.username;
            row.appendChild(name);

            const note = document.createElement("span");
            note.className = "dw-editor-mention-note";
            if (item.external) note.textContent = item.site;
            else if (item.literal) note.textContent = this.options.strings.mentionLiteral;
            else if (item.journaltype == "C") note.textContent = this.options.strings.mentionCommunity;
            if (note.textContent) row.appendChild(note);

            this.dom.appendChild(row);
        });

        const coords = this.view.coordsAtPos(this.match.from);
        this.dom.style.display = "block";
        this.dom.style.left = coords.left + window.scrollX + "px";
        this.dom.style.top = coords.bottom + window.scrollY + 2 + "px";
        this.visible = true;
    }

    hide() {
        this.match = null;
        this.visible = false;
        this.dom.style.display = "none";
    }

    move(dir) {
        this.index = (this.index + dir + this.items.length) % this.items.length;
        this.render();
    }

    select(index) {
        const item = this.items[index];
        const match = this.match;
        if (!item || !match) return;

        const view = this.view;
        const userNode = view.state.schema.nodes.user.create(
            item.external
                ? { name: item.username, site: item.site }
                : { name: item.username, ctype: item.journaltype || "P" }
        );
        view.dispatch(
            view.state.tr.replaceWith(match.from, match.to, [
                userNode,
                view.state.schema.text(" "),
            ])
        );
        view.focus();
    }

    suppress() {
        const view = this.view;
        view.dispatch(view.state.tr.setMeta(key, this.match.from));
        view.focus();
    }

    destroy() {
        this.dom.remove();
    }
}

export function mentionsPlugin(options) {
    let dropdown = null;

    return new Plugin({
        key: key,

        // Plugin state: the match position the user dismissed with Escape
        // (so it doesn't pop right back open), or null.
        state: {
            init: () => null,
            apply(tr, value) {
                const meta = tr.getMeta(key);
                if (meta !== undefined) return meta;
                return value == null ? null : tr.mapping.map(value);
            },
        },

        view(editorView) {
            dropdown = new MentionDropdown(editorView, options);
            return {
                update: (view) => dropdown.update(view),
                destroy: () => {
                    dropdown.destroy();
                    dropdown = null;
                },
            };
        },

        props: {
            handleKeyDown(view, event) {
                if (!dropdown || !dropdown.visible) return false;
                if (event.key == "ArrowDown") {
                    dropdown.move(1);
                    return true;
                }
                if (event.key == "ArrowUp") {
                    dropdown.move(-1);
                    return true;
                }
                if (event.key == "Enter" || event.key == "Tab") {
                    dropdown.select(dropdown.index);
                    return true;
                }
                if (event.key == "Escape") {
                    dropdown.suppress();
                    return true;
                }
                return false;
            },
        },
    });
}
