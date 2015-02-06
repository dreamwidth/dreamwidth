(function($) {

function TagBrowser($el, options) {
    var tagBrowser = this;

    $.extend(tagBrowser, {
        element: $el,
        modal: $("#" + options.modalId),
        modalId: options.modalId
    });

    $("<button class='small secondary'>browse</button>")
        .attr("data-reveal-id", options.modalId)
        .insertAfter(options.fallbackLink || $(this).closest("div"));

    if (options.fallbackLink) {
        $(options.fallbackLink).remove();
    }

    $(document)
        .on('open.fndtn.reveal', "#" + options.modalId, function(e) {
            // hackety hack -- being triggered on both 'open' and 'open.fndtn.reveal'; just want once
            if (e.namespace === "") return;

            tagBrowser.loadTags();
            tagBrowser.registerListeners();
        });
}

var attributeCharRegex = new RegExp("[^a-z0-9]","ig");
function validAttribute(text) {
    return text.replace(attributeCharRegex, "_");
}

TagBrowser.prototype = {
    newTags: undefined,
    isLoaded: false,
    listenersRegistered: false,
    tagsData: function(full) {
        var tags_data = this.element.data("autocompletewithunknown");
        if (!tags_data)
            return null;

        return full ? tags_data : tags_data.cache[tags_data.currentCache];
    },
    tagsJournal: function() {
        var tags_data = this.tagsData(true);
        return tags_data ? tags_data.currentCache : "";
    },
    selectedTags: function() {
        var tags = this.tagsData(true);
        if (tags) {
            var selected = tags.tagslist;
            var cachedTags = tags.cachemap[tags.currentCache];
            var newTags = [];

            $.each(selected, function(key, value) {
                if (!cachedTags[key])
                    newTags.push(key);
            });

            this.newTags = newTags;
            return selected;
        }
        return {};
    },
    loadTags: function() {
        var tagBrowser = this;
        var tagJournalLoaded = "journal-tags-loaded--" + this.tagsJournal();
        var $content = $("#js-tag-browser-content");
        if ( tagBrowser[tagJournalLoaded] ) {
            $content.find("input").prop("checked", false);
            this.resetFilter();

            var selected = this.selectedTags();
            $.each(selected, function(key, value) {
                var attr = validAttribute(key);
                $("#tag-browser-tag-" + attr).prop("checked", true);
            });

        } else {
            tagBrowser.modal.find(":input[type=search]").prop("disabled", true);

            var $status = $content.find(".tag-browser-status");

            var data = this.tagsData();
            if (!data) {
                $status.html("<p>Unable to load tags</p>");
                return;
            }

            $status.remove();

            var $tagslist = $content.find("ul");
            $tagslist.empty();

            var selected = this.selectedTags();
            $.each(data, function(index, value) {
                var attr = validAttribute(value);
                $("<li>").append(
                    $( "<input>", { "type": "checkbox", "id": "tag-browser-tag-" + attr, "value": value, "checked": selected[value] } ),
                    $("<label>", { "for": "tag-browser-tag-" + attr } ).text(value) )
                .appendTo($tagslist)
            });

            tagBrowser.modal.find(":input[type=search]")
                .prop("disabled", false)
                .focus();

            tagBrowser[tagJournalLoaded] = true;
        }
    },
    updateOwner: function(e) {
        // hackety hack -- being triggered on both 'close' and 'close.fndtn.reveal'; just want once
        if (e.namespace === "") return;

        // add in newly checked
        var selected = [];
        $("#js-tag-browser-content input:checked").each(function() {
            selected.push($(this).val());
        });

        // save new tags (no checkbox, were input via textbox)
        if (this.newTags)
            selected.push(this.newTags);

        this.element.trigger("autocomplete_inittext", selected.join(","));

        this.close();
    },
    close: function() {
        this.modal.foundation('reveal', 'close');
    },
    closeByEnter: function(e) {
        if (e.keyCode && e.keyCode === 13)
            this.close();
    },
    filter: function(e) {
        var val = $(e.target).val().toLocaleLowerCase();
        $("#js-tag-browser-content li").hide().each(function(i, item) {
            if ( $(this).text().indexOf(val) != -1 )
                $(this).show();
        });
    },
    resetFilter: function() {
        $("#js-tag-browser-search").val("");
        $("#js-tag-browser-content li").show();
    },
    deregisterListeners: function() {
        $(document).off('keydown.tag-browser');
    },
    registerListeners: function() {
        $(document).on('keydown.tag-browser', this.closeByEnter.bind(this));

        if ( this.listenersRegistered ) return;

        $("#js-tag-browser-search").bind("keyup click", this.filter.bind(this));
        $("#js-tag-browser-select").on("click", this.updateOwner.bind(this));

        $(document)
            .on('closed.fndtn.reveal', '#' + this.modalId, this.deregisterListeners.bind(this));


        this.listenersRegistered = true;
    }
};

$.fn.extend({
    tagBrowser: function(options) {

        return $(this).each(function(){
            var defaults = {
                fallbackLink: "#js-taglist-link",
                modalId: "js-tag-browser"
            };

            new TagBrowser($(this), $.extend({}, defaults, options));
        });

    }
});

})(jQuery);
