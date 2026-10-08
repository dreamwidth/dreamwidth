// The editor toolbar: a hand-rolled strip of buttons (no menu library).
// Button state refreshes on every editor update via update().

import { toggleMark, setBlockType, wrapIn, lift } from "prosemirror-commands";
import { wrapInList } from "prosemirror-schema-list";
import { undo, redo } from "prosemirror-history";
import { linkDialog, imageDialog, userDialog } from "./dialogs.js";

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

function makeInsertImage(schema, strings) {
    return function (state, dispatch, view) {
        if (!dispatch) return true;
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

export function buildToolbar(schema, strings) {
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
    const options = blockOptions(schema, strings);
    const select = document.createElement("select");
    select.className = "dw-editor-blockselect";
    select.setAttribute("aria-label", strings.blockLabel);
    options.forEach((opt) => {
        const el = document.createElement("option");
        el.value = opt.value;
        el.textContent = opt.label;
        select.appendChild(el);
    });
    select.addEventListener("change", () => {
        if (!currentView) return;
        const opt = options.find((o) => o.value == select.value);
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
        html: "&#128279;",
        command: editLink,
        active: (state) => markActive(state, schema.marks.link),
    });
    addButton(group, {
        name: "image",
        title: strings.image,
        html: "&#128247;",
        command: makeInsertImage(schema, strings),
    });
    addButton(group, {
        name: "user",
        title: strings.user,
        html: "@",
        command: makeInsertUser(schema, strings),
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
        html: "&#10078;",
        command: wrapIn(schema.nodes.blockquote),
    });
    addButton(group, {
        name: "cut",
        title: strings.cut,
        html: "&#9986;",
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
        html: "&#8612;",
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
