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
                    e.preventDefault();
                    _open.apply( $.fn.tagselector.owner, [ opts ] );
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

    function _filter(event) {
        var val = $("#tagselector_search").val().toLocaleLowerCase();
        $("#tagselector_tags_list li").hide().each(function(i, item) {
            if ( $(this).text().indexOf(val) != -1 )
                $(this).show();
        });
    };

    function _dialogHTML() {
            return "<div>\
      <div class='tagselector_top'>\
        <span class='tagselector_searchbox'>\
          Search: <input type='search' id='tagselector_search'>\
          </span>\
          <button id='tagselector_select' class='ui-state-default' disabled='disabled'>Save</button>\
      </div>\
      <div id='tagselector_tags'><span class='tagselector_status'>Loading...</span></div>\
    </div>";
    };

    var _regex = new RegExp("[^a-z0-9]","ig");
    function _as_attr(tag) {
        return tag.replace(_regex, "_");
    }

    function _initTags() {
        $("button", $.fn.tagselector.instance.siblings()).prop("disabled", true);
        $(":input", $.fn.tagselector.instance).prop("disabled", true);

        var data = _tags();
        if ( !data ) {
            $("#tagselector_tags").html("<h2>Error</h2><p>Unable to load tags data</p>");
            return;
        }

        var selected = _selectedTags();

        var $tagslist = $("<ul id='tagselector_tags_list'></ul>");

        $.each(data, function(index, value) {
            var attr = _as_attr(value);
            $("<li>").append(
                $( "<input>", { "type": "checkbox", "id": "tagselector_tag_" + attr, "value": value, "checked": selected[value] } ),
                $("<label>", { "for": "tagselector_tag_" + attr } ).text(value) )
            .appendTo($tagslist)
        });

        $("#tagselector_tags").empty().append($tagslist);

        $("button", $.fn.tagselector.instance.siblings()).prop("disabled", false);
        $(":input", $.fn.tagselector.instance).prop("disabled", false);
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

            $("#tagselector_search").bind("keyup click", _filter);
            $("#tagselector_select").click(_save);

            _initTags();
        } else {
            _initTags();
            $.fn.tagselector.instance.dialog("open");
        }
    };

})(jQuery);
