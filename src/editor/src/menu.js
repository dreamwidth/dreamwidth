// src/editor/src/menu.js
//
// The editor toolbar: a hand-rolled strip of buttons (no menu library).
// Button state refreshes on every editor update via update().
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { toggleMark, setBlockType, wrapIn } from "prosemirror-commands";
import { wrapInList } from "prosemirror-schema-list";
import { undo, redo } from "prosemirror-history";
import {
    addRowBefore,
    addRowAfter,
    addColumnBefore,
    addColumnAfter,
    deleteRow,
    deleteColumn,
    mergeCells,
    splitCell,
    toggleHeaderRow,
    toggleHeaderColumn,
    deleteTable,
} from "prosemirror-tables";
import {
    linkDialog,
    imageDialog,
    userDialog,
    embedDialog,
    textDialog,
    tableDialog,
} from "./dialogs.js";
import { insertRawBlock } from "./paste.js";
import {
    blockAlignment,
    setAlignment,
    indent,
    outdent,
    currentTextStyle,
    setTextStyle,
    setTextStyles,
    insertTable,
} from "./commands.js";
import { normalizeColor, normalizeFontSize } from "./style.js";

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
    indent: icon('<path d="M2.5 3h11M7 6.5h6.5M7 9.5h6.5M2.5 13h11"/><path d="M2.4 5.8L5 8 2.4 10.2z" fill="currentColor"/>'),
    alignLeft: icon('<path d="M2.5 3.5h11M2.5 6.5h7M2.5 9.5h11M2.5 12.5h7"/>'),
    alignCenter: icon('<path d="M2.5 3.5h11M4.5 6.5h7M2.5 9.5h11M4.5 12.5h7"/>'),
    alignRight: icon('<path d="M2.5 3.5h11M6.5 6.5h7M2.5 9.5h11M6.5 12.5h7"/>'),
    alignJustify: icon('<path d="M2.5 3.5h11M2.5 6.5h11M2.5 9.5h11M2.5 12.5h11"/>'),
    table: icon('<rect x="1.8" y="2.5" width="12.4" height="11" rx="1"/><path d="M1.8 6.2h12.4M1.8 9.9h12.4M6 2.5v11M10 2.5v11"/>'),
    textColor: icon('<path d="M4.5 11L8 2.5 11.5 11M5.7 8h4.6"/>'),
    highlight: icon('<path d="M9.8 2.6l3.6 3.6-5.6 5.6H4.2V8.2z"/><path d="M6.4 6l3.6 3.6"/>'),
    removeColor: icon('<path d="M4.5 11L8 2.5 11.5 11M5.7 8h4.6"/><path d="M2.5 2.5l11 11"/>'),
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

function makeInsertTable(schema, strings) {
    return function (state, dispatch, view) {
        const insert = insertTable(schema, 1, 1);
        if (!dispatch) return insert(state);
        tableDialog(strings).then((size) => {
            if (!size) return;
            insertTable(schema, size.rows, size.cols)(view.state, view.dispatch);
            view.focus();
        });
        return true;
    };
}

