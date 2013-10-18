(function($) {
    $.fn.selectAll = function() {
        var $table = $(this);
        $(".select-all input[data-role]", this).click(function(e) {
            var $checkbox = $(this);

            $table
                .find( "input[name=" + $checkbox.data("role") + "]" )
                    .prop( "checked", $checkbox.is(":checked") )
        })
    }
})(jQuery);

jQuery(function($) {
    $("table").selectAll();
});