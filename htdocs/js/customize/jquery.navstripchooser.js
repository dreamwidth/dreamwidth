(function($) {

function NavStripChooser($el) {
    var navStripChooser = this;
    navStripChooser.init();
}

NavStripChooser.prototype = {

        init: function () {
            var navStripChooser = this;
            if (!$('#control_strip_color_custom')) return;
            navStripChooser.hideSubDivs();
            if ($('#control_strip_color_custom').checked) navStripChooser.showSubDiv();
            $('#control_strip_color_dark').click( function (evt) { navStripChooser.hideSubDivs(); });
            $('#control_strip_color_light').click( function (evt) { navStripChooser.hideSubDivs(); });
            $('#control_strip_color_custom').click( function (evt) { navStripChooser.showSubDiv(); });
        },

        hideSubDivs: function  () {
            $('#custom_subdiv').css('display', "none");
        },
        showSubDivs: function () {
            $('#custom_subdiv').css('display', "block");
        },
};

$.fn.extend({
    navStripChooser: function() {
        new NavStripChooser( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $(".appwidget-journaltitles").navStripChooser();
});
