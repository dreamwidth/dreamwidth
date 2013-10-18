(function($) {
    $.fn.selectAll = function() {
        var $table = $(this);
        $("input[data-role]", this).click(function(e) {
            var $checkbox = $(this);

            $table
                .find( "input[name=" + $checkbox.data("role") + "]" )
                    .prop( "checked", $checkbox.is(":checked") )
        })
    }
})(jQuery);

jQuery(function($) {
    $("table.select-all").selectAll();
});