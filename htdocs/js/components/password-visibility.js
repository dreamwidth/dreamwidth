(function() {
    "use strict";

    function initialize() {
        var buttons = document.querySelectorAll("[data-password-visibility]");
        Array.prototype.forEach.call(buttons, function(button) {
            var input = document.getElementById(button.getAttribute("aria-controls"));
            if (!input || input.type !== "password") return;

            function setVisible(visible) {
                input.type = visible ? "text" : "password";
                button.textContent = visible ? "Hide" : "Show";
                button.setAttribute("aria-label", visible ? "Hide password" : "Show password");
            }

            function mask() {
                if (input.type === "text") setVisible(false);
            }

            button.addEventListener("click", function() {
                setVisible(input.type === "password");
            });
            if (input.form) {
                input.form.addEventListener("submit", mask, true);
                input.form.addEventListener("reset", mask);
            }
            window.addEventListener("pagehide", mask);

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
