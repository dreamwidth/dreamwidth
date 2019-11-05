(function($) {

function ThemeChooser() {
    var themeChooser = this;
    themeChooser.init();
}

ThemeChooser.prototype = {
        cat : "",
        layoutid : 0,
        designer : "",
        search : "",
        page : 1,
        show : "",

        init: function () {
            var themeChooser = this;
            //Handle cat links
            $(".theme-selector-wrapper").on( "click", ".theme-nav-cat", function(event){
                    event.preventDefault();
                    var catLink = $(this).attr('href');
                    var newCat = catLink.replace(/.*cat=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    themeChooser.filterThemes(event, "cat", newCat);

                    //move CSS classes around for rendering
                    $('li.on').removeClass('on');
                    $(this).parent('li').addClass('on');
                    
                        
                return false;
            })

            $(".theme-selector-wrapper").on("theme:filter", function(evt, data) {
                for (var dkey in Object.keys(data)) {
                        var dvalue = data[key];
                      themeChooser.filterThemes(evt, dkey, dvalue);
                    }

            });

            if ($('#search_box')) {
                //var keywords = new InputCompleteData(Customize.ThemeNav.searchwords, "ignorecase");
                //var ic = new InputComplete($('#search_box'), keywords);

                var text = "theme, layout, or designer";
                var color = "#999";
                $('#search_box').css("color", color);
                $('#search_box').val(text);
                $(".theme-selector-wrapper").on("focus", "#search_box", function (evt) {
                    if ($('#search_box').val() == text) {
                        $('#search_box').css("color", "");
                        $('#search_box').val("");
                    }
                });
                $(".theme-selector-wrapper").on("blur", "#search_box", function (evt) {
                    if ($('#search_box').val() == "") {
                        $('#search_box').css("color", color);
                        $('#search_box').val(text);
                    }
                });
            }

            // add event listener to the search form
            $(".theme-selector-wrapper").on("submit", "#search_form", function (evt) { themeChooser.filterThemes(evt, "search", $('#search_box').val()) });

            //Handle preview links
            $(".theme-selector-wrapper").on("click", ".theme-preview-link", function(){
                        window.open($(this).attr("href"), 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
                return false;
            })

            //Handle the 'apply theme' buttons
            $(".theme-selector-wrapper").on("submit", ".theme-form", function(event){
                var given_themeid = $(this).children("[name=apply_themeid]").val(); 
                var given_layoutid = $(this).children("[name=apply_layoutid]").val(); 
                var auth_token = $(this).children("[name=lj_form_auth]").val(); 

                themeChooser.applyTheme(event, given_themeid, given_layoutid, auth_token);

                
            })

            //Handle page select
            $(".theme-selector-wrapper").on( "change", "#page_dropdown_top",
                function (event) { themeChooser.filterThemes(event, "page", $(this).val()) }
            )

            $(".theme-selector-wrapper").on("change", "#page_dropdown_bottom", 
                function (event) { themeChooser.filterThemes(event, "page", $(this).val()) }
            )

            //Handle show select
            $(".theme-selector-wrapper").on("change", "#show_dropdown_top", 
                function (event) { themeChooser.filterThemes(event, "show", $(this).val()) }
            )

            $(".theme-selector-wrapper").on( "change", "#show_dropdown_bottom",
                function (event) { themeChooser.filterThemes(event, "show", $(this).val()) }
            )

            $(".theme-selector-wrapper").on("click", ".theme-page", function(event){
                    event.preventDefault();
                    var pageLink = $(this).attr('href');
                    var newPage = pageLink.replace(/.*page=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    themeChooser.filterThemes(event, "page", newPage);
            })

            //Handle designer and layoutid links
            $(".theme-selector-wrapper").on("click", ".theme-layout", function(event){
                    event.preventDefault();
                    var layoutLink = $(this).attr('href');
                    var newLayout = layoutLink.replace(/.*layoutid=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    themeChooser.filterThemes(event, "layoutid", newLayout);
            })

            $(".theme-selector-wrapper").on("click", ".theme-designer", function(event){
                    event.preventDefault();
                    var designerLink = $(this).attr('href');
                    var newDesigner = designerLink.replace(/.*designer=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    themeChooser.filterThemes(event, "designer", newDesigner);
            })

        },

        applyTheme: function (event, themeid, layoutid, auth_token) {
            var themeChooser = this;
                $("#theme_btn_" + layoutid + themeid).attr("disabled", true);
                $("#theme_btn_" + layoutid + themeid).addClass("theme-button-disabled disabled");
                $.ajax({
                  type: "POST",
                  url: "/__rpc_themechooser",
                  data: {
                         apply_themeid: themeid,
                         apply_layoutid: layoutid,
                         lj_form_auth: auth_token,
                        //'authas' : authas,
                         'cat': themeChooser.cat,
                         'layoutid': themeChooser.layoutid,
                        'designer': themeChooser.designer,
                        'page': themeChooser.page,
                        'search': themeChooser.search,
                        'show': themeChooser.show },
                  success: function( data ) { $( "div.theme-selector-content" ).html(data.themechooser);
                                                $( "div.layout-selector-wrapper" ).html(data.layoutchooser);
                                                $("div.theme-current").html(data.currenttheme);
                                                    alert(confirmation);
                                                    },
                  dataType: "json"
                });
                event.preventDefault();

        },

        filterThemes: function (evt, key, value) {
            var themeChooser = this;
            if (key == "show") {
                // need to go back to page 1 if the show amount was switched because
                // the current page may no longer have any themes to show on it
                page = 1;
            } else if (key != "page") {
                themeChooser.resetFilters();
            }

            // do not do anything with a layoutid of 0
            if (key == "layoutid" && value == 0) {
                event.preventDefault();
                return;
            }

            if (key == "cat") themeChooser.cat = value;
            if (key == "layoutid") themeChooser.layoutid = value;
            if (key == "designer") themeChooser.designer = value;
            if (key == "search") themeChooser.search = value;
            if (key == "page") themeChooser.page = value;
            if (key == "show") themeChooser.show = value;

            $.ajax({
              type: "GET",
              url: "/__rpc_themefilter",
              data: {
                    'cat': themeChooser.cat,
                    'layoutid': themeChooser.layoutid,
                    'designer': themeChooser.designer,
                    'search': themeChooser.search,
                    'page': themeChooser.page,
                    'show': themeChooser.show,
                   // 'authas': authas
                     },
              success: function( data ) { $( "div.theme-selector-content" ).html(data.themechooser);
                                            $("div.theme-current").html(data.currenttheme);},
              dataType: "json"
            });

            evt.preventDefault();

            if (key == "search") {
                $("search_btn").disabled = true;
            } else if (key == "page" || key == "show") {
                $("paging_msg_area_top").innerHTML = "<em>Please wait...</em>";
                $("paging_msg_area_bottom").innerHTML = "<em>Please wait...</em>";
            } else {
                //cursorHourglass(evt);
            }
        },

        //Clear filters
        resetFilters: function () {
            var tc = this;
            tc.cat = "";
            tc.layoutid = 0;
            tc.designer = "";
            tc.search = "";
            tc.page = 1;
        },

}

$.fn.extend({
    themeChooser: function() {
        new ThemeChooser( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $().themeChooser();
});