// The text-size menu's preset sizes.
const FONT_SIZES = [
    "10px",
    "12px",
    "14px",
    "16px",
    "18px",
    "20px",
    "24px",
    "28px",
    "32px",
    "40px",
    "48px",
];

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

    // A color control: a button-sized native color picker. Picking a color
    // applies it to the selection (or to what's typed next).
    function addColorPicker(group, spec) {
        const wrap = document.createElement("span");
        wrap.className = "dw-editor-button dw-editor-color dw-editor-button-" + spec.name;
        wrap.title = spec.title;
        wrap.innerHTML = spec.html;
        const bar = document.createElement("span");
        bar.className = "dw-editor-color-bar";
        wrap.appendChild(bar);
        const input = document.createElement("input");
        input.type = "color";
        input.setAttribute("aria-label", spec.title);
        wrap.appendChild(input);
        input.addEventListener("change", () => {
            if (!currentView) return;
            const value = normalizeColor(input.value);
            if (value)
                setTextStyle(schema, spec.attr, value)(currentView.state, currentView.dispatch);
            currentView.focus();
        });
        group.appendChild(wrap);

        updaters.push((view) => {
            const enabled = setTextStyle(schema, spec.attr, null)(view.state, null);
            input.disabled = !enabled;
            wrap.classList.toggle("dw-editor-disabled", !enabled);
            const current = currentTextStyle(view.state, schema)[spec.attr];
            bar.style.backgroundColor = current || "";
            const hex = normalizeColor(current);
            if (hex) input.value = hex;
        });
    }

    // The text-size menu: preset sizes, "other size" (typed in), and default.
    function addFontSize(group) {
        const sizeSelect = document.createElement("select");
        sizeSelect.className = "dw-editor-sizeselect";
        sizeSelect.setAttribute("aria-label", strings.fontSize);
        sizeSelect.title = strings.fontSize;
        const option = (value, label) => {
            const el = document.createElement("option");
            el.value = value;
            el.textContent = label;
            sizeSelect.appendChild(el);
            return el;
        };
        option("", strings.fontSize);
        // Shows a size that isn't one of the presets (from an old entry, or
        // typed in) while the cursor is in it.
        const other = option("current", "");
        other.hidden = true;
        FONT_SIZES.forEach((size) => option(size, size));
        option("custom", strings.fontSizeCustom);
        option("default", strings.fontSizeDefault);

        const apply = (value) => {
            setTextStyle(schema, "fontSize", value)(currentView.state, currentView.dispatch);
            currentView.focus();
        };
        sizeSelect.addEventListener("change", () => {
            if (!currentView) return;
            const choice = sizeSelect.value;
            if (choice == "custom") {
                const view = currentView;
                textDialog(strings.fontSizeCustomTitle, strings, "").then((text) => {
                    if (text == null || !text.trim()) return view.focus();
                    const size = normalizeFontSize(text);
                    if (!size) {
                        window.alert(strings.fontSizeInvalid);
                        return view.focus();
                    }
                    apply(size);
                });
            } else if (choice == "default") {
                apply(null);
            } else if (choice && choice != "current") {
                apply(choice);
            }
            if (currentView) toolbarUpdate(currentView);
        });
        group.appendChild(sizeSelect);

        updaters.push((view) => {
            sizeSelect.disabled = !setTextStyle(schema, "fontSize", null)(view.state, null);
            const current = currentTextStyle(view.state, schema).fontSize;
            other.hidden = true;
            if (!current) {
                sizeSelect.value = "";
            } else if (FONT_SIZES.indexOf(current) >= 0) {
                sizeSelect.value = current;
            } else {
                other.textContent = current;
                other.hidden = false;
                sizeSelect.value = "current";
            }
        });
    }

    // A toolbar button that opens a small menu of commands (alignment,
    // tables), so a family of related commands takes one slot in the
    // toolbar. spec.icon(state) gives the button's icon; each item is
    // { label, icon?, command, checked?(state) } or "separator".
    function addDropdown(group, spec) {
        const wrap = document.createElement("span");
        wrap.className = "dw-editor-dropdown dw-editor-dropdown-" + spec.name;

        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "dw-editor-button dw-editor-dropdown-button";
        btn.title = spec.title;
        btn.setAttribute("aria-label", spec.title);
        btn.setAttribute("aria-haspopup", "menu");
        btn.setAttribute("aria-expanded", "false");
        const face = document.createElement("span");
        face.className = "dw-editor-dropdown-face";
        btn.appendChild(face);
        const caret = document.createElement("span");
        caret.className = "dw-editor-dropdown-caret";
        caret.setAttribute("aria-hidden", "true");
        btn.appendChild(caret);
        wrap.appendChild(btn);

        const popup = document.createElement("div");
        popup.className = "dw-editor-dropdown-menu";
        popup.setAttribute("role", "menu");
        popup.hidden = true;
        wrap.appendChild(popup);

        const items = spec.items.map((item) => {
            if (item == "separator") {
                const hr = document.createElement("div");
                hr.className = "dw-editor-dropdown-separator";
                hr.setAttribute("role", "separator");
                popup.appendChild(hr);
                return null;
            }
            const el = document.createElement("button");
            el.type = "button";
            el.className = "dw-editor-dropdown-item";
            el.setAttribute("role", item.checked ? "menuitemradio" : "menuitem");
            el.innerHTML = (item.icon || "") + "<span></span>";
            el.lastChild.textContent = item.label;
            el.addEventListener("mousedown", (e) => e.preventDefault());
            el.addEventListener("click", (e) => {
                e.preventDefault();
                close();
                if (!currentView) return;
                item.command(currentView.state, currentView.dispatch, currentView);
                currentView.focus();
            });
            popup.appendChild(el);
            return { el, item };
        });

        function onOutside(e) {
            if (!wrap.contains(e.target)) close();
        }
        function open() {
            if (currentView) toolbarUpdate(currentView);
            popup.hidden = false;
            btn.setAttribute("aria-expanded", "true");
            document.addEventListener("mousedown", onOutside, true);
            const first = items.find((entry) => entry && !entry.el.disabled);
            if (first) first.el.focus();
        }
        function close() {
            popup.hidden = true;
            btn.setAttribute("aria-expanded", "false");
            document.removeEventListener("mousedown", onOutside, true);
        }

        btn.addEventListener("mousedown", (e) => e.preventDefault());
        btn.addEventListener("click", (e) => {
            e.preventDefault();
            if (popup.hidden) open();
            else close();
        });
        // Escape closes; arrow keys move through the enabled items.
        popup.addEventListener("keydown", (e) => {
            const enabled = items.filter((entry) => entry && !entry.el.disabled);
            const at = enabled.findIndex((entry) => entry.el == document.activeElement);
            if (e.key == "Escape") {
                e.preventDefault();
                close();
                btn.focus();
            } else if ((e.key == "ArrowDown" || e.key == "ArrowUp") && enabled.length) {
                e.preventDefault();
                const step = e.key == "ArrowDown" ? 1 : -1;
                enabled[(at + step + enabled.length) % enabled.length].el.focus();
            }
        });
        group.appendChild(wrap);

        updaters.push((view) => {
            face.innerHTML = spec.icon(view.state);
            let any = false;
            items.forEach((entry) => {
                if (!entry) return;
                entry.el.disabled = !entry.item.command(view.state, null, view);
                if (!entry.el.disabled) any = true;
                if (entry.item.checked)
                    entry.el.setAttribute(
                        "aria-checked",
                        entry.item.checked(view.state) ? "true" : "false"
                    );
            });
            btn.disabled = !any;
            if (!any) close();
        });
    }

    function toolbarUpdate(view) {
        updaters.forEach((fn) => fn(view));
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

    // Text color, highlight, size
    group = addGroup();
    addColorPicker(group, {
        name: "text-color",
        title: strings.textColor,
        html: ICONS.textColor,
        attr: "color",
    });
    addColorPicker(group, {
        name: "highlight",
        title: strings.highlight,
        html: ICONS.highlight,
        attr: "background",
    });
    addButton(group, {
        name: "remove-color",
        title: strings.removeColor,
        html: ICONS.removeColor,
        command: setTextStyles(schema, { color: null, background: null }),
    });
    addFontSize(group);

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
    // Tables: insert one, and edit the one the cursor is in
    addDropdown(group, {
        name: "table",
        title: strings.tableMenu,
        icon: () => ICONS.table,
        items: [
            { label: strings.table, command: makeInsertTable(schema, strings) },
            "separator",
            { label: strings.tableRowBefore, command: addRowBefore },
            { label: strings.tableRowAfter, command: addRowAfter },
            { label: strings.tableColBefore, command: addColumnBefore },
            { label: strings.tableColAfter, command: addColumnAfter },
            { label: strings.tableDeleteRow, command: deleteRow },
            { label: strings.tableDeleteCol, command: deleteColumn },
            "separator",
            { label: strings.tableMerge, command: mergeCells },
            { label: strings.tableSplit, command: splitCell },
            { label: strings.tableHeaderRow, command: toggleHeaderRow },
            { label: strings.tableHeaderCol, command: toggleHeaderColumn },
            "separator",
            { label: strings.tableDelete, command: deleteTable },
        ],
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
        name: "outdent",
        title: strings.outdent,
        html: ICONS.outdent,
        command: outdent(schema),
    });
    addButton(group, {
        name: "indent",
        title: strings.indent,
        html: ICONS.indent,
        command: indent(schema),
    });

    // Alignment, as one button showing the current alignment
    group = addGroup();
    const alignments = [
        { value: "left", label: strings.alignLeft, icon: ICONS.alignLeft },
        { value: "center", label: strings.alignCenter, icon: ICONS.alignCenter },
        { value: "right", label: strings.alignRight, icon: ICONS.alignRight },
        { value: "justify", label: strings.alignJustify, icon: ICONS.alignJustify },
    ];
    addDropdown(group, {
        name: "align",
        title: strings.alignLabel,
        icon: (state) => {
            const current = alignments.find((a) => a.value == blockAlignment(state));
            return (current || alignments[0]).icon;
        },
        items: alignments.map((a) => ({
            label: a.label,
            icon: a.icon,
            command: setAlignment(a.value),
            checked: (state) => blockAlignment(state) == a.value,
        })),
    });

    // Keep the toolbar to one row: groups that don't fit move, from the end,
    // into a "More" panel, and come back out when there's room again.
    const more = document.createElement("span");
    more.className = "dw-editor-more";
    const moreBtn = document.createElement("button");
    moreBtn.type = "button";
    moreBtn.className = "dw-editor-button dw-editor-more-button";
    moreBtn.title = strings.more;
    moreBtn.setAttribute("aria-label", strings.more);
    moreBtn.setAttribute("aria-haspopup", "true");
    moreBtn.setAttribute("aria-expanded", "false");
    moreBtn.innerHTML = "&#8943;";
    const morePanel = document.createElement("div");
    morePanel.className = "dw-editor-more-panel";
    morePanel.hidden = true;
    more.appendChild(moreBtn);
    more.appendChild(morePanel);
    dom.appendChild(more);

    const groups = Array.from(dom.children).filter((el) =>
        el.classList.contains("dw-editor-toolbar-group")
    );

    function onOutsideMore(e) {
        if (!more.contains(e.target)) closeMore();
    }
    function closeMore() {
        morePanel.hidden = true;
        moreBtn.setAttribute("aria-expanded", "false");
        document.removeEventListener("mousedown", onOutsideMore, true);
    }
    moreBtn.addEventListener("mousedown", (e) => e.preventDefault());
    moreBtn.addEventListener("click", (e) => {
        e.preventDefault();
        if (!morePanel.hidden) return closeMore();
        morePanel.hidden = false;
        moreBtn.setAttribute("aria-expanded", "true");
        document.addEventListener("mousedown", onOutsideMore, true);
    });
    morePanel.addEventListener("keydown", (e) => {
        if (e.key != "Escape" || e.defaultPrevented) return;
        closeMore();
        moreBtn.focus();
    });

    // Measured from the groups themselves: an open menu hanging past the
    // edge mustn't count.
    function overflows() {
        const inBar = groups.filter((g) => g.parentNode == dom);
        if (!inBar.length) return false;
        const box = dom.getBoundingClientRect();
        const pad = parseFloat(window.getComputedStyle(dom).paddingRight) || 0;
        const moreWidth = more.hidden ? 0 : more.getBoundingClientRect().width + 2;
        return inBar[inBar.length - 1].getBoundingClientRect().right > box.right - pad - moreWidth + 0.5;
    }
    function layout() {
        groups.forEach((g) => dom.insertBefore(g, more));
        more.hidden = true;
        if (!overflows()) return closeMore();
        more.hidden = false;
        for (let i = groups.length - 1; i > 1 && overflows(); i--)
            morePanel.insertBefore(groups[i], morePanel.firstChild);
    }
    if (typeof ResizeObserver == "function") new ResizeObserver(() => layout()).observe(dom);

    return {
        dom: dom,
        commands: { editLink: editLink },
        update(view) {
            currentView = view;
            toolbarUpdate(view);
        },
    };
}
