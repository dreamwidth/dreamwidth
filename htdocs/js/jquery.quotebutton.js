// On pages with a reply form, create a quote button that pastes in selected
// page text wrapped in a quote element. #body is what the quickreply form uses,
// and #commenttext is like some old talkpost_do shenanigans that will take some
// extra effort to dispose of.
jQuery(function(jQ){
    var helped = 0; var pasted = 0;
    function quote(e) {
        var textarea = $('textarea#body');
        if (textarea.length === 0) {
            textarea = $('textarea#commenttext');
            if (textarea.length === 0) {
                return;
            }
        }
        textarea = textarea.get(0);

        var text = '';

        if (document.getSelection) {
            text = document.getSelection();
        } else if (document.selection) {
            text = document.selection.createRange().text;
        } else if (window.getSelection) {
            text = window.getSelection();
        }

        text = text.toString().replace(/^\s+/, '').replace(/\s+$/, '');

        if (text == '') {
            if (helped != 1 && pasted != 1) {
                helped = 1;
                alert( $(e.target).parent('#quotebuttonspan').data('quoteError') );
            }
        } else {
            pasted = 1;
        }

        var element = text.search(/\n/) == -1 ? 'q' : 'blockquote';
        textarea.focus();
        textarea.value = textarea.value + "<" + element + ">" + text + "</" + element + ">";
        textarea.caretPos = textarea.value;
        textarea.focus();
    }

    jQ("<input type='button' value='Quote' />")
        .appendTo("#quotebuttonspan")
        .click(quote);
});
