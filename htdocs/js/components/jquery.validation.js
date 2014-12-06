// handles form validation on foundation pages
(function($) {
    // marks the form element as being in the error state
    $.fn.validateError = function(errorMsg) {
        this.each(function() {
            var $element = $(this);

            // insert error message (into new or existing element)
            var $error = $element.next( ".error" );
            if ( $error.length == 0 ) {
                $error = $("<small class='error js-generated'></small>")
                            .insertAfter( $element );
            }
            $error.text(errorMsg);

            // add the error class
            $element.addClass( "error" );

            // add the aria state on inputs
            $element.attr( "aria-invalid", "true" );
        });
    };

    // removes error state from the form element
    $.fn.validateOk = function() {
        this.each(function() {
            var $element = $(this);

            // remove error message
            $element.next( ".error" ).remove();

            // remove the error class
            $element.removeClass( "error" );

            // remove the aria state
            $element.attr( "aria-invalid", "false" );
        });
    };
})(jQuery);