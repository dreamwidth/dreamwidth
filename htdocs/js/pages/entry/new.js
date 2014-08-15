(function($) {
$.postForm = {

init: function(formData) {
    if ( ! formData ) formData = {};
}
} })(jQuery);

jQuery(function($) {
    $("#nojs").val(0);
    $.postForm.init(window.postFormInitData);
});