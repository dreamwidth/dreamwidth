jQuery(function($) {

function saveOriginalValues(elements) {
    elements.filter(":radio, :checkbox").each(function() {
        var $this = $(this);
        $this.data("originalValue",  $this.is(":selected") || $this.is(":checked"));
    });
}

var $inputs = $("#post-options input");
saveOriginalValues($inputs);

$("#post-options").bind( "settings.cancel", function() {
    stopEditing();

    // restore to original
    $inputs.filter(":radio").each(function(i,val) {
        var $this = $(this);
        if ($this.data("originalValue") != $this.is(":selected") ) $this.click();
    }).end()
    .filter(":checkbox").each(function(i,val) {
        var $this = $(this);
        if ($this.data("originalValue") != $this.is(":checked") ) $this.click();
    });
})

var $cancel_button = $("<input>", { "type": "submit", "value" : "Cancel" }).click(function(e) {
    e.preventDefault();

    $("#post-options").trigger("settings.cancel");

}).wrap("<fieldset class='destructive submit'></fieldset>").parent();

$inputs
.filter(":submit").click(function(e) {
    e.preventDefault();

    var postPanels = [];
    $(".column").each(function(columnNum) {
        var ids = $(this).sortable("toArray");
        for ( var i = 0; i < ids.length; i++ ) {
            if ( ids[i] != "" )
                postPanels.push( { "name" : "column_"+columnNum, "value": i+":"+ids[i] } );
        }
    })

    var post = $(this.form).serialize();
    var sep = ( post == "" ) ? "" : "&";
    var jqxhr = $.post( Site.siteroot + "/__rpc_entryoptions", post + sep + $.param(postPanels) )
        .success(function () {
            stopEditing();
            saveOriginalValues($inputs);
        } )
        .error(function(response) {
            $("#settings-tools").html(response.responseText)
        });
    $(this).throbber( "before", jqxhr );
})
    .parent().after($cancel_button).end()
.end()
.filter(":checkbox[name='visible_panels']").click(function() {
    // remove "panel_"
    $("#"+this.id.substr(6)+"_component").toggleClass("inactive_component")
}).end()
.filter(":radio[name='entry_field_width']").click(function() {
    var val = $(this).val();
    $("#post_entry").toggleClass("entry-full-width", val == "F" )
        .toggleClass("entry-partial-width", val == "P" );
}).end();

$("#minimal_animations").click(function() {
    $.fx.off = $(this).is(":checked");
});

$(".panels-list").append("<p class='note'>Scroll down to arrange panels to your preference</p>")


if ($(".sortable_column_text").length == 0) {
    $.getScript(Site.siteroot + "/js/jquery/jquery.ui.mouse.min.js",
        function() { $.getScript(Site.siteroot + "/js/jquery/jquery.ui.sortable.min.js",
            setupSortable
        ) }
    );
}

function setupSortable() {
    var $draginstructions = $("<div class='sortable_column_text'>drag and drop to rearrange</div>").disableSelection();

    $(".column").sortable({
      connectWith: ".column",
      placeholder: "ui-state-highlight",
      forcePlaceholderSize: true,
      opacity: 0.8,
      cancel: ".sortable_column_text"
    })
    .sortable( "enable" ).disableSelection()
    .append($draginstructions);
}

startEditing();

function stopEditing() {
    if ( $.fn.sortable )
        $(".column").sortable( "disable" ).enableSelection();
    $(document.body).removeClass("screen-customize-mode");

    $("#post-options").slideUp();
}

function startEditing() {
    if ( $.fn.sortable )
        $(".column").sortable( "enable" ).disableSelection();
    $(document.body).addClass("screen-customize-mode");
}

});
