/**
* initialize JS for the create pages
*/
jQuery(function($) {
    $("#js-user").checkUsername();

    var showTip = function() {
        $("#" + $(this).data("tooltipId")).show();
    }
    var hideTip = function(e) {
        $("#" + $(this).data("tooltipId")).hide();
    }

    $.fn.tooltip = function(tooltipId) {
        $(this)
            .data("tooltipId", tooltipId)
            .focus(showTip)
            .blur(hideTip);
    }

    $("input[name=user]").tooltip("hint-user");
    $("input[name=email]").tooltip("hint-email");
    $("input[name=password1],input[name=password2]").tooltip("hint-password");
    $("select[name=bday_mm],select[name=bday_dd],input[name=bday_yyyy]").tooltip("hint-birthdate");
});
