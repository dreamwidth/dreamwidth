// Simple mode of the entry form: presentation-only behaviour on top of the
// shared entry form scripts (new.js, editor.js, drafts.js, image-insert.js).
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
(function ($) {
    "use strict";

    function zeropad(num) { return num < 10 ? "0" + num : "" + num; }

    $(function () {
        var $form = $("#js-post-entry.entry-simple");
        if (!$form.length) return;

        // Rich Text / HTML tabs drive the shared format select; editor.js reacts
        // to its change event exactly as it does on the advanced form. It
        // listens natively, so a jQuery-triggered event would not reach it.
        var $editor = $("#editor");
        var setEditor = function (value) {
            $editor.val(value);
            $editor[0].dispatchEvent(new Event("change", { bubbles: true }));
        };
        // The HTML tab edits explicit HTML, so raw HTML is its default.
        var lastPlain = $editor.val() !== "rte1" ? $editor.val()
            : $editor.find("option[value='html_raw0']").length ? "html_raw0"
            : $editor.find("option:not([value='rte1'])").first().val();
        var syncTabs = function () {
            var rich = $editor.val() === "rte1";
            $("#jrich").toggleClass("on", rich);
            $("#jplain").toggleClass("on", !rich);
            $("#htmltools").toggle(!rich);
            if (!rich) lastPlain = $editor.val();
        };
        $("#jrich a").on("click", function (e) {
            e.preventDefault();
            if ($editor.val() === "rte1") return;
            setEditor("rte1");
        });
        $("#jplain a").on("click", function (e) {
            e.preventDefault();
            if ($editor.val() !== "rte1") return;
            setEditor(lastPlain);
        });
        $editor.on("change", syncTabs);
        syncTabs();

        // Show the date as text until the poster asks to edit it.
        var showDateInputs = function () {
            $("#currentdate").hide();
            $("#modifydate").show();
        };
        $("#currentdate-edit").on("click", function (e) {
            e.preventDefault();
            showDateInputs();
        });
        if ($("#js-entrytime-outoforder").is(":checked")) showDateInputs();

        // The shared date code may reset the fields to now; mirror them.
        var months = [ "January", "February", "March", "April", "May", "June", "July",
            "August", "September", "October", "November", "December" ];
        var showDate = function () {
            var d = ($("#js-entrytime-date").val() || "").split("-");
            var t = $("#js-entrytime-time").val() || "";
            if (d.length !== 3 || !months[parseInt(d[1], 10) - 1]) return;
            $("#currentdate-date").text(months[parseInt(d[1], 10) - 1] + " "
                + parseInt(d[2], 10) + ", " + d[0] + ", " + t);
        };
        $("#js-entrytime-date, #js-entrytime-time").on("change", showDate);
        showDate();

        $("#js-update-date").on("click", function () {
            var now = new Date();
            $("#js-entrytime-date").val([ now.getFullYear(), zeropad(now.getMonth() + 1),
                zeropad(now.getDate()) ].join("-")).trigger("change");
            $("#js-entrytime-time").val(zeropad(now.getHours()) + ":" + zeropad(now.getMinutes()))
                .trigger("change");
            $("#js-trust-datetime").val(1);
            showDateInputs();
        });

        // Keep "Post to: journal" naming the selected journal.
        var $post = $("#js-post-button");
        $("#js-usejournal").on("change input", function () {
            var $journal = $(this);
            var name = $journal.is("select") ? $journal.find("option:selected").text() : $journal.val();
            name = name || $("#js-remote").val();
            $post.val(name ? $post.data("label-prefix") + " " + name : $post.data("label-default"));
        });

        // The shared security code opens the custom-groups dialog on change;
        // offer a way back into it while "Custom" stays selected.
        var $customEdit = $("#js-custom-groups-edit");
        $("#js-security").on("change", function () {
            $customEdit.toggle($(this).val() === "custom");
        }).triggerHandler("change");
    });
}(jQuery));
