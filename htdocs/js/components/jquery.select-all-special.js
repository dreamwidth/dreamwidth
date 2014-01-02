(function($) {
    $.fn.selectAll = function() {
        var $table = $(this);
        $("input[data-select-all]", this).click(function(e) {
            var $checkbox = $(this);

            $table
                .find( "input[data-selected-by=" + $checkbox.data("select-all") + "]" )
                    .prop( "checked", $checkbox.is(":checked") )
        })
    }
})(jQuery);

jQuery(function($) {
    $("table.select-all").selectAll();
});