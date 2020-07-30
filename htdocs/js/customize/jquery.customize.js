jQuery(function($){

var authas = $('#authas').val();

// Set up journaltitles functions
function editTitle(event) {
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
        }

function cancelTitle(event) {
    event.preventDefault();
    var title = $(event.target).closest(".title_form");

    title.find(".title_modify").css("display", "none");
    title.find(".title_view").css( "display",  "inline");

    // reset appropriate field to default
    title.find(".title_input").value = title.find(".title").value;

    return false;
}

function saveTitle(event) {
    event.preventDefault();
    var journalTitles = this;
    var title = $(event.target).closest(".title_form");

    title.find(".title_save").attr("disabled", true);
    var value = title.find("input[name=title_value]").val();
    var which = title.find(".which_title").val();
    var postData = {
            which_title: which,
            title_value: value
             };
    if (authas)  postData.authas = authas;

    $.ajax({
      type: "POST",
      url: "/__rpc_journaltitles",
      data: postData,
      success: function( data ) {
          title.find(".title_modify").css("display", "none");
          title.find(".title_view").css( "display",  "inline");
          title.find(".title").text(value);
          title.find(".title_save").attr("disabled", false);
        },

      dataType: "html"
    });

    return false
}
// show view mode & set up handlers for journaltitles
$(".title_view").css("display", "inline");
$(".title_cancel").css("display", "inline");
$(".title_modify").css("display", "none");

$(".title_edit").click(function(event) { editTitle(event); });
$(".title_cancel").click(function(event) { cancelTitle(event); });
$(".title_form").submit(function(event){ saveTitle(event) });

// set up layoutchooser functions
function applyLayout(form, event) {
        var given_layout_choice = $(form).children("[name=layout_choice]").val();
        var given_layout_prop = $(form).children("[name=layout_prop]").val();
        var given_show_sidebar_prop = $(form).children("[name=show_sidebar_prop]").val();

        $("#layout_btn_" + given_layout_choice).attr("disabled", true);
        $("#layout_btn_" + given_layout_choice).addClass("layout-button-disabled disabled");

        var postData = {
                 'layout_choice': given_layout_choice,
                 'layout_prop': given_layout_prop,
                 'show_sidebar_prop': given_show_sidebar_prop
              }
        if (authas)  postData.authas = authas;


        $.ajax({
          type: "POST",
          url: "/__rpc_layoutchooser",
          data: postData,
          success: function( data ) { $( "div.layout-selector-wrapper" ).html(data); },
          dataType: "html"
        });
        event.preventDefault();
}

// init event listeners for layoutchooser
$(".layout-selector-wrapper").on("submit", ".layout-form", function(event){
    event.preventDefault();
    applyLayout(this, event);
});

// init event listeners for currenttheme
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

});