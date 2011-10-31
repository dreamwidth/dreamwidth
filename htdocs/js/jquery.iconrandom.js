(function($) {
    $.fn.iconrandom = function( opts ) {
        var $selector = this;

        if ( opts.trigger ) {
            $(opts.trigger).click(
                function() {
                    var numicons = $selector.attr("length");

                    // we need to ignore the first option "(default)"
                    var randomnumber = Math.floor(Math.random() * (numicons - 1));
                    $selector.attr("selectedIndex", randomnumber + 1);

                    if ( opts.handler && $selector.get(0) )
                        opts.handler.apply($selector.get(0));
                    return false;
                });
        }
    };

})(jQuery);
