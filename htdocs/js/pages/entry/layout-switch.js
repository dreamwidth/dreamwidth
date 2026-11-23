// Switching between the advanced and simple entry form layouts reloads the
// page, so confirm first if the poster has changed anything.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
(function ($) {
    "use strict";
    $(function () {
        var form = document.getElementById("js-post-entry");
        var $links = $("a.js-layout-switch");
        if (!form || !$links.length) return;

        // Only count changes the poster makes; form setup also fires events.
        var dirty = false;
        var mark = function (e) { if (e.isTrusted) dirty = true; };
        form.addEventListener("input", mark, true);
        form.addEventListener("change", mark, true);

        var richTextDirty = function () {
            if (typeof FCKeditorAPI === "undefined") return false;
            var editor = FCKeditorAPI.GetInstance("entry-body");
            return !!(editor && editor.IsDirty && editor.IsDirty());
        };

        $links.on("click", function (e) {
            if ((dirty || richTextDirty()) && !window.confirm($(this).data("confirm"))) {
                e.preventDefault();
            }
        });
    });
}(jQuery));
