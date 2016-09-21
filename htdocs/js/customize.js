$(document).ready(function(){

var Customize = new Object();

       var pageGetArgs = LiveJournal.parseGetArgs(document.location.href);

    Customize.cat = pageGetArgs["cat"] ? pageGetArgs["cat"] : "";
    Customize.layoutid = pageGetArgs["layoutid"] ? pageGetArgs["layoutid"] : 0;
    Customize.designer = pageGetArgs["designer"] ? pageGetArgs["designer"] : "";
    Customize.search = pageGetArgs["search"] ? pageGetArgs["search"] : "";
    Customize.page = pageGetArgs["page"] ? pageGetArgs["page"] : 1;
    Customize.show = pageGetArgs["show"] ? pageGetArgs["show"] : 12;
    Customize.hourglass = null;

console.log("code is running!")

//Handle preview links
$(".theme-preview-link").click(function(){
            window.open($(this).attr("href"), 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
    return false;
})

//Handle the 'apply theme' buttons
$(".theme-form").submit(function(event){
event.preventDefault();
    var given_themeid = $(this).children("[name=apply_themeid]").val(); 
    var given_layoutid = $(this).children("[name=apply_layoutid]").val(); 
    var auth_token = $(this).children("[name=lj_form_auth]").val(); 
    $("#theme_btn_" + given_layoutid + given_themeid).attr("disabled", true);
    $("#theme_btn_" + given_layoutid + given_themeid).addClass("theme-button-disabled disabled");
    $.ajax({
      type: "POST",
      url: "/__rpc_themechooser",
      data: {
             apply_themeid: given_themeid,
             apply_layoutid: given_layoutid,
             lj_form_auth: auth_token,
             'cat': Customize.cat,
             'layoutid': Customize.layoutid,
            'designer': Customize.designer,
            'page': Customize.page,
            'search': Customize.search,
            'show': Customize.show },
      success: function( data ) { $( "div.theme-selector-content" ).html(data);},
      dataType: "html"
    });

    
}

)



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

function filterThemes (evt, key, value) {
            if (key == "show") {
                // need to go back to page 1 if the show amount was switched because
                // the current page may no longer have any themes to show on it
                Customize.page = 1;
            } else if (key != "page") {
                Customize.resetFilters();
            }

            // do not do anything with a layoutid of 0
            if (key == "layoutid" && value == 0) {
                event.preventDefault();
                return;
            }

            if (key == "cat") Customize.cat = value;
            if (key == "layoutid") Customize.layoutid = value;
            if (key == "designer") Customize.designer = value;
            if (key == "search") Customize.search = value;
            if (key == "page") Customize.page = value;
            if (key == "show") Customize.show = value;

            $.ajax({
              type: "GET",
              url: "/__rpc_customizepaging",
              data: {
                    cat: Customize.cat,
                    layoutid: Customize.layoutid,
                    designer: Customize.designer,
                    search: Customize.search,
                    page: Customize.page,
                    show: Customize.show
                     },
              success: function( data ) { $( "div.theme-selector-content" ).html(data);},
              dataType: "html"
            });

            evt.preventDefault();

            if (key == "search") {
                $("search_btn").disabled = true;
            } else if (key == "page" || key == "show") {
                $("paging_msg_area_top").innerHTML = "<em>Please wait...</em>";
                $("paging_msg_area_bottom").innerHTML = "<em>Please wait...</em>";
            } else {
                Customize.cursorHourglass(evt);
            }
        }



// Functions for making hourglasses on our page
Customize.cursorHourglass = function (evt) {
    var posX = evt.pageX;
    var posY = evt.pageY
    if (!posX) return;

    if (!Customize.hourglass) {
        Customize.hourglass = new Hourglass();
        Customize.hourglass.init();
        Customize.hourglass.hourglass_at(posX, posY);
    }
}

Customize.elementHourglass = function (element) {
    if (!element) return;

    if (!Customize.hourglass) {
        Customize.hourglass = new Hourglass();
        Customize.hourglass.init();
        Customize.hourglass.hourglass_at_widget(element);
    }
}

Customize.hideHourglass = function () {
    if (Customize.hourglass) {
        Customize.hourglass.hide();
        Customize.hourglass = null;
    }
}

//Clear filters
Customize.resetFilters = function () {
    Customize.cat = "";
    Customize.layoutid = 0;
    Customize.designer = "";
    Customize.search = "";
    Customize.page = 1;
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

}



initJournalTitles();
initLayoutChooser();
initThemeNav();


});


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
                     title_value: title
                     },
              success: function( data ) { $( "div.theme-titles" ).html(data);},
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
                 'show_sidebar_prop': given_show_sidebar_prop },
          success: function( data ) { $( "div.layout-selector-wrapper" ).html(data);},
          dataType: "html"
        });
                initLayoutChooser();
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
        $('li .on').removeClass('on');
        $(this).parent('li').addClass('on');
        
            
    return false;
})

}
