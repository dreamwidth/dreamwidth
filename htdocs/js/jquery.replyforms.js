// Helpers for interactive features in the reply forms. Code that messes with
// the actual form submission should go in either jquery.quickreply.js or
// jquery.talkform.js.
jQuery(function($) {
    var iconSelect = $("#prop_picture_keyword");
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

    function randomIcon() {
        if ( iconSelect.length === 0 ) return;

        // take a random number, ignoring the "(default)" and "(random)" options
        var randomnumber = Math.floor(
            Math.random() * (iconSelect.prop("length") - 2)
        ) + 2;
        iconSelect.prop("selectedIndex", randomnumber);
        iconSelect.change();
    }

    // Add random icon option to menu if there's more than one icon
    if ( $('option#random').length === 0 && iconSelect.children('option').length > 2 ) {
        iconSelect.children('option').first()
            .after('<option value=",random" id="random">(random) 🔀</option>');
            // Commas are illegal in keywords, so this won't conflict with
            // anyone's real icons. Since the value immediately changes to
            // something else if you select it, this should never be
            // submitted... but if it is, it just reverts to the default icon.
    }

    // Random icon re-roll button (hidden until random is selected once)
    $("#randomicon").on("click", randomIcon);


    // New-new icon browser, if available
    if ( $.fn.iconBrowser ) {
        iconSelect.iconBrowser({
            triggerSelector: "#lj_userpicselect",
            modalId: "js-icon-browser",
            preferences: {
                "keywordorder": $('#lj_userpicselect').data('iconbrowserKeywordorder'),
                "metatext": $('#lj_userpicselect').data('iconbrowserMetatext'),
                "smallicons": $('#lj_userpicselect').data('iconbrowserSmallicons')
            }
        });
    }

    iconSelect.on("change", function(e) {
        var selection = $(this).find("option:selected");
        if (selection.attr('id') === 'random') {
            randomIcon();
            // For easy re-rolls:
            $("#randomicon").show();
        } else {
            // Update icon preview
            var iconPreview = $(".qr-icon");
            iconPreview.removeClass("no-label"); // hides browse button in talkform when no JS.
            iconPreview.find("img")
                .attr("src", selection.data("url"))
                .removeAttr("width").removeAttr("height").removeAttr("alt");
            if (selection.attr('value') === '') {
                iconPreview.addClass("default");
            } else {
                iconPreview.removeClass("default");
            }
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