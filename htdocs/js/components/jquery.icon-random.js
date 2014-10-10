(function($) {
    $.fn.iconrandom = function( opts ) {
        var $selector = this;

        if ( opts.trigger ) {
            $(opts.trigger).click(
                function(e) {
                    var numicons = $selector.prop("length");

                    // we need to ignore the first option "(default)"
                    var randomnumber = Math.floor(Math.random() * (numicons - 1));
                    $selector
                        .prop( "selectedIndex", randomnumber + 1 )
                        .trigger( "change" );

                    e.preventDefault();
                });
        }

        return this;
    };

})(jQuery);
