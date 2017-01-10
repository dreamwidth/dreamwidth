var NavStripChooser = {

        init: function () {
            if (!$('#control_strip_color_custom')) return;
            NavStripChooser.hideSubDivs();
            if ($('#control_strip_color_custom').checked) showSubDiv();
            $('#control_strip_color_dark').click( function (evt) { NavStripChooser.hideSubDivs(); });
            $('#control_strip_color_light').click( function (evt) { NavStripChooser.hideSubDivs(); });
            $('#control_strip_color_custom').click( function (evt) { NavStripChooser.showSubDiv(); });
        },

        hideSubDivs: function  () {
            $('#custom_subdiv').css('display', "none");
        },
        showSubDivs: function () {
            $('#custom_subdiv').css('display', "block");
        },
};

jQuery(document).ready(function(){
    NavStripChooser.init();
});
