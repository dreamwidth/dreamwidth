var CurrentTheme = {
    init: function () {
                        //Handle designer and layoutid links

        $(".theme-current-designer").click(function(event){
                    event.preventDefault();
                    var designerLink = $(this).attr('href');
                    var newDesigner = designerLink.replace(/.*designer=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    filterThemes(event, "designer", newDesigner);
            })


            $(".theme-current-layout").click(function(event){
                    event.preventDefault();
                    var layoutLink = $(this).attr('href');
                    var newLayout = layoutLink.replace(/.*layoutid=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    CurrentTheme.trigger("theme:filter", {"layoutid", newLayout});
            })

        },

        refresh: function() {

        }
}

jQuery(document).ready(function(){
    CurrentTheme.init;
    CurrentTheme.on("theme:changed", CurrentTheme.refresh);
    CurrentTheme.on("themechooser:changed", CurrentTheme.refresh);
})
