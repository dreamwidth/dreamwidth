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
});
