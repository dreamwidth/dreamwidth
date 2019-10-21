(function($) {

function CurrentTheme($el) {
    var currentTheme = this;
    currentTheme.init();
}

CurrentTheme.prototype = {
    init: function () {
        var currentTheme = this;
        //Handle designer and layoutid links

        $(".theme-current").on("click", ".theme-current-designer", function(event){
                    event.preventDefault();
                    var designerLink = $(this).attr('href');
                    var newDesigner = designerLink.replace(/.*designer=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    $(".theme-selector-wrapper").trigger("theme:filter", {"designer": newDesigner});
            });


            $(".theme-current").on("click", ".theme-current-layout", function(event){
                    event.preventDefault();
                    var layoutLink = $(this).attr('href');
                    var newLayout = layoutLink.replace(/.*layoutid=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    $(".theme-selector-wrapper").trigger("theme:filter", {"layoutid" : newLayout});
            });

        },

    refresh: function() {
        return true;
        }
}

$.fn.extend({
    currentTheme: function() {
        new CurrentTheme( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $(".theme").currentTheme();
});
