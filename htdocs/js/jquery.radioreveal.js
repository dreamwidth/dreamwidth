(function($) {
    $.fn.radioreveal = function( options ) {
        var $caller = $(this);
        var opts = $.extend({}, $.fn.radioreveal.defaults, options );

        var $radio = $("#"+opts.radio).filter(":radio");

        if ( $radio.length > 0 ) {
            $radio.attr("checked") ? $caller.show() : $caller.hide();

            var name = $radio.attr("name");
            if ( name ) {
                $("input:radio[name='"+name+"']").click(function() {
                    if ( $("input:radio[name='"+name+"']:checked").attr("id") == opts.radio ) {
                        $caller .show()
                                .find(":input").first().focus();
                    } else {
                        $caller.hide();
                    }
                });
            }
        }

        return $caller;
    }

    $.fn.radioreveal.defaults = {
        radio: ""          // the id of the radio element that will reveal the caller
    };
})(jQuery);

