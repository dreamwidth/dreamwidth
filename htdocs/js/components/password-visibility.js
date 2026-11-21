/*
 * htdocs/js/components/password-visibility.js
 *
 * Enhance password fields with a visibility control.
 *
 * Authors:
 *     SAPHID <saphid@users.noreply.github.com>
 *
 * Copyright (c) 2026 by Dreamwidth Studios, LLC.
 *
 * This program is free software; you may redistribute it and/or modify it under
 * the same terms as Perl itself.  For a copy of the license, please reference
 * 'perldoc perlartistic' or 'perldoc perlgpl'.
 */

(function() {
    "use strict";

    function getInput(button) {
        return document.getElementById(button.getAttribute("aria-controls"));
    }

    function setVisible(input, button, visible) {
        input.type = visible ? "text" : "password";
        button.textContent = visible ? "Hide" : "Show";
        button.setAttribute("aria-label", visible ? "Hide password" : "Show password");
    }

    function maskPasswords(event) {
        var target = event.currentTarget;
        var buttons = document.querySelectorAll("button[data-password-visibility-bound]");
        Array.prototype.forEach.call(buttons, function(button) {
            var input = getInput(button);
            if (input && input.type === "text" && (target === window || input.form === target)) {
                setVisible(input, button, false);
            }
        });
    }

    function initialize() {
        var buttons = document.querySelectorAll("[data-password-visibility]");
        Array.prototype.forEach.call(buttons, function(button) {
            if (button.dataset.passwordVisibilityBound) return;
            var input = getInput(button);
            if (!input || input.type !== "password") return;

            button.dataset.passwordVisibilityBound = "1";
            button.addEventListener("click", function() {
                setVisible(input, button, input.type === "password");
            });
            var form = input.form;
            if (form && !form.dataset.passwordVisibilityFormBound) {
                form.dataset.passwordVisibilityFormBound = "1";
                form.addEventListener("submit", maskPasswords, true);
                form.addEventListener("reset", maskPasswords);
            }
            if (!window.dwPasswordVisibilityBound) {
                window.dwPasswordVisibilityBound = true;
                window.addEventListener("pagehide", maskPasswords);
            }

            button.parentNode.classList.add("password-visibility-ready");
            button.hidden = false;
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initialize);
    } else {
        initialize();
    }
}());
