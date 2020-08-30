// Helpers for interactive features in the reply forms. Code that messes with
// the actual form submission should go in either jquery.quickreply.js or
// jquery.talkform.js.
jQuery(function($) {
    var commentForm = $('form#qrform'); // quickreply
        if (commentForm.length === 0) {
            commentForm = $('form#postform'); // talkform
        }
    var commentText = $('textarea#body'); // quickreply
        if (commentText.length === 0) {
            commentText = $('textarea#commenttext'); // talkform
        }
    var quoteButton = $('#comment-text-quote');
    var maxLength = Site.cmax_comment;

    // Reveal any controls that are hidden when JS is disabled... and vice versa
    $(".js-only").show();
    $(".no-js").hide();
    // Re-enable submit buttons when page is thawed from bfcache (Safari, Firefox)
    $(window).on('pageshow', function(e){
        if ( e.originalEvent.persisted ) {
            commentForm.find('input[type="submit"]').prop("disabled", false);
        }
    });

    // Quote button
    var showHelp = true;
    var lastSelection = '';
    // Touch-based browsers like to collapse the selection too early, so
    // retain the last real selection.
    if (window.matchMedia("(any-hover: none)").matches) {
        document.addEventListener('selectionchange', function() {
            newSelection = document.getSelection().toString();
            if (newSelection.length > 0) {
                lastSelection = newSelection;
            }
        });
    }
    // Return current selection or last intentional selection
    function getSelection() {
        var currentSelection = document.getSelection().toString();
        if (currentSelection.length === 0) {
            currentSelection = lastSelection;
        }
        lastSelection = ''; // avoid re-quotes
        return currentSelection;
    }
    quoteButton.click(function(e) {
        var text = getSelection();
        text = text.replace(/^\s+/, '').replace(/\s+$/, '');

        if (text.length === 0 && showHelp) {
            alert( $(e.target).data('quoteError') );
        }
        showHelp = false;

        var element = text.search(/\n/) == -1 ? 'q' : 'blockquote';
        var quoteTarget = commentText[0];
        quoteTarget.focus();
        quoteTarget.value = quoteTarget.value + "<" + element + ">" + text + "</" + element + ">";
        quoteTarget.caretPos = quoteTarget.value;
        quoteTarget.focus();
    });

    // Stop form submission (and any other submit handlers) if the comment text is too long
    commentForm.submit(function(e) {
        var length = commentText.val().length;
        if (length > maxLength) {
            alert('Sorry, but your comment of ' + length + ' characters exceeds the maximum character length of ' + maxLength + '.  Please try shortening it and then post again.');
            e.stopImmediatePropagation(); // stop other listeners on same event
            e.preventDefault();
            commentForm.find('input[type="submit"]').prop("disabled", false);
        }
    });

});