// Switching between the advanced and simple entry form layouts reloads the
// page, so confirm first if the poster has changed anything, and remembers
// the choice.
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

        // Remember the chosen layout for links from the retired pages. A beacon
        // is still delivered after the page has navigated away; if the browser
        // won't queue one, save first and then follow the link.
        var saveLayout = function (e, link) {
            var layout = $(link).data("layout");
            var auth = form.elements.lj_form_auth;
            if (!layout || !auth) return;

            // URL-encoded: the server does not parse multipart RPC posts
            var data = new URLSearchParams({ layout: layout, lj_form_auth: auth.value });
            var url = Site.siteroot + "/__rpc_entryformlayout";
            if (navigator.sendBeacon && navigator.sendBeacon(url, data)) return;

            e.preventDefault();
            $.post(url, data.toString()).always(function () {
                window.location.href = link.href;
            });
        };

        $links.on("click", function (e) {
            if ((dirty || richTextDirty()) && !window.confirm($(this).data("confirm"))) {
                e.preventDefault();
                return;
            }
            saveLayout(e, this);
        });
    });
}(jQuery));
