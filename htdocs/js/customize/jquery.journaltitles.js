var JournalTitles = {
      init: function () {
            console.log("trying to initialize");
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
            $("#journaltitle_edit").click(function(event) { JournalTitles.editTitle(event, "journaltitle"); });
            $("#journalsubtitle_edit").click(function(event) { JournalTitles.editTitle(event, "journalsubtitle"); });
            $("#friendspagetitle_edit").click(function(event) { JournalTitles.editTitle(event, "friendspagetitle"); });
            $("#friendspagesubtitle_edit").click(function(event) { JournalTitles.editTitle(event, "friendspagesubtitle"); });

            // set up cancel links
            $("#journaltitle_cancel").click(function(event) { JournalTitles.cancelTitle(event, "journaltitle"); });
            $("#journalsubtitle_cancel").click(function(event) { JournalTitles.cancelTitle(event, "journalsubtitle"); });
            $("#friendspagetitle_cancel").click(function(event) { JournalTitles.cancelTitle(event, "friendspagetitle"); });
            $("#friendspagesubtitle_cancel").click(function(event) { JournalTitles.cancelTitle(event, "friendspagesubtitle"); });


            // set up save forms
            $("#journaltitle_form").submit(function(event){ JournalTitles.saveTitle(event, "journaltitle") });
            $("#journalsubtitle_form").submit(function(event){ JournalTitles.saveTitle(event, "journalsubtitle") });
            $("#friendspagetitle_form").submit(function(event){ JournalTitles.saveTitle(event, "friendspagetitle") });
            $("#friendspagesubtitle_form").submit(function(event){ JournalTitles.saveTitle(event, "friendspagesubtitle") });

        },

        editTitle: function (event, id) {
            event.preventDefault();

            $("#" + id + "_modify").css("display", "inline");
            $("#" + id + "_view").css( "display",  "none");
            $("#" + id).focus();

            // cancel any other titles that are being edited since
            // we only want one title in edit mode at a time
            if (id == "journaltitle") {
                JournalTitles.cancelTitle(event, "journalsubtitle");
                JournalTitles.cancelTitle(event, "friendspagetitle");
                JournalTitles.cancelTitle(event, "friendspagesubtitle");
            } else if (id == "journalsubtitle") {
                JournalTitles.cancelTitle(event, "journaltitle");
                JournalTitles.cancelTitle(event, "friendspagetitle");
                JournalTitles.cancelTitle(event, "friendspagesubtitle");
            } else if (id == "friendspagetitle") {
                JournalTitles.cancelTitle(event, "journaltitle");
                JournalTitles.cancelTitle(event, "journalsubtitle");
                JournalTitles.cancelTitle(event, "friendspagesubtitle");
            } else if (id == "friendspagesubtitle") {
                JournalTitles.cancelTitle(event, "journaltitle");
                JournalTitles.cancelTitle(event, "journalsubtitle");
                JournalTitles.cancelTitle(event, "friendspagetitle");
            }


            return false;
        },

        cancelTitle: function (event, id) {
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
        },

        saveTitle: function (event, id) {
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
                                        JournalTitles.init},
              dataType: "html"
            });

            event.preventDefault();
        }
}

jQuery(document).ready(function(){
    JournalTitles.init();
})
