(function($) {
    var kwtoicon = {};
    var opts;

    $.fn.iconselector = function( options ) {
        opts = $.extend({}, $.fn.iconselector.defaults, options );

        $.fn.iconselector.owner = $(this);

        if( opts.selectorButtons ) {
            $(opts.selectorButtons)
                .click(function(e) {
                    _open.apply( $.fn.iconselector.owner, [ opts ] );
                    e.preventDefault();
                });
        }

        return $(this).wrap("<span class='iconselect_trigger_wrapper'></span>");
    };

    // selected icon
    $.fn.iconselector.selected = null;
    // selected keyword
    $.fn.iconselector.selectedKeyword = null;

    $.fn.iconselector.defaults = {
        title: 'Choose Icon',
        width: "70%",
        height: $(window).height() * 0.8,
        selectedClass: "iconselector_selected",
        onSelect: function() {},
        selectorButtons: null,

        // user options
        metatext: true,
        smallicons: false
    };

    function _dialogHTML() {
            return "<div>\
      <div class='iconselector_top'>\
        <span class='iconselector_searchbox'>\
          Search: <input type='search' id='iconselector_search'>\
        </span>\
        <span class='image-text-toggle' id ='iconselector_image_text_toggle'>\
          <span class='toggle-meta-on'>Meta text / <a href='#' class='no_meta_text'>No meta text</a></span>\
          <span class='toggle-meta-off'><a href='#' class ='meta_text'>Meta text</a> / No meta text</span>\
        </span>\
        <span class='image-size-toggle' id='iconselector_image_size_toggle'>\
          <span class='toggle-half-image'>Small images / <a href='#' class='full_image'>Large images</a></span>\
          <span class='toggle-full-image'><a href='#' class='half_image'>Small images</a> / Large images</span>\
        </span>\
        <div class='kwmenu'>\
          <label for='iconselector_kwmenu'>Keywords of selected icon:</label>\
          <div class='keywords'></div>\
          <input id='iconselector_select' disabled='disabled' type='button' value='Select'>\
        </div>\
      </div>\
      <div id='iconselector_icons'><span class='iconselector_status'>Loading...</span></div>\
    </div>";
    };

    function _selectContainer($container, keyword, replaceKwMenu) {
        $("#"+$.fn.iconselector.selected).removeClass(opts.selectedClass);
        if ( $container.length == 0 ) return;

        $.fn.iconselector.selected = $container.attr("id");
        $container.addClass(opts.selectedClass);
        $container.show();

        if ( keyword != null ) {
            // select by keyword
            $.fn.iconselector.selectedKeyword = keyword;
        } else {
            // select by picid (first keyword)
            $.fn.iconselector.selectedKeyword = $container.data("defaultkw");
        }

        if ( replaceKwMenu ) {
            var $keywords = $container.find(".keywords");
            $(".iconselector_top .keywords", $.fn.iconselector.instance)
                .replaceWith($keywords.clone());
            if ($keywords.length > 0)
                $("#iconselector_select").prop("disabled", false);
            else
                $("#iconselector_select").prop("disabled", true);
        } else {
            $(".iconselector_top .selected", $.fn.iconselector.instance)
                .removeClass("selected");
        }

        // can't rely on a cached value, because it may have been replaced
        $(".iconselector_top .keywords", $.fn.iconselector.instance)
            .find("a.keyword")
            .filter(function() {
                return $(this).text() == $.fn.iconselector.selectedKeyword;
            })
            .addClass("selected");
    }

    function _selectByKeyword(keyword) {
        var iconcontainer_id = kwtoicon[keyword];
        if ( iconcontainer_id )
            _selectContainer($("#"+iconcontainer_id), keyword, true);
    }

    function _selectByKeywordClick(event) {
        var $keyword = $(event.target).closest("a.keyword");
        if ( $keyword.length > 0 ) {
            var keyword = $keyword.text();
            var iconcontainer_id = kwtoicon[keyword];
            if ( iconcontainer_id )
                _selectContainer($("#"+iconcontainer_id), keyword, false);
        }

        event.stopPropagation();
        event.preventDefault();
    }

    function _selectByClick(event) {
        var $icon = $(event.target).closest("li");
        var $keyword = $(event.target).closest("a.keyword");

        _selectContainer($icon, $keyword.length > 0 ? $keyword.text() : null, true);

        event.stopPropagation();
        event.preventDefault();
    };

    function _selectByEnter(event) {
        if (event.keyCode && event.keyCode === $.ui.keyCode.ENTER) {
            var $originalTarget = $(event.originalTarget);
            if ($originalTarget.hasClass("keyword")) {
                $originalTarget.click();
            } else if ($originalTarget.is("a")) {
                return;
            }
            _selectCurrent();
        }
    }

    function _selectCurrent() {
        if ($.fn.iconselector.selectedKeyword) {
            $.fn.iconselector.owner.val($.fn.iconselector.selectedKeyword);
            $.fn.iconselector.owner.trigger("change");
            opts.onSelect.apply($.fn.iconselector.owner[0]);
            $.fn.iconselector.instance.dialog("close");
        }
    }

    function _filterPics(event) {
        var val = $("#iconselector_search").val().toLocaleUpperCase();
        $("#iconselector_icons_list li").hide().each(function(i, item) {
            if ( $(this).data("keywords").indexOf(val) != -1 || $(this).data("comment").indexOf(val) != -1
                || $(this).data("alt").indexOf(val) != -1 ) {

                $(this).show();
             }
        });

        var $visible = $("#iconselector_icons_list li:visible");
        if ( $visible.length == 1 )
            _selectContainer($visible, null, true);
    };

    function _persist( option, value ) {
        var params = {};
        params[option] = value;

        // this is a best effort thing, so be silent about success/error
        $.post( "/__rpc_iconbrowser_save", params );
    }

    function _open () {
        if ( ! $.fn.iconselector.instance ) {
            $.fn.iconselector.instance = $(_dialogHTML());

            $.fn.iconselector.instance.dialog( { title: opts.title, width: opts.width, height: opts.height, dialogClass: "iconselector", modal: true,
                close: function() { $("#iconselect").focus(); },
                resize: function() {
                    $("#iconselector_icons").height(
                        $.fn.iconselector.instance.height() -
                        $.fn.iconselector.instance.find('.iconselector_top').height()
                        - 5
                    );
                }
             } )
            .keydown(_selectByEnter);


            $("#iconselector_image_size_toggle a").click(function(e, init) {
                if ($(this).hasClass("half_image") ) {
                    $("#iconselector_icons, #iconselector_image_size_toggle, #iconselector_icons_list").addClass("half_icons");
                    if ( ! init ) _persist( "smallicons", true );
                } else {
                    $("#iconselector_icons, #iconselector_image_size_toggle, #iconselector_icons_list").removeClass("half_icons");
                    if ( ! init ) _persist( "smallicons", false );
                }

                //refocus
                $("#iconselector_image_size_toggle a:visible:first").focus();

                return false;
            }).filter( opts.smallicons ? ".half_image" : ":not(.half_image)" )
                    .triggerHandler("click", true);

            $("#iconselector_image_text_toggle a").click(function(e, init) {
                if ($(this).hasClass("no_meta_text") ) {
                    $("#iconselector_icons, #iconselector_image_text_toggle, #iconselector_icons_list").addClass("no_meta");
                    if ( ! init ) _persist( "metatext", false );
                } else {
                    $("#iconselector_icons, #iconselector_image_text_toggle, #iconselector_icons_list").removeClass("no_meta");
                    if ( ! init ) _persist( "metatext", true );
                }

                // refocus because we just hid the link we clicked on
                $("#iconselector_image_text_toggle a:visible:first").focus();

                return false;
            }).filter( opts.metatext ? ":not(.no_meta_text)" : ".no_meta_text" )
                    .triggerHandler("click", true);

            $("#iconselector_icons").height(
                $.fn.iconselector.instance.height() -
                $.fn.iconselector.instance.find('.iconselector_top').height()
                - 5
            );

            $("button", $.fn.iconselector.instance.siblings()).prop("disabled", true);
            $(":input", $.fn.iconselector.instance).prop("disabled", true);
            $("#iconselector_search", $.fn.iconselector.instance).bind("keyup click", _filterPics);

            var url = Site.currentJournalBase ? "/" + Site.currentJournal + "/__rpc_userpicselect" : "/__rpc_userpicselect";
            $.getJSON(url,
                function(data) {
                    if ( !data ) {
                        $("#iconselector_icons").html("<h2>Error</h2><p>Unable to load icons data</p>");
                        return;
                    }

                    if ( data.alert ) {
                        $("#iconselector_icons").html("<h2>Error</h2><p>"+data.alert+"</p>");
                        return;
                    }

                    var $iconslist = $("<ul id='iconselector_icons_list'></ul>");

                    var pics = data.pics;
                    $.each(data.ids, function(index,id) {
                        var icon = pics[id];
                        var idstring = "iconselector_item_"+id;

                        var $img = $("<img />").attr( { src: icon.url, alt: icon.alt, height: icon.height, width: icon.width } ).wrap("<div class='icon_image'></div>").parent();
                        var $keywords = "";
                        if ( icon.keywords ) {
                            $keywords = $("<div class='keywords'></div>");
                            var last = icon.keywords.length - 1;

                            $.each(icon.keywords, function(i, kw) {
                                kwtoicon[kw] = idstring;
                                $keywords.append( $("<a href='#' class='keyword'></a>").text(kw) );
                                if ( i < last )
                                    $keywords.append(document.createTextNode(", "));
                            });
                        }

                        var $comment = ( icon.comment != "" ) ? $("<div class='icon-comment'></div>").text( icon.comment ) : "";

                        var $meta = $("<div class='meta_wrapper'></div>").append($keywords).append($comment);
                        var $item = $("<div class='iconselector_item'></div>").append($img).append($meta);
                        $("<li></li>").append($item).appendTo($iconslist)
                            .data( "keywords", icon.keywords.join(" ").toLocaleUpperCase() )
                            .data( "comment", icon.comment.toLocaleUpperCase() )
                            .data( "alt", icon.alt.toLocaleUpperCase() )
                            .data( "defaultkw", icon.keywords[0] )
                            .attr( "id", idstring );
                    });

                    $("#iconselector_icons").empty().append($iconslist);

                    $("button", $.fn.iconselector.instance.siblings()).prop("disabled", false);
                    $(":input:not([id='iconselector_select'])", $.fn.iconselector.instance).prop("disabled", false);
                    $("#iconselector_icons_list")
                        .click(_selectByClick)
                        .dblclick(function(e) {
                            _selectByClick(e);
                            _selectCurrent();
                        });

                    $(".iconselector_top .kwmenu", $.fn.iconselector.instance)
                        .click(_selectByKeywordClick)
                        .dblclick(function(e) {
                            _selectByKeywordClick(e);
                            _selectCurrent();
                        });


                    $("#iconselector_search").focus();

                    $("#iconselector_select").click(_selectCurrent);
                    $(document).bind("keydown.dialog-overlay", _selectByEnter);

                    // initialize
                    _selectByKeyword($.fn.iconselector.owner.val());
                 });
        } else {
            // reinitialize
            _selectByKeyword($.fn.iconselector.owner.val());
            $.fn.iconselector.instance.dialog("open");
            $("#iconselector_search").focus();

            $(document).bind("keydown.dialog-overlay", _selectByEnter);
        }
    };

})(jQuery);
