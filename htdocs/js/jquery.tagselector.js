(function($) {
    var tagCache = {};
    var opts;

    $.fn.tagselector = function( options ) {
        opts = $.extend({}, $.fn.tagselector.defaults, options );

        $.fn.tagselector.owner = $(this);

        if ( opts.fallbackLink ) {
            $(opts.fallbackLink).remove();
        }

        $("<button class='tagselector_trigger ui-state-default'>browse</button>")
            .click(function(e) {
                    _open.apply( $.fn.tagselector.owner, [ opts ] );
                    e.preventDefault();
            })
            .insertAfter($(this).closest("div"));

        return $(this);
    };

    $.fn.tagselector.defaults = {
        title: 'Choose Tags',
        width: "70%",
        height: $(window).height() * 0.8,
        onSelect: function() {},
        fallbackLink: undefined
    };

    function _tags() {
        // FIXME: more generic, please
        var tags_data = $("#taglist").data("autocompletewithunknown");
        return tags_data ? tags_data.cache[tags_data.currentCache] : null;
    }

    function _selectedTags() {
        var tags_data = $("#taglist").data("autocompletewithunknown");
        if ( tags_data ) {
            var selected = tags_data.tagslist;
            var cachedTags = tags_data.cachemap[tags_data.currentCache];
            var newTags = [];

            $.each(selected, function(key, value) {
                if (!cachedTags[key])
                    newTags.push(key);
            });

            $("#tagselector_tags").data("new", newTags);
            return selected;
        }

        return {};
    }

    function _updateSelectedTags(tags) {
        $("#taglist").trigger("autocomplete_inittext", tags);
    }

    function _selectContainer($container, keyword, replaceKwMenu) {
        $("#"+$.fn.tagselector.selected).removeClass(opts.selectedClass);
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
                $("#iconselector_select").removeAttr("disabled");
            else
                $("#iconselector_select").attr("disabled", "disabled");
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

    function _filter(event) {
        var val = $("#tagselector_search").val().toLocaleLowerCase();
        $("#tagselector_tags_list li").hide().each(function(i, item) {
            if ( $(this).text().indexOf(val) != -1 )
                $(this).show();
        });

        var $visible = $("#tagselector_tags_list li:visible");
        if ( $visible.length == 1 )
            _selectContainer($visible);
    };

    function _dialogHTML() {
            return "<div>\
      <div class='tagselector_top'>\
        <span class='tagselector_searchbox'>\
          Search: <input type='text' id='tagselector_search'>\
          </span>\
          <button id='tagselector_select' disabled='disabled'>Save</button>\
      </div>\
      <div id='tagselector_tags'><span class='tagselector_status'>Loading...</span></div>\
    </div>";
    };

    function _initTags() {
        $("button", $.fn.tagselector.instance.siblings()).attr("disabled", "true");
        $(":input", $.fn.tagselector.instance).attr("disabled", "true");

        var data = _tags();
        if ( !data ) {
            $("#tagselector_tags").html("<h2>Error</h2><p>Unable to load tags data</p>");
            return;
        }

        var selected = _selectedTags();

        var $tagslist = $("<ul id='tagselector_tags_list'></ul>");

        $.each(data, function(index, value) {
            var checked = selected[value] ? "checked='checked'" : "";
            $("<li><input type='checkbox' id='tagselector_tag_"+value+"' value='"+value+"' "+checked+"/><label for='tagselector_tag_"+value+"'>"+value+"</label></li>").appendTo($tagslist);
        });

        $("#tagselector_tags").empty().append($tagslist);

        $("button", $.fn.tagselector.instance.siblings()).removeAttr("disabled");
        $(":input", $.fn.tagselector.instance).removeAttr("disabled");
    }

    function _save() {
        // remove newly unchecked
        // make sure new doesn't get lost
        // add in newly checked
        var selected = [];
        $("#tagselector_tags_list input:checked").each(function() {
            selected.push($(this).val());
        });

        if ($("#tagselector_tags").data("new"))
            selected.push($("#tagselector_tags").data("new"));

        _updateSelectedTags(selected.join(","));

        $.fn.tagselector.instance.dialog("close");
    }

    function _open () {
        if ( ! $.fn.tagselector.instance ) {
            $.fn.tagselector.instance = $(_dialogHTML());

            $.fn.tagselector.instance.dialog( { title: opts.title, width: opts.width, height: opts.height, dialogClass: "tagselector", modal: true,
                close: function() {    $.fn.tagselector.owner.parent().find(":input").focus(); },
                resize: function() {
                    $("#tagselector_tags").height(
                        $.fn.tagselector.instance.height() -
                        $.fn.tagselector.instance.find('.tagselector_top').height()
                        - 5
                    );
                }
             } ).keydown(function(event) {
                if (event.keyCode && event.keyCode === $.ui.keyCode.ENTER) {
                    _save();

                    event.stopPropagation();
                    event.preventDefault();
                }
            });

            $("#tagselector_tags").height(
                $.fn.tagselector.instance.height() -
                $.fn.tagselector.instance.find('.tagselector_top').height()
                - 5
            );

            $("#tagselector_search").bind("keyup", _filter);
            $("#tagselector_select").click(_save);

            _initTags();
        } else {
            _initTags();
            $.fn.tagselector.instance.dialog("open");
        }
    };

})(jQuery);
