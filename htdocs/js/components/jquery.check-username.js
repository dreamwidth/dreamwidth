(function($) {
    $.fn.checkUsername = function() {
        this.each(function() {
            var $element = $(this);

            $element.blur(function() {
                var request = $.getJSON(
                    "/__rpc_checkforusername?user=" + encodeURIComponent( this.value )
                );

                $element.removeClass( "username-okay" );
                $element.addClass( "loading" );

                request.done(function(data) {
                    $element.removeClass( "username-okay loading" );
                    if ( data.error ) {
                        $element.validateError( data.error );
                    } else {
                        $element.addClass( "username-okay" );
                        $element.validateOk();
                    }
                }).fail(function(data) {
                    $element.removeClass( "username-okay loading" );
                    $element.validateError( data.statusText );
                });
            });
        })
    };
})(jQuery);
