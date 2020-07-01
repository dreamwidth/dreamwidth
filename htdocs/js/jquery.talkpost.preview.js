// Tiny script for hiding/revealing the full text of the comment/entry you're
// replying to.
jQuery(function($) {
    "use strict";

    var replyTo = $('#preview-parent-entry');
    var toggleButtons = $('.js-parent-toggle');

    // Move parent content to the top of the page, since it defaults to the
    // bottom for no-JS users. This uses flex `order`, so it shouldn't obstruct
    // screenreaders...
    $('#talkpost-wrapper').addClass('js-preview');

    // Set up initial state
    replyTo.addClass('collapsed');
    $('#js-preview-parent-expand').removeClass('js-hidden');

    // And then:
    toggleButtons.on('click', function(e) {
        replyTo.toggleClass('collapsed');
        toggleButtons.toggleClass('js-hidden');
    });
});
