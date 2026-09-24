// Native plain-editor image URL insertion.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
// Native plain-editor image URL insertion.
(function () {
    "use strict";
    document.addEventListener("DOMContentLoaded", function () {
        var body = document.getElementById("entry-body");
        var editor = document.getElementById("editor");
        var panel = document.querySelector("[data-image-insert]");
        var open = document.querySelector("[data-image-insert-open]");
        if (!body || !editor || !panel || !open) return;
        var url = document.getElementById("entry-image-url");
        var alt = document.getElementById("entry-image-alt");
        var plain = function () { return editor.value !== "rte0"; };
        var sync = function () { open.hidden = !plain(); if (!plain()) panel.hidden = true; };
        open.addEventListener("click", function () { panel.hidden = false; url.focus(); });
        panel.querySelector("[data-image-insert-cancel]").addEventListener("click", function () { panel.hidden = true; body.focus(); });
        panel.querySelector("[data-image-insert-confirm]").addEventListener("click", function () {
            var src = url.value; if (!src) return url.focus();
            var escape = function (value) { return value.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;"); };
            var markup = '<img src="' + escape(src) + '"' + (alt.value ? ' alt="' + escape(alt.value) + '"' : '') + '>';
            var start = body.selectionStart, end = body.selectionEnd;
            body.setRangeText(markup, start, end, "end"); body.dispatchEvent(new Event("input", { bubbles: true }));
            panel.hidden = true; body.focus();
        });
        panel.addEventListener("keydown", function (event) {
            if (event.key === "Enter" && (event.target === url || event.target === alt)) {
                event.preventDefault();
                panel.querySelector("[data-image-insert-confirm]").click();
            }
        });
        editor.addEventListener("change", sync); sync();
    });
}());
