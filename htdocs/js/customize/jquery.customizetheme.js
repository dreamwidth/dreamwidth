(function($) {

function CustomizeTheme() {
    var customizeTheme = this;
    customizeTheme.init();
}

CustomizeTheme.prototype = {
        init: function () {
            var customizeTheme = this;
            // confirmation when reseting the form
            $('#reset_btn_top').click(function (evt) { customizeTheme.confirmReset(evt) });
            $('#reset_btn_bottom').click(function (evt) { customizeTheme.confirmReset(evt) });

             $("#collapse").click(function (evt) { 
                 evt.preventDefault();
                 $(".collapse-expanded .collapse-trigger").click();  
            });

             $("#expand").click(function (evt) { 
                 evt.preventDefault();
                 $(".customize-content .collapse-collapsed .collapse-trigger").click(); 
            });

            // show the expand/collapse links
             $(".s2propgroup-outer-expandcollapse").css("display", "inline");
        },

        confirmReset: function (evt) {
            if (! confirm("Are you sure you want to reset all changes on this page to their defaults?")) {
                Event.stop(evt);
            }
        },

};

$.fn.extend({
    customizeTheme: function() {
        new CustomizeTheme( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $("body").collapse();
    $().customizeTheme();
    var form = $('#customize-form'),
        original = form.serialize()

    form.submit(function(){
        window.onbeforeunload = null
    })

    window.onbeforeunload = function(){
        if (form.serialize() != original)
            return 'Are you sure you want to leave?'
    }
});
