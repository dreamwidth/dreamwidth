var postForm = (function($) {
    var initializeCollapsible = function() {
        $("#post_entry").collapse({ endpointUrl: "/__rpc_entryformcollapse" });
    };

    var init = function(formData) {
        $("#nojs").val(0);
        initializeCollapsible();

        if ( ! formData ) formData = {};
    };

    return {
        init: init
    };
})(jQuery);

jQuery(function($) {
    postForm.init(window.postFormInitData);
});