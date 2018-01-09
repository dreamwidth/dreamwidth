var LayoutChooser = {

        init: function () {
            //Handle the 'apply theme' buttons
            $(".layout-form").submit(function(event){
                event.preventDefault();
                applyLayout(this, event);       
            })

        },

        applyLayout: function (form, event) {
            console.log("trying to apply layout");

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
                    'authas': authas },
              success: function( data ) { $( "div.layout-selector-wrapper" ).html(data);
                                            LayoutChooser.init;},
              dataType: "html"
            });
            event.preventDefault();
    },
    
    refresh: fuction () {
      return true;
    },
};

jQuery(document).ready(function(){
    LayoutChooser.init;
    LayoutChooser.on("theme:changed", LayoutChooser.refresh);
});

