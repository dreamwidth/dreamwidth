(function($) {
    $(document).on('submit', 'form#default_editor', function(e) {
        e.preventDefault();
        e.stopPropagation();

        var $form = $(this);
        var $submit = $form.find('input[type="submit"]');

        var request = $.ajax({
            method: 'POST',
            type: 'POST', // until we upgrade jquery ≥ 1.9
            url: $.endpoint($form.data('rpcEndpoint')),
            data: $form.serialize(),
            dataType: 'json',
            success: function(data) {
                if (data.success) {
                    $form.replaceWith('<span class="success">' + data.message + '</span>');
                } else {
                    $form.replaceWith('<span class="failure">' + data.error + '</span>');
                }
            },
            error: function(jqXHR, errorText) {
                $form.after('<span class="failure">Sorry, an error occurred: ' + errorText + '. Please try again.</span>');
                $(document).off('submit', 'form#default_editor'); // fall back to no-JS behavior.
            },
        });

        $submit.throbber(request);
    });

})(jQuery);
