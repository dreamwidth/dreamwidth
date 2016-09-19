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
    var given_themeid = $(this).children("[name=apply_themeid]").attr("value"); 
    var given_layoutid = $(this).children("[name=apply_layoutid]").attr("value"); 
    var auth_token = $(this).children("[name=lj_form_auth]").attr("value"); 
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
$(".page_dropdown_top").change(
    //Customize.filterThemes(evt, "page", $('page_dropdown_top').value)
)

$(".page_dropdown_bottom").change(
    //Customize.filterThemes(evt, "page", $('page_dropdown_bottom').value)
)

//Handle show select
$(".show_dropdown_top").change(
    //Customize.filterThemes(evt, "show", $('page_dropdown_top').value)
)

$(".show_dropdown_bottom").change(
    //Customize.filterThemes(evt, "show", $('page_dropdown_bottom').value)
)

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

initJournalTitles();


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
            var title = $("#" + id).attr(value);
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


/* From LayoutChooser widget:

        initWidget: function () {
            var self = this;

            var apply_forms = DOM.getElementsByClassName(document, "layout-form");

            // add event listeners to all of the apply layout forms
            apply_forms.forEach(function (form) {
                DOM.addEventListener(form, "submit", function (evt) { self.applyLayout(evt, form) });
            });

            if ( ! self._init ) {
                LiveJournal.register_hook( "update_other_widgets", function( updated ) { self.refreshLayoutChoices.apply( self, [ updated ] ) } )
                self._init = true;
            }
        },
        applyLayout: function (evt, form) {
            var given_layout_choice = form["Widget[LayoutChooser]_layout_choice"].value + "";
            $("layout_btn_" + given_layout_choice).disabled = true;
            DOM.addClassName($("layout_btn_" + given_layout_choice), "layout-button-disabled disabled");

            this.doPostAndUpdateContent({
                layout_choice: given_layout_choice,
                layout_prop: form["Widget[LayoutChooser]_layout_prop"].value + "",
                show_sidebar_prop: form["Widget[LayoutChooser]_show_sidebar_prop"].value
            });

            Event.stop(evt);
        },
        onData: function (data) {
            LiveJournal.run_hook("update_other_widgets", "LayoutChooser");
        },
        onRefresh: function (data) {
            this.initWidget();
        },
        refreshLayoutChoices: function( updatedWidget ) {
            if ( updatedWidget == "ThemeChooser" ) {
                this.updateContent();
            }
        }
    ];
} */
