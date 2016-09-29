       var pageGetArgs = LiveJournal.parseGetArgs(document.location.href);

    var Customize = new Object();

    cat = pageGetArgs["cat"] ? pageGetArgs["cat"] : "";
    layoutid = pageGetArgs["layoutid"] ? pageGetArgs["layoutid"] : 0;
    designer = pageGetArgs["designer"] ? pageGetArgs["designer"] : "";
    search = pageGetArgs["search"] ? pageGetArgs["search"] : "";
    page = pageGetArgs["page"] ? pageGetArgs["page"] : 1;
    show = pageGetArgs["show"] ? pageGetArgs["show"] : 12;
    authas = pageGetArgs["authas"] ? pageGetArgs["authas"] : "";
    hourglass = null;

// Functions for making hourglasses on our page
function cursorHourglass (evt) {
    var posX = evt.pageX;
    var posY = evt.pageY
    if (!posX) return;

    if (!hourglass) {
        hourglass = new Hourglass();
        hourglass.init();
        hourglass.hourglass_at(posX, posY);
    }
}

function elementHourglass (element) {
    if (!element) return;

    if (!hourglass) {
        hourglass = new Hourglass();
        hourglass.init();
        hourglass.hourglass_at_widget(element);
    }
}

function hideHourglass () {
    if (hourglass) {
        hourglass.hide();
        hourglass = null;
    }
}

