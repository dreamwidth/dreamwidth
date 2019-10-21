(function($) {

function LayoutChooser($el) {
    var layoutChooser = this;
    layoutChooser.init();
}

LayoutChooser.prototype = { 
        init: function () {
          var layoutChooser = this;
            //Handle the 'apply theme' buttons
            $(".layout-selector-wrapper").on("submit", ".layout-form", function(event){
                event.preventDefault();
                layoutChooser.applyLayout(this, event);       
            })

        },
        applyLayout: function (form, event) {
          var layoutChooser = this;
            var given_layout_choice = $(form).children("[name=layout_choice]").val(); 
            var given_layout_prop = $(form).children("[name=layout_prop]").val(); 
            var given_show_sidebar_prop = $(form).children("[name=show_sidebar_prop]").val(); 

            $("#layout_btn_" + given_layout_choice).attr("disabled", true);
            $("#layout_btn_" + given_layout_choice).addClass("layout-button-disabled disabled");
            $.ajax({
              type: "POST",
              url: "/__rpc_layoutchooser",
              data: {
                     'layout_choice': given_layout_choice,
                     'layout_prop': given_layout_prop,
                     'show_sidebar_prop': given_show_sidebar_prop,
                    //'authas': authas 
                  },
              success: function( data ) { $( "div.layout-selector-wrapper" ).html(data);
                                            layoutChooser.init();},
              dataType: "html"
            });
            event.preventDefault();
    },

 };



$.fn.extend({
    layoutChooser: function() {
        new LayoutChooser( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $(".layout-selector-wrapper").layoutChooser();
});
