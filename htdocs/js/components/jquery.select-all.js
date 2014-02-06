(function($) {
    $.fn.selectAll = function() {
        var $table = $(this);
        $("input[data-select-all]", this).click(function(e) {
            var $checkbox = $(this);

            var select_this = $checkbox.data("select-all")
            $table
                .find( "input[name=" + select_this + "], input[value=" + select_this + "]" )
                    .prop( "checked", $checkbox.is(":checked") );
            e.stopPropagation();
        })
        $table.click(function(e) {
            $("input[data-select-all]").prop( "checked", false );
        })
    }
})(jQuery);

jQuery(function($) {
    $("table.select-all").selectAll();
});