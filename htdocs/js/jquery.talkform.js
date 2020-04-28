// Helpers specific to the talkform aka slowreply aka ReplyPage aka The Varmint
// See also jquery.quickreply.js, jquery.replyforms.js
jQuery(function($){
    var commentForm = $('#postform');
    var fromOptions = $('input[name="usertype"]');
    var authForms = $('.from-login');
    var iconSelect = $('#prop_picture_keyword');

    // Helpers for modifying every input in a sub-section of the form:
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
        },
        disableFormFields: function() {
            this.find('input').each(function(i, elm) {
                elm.disabled = true;
            });
            return this;
        },
        enableFormFields: function() {
            this.find('input').each(function(i, elm) {
                elm.disabled = false;
            });
            return this;
        }
    });

    // Tidy up irrelevant controls when choosing who the comment is from
    fromOptions.change(function(e) {
        // If the backend gets a user/password value AND a usertype that doesn't
        // need it, it considers that an error. So in addition to keeping
        // irrelevant sections of the form out of the way, we blank+disable any
        // other login forms to avoid sending contradictory info. (Disabling is
        // necessary to keep browser password managers from sending an unwanted
        // user/password at the last minute; browsers omit disabled fields.)
        var associatedLoginForm = document.getElementById( $(this).data('more') );
        authForms.hide();
        $(associatedLoginForm).show().enableFormFields();
        authForms.not(associatedLoginForm).clearFormFields().disableFormFields();

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
