// The editor toolbar: a hand-rolled strip of buttons (no menu library).
// Button state refreshes on every editor update via update().

import { toggleMark, setBlockType, wrapIn, lift } from "prosemirror-commands";
import { wrapInList } from "prosemirror-schema-list";
import { undo, redo } from "prosemirror-history";
import { linkDialog, imageDialog, userDialog, embedDialog } from "./dialogs.js";
import { insertRawBlock } from "./paste.js";

// Icons for the buttons that have no dependable text glyph. They're inline
// SVG, so they don't rely on any font having an emoji or symbol (the emoji
// versions rendered as empty boxes where the font lacked them).
function icon(paths) {
    return (
        '<svg class="dw-editor-icon" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" ' +
        'focusable="false" fill="none" stroke="currentColor" stroke-width="1.6" ' +
        'stroke-linecap="round" stroke-linejoin="round">' +
        paths +
        "</svg>"
    );
}

const ICONS = {
    link: icon('<path d="M6.5 9.5l3-3"/><path d="M7 4.5l1-1a2.5 2.5 0 013.5 3.5l-1 1"/><path d="M9 11.5l-1 1A2.5 2.5 0 014.5 9l1-1"/>'),
    image: icon('<rect x="1.8" y="3" width="12.4" height="10" rx="1.2"/><circle cx="5.4" cy="6.4" r="1.1"/><path d="M2.5 12l3.6-3.4 2.6 2.4 2-1.8 3.3 2.8"/>'),
    embed: icon('<rect x="1.8" y="3" width="12.4" height="10" rx="1.2"/><path d="M6.6 5.8v4.4l3.6-2.2z" fill="currentColor"/>'),
    quote: icon('<path d="M3 11V8.2C3 6.2 4 5 5.8 4.6M8.6 11V8.2c0-2 1-3.2 2.8-3.6"/><path d="M3 11h2.6V8.2H3zM8.6 11h2.6V8.2H8.6z" fill="currentColor"/>'),
    cut: icon('<circle cx="4.4" cy="11.6" r="1.8"/><circle cx="11.6" cy="11.6" r="1.8"/><path d="M5.6 10.2L12 2.5M10.4 10.2L4 2.5"/>'),
    outdent: icon('<path d="M2.5 3h11M7 6.5h6.5M7 9.5h6.5M2.5 13h11"/><path d="M5 5.8L2.4 8 5 10.2z" fill="currentColor"/>'),
    poll: icon('<path d="M2.5 13.5h11"/><rect x="3" y="7" width="2.2" height="6"/><rect x="6.9" y="3" width="2.2" height="10"/><rect x="10.8" y="9" width="2.2" height="4"/>'),
};

function markActive(state, type) {
    const { from, $from, to, empty } = state.selection;
    if (empty) return !!type.isInSet(state.storedMarks || $from.marks());
    return state.doc.rangeHasMark(from, to, type);
}

// Toggle a link: remove it if the selection has one, otherwise prompt for a
// URL. With an empty selection, the URL itself is inserted as the link text.
function makeEditLink(schema, strings) {
    return function (state, dispatch, view) {
        const type = schema.marks.link;
        if (markActive(state, type)) {
            if (dispatch) toggleMark(type)(state, dispatch);
            return true;
        }
        if (!dispatch) return !state.selection.$from.parent.type.spec.code;
        linkDialog(strings).then((href) => {
            if (!href) return;
            const current = view.state;
            if (current.selection.empty) {
                const node = schema.text(href, [type.create({ href: href })]);
                view.dispatch(current.tr.replaceSelectionWith(node, false));
            } else {
                toggleMark(type, { href: href })(current, view.dispatch);
            }
            view.focus();
        });
        return true;
    };
}

