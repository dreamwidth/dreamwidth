// src/editor/src/dialogs.js
//
// Small form dialogs built on the native <dialog> element. Each returns a
// Promise resolving to the entered values, or null if cancelled.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

let dialogCount = 0;

function buildDialog(title, fields, strings) {
    const dialog = document.createElement("dialog");
    dialog.className = "dw-editor-dialog";

    const form = document.createElement("form");
    form.method = "dialog";

    // The heading names the dialog for screen readers.
    const heading = document.createElement("h3");
    heading.id = "dw-editor-dialog-title-" + ++dialogCount;
    heading.textContent = title;
    dialog.setAttribute("aria-labelledby", heading.id);
    form.appendChild(heading);

    const inputs = {};
    fields.forEach((field) => {
        const label = document.createElement("label");
        label.textContent = field.label;
        const input = document.createElement(field.multiline ? "textarea" : "input");
        if (field.multiline) input.rows = 5;
        else input.type = field.type || "text";
        if (field.min != null) input.min = field.min;
        if (field.max != null) input.max = field.max;
        input.name = field.name;
        input.value = field.value || "";
        if (field.placeholder) input.placeholder = field.placeholder;
        if (field.required) input.required = true;
        label.appendChild(input);
        form.appendChild(label);
        inputs[field.name] = input;
    });

    const buttons = document.createElement("div");
    buttons.className = "dw-editor-dialog-buttons";

    const cancel = document.createElement("button");
    cancel.type = "button";
    cancel.textContent = strings.cancel;
    cancel.addEventListener("click", () => {
        dialog.returnValue = "";
        dialog.close();
    });

    const ok = document.createElement("button");
    ok.type = "submit";
    ok.value = "ok";
    ok.className = "dw-editor-dialog-ok";
    ok.textContent = strings.ok;

    buttons.appendChild(cancel);
    buttons.appendChild(ok);
    form.appendChild(buttons);
    dialog.appendChild(form);
    document.body.appendChild(dialog);

    // Older browsers have no <dialog>: there it's shown as a fixed box over a
    // backdrop, and does by hand what showModal and method="dialog" do --
    // which, left to such a browser, would submit the page's form instead.
    if (typeof dialog.showModal != "function") {
        const backdrop = document.createElement("div");
        backdrop.className = "dw-editor-dialog-backdrop";
        dialog.classList.add("dw-editor-dialog-fallback");
        dialog.setAttribute("role", "dialog");
        dialog.setAttribute("aria-modal", "true");
        dialog.returnValue = "";
        dialog.close = () => {
            if (!dialog.parentNode) return;
            backdrop.remove();
            dialog.dispatchEvent(new dialog.ownerDocument.defaultView.Event("close"));
        };
        dialog.showModal = () => {
            dialog.setAttribute("open", "");
            document.body.insertBefore(backdrop, dialog);
        };
        form.addEventListener("submit", (e) => {
            e.preventDefault();
            dialog.returnValue = "ok";
            dialog.close();
        });
        dialog.addEventListener("keydown", (e) => {
            if (e.key != "Escape" && e.key != "Esc") return;
            e.preventDefault();
            dialog.returnValue = "";
            dialog.close();
        });
    }

    return new Promise((resolve) => {
        dialog.addEventListener("close", () => {
            const values = {};
            Object.keys(inputs).forEach((name) => {
                values[name] = inputs[name].value.trim();
            });
            dialog.remove();
            resolve(dialog.returnValue == "ok" ? values : null);
        });
        dialog.showModal();
        // Without a real modal dialog, the editor takes the focus back once
        // the toolbar click is done; so focus the field after that.
        const first = fields.find((f) => !f.value) || fields[0];
        const focus = () => first && inputs[first.name].focus();
        focus();
        if (dialog.classList.contains("dw-editor-dialog-fallback")) setTimeout(focus, 0);
    });
}

export function linkDialog(strings, href) {
    return buildDialog(
        strings.linkTitle,
        [{ name: "href", label: strings.linkUrl, value: href, required: true }],
        strings
    ).then((values) => values && values.href);
}

export function imageDialog(strings) {
    return buildDialog(
        strings.imageTitle,
        [
            { name: "src", label: strings.imageUrl, required: true },
            { name: "alt", label: strings.imageAlt },
        ],
        strings
    );
}

export function userDialog(strings) {
    return buildDialog(
        strings.userTitle,
        [
            { name: "name", label: strings.userName, required: true },
            { name: "site", label: strings.userSite, placeholder: strings.userSiteHint },
        ],
        strings
    );
}

// Single-text-field prompt (used for cut captions).
export function textDialog(title, strings, value) {
    return buildDialog(title, [{ name: "text", label: title, value: value }], strings).then(
        (values) => (values ? values.text : null)
    );
}

// Media embed code (an <iframe>, <object>, ...). Resolves to the pasted code.
export function embedDialog(strings) {
    return buildDialog(
        strings.embedTitle,
        [{ name: "code", label: strings.embedCode, required: true, multiline: true }],
        strings
    ).then((values) => values && values.code);
}

// Size of a new table. Resolves to { rows, cols } as numbers.
export function tableDialog(strings) {
    return buildDialog(
        strings.tableTitle,
        [
            { name: "rows", label: strings.tableRows, value: "3", type: "number", min: 1, max: 50 },
            { name: "cols", label: strings.tableCols, value: "3", type: "number", min: 1, max: 20 },
        ],
        strings
    ).then((values) => {
        if (!values) return null;
        const rows = Math.min(50, Math.max(1, parseInt(values.rows, 10) || 0));
        const cols = Math.min(20, Math.max(1, parseInt(values.cols, 10) || 0));
        return { rows, cols };
    });
}