//Clear filters
function resetFilters () {
    cat = "";
    layoutid = 0;
    designer = "";
    search = "";
    page = 1;
}

    function initThemeNav () {
            //Handle cat links
        $(".theme-nav-cat").click(function(event){
        event.preventDefault();

        var catLink = $(this).attr('href');
        var newCat = catLink.replace(/.*cat=([^&?]*)&?.*/, "$1");

        
        //reload the theme chooser area
        filterThemes(event, "cat", newCat);

        //move CSS classes around for rendering
        $('li.on').removeClass('on');
        $(this).parent('li').addClass('on');
        
            
    return false;
})

}



       function initJournalTitles() {

            // store current field values
            var journaltitle_value = $("journaltitle").value;
            var journalsubtitle_value = $("journalsubtitle").value;
            var friendspagetitle_value = $("friendspagetitle").value;
            var friendspagesubtitle_value = $("friendspagesubtitle").value;

            // show view mode
            $("#journaltitle_view").css("display", "inline");
            $("#journalsubtitle_view").css("display", "inline");
            $("#friendspagetitle_view").css("display", "inline");
            $("#friendspagesubtitle_view").css("display", "inline");
            $("#journaltitle_cancel").css("display", "inline");
            $("#journalsubtitle_cancel").css("display", "inline");
            $("#friendspagetitle_cancel").css("display", "inline");
            $("#friendspagesubtitle_cancel").css("display", "inline");
            $("#journaltitle_modify").css("display", "none");
            $("#journalsubtitle_modify").css("display", "none");
            $("#friendspagetitle_modify").css("display", "none");
            $("#friendspagesubtitle_modify").css("display", "none");


            // set up edit links
            $("#journaltitle_edit").click(function(event) { editTitle(event, "journaltitle"); });
            $("#journalsubtitle_edit").click(function(event) { editTitle(event, "journalsubtitle"); });
            $("#friendspagetitle_edit").click(function(event) { editTitle(event, "friendspagetitle"); });
            $("#friendspagesubtitle_edit").click(function(event) { editTitle(event, "friendspagesubtitle"); });

            // set up cancel links
            $("#journaltitle_cancel").click(function(event) { cancelTitle(event, "journaltitle"); });
            $("#journalsubtitle_cancel").click(function(event) { cancelTitle(event, "journalsubtitle"); });
            $("#friendspagetitle_cancel").click(function(event) { cancelTitle(event, "friendspagetitle"); });
            $("#friendspagesubtitle_cancel").click(function(event) { cancelTitle(event, "friendspagesubtitle"); });


            // set up save forms
            $("#journaltitle_form").submit(function(event){ saveTitle(event, "journaltitle") });
            $("#journalsubtitle_form").submit(function(event){ saveTitle(event, "journalsubtitle") });
            $("#friendspagetitle_form").submit(function(event){ saveTitle(event, "friendspagetitle") });
            $("#friendspagesubtitle_form").submit(function(event){ saveTitle(event, "friendspagesubtitle") });

        }

        function editTitle (event, id) {
            event.preventDefault();

            $("#" + id + "_modify").css("display", "inline");
            $("#" + id + "_view").css( "display",  "none");
            $("#" + id).focus();

            // cancel any other titles that are being edited since
            // we only want one title in edit mode at a time
            if (id == "journaltitle") {
                cancelTitle(event, "journalsubtitle");
                cancelTitle(event, "friendspagetitle");
                cancelTitle(event, "friendspagesubtitle");
            } else if (id == "journalsubtitle") {
                cancelTitle(event, "journaltitle");
                cancelTitle(event, "friendspagetitle");
                cancelTitle(event, "friendspagesubtitle");
            } else if (id == "friendspagetitle") {
                cancelTitle(event, "journaltitle");
                cancelTitle(event, "journalsubtitle");
                cancelTitle(event, "friendspagesubtitle");
            } else if (id == "friendspagesubtitle") {
                cancelTitle(event, "journaltitle");
                cancelTitle(event, "journalsubtitle");
                cancelTitle(event, "friendspagetitle");
            }


            return false;
        }

        function cancelTitle (event, id) {
            event.preventDefault();

            $("#" + id + "_modify").css("display", "none");
            $("#" + id + "_view").css("display",  "inline");

            // reset appropriate field to default
            if (id == "journaltitle") {
                $("journaltitle").value = this.journaltitle_value;
            } else if (id == "journalsubtitle") {
                $("journalsubtitle").value = this.journalsubtitle_value;
            } else if (id == "friendspagetitle") {
                $("friendspagetitle").value = this.friendspagetitle_value;
            } else if (id == "friendspagesubtitle") {
                $("friendspagesubtitle").value = this.friendspagesubtitle_value;
            }

            return false;
        }

        function saveTitle (event, id) {
            $("#save_btn_" + id).attr("disabled", true);
            var title = $("#" + id).val();
            $.ajax({
              type: "POST",
              url: "/__rpc_journaltitle",
              data: {
                     which_title: id,
                     title_value: title,
                    "authas": authas
                     },
              success: function( data ) { $( "div.theme-titles" ).html(data);
                                        initJournalTitles();},
              dataType: "html"
            });

            event.preventDefault();
        }


        function initLayoutChooser () {
            //Handle the 'apply theme' buttons
            $(".layout-form").submit(function(event){

                applyLayout(this, event);       
            })

        }

        function applyLayout (form, event) {

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
                                        initLayoutChooser();},
          dataType: "html"
        });
                initLayoutChooser();
                event.preventDefault();
    }

        function applyTheme (event, themeid, layoutid, auth_token) {
                $("#theme_btn_" + layoutid + themeid).attr("disabled", true);
                $("#theme_btn_" + layoutid + themeid).addClass("theme-button-disabled disabled");
                $.ajax({
                  type: "POST",
                  url: "/__rpc_themechooser",
                  data: {
                         apply_themeid: themeid,
                         apply_layoutid: layoutid,
                         lj_form_auth: auth_token,
                        'authas' : authas,
                         'cat': cat,
                         'layoutid': layoutid,
                        'designer': designer,
                        'page': page,
                        'search': search,
                        'show': show },
                  success: function( data ) { $( "div.theme-selector-content" ).html(data.themechooser);
                                                $( "div.layout-selector-wrapper" ).html(data.layoutchooser);
                                                    initLayoutChooser();
                                                    initThemeChooser();
                                                    alert(confirmation);
                                                                Customize.CurrentTheme.updateContent({
                'show': show, 'authas': authas
            });},
                  dataType: "json"
                });
                event.preventDefault();

}

        function initThemeNav () {
            //Handle cat links
            $(".theme-nav-cat").click(function(event){
                    event.preventDefault();
                    console.log("clicked a cat link!");
                    var catLink = $(this).attr('href');
                    var newCat = catLink.replace(/.*cat=([^&?]*)&?.*/, "$1");
                    console.log(newCat);
                    
                    //reload the theme chooser area
                    filterThemes(event, "cat", newCat);

                    //move CSS classes around for rendering
                    $('li.on').removeClass('on');
                    $(this).parent('li').addClass('on');
                    
                        
                return false;
            })

            if ($('#search_box')) {
                //var keywords = new InputCompleteData(Customize.ThemeNav.searchwords, "ignorecase");
                //var ic = new InputComplete($('#search_box'), keywords);

                var text = "theme, layout, or designer";
                var color = "#999";
                $('#search_box').css("color", color);
                $('#search_box').val(text);
                $('#search_box').focus( function (evt) {
                    if ($('#search_box').val() == text) {
                        $('#search_box').css("color", "");
                        $('#search_box').val("");
                    }
                });
                $('#search_box').blur(function (evt) {
                    if ($('#search_box').val() == "") {
                        $('#search_box').css("color", color);
                        $('#search_box').val(text);
                    }
                });
            }

            // add event listener to the search form
            $('#search_form').submit( function (evt) { self.filterThemes(evt, "search", $('#search_box').val()) });

            }

        function initThemeChooser () {
            //Handle preview links
            $(".theme-preview-link").click(function(){
                        window.open($(this).attr("href"), 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
                return false;
            })

            //Handle the 'apply theme' buttons
            $(".theme-form").submit(function(event){
                var given_themeid = $(this).children("[name=apply_themeid]").val(); 
                var given_layoutid = $(this).children("[name=apply_layoutid]").val(); 
                var auth_token = $(this).children("[name=lj_form_auth]").val(); 

                applyTheme(event, given_themeid, given_layoutid, auth_token);

                
            })

            //Handle page select
            $("#page_dropdown_top").change(
                function (event) { filterThemes(event, "page", $(this).val()) }
            )

            $("#page_dropdown_bottom").change(
                function (event) { filterThemes(event, "page", $(this).val()) }
            )

            //Handle show select
            $("#show_dropdown_top").change(
                function (event) { filterThemes(event, "show", $(this).val()) }
            )

            $("#show_dropdown_bottom").change(
                function (event) { filterThemes(event, "show", $(this).val()) }
            )

            //Handle designer and layoutid links
            $(".theme-layout").click(function(event){
                    event.preventDefault();
                    var layoutLink = $(this).attr('href');
                    var newLayout = layoutLink.replace(/.*layoutid=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    filterThemes(event, "layoutid", newLayout);
    })

            $(".theme-designer").click(function(event){
                    event.preventDefault();
                    var designerLink = $(this).attr('href');
                    var newDesigner = designerLink.replace(/.*designer=([^&?]*)&?.*/, "$1");
                    
                    //reload the theme chooser area
                    filterThemes(event, "designer", newDesigner);
    })

}

function filterThemes (evt, key, value) {
            if (key == "show") {
                // need to go back to page 1 if the show amount was switched because
                // the current page may no longer have any themes to show on it
                page = 1;
            } else if (key != "page") {
                resetFilters();
            }

            // do not do anything with a layoutid of 0
            if (key == "layoutid" && value == 0) {
                event.preventDefault();
                return;
            }

            if (key == "cat") cat = value;
            if (key == "layoutid") layoutid = value;
            if (key == "designer") designer = value;
            if (key == "search") search = value;
            if (key == "page") page = value;
            if (key == "show") show = value;

            $.ajax({
              type: "GET",
              url: "/__rpc_themefilter",
              data: {
                    'cat': cat,
                    'layoutid': layoutid,
                    'designer': designer,
                    'search': search,
                    'page': page,
                    'show': show,
                    'authas': authas
                     },
              success: function( data ) { $( "div.theme-selector-content" ).html(data);
                                            initThemeChooser();},
              dataType: "html"
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
        }


//Initialize everything
$(document).ready(function(){

        initJournalTitles();
        initLayoutChooser();
        initThemeChooser();
        initThemeNav();
});

