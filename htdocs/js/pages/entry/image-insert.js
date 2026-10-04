// Native plain-editor image insertion dialog (a Foundation reveal modal).
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
(function ($) {
    "use strict";
    $(function () {
        var body = document.getElementById("entry-body");
        var editor = document.getElementById("editor");
        var $modal = $("#js-image-insert");
        var open = document.querySelector("[data-image-insert-open]");
        if (!body || !editor || !$modal.length || !open) return;
        var url = document.getElementById("entry-image-url");
        var alt = document.getElementById("entry-image-alt");

        var plain = function () { return editor.value !== "rte0"; };
        var close = function () { $modal.foundation("reveal", "close"); };
        var sync = function () {
            open.hidden = !plain();
            if (!plain() && $modal.hasClass("open")) close();
        };

        // Open from JS so the first call also initialises Foundation's reveal
        // handlers; start each visit with empty fields.
        $(open).on("click", function () {
            url.value = "";
            alt.value = "";
            $modal.foundation("reveal", "open");
        });

        $modal.find("[data-image-insert-cancel]").on("click", close);
        $modal.find("[data-image-insert-confirm]").on("click", function () {
            var src = url.value;
            if (!src) { url.focus(); return; }
            var escape = function (value) {
                return value.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
            };
            var markup = '<img src="' + escape(src) + '"' + (alt.value ? ' alt="' + escape(alt.value) + '"' : '') + '>';
            var start = body.selectionStart, end = body.selectionEnd;
            body.setRangeText(markup, start, end, "end");
            body.dispatchEvent(new Event("input", { bubbles: true }));
            close();
        });
        $modal.on("keydown", function (event) {
            if (event.key === "Enter" && (event.target === url || event.target === alt)) {
                event.preventDefault();
                $modal.find("[data-image-insert-confirm]").click();
            }
        });
        $(editor).on("change", sync); sync();
    });
}(jQuery));
