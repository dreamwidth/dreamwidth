// Helpers specific to the talkform aka slowreply aka ReplyPage aka The Varmint
// See also jquery.quickreply.js, jquery.replyforms.js
jQuery(function($){
    var commentForm = $('#postform');
    var fromOptions = $('input[name="usertype"]');
    var authForms = $('.from-login');
    var iconSelect = $('#prop_picture_keyword');

    // Blank out any input children.
    jQuery.fn.extend({
        clearFormFields: function() {
            this.find('input').each(function(i, elm){
                var type = elm.getAttribute('type');
                if (type === 'checkbox' || type === 'radio') {
                    elm.checked = false;
                } else if (type === 'text' || type === 'password' ){
                    elm.value = '';
                }
            });
            return this;
        }
    });

    // Tidy up irrelevant controls when choosing who the comment is from
    fromOptions.change(function(e) {
        // When a "from" option is selected, show its associated login form (if
        // any), and blank out the values of any other login forms so we don't
        // send contradictory info.
        var associatedLoginForm = document.getElementById( $(this).data('more') );
        authForms.hide();
        $(associatedLoginForm).show();
        authForms.not(associatedLoginForm).clearFormFields();

        // Icon select menu is only available for logged-in user
        if (this.id === 'talkpostfromremote' || this.id === 'talkpostfromoidli') {
            iconSelect.prop('disabled', false);
        } else {
            iconSelect.val('').change().prop('disabled', true);
        }
    });

    // setup:
    // hide login forms. show the currently relevant one, if any.
    fromOptions.filter(':checked').change();
    // confirm the selected icon, to update preview and browse button label.
    iconSelect.change();

    // subjecticons :|
    $('#subjectIconImage').click(function(){
        $('#subjectIconList').toggle();
    });
    $('#subjectIconList').find('img').click(function(){
        $('#subjectIconField').val(this.id);
        $('#subjectIconImage')
            .attr('src', this.src)
            .attr('width', this.width)
            .attr('height', this.height);
        $('#subjectIconList').hide();
    });

    // nohtml messages :|
    $('#subject').keyup(function(e) {
        if (this.value.includes('<')) {
            $('#ljnohtmlsubj').show();
        }
    });
    $('#editreason').keyup(function(e) {
        if (this.value.includes('<')) {
            $('#nohtmledit').show();
        }
    });

    // submit handlers :|

    // If JS is disabled, the preview button works normally.
    // If JS is enabled, we disable the submit buttons to guard against
    // double-submits, and that causes the preview button's value to appear as
    // falsy when the form data arrives back in perl-land. So if the user
    // clicked preview, we need to preserve that info in a non-disabled input.
    $('#submitpview').click(function(e) {
        this.name = 'submitpview';
        $('#previewplaceholder').prop('name', 'submitpreview');
    });

    commentForm.submit(function(e) {
        // prevent double-submits
        commentForm.find('input[type="submit"]').prop("disabled", true);
    });

});
