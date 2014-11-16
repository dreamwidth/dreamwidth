jQuery(function($) {
    $(".filter-section").collapse({
        trigger: "legend",
        target: ".inner",
    });

    $("form[data-warning]").submit(function(e) {
        if ( confirm( $(this).data("warning") ) ) {
            return true;
        }
        return false;
    });
});