// The page may supply its own image dialog (the entry form's upload-capable
// modal); otherwise fall back to a bare URL prompt.
function makeInsertImage(schema, strings, onImage) {
    return function (state, dispatch, view) {
        if (!dispatch) return true;
        if (onImage) {
            onImage();
            return true;
        }
        imageDialog(strings).then((values) => {
            if (!values || !values.src) return;
            const node = schema.nodes.image.create({ src: values.src, alt: values.alt });
            view.dispatch(view.state.tr.replaceSelectionWith(node, false));
            view.focus();
        });
        return true;
    };
}

function makeInsertUser(schema, strings) {
    return function (state, dispatch, view) {
        if (!dispatch) return true;
        userDialog(strings).then((values) => {
            if (!values || !values.name) return;
            const node = schema.nodes.user.create({
                name: values.name,
                site: values.site || "",
            });
            view.dispatch(view.state.tr.replaceSelectionWith(node, false));
            view.focus();
        });
        return true;
    };
}

// Embedded media (a video player's <iframe>, ...) is kept as an HTML block; the
// server turns it into a proper embed when the entry is posted.
function makeInsertEmbed(strings) {
    return function (state, dispatch, view) {
        if (!dispatch) return true;
        embedDialog(strings).then((code) => {
            if (code) insertRawBlock(view, code);
        });
        return true;
    };
}

// Polls are made on their own page (which also checks the poster's
// permissions); the code it gives back is pasted in and becomes a block.
function makeInsertPoll(pollUrl) {
    return function (state, dispatch) {
        if (dispatch) window.open(pollUrl, "_blank");
        return true;
    };
}

function insertHr(schema) {
    return function (state, dispatch) {
        if (dispatch)
            dispatch(
                state.tr.replaceSelectionWith(schema.nodes.horizontal_rule.create()).scrollIntoView()
            );
        return true;
    };
}

// Wrap the selection in a cut tag (or insert an empty one).
function makeInsertCut(schema) {
    return wrapIn(schema.nodes.cut);
}

// Options for the block-type select.
function blockOptions(schema, strings) {
    return [
        { value: "paragraph", label: strings.blockParagraph, type: schema.nodes.paragraph },
        ...[1, 2, 3, 4].map((level) => ({
            value: "heading" + level,
            label: strings.blockHeading + " " + level,
            type: schema.nodes.heading,
            attrs: { level: level },
        })),
        { value: "code_block", label: strings.blockCode, type: schema.nodes.code_block },
        { value: "html_block", label: strings.blockHtml, type: schema.nodes.html_block },
    ];
}

export function buildToolbar(schema, strings, pageOptions) {
    const options = pageOptions || {};
    const editLink = makeEditLink(schema, strings);

    const dom = document.createElement("div");
    dom.className = "dw-editor-toolbar";
    dom.setAttribute("role", "toolbar");
    dom.setAttribute("aria-label", strings.toolbarLabel);

    const updaters = [];
    let currentView = null;

    function addGroup() {
        const group = document.createElement("span");
        group.className = "dw-editor-toolbar-group";
        dom.appendChild(group);
        return group;
    }

    function addButton(group, spec) {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "dw-editor-button dw-editor-button-" + spec.name;
        btn.title = spec.title;
        btn.setAttribute("aria-label", spec.title);
        btn.innerHTML = spec.html;
        btn.addEventListener("mousedown", (e) => e.preventDefault()); // keep editor focus
        btn.addEventListener("click", (e) => {
            e.preventDefault();
            if (!currentView) return;
            spec.command(currentView.state, currentView.dispatch, currentView);
            currentView.focus();
        });
        group.appendChild(btn);

        updaters.push((view) => {
            btn.disabled = !spec.command(view.state, null, view);
            if (spec.active)
                btn.setAttribute("aria-pressed", spec.active(view.state) ? "true" : "false");
        });
    }

    // History
    let group = addGroup();
    addButton(group, { name: "undo", title: strings.undo, html: "&#8617;", command: undo });
    addButton(group, { name: "redo", title: strings.redo, html: "&#8618;", command: redo });

    // Block type
    group = addGroup();
    const blockChoices = blockOptions(schema, strings);
    const select = document.createElement("select");
    select.className = "dw-editor-blockselect";
    select.setAttribute("aria-label", strings.blockLabel);
    blockChoices.forEach((opt) => {
        const el = document.createElement("option");
        el.value = opt.value;
        el.textContent = opt.label;
        select.appendChild(el);
    });
    select.addEventListener("change", () => {
        if (!currentView) return;
        const opt = blockChoices.find((o) => o.value == select.value);
        if (opt) {
            setBlockType(opt.type, opt.attrs)(currentView.state, currentView.dispatch);
            currentView.focus();
        }
    });
    group.appendChild(select);

    updaters.push((view) => {
        const $from = view.state.selection.$from;
        const parent = $from.parent;
        let value = "paragraph";
        if (parent.type == schema.nodes.heading) value = "heading" + parent.attrs.level;
        else if (parent.type == schema.nodes.code_block) value = "code_block";
        else if (parent.type == schema.nodes.html_block) value = "html_block";
        select.value = value;
    });

    // Inline marks
    group = addGroup();
    [
        { name: "strong", title: strings.bold, html: "<strong>B</strong>", mark: schema.marks.strong },
        { name: "em", title: strings.italic, html: "<em>I</em>", mark: schema.marks.em },
        { name: "underline", title: strings.underline, html: "<u>U</u>", mark: schema.marks.underline },
        { name: "strike", title: strings.strike, html: "<s>S</s>", mark: schema.marks.strike },
        { name: "code", title: strings.codeMark, html: "&lt;/&gt;", mark: schema.marks.code },
    ].forEach((spec) => {
        addButton(group, {
            name: spec.name,
            title: spec.title,
            html: spec.html,
            command: toggleMark(spec.mark),
            active: (state) => markActive(state, spec.mark),
        });
    });

    // Insertions: link, image, user mention
    group = addGroup();
    addButton(group, {
        name: "link",
        title: strings.link,
        html: ICONS.link,
        command: editLink,
        active: (state) => markActive(state, schema.marks.link),
    });
    addButton(group, {
        name: "image",
        title: strings.image,
        html: ICONS.image,
        command: makeInsertImage(schema, strings, options.onImage),
    });
    addButton(group, {
        name: "user",
        title: strings.user,
        html: "@",
        command: makeInsertUser(schema, strings),
    });

    if (options.canEmbed)
        addButton(group, {
            name: "embed",
            title: strings.embed,
            html: ICONS.embed,
            command: makeInsertEmbed(strings),
        });
    if (options.pollUrl)
        addButton(group, {
            name: "poll",
            title: strings.poll,
            html: ICONS.poll,
            command: makeInsertPoll(options.pollUrl),
        });

    // Blocks: lists, quote, cut, hr, outdent
    group = addGroup();
    addButton(group, {
        name: "bullet-list",
        title: strings.bulletList,
        html: "&#8226;&#8210;",
        command: wrapInList(schema.nodes.bullet_list),
    });
    addButton(group, {
        name: "ordered-list",
        title: strings.orderedList,
        html: "1.&#8210;",
        command: wrapInList(schema.nodes.ordered_list),
    });
    addButton(group, {
        name: "blockquote",
        title: strings.blockquote,
        html: ICONS.quote,
        command: wrapIn(schema.nodes.blockquote),
    });
    addButton(group, {
        name: "cut",
        title: strings.cut,
        html: ICONS.cut,
        command: makeInsertCut(schema),
    });
    addButton(group, {
        name: "hr",
        title: strings.hr,
        html: "&#8213;",
        command: insertHr(schema),
    });
    addButton(group, {
        name: "lift",
        title: strings.outdent,
        html: ICONS.outdent,
        command: lift,
    });

    return {
        dom: dom,
        commands: { editLink: editLink },
        update(view) {
            currentView = view;
            updaters.forEach((fn) => fn(view));
        },
    };
}
