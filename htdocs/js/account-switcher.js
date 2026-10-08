/*
 * Copyright (c) 2026 by Dreamwidth Studios, LLC.
 *
 * This program is free software; you may redistribute it and/or modify it under
 * the same terms as Perl itself. For a copy of the license, please reference
 * 'perldoc perlartistic' or 'perldoc perlgpl'.
 */
jQuery(function($) {
    $(document).on("click", ".account-switcher-cancel", function() {
        $(this).closest("[data-reveal]").foundation("reveal", "close");
    });

    $(document).on("keydown", ".account-switcher-modal", function(event) {
        if (event.which !== 9) return;

        var controls = $(this).find("a[href], button, input").filter(":visible").not(":disabled");
        var first = controls.first()[0];
        var last = controls.last()[0];
        if (event.shiftKey && event.target === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && event.target === last) {
            event.preventDefault();
            first.focus();
        }
    });
});
