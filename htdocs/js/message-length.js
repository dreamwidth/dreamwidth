// htdocs/js/message-length.js
//
// Warn before sending an overlong private message, without discarding text.
//
// Authors:
//      SAPHID <saphid@users.noreply.github.com>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

(function () {
    "use strict";

    function initialize() {
        const body = document.querySelector("textarea[data-message-limit]");
        const warning = document.querySelector("#msg_body_warning strong");
        if (!body || !warning) return;

        const limit = Number(body.dataset.messageLimit);
        const message = body.dataset.messageWarning;
        if (!Number.isFinite(limit) || limit < 0 || !message) return;

        function update() {
            // HTML forms submit CRLF line endings. Count Unicode code points,
            // as LJ::text_length does, rather than JavaScript's UTF-16 units.
            const submitted = body.value.replace(/\r\n|\r|\n/g, "\r\n");
            const tooLong = Array.from(submitted).length > limit;
            const text = tooLong ? message : "";

            // Announce only crossing the limit, not every subsequent keystroke.
            if (warning.textContent !== text) warning.textContent = text;
            body.setCustomValidity(text);
        }

        body.addEventListener("input", update);
        body.addEventListener("change", update);
        window.addEventListener("pageshow", update);
        body.form.addEventListener("reset", function () {
            // The reset event runs before the textarea's value is restored.
            window.setTimeout(update, 0);
        });
        update();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initialize);
    } else {
        initialize();
    }
}());
