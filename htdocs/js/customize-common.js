       

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




        function applyLayout (form, event) {
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
                                        initLayoutChooser();},
          dataType: "html"
        });
                initLayoutChooser();
                event.preventDefault();
    }

            function initLayoutChooser () {
            //Handle the 'apply theme' buttons
            $(".layout-form").submit(function(event){
                event.preventDefault();
                applyLayout(this, event);       
            })

        }

    //Initialize everything
jQuery(document).ready(function(){

        initJournalTitles();
        initLayoutChooser();

});
