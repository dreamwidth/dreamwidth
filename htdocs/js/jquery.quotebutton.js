// On pages with a reply form, create a quote button that pastes in selected
// page text wrapped in a quote element.
jQuery(function($){
    var showHelp = true;
    var lastSelection = '';
    var quoteTarget = $('textarea#body'); // quickreply
    if (quoteTarget.length === 0) {
        quoteTarget = $('textarea#commenttext'); // talkform
        if (quoteTarget.length === 0) {
            return; // Nowhere to paste, skip all other quote button setup.
        }
    }
    quoteTarget = quoteTarget.get(0);

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

    function quote(e) {
        var text = getSelection();
        text = text.replace(/^\s+/, '').replace(/\s+$/, '');

        if (text.length === 0 && showHelp) {
            alert( $(e.target).parent('#quotebuttonspan').data('quoteError') );
        }
        showHelp = false;

        var element = text.search(/\n/) == -1 ? 'q' : 'blockquote';
        quoteTarget.focus();
        quoteTarget.value = quoteTarget.value + "<" + element + ">" + text + "</" + element + ">";
        quoteTarget.caretPos = quoteTarget.value;
        quoteTarget.focus();
    }

    $("<input type='button' value='Quote' />")
        .appendTo("#quotebuttonspan")
        .click(quote);
});
