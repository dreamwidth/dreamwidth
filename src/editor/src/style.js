// Reading and writing inline CSS (style="...") for the formatting the toolbar
// sets: text colour, highlight, font size, alignment and indent.
//
// A style attribute is handled as an ordered list of [property, value]
// declarations, so the declarations the toolbar doesn't touch (an old entry's
// border, padding, font-family, ...) come back out in the order they were in.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

// Split a style attribute into declarations. Semicolons inside quotes or
// parentheses (url(...;...)) don't end a declaration. Returns null if the text
// isn't plain "prop: value; ..." (an unbalanced quote, a declaration without a
// colon), so callers can leave anything odd alone.
export function parseStyle(text) {
    const decls = [];
    let current = "";
    let quote = null;
    let depth = 0;
    const flush = () => {
        const part = current.trim();
        current = "";
        if (!part) return true;
        const colon = part.indexOf(":");
        if (colon <= 0) return false;
        const prop = part.slice(0, colon).trim().toLowerCase();
        const value = part.slice(colon + 1).trim();
        if (!/^-?[a-z][a-z-]*$/.test(prop) || !value) return false;
        decls.push([prop, value]);
        return true;
    };
    const src = String(text || "");
    for (let i = 0; i < src.length; i++) {
        const ch = src[i];
        if (quote) {
            if (ch == quote) quote = null;
        } else if (ch == '"' || ch == "'") {
            quote = ch;
        } else if (ch == "(") {
            depth++;
        } else if (ch == ")") {
            if (depth) depth--;
        } else if (ch == ";" && !depth) {
            if (!flush()) return null;
            continue;
        }
        current += ch;
    }
    if (quote || depth) return null;
    if (!flush()) return null;
    return decls;
}

export function formatStyle(decls) {
    return decls.map(([prop, value]) => prop + ": " + value + ";").join(" ");
}

export function getStyleProp(decls, prop) {
    for (let i = decls.length - 1; i >= 0; i--) if (decls[i][0] == prop) return decls[i][1];
    return null;
}

// A copy of decls with prop set to value (or removed, for a null value). The
// first declaration of prop keeps its place; any repeats are dropped.
export function setStyleProp(decls, prop, value) {
    const out = [];
    let placed = false;
    decls.forEach((decl) => {
        if (decl[0] != prop) return out.push(decl);
        if (!placed && value != null) out.push([prop, value]);
        placed = true;
    });
    if (!placed && value != null) out.push([prop, value]);
    return out;
}

// Change one style property inside a node's preserved attributes (`extra`).
// Returns the new extra object (null when nothing is left), or undefined if
// the existing style attribute can't be safely edited.
export function extraWithStyle(extra, prop, value, alsoRemove) {
    const attrs = Object.assign({}, extra || {});
    const decls = parseStyle(attrs.style);
    if (!decls) return undefined;
    const next = setStyleProp(decls, prop, value);
    if (next.length) attrs.style = formatStyle(next);
    else delete attrs.style;
    (alsoRemove || []).forEach((name) => delete attrs[name]);
    return Object.keys(attrs).length ? attrs : null;
}

export function styleOfExtra(extra) {
    return (extra && parseStyle(extra.style)) || [];
}

// The properties the text-style mark models. A <span style="..."> made of only
// these becomes that mark (editable from the toolbar); anything else stays a
// generic span.
export const TEXT_STYLE_PROPS = {
    color: "color",
    "background-color": "background",
    "font-size": "fontSize",
};

// Values a person can type for a font size: a number with a CSS unit, or one
// of the size keywords. Kept to these so the style the cleaner sees is plain.
const SIZE_KEYWORDS = [
    "xx-small",
    "x-small",
    "small",
    "medium",
    "large",
    "x-large",
    "xx-large",
    "smaller",
    "larger",
];

export function normalizeFontSize(text) {
    const value = String(text || "")
        .trim()
        .toLowerCase();
    if (SIZE_KEYWORDS.indexOf(value) >= 0) return value;
    const m = /^(\d{1,4}(?:\.\d{1,3})?)\s*(px|pt|em|rem|%)?$/.exec(value);
    if (!m || +m[1] == 0) return null;
    return m[1] + (m[2] || "px");
}

// Colours come from the browser's colour picker, which always gives #rrggbb.
export function normalizeColor(text) {
    const value = String(text || "").trim();
    return /^#[0-9a-fA-F]{6}$/.test(value) ? value.toLowerCase() : null;
}
