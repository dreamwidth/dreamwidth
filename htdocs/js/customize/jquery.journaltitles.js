(function($) {

function JournalTitles($el) {
    var journalTitles = this;
    journalTitles.init();
}

JournalTitles.prototype = {
      init: function () {
            var journalTitles = this;

            // show view mode
            $(".title_view").css("display", "inline");
            $(".title_cancel").css("display", "inline");
            $(".title_modify").css("display", "none");

            // set up handlers

            $(".title_edit").click(function(event) { journalTitles.editTitle(event); });
            $(".title_cancel").click(function(event) { journalTitles.cancelTitle(event); });
            $(".title_form").submit(function(event){ journalTitles.saveTitle(event) });

        },

        editTitle: function (event) {
            event.preventDefault();
            var title = $(event.target).closest(".title_form");

            title.find(".title_modify").css("display", "inline");
            title.find(".title_view").css( "display",  "none");
            title.find(".title_input").focus();

            $(".title_form").each(function() {
                if (!$( this ).is(title)) {
                    $( this ).find(".title_cancel").click();
                }
            });


            return false;
        },

        cancelTitle: function (event) {
            event.preventDefault();
            var title = $(event.target).closest(".title_form");

            title.find(".title_modify").css("display", "none");
            title.find(".title_view").css( "display",  "inline");

            // reset appropriate field to default
            title.find(".title_input").value = title.find(".title").value;

            return false;
        },

        saveTitle: function (event) {
            event.preventDefault();
            var journalTitles = this;
            var title = $(event.target).closest(".title_form");

            title.find(".title_save").attr("disabled", true);
            var value = title.find("input[name=title_value]").val();
            var which = title.find(".which_title").val();
            $.ajax({
              type: "POST",
              url: "/__rpc_journaltitles",
              data: {
                     which_title: which,
                     title_value: value,
                    //"authas": authas
                     },
              success: function( data ) { $( "div.theme-titles" ).html(data);
                                        journalTitles.init();},
              dataType: "html"
            });

            return false
        }
}



$.fn.extend({
    journalTitles: function() {
        new JournalTitles( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $(".appwidget-journaltitles").journalTitles();
});