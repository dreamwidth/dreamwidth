// Small form dialogs built on the native <dialog> element. Each returns a
// Promise resolving to the entered values, or null if cancelled.

function buildDialog(title, fields, strings) {
    const dialog = document.createElement("dialog");
    dialog.className = "dw-editor-dialog";

    const form = document.createElement("form");
    form.method = "dialog";

    const heading = document.createElement("h3");
    heading.textContent = title;
    form.appendChild(heading);

    const inputs = {};
    fields.forEach((field) => {
        const label = document.createElement("label");
        label.textContent = field.label;
        const input = document.createElement("input");
        input.type = "text";
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
        const first = fields.find((f) => !f.value);
        if (first) inputs[first.name].focus();
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
