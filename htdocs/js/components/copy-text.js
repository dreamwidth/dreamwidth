/* Copy-to-clipboard buttons for fields made by LJ::html_copy_text
 * (form.copy_text in templates).
 *
 * The button is hidden in the markup and shown here, so it only appears when
 * it can work. The Clipboard API needs a secure (HTTPS) page; elsewhere, or
 * if it is refused, we fall back to copying the selected field text. If both
 * fail, the text stays selected and the status message asks the reader to
 * copy it with the keyboard.
 */
(function() {
    "use strict";

    function selectValue(field) {
        // select exactly the trimmed text, so a manual copy matches ours
        var text = field.value.trim();
        var start = field.value.indexOf(text);
        field.focus();
        field.setSelectionRange(start, start + text.length);
    }

    function copyBySelection(field) {
        selectValue(field);
        try {
            return document.execCommand("copy");
        } catch (e) {
            return false;
        }
    }

    function showStatus(button, message) {
        var status = document.getElementById(button.getAttribute("data-copy-status"));
        if (!status) return;

        // empty the live region first so that a repeated message is announced again
        status.textContent = "";
        window.setTimeout(function() {
            status.textContent = message;
        }, 100);
    }

    function copy(button) {
        var field = document.getElementById(button.getAttribute("aria-controls"));
        if (!field) return;

        var copied = function() {
            showStatus(button, button.getAttribute("data-copied-message"));
        };
        var fallback = function() {
            if (copyBySelection(field)) {
                copied();
            } else {
                selectValue(field);
                showStatus(button, button.getAttribute("data-failed-message"));
            }
        };

        if (window.isSecureContext && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(field.value.trim()).then(copied, fallback);
        } else {
            fallback();
        }
    }

    document.addEventListener("click", function(e) {
        var target = e.target;
        if (!target.closest) return;

        var button = target.closest("[data-copy-text]");
        if (button) {
            copy(button);
            return;
        }

        var field = target.closest("[data-copy-text-field]");
        if (field) selectValue(field);
    });

    function showButtons() {
        var buttons = document.querySelectorAll("[data-copy-text]");
        for (var i = 0; i < buttons.length; i++) {
            buttons[i].hidden = false;
        }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", showButtons);
    } else {
        showButtons();
    }
})();
