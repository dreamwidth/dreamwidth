jQuery(function($) {
    function saveOriginalValues(elements) {
        elements.filter(":radio, :checkbox").each(function() {
            var $this = $(this);
            $this.data("originalValue",  $this.is(":selected") || $this.is(":checked"));
        });
    }

    var $inputs = $("#js-settings-panel input");
    saveOriginalValues($inputs);

    var $cancel_button = $("<button class='secondary right'>Cancel</button>").click(function(e) {
        e.preventDefault();

        $("#js-settings-panel").trigger( "settings.cancel" );
    });

    $inputs
        .filter(":submit")
            .after($cancel_button)
            .click(function(e) {
                    e.preventDefault();

                    var postPanels = [];
                    if ( $.fn.sortable ) {
                        $(".ui-sortable").each(function(columnNum) {
                            var panelNames = $(this).sortable("toArray", { attribute: "data-collapse"});
                            for ( var i = 0; i < panelNames.length; i++ ) {
                                if ( panelNames[i] != "" )
                                    postPanels.push( { "name" : "column_"+columnNum, "value": i+":"+panelNames[i] } );
                            }
                        });
                    }

                    var post = $(this.form).serialize();
                    var sep = ( post == "" ) ? "" : "&";
                    var jqxhr = $.post( Site.siteroot + "/__rpc_entryoptions", post + sep + $.param(postPanels) )
                        .success(function () {
                            stopEditing();
                            saveOriginalValues($inputs);
                        } )
                        .error(function(response) {
                            $("#js-settings-panel").html(response.responseText)
                        });

                    $(this).throbber( jqxhr );
                })
        .end()
        .filter(":checkbox[name='visible_panels']")
            .click(function() {
                $("." + this.value + "-component").toggleClass("inactive-component");
            })
        .end()
        .filter(":radio[name='entry_field_width']")
            .click(function() {
                var val = $(this).val();
                $("#js-post-entry")
                    .toggleClass("entry-full-width", val == "F" )
                    .toggleClass("entry-partial-width", val == "P" );
            })
        .end();

    $("#js-settings-panel").bind( "settings.cancel", function() {
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
    });

    $("#js-minimal-animations").click(function() {
        $.fx.off = $(this).is(":checked");
    });

    function stopEditing() {
        if ( $.fn.sortable )
            $(".ui-sortable").sortable( "disable" ).enableSelection();
        $(document.body).removeClass("screen-customize-mode");

        $("#js-settings-panel").slideUp();
    }

    function startEditing() {
        if ( $.fn.sortable )
            $(".ui-sortable").sortable( "enable" ).disableSelection();
        $(document.body).addClass("screen-customize-mode");
    }

    if ($(".sortable-column-text").length == 0) {
        $.getScript(Site.siteroot + "/js/jquery/jquery.ui.mouse.min.js",
            function() { $.getScript(Site.siteroot + "/js/jquery/jquery.ui.sortable.min.js",
                setupSortable
            ) }
        );
    }

    function setupSortable() {
        var $draginstructions = $("<div class='sortable-column-text'>drag and drop to rearrange</div>").disableSelection();

        $(".sortable-components > .inner").sortable({
          connectWith: ".sortable-components > .inner",
          placeholder: "panel callout",
          forcePlaceholderSize: true,
          opacity: 0.8,
          cancel: ".sortable_column_text"
        })
        .sortable( "enable" ).disableSelection()
        .append($draginstructions);
    }

    startEditing();
});
