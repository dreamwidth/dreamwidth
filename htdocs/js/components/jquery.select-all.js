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
            // if we clicked anywhere else in the table, uncheck any select-all checkbox
            // but not any select-all checkbox is what we just clicked
            // this is to avoid interfering with deselecting everyhing by clicking on a label
            $("input[data-select-all]")
                .not($(e.target).find("input[data-select-all]"))
                .prop( "checked", false );
        })
    }
})(jQuery);

jQuery(function($) {
    $("table.select-all").selectAll();
});