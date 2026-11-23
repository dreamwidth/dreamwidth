// Native image insertion dialog (a Foundation reveal modal). Inserts into the
// rich text editor when it is mounted, otherwise into the plain textarea.
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

        var rich = function () { return !!(window.DWEditor && DWEditor.isActive("entry-body")); };
        var close = function () { $modal.foundation("reveal", "close"); };

        // Open from JS so the first call also initialises Foundation's reveal
        // handlers; start each visit with empty fields.
        var openModal = function () {
            // The body is being converted; it can't take an image right now.
            if (window.DWConvert && DWConvert.busy()) return;
            url.value = "";
            alt.value = "";
            $modal.foundation("reveal", "open");
        };
        $(open).on("click", function (event) {
            event.preventDefault();
            openModal();
        });

        // The rich editor's toolbar button opens the same dialog.
        window.DWImageInsert = { open: openModal };

        $modal.find("[data-image-insert-cancel]").on("click", close);
        $modal.find("[data-image-insert-confirm]").on("click", function () {
            var src = url.value;
            if (!src) { url.focus(); return; }
            if (window.DWConvert && DWConvert.busy()) { close(); return; }
            if (rich()) {
                DWEditor.insertImage("entry-body", { src: src, alt: alt.value });
                close();
                return;
            }
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
    });
}(jQuery));
