(function($) {

function IconBrowser($el, options) {
    var iconBrowser = this;

    $.extend(iconBrowser, {
        element: $el,
        modal: $("#" + options.modalId),
        modalId: options.modalId
    });

    $(options.triggerSelector).attr("data-reveal-id", options.modalId);

    new Options(this.modal, options.preferences);

    $(document)
        .on('open.fndtn.reveal', "#" + options.modalId, function(e) {
            // hackety hack -- being triggered on both 'open' and 'open.fndtn.reveal'; just want one
            if (e.namespace === "") return;

            iconBrowser.loadIcons();
            iconBrowser.registerListeners();
        });
}

IconBrowser.prototype = {
    kwToIcon: {},
    selectedId: undefined,
    selectedKeyword: undefined,
    isLoaded: false,
    listenersRegistered: false,
    loadIcons: function() {
        var iconBrowser = this;
        if ( iconBrowser.isLoaded ) {
            iconBrowser.resetFilter();
            iconBrowser.initializeKeyword();
        } else {
            iconBrowser.modal.find(":input[type=search]").prop("disabled", true);

            var url = Site.currentJournalBase ? "/" + Site.currentJournal + "/__rpc_userpicselect" : "/__rpc_userpicselect";
            $.getJSON(url).then(function(data) {
                var $content = $("#js-icon-browser-content");
                var $status = $content.find(".icon-browser-status");

                if ( !data ) {
                    $status.html("<p>Unable to load icons</p>");
                    return;
                }

                if ( data.alert ) {
                    $status.html("<p>" + data.alert + "</p>");
                    return;
                }

                $status.remove();

                var $iconslist = $content.find("ul");
                $iconslist.empty();

                var pics = data.pics;
                $.each(data.ids, function(index,id) {
                    var icon = pics[id];
                    var idstring = "js-icon-browser-icon-"+id;

                    var $img = $("<img />").attr( {
                            src: icon.url,
                            alt: icon.alt,
                            height:
                            icon.height,
                            width: icon.width,
                            "class": "th" } )
                        .wrap("<div class='icon-image'></div>").parent();
                    var $keywords = "";
                    if ( icon.keywords ) {
                        $keywords = $("<div class='keywords'></div>");
                        var last = icon.keywords.length - 1;

                        $.each(icon.keywords, function(i, kw) {
                            iconBrowser.kwToIcon[kw] = idstring;
                            $keywords
                                .append( $("<a href='#' class='keyword radius' data-kw='" + kw + "'></a>").text(kw) )
                                .append(document.createTextNode(" "));

                        });
                    }

                    var $comment = ( icon.comment != "" ) ? $("<small class='icon-browser-item-comment'></small>").text( icon.comment ) : "";

                    var $meta = $("<div class='icon-browser-item-meta'></div>").append($keywords).append($comment);
                    var $item = $("<div class='icon-browser-item'></div>").append($img).append($meta);
                    $("<li></li>").append($item).appendTo($iconslist)
                        .data( "keywords", icon.keywords.join(" ").toLocaleUpperCase() )
                        .data( "comment", icon.comment.toLocaleUpperCase() )
                        .data( "alt", icon.alt.toLocaleUpperCase() )
                        .data( "defaultkw", icon.keywords[0] )
                        .attr( "id", idstring );
                });

                iconBrowser.modal.find(":input[type=search]")
                    .prop("disabled", false)
                    .focus();

                iconBrowser.initializeKeyword();
            });
            iconBrowser.isLoaded = true;
        }
    },
    deregisterListeners: function() {
        $(document).off('keydown.icon-browser');
    },
    registerListeners: function() {
        $(document).on('keydown.icon-browser', this.selectByEnter.bind(this));

        if ( this.listenersRegistered ) return;

        $("#js-icon-browser-content")
            .on("click", this.selectByClick.bind(this))
            .on("dblclick", this.selectByDoubleClick.bind(this));

        this.modal
            .find(".keyword-menu")
                .on("click", ".keyword", this.selectByKeywordMenuClick.bind(this))
                .on("dblclick", ".keyword", this.selectByKeywordMenuDoubleClick.bind(this));

        $("#js-icon-browser-search").on("keyup click", this.filter.bind(this));
        $("#js-icon-browser-select").on("click", this.updateOwner.bind(this));

        $(document)
            .on('closed.fndtn.reveal', '#' + this.modalId, this.deregisterListeners.bind(this));

        this.listenersRegistered = true;
    },
    selectByEnter: function(e) {
        // enter
        if (e.keyCode && e.keyCode === 13) {
            var $originalTarget = $(e.originalTarget);
            if ($originalTarget.hasClass("keyword")) {
                $originalTarget.click();
            } else if ($originalTarget.is("a")) {
                return;
            }
            this.updateOwner.call(this, e);
        }
    },
    selectByClick: function(e) {
        // this may be on either the icon or the keyword
        var container = $(e.target).closest("li");
        var keyword = $(e.target).closest("a.keyword");

        this.doSelect(container, keyword.length > 0 ? keyword.text() : null, true);

        e.stopPropagation();
        e.preventDefault();
    },
    selectByDoubleClick: function(e) {
        this.selectByClick.call(this, e);
        this.updateOwner.call(this, e);
    },
    selectByKeywordMenuClick: function(e) {
        var keyword = $(e.target).text();
        var id = this.kwToIcon[keyword];
        if ( id ) {
            this.doSelect($("#" + id), keyword, false);
        }

        e.stopPropagation();
        e.preventDefault();
    },
    selectByKeywordMenuDoubleClick: function(e) {
        this.selectByKeywordMenuClick(e);
        this.updateOwner.call(this, e);
    },
    initializeKeyword: function() {
        var keyword = this.element.val();
        this.doSelect($("#" + this.kwToIcon[keyword]), keyword, true);
    },
    doSelect: function($container, keyword, replaceKwMenu) {
        var iconBrowser = this;

        $("#" + iconBrowser.selectedId).find(".th, a").removeClass("active");
        if ( $container.length == 0 ) return;

        // select keyword
        if ( keyword != null ) {
            // select by keyword
            iconBrowser.selectedKeyword = keyword;
        } else {
            // select by picid (first keyword)
            iconBrowser.selectedKeyword = $container.data("defaultkw");
        }

        iconBrowser.selectedId = $container.attr("id");
        $container
            .show()
            .find(".th, a[data-kw='" + iconBrowser.selectedKeyword + "']")
                .addClass("active");

        // keyword menu
        if ( replaceKwMenu ) {
            var $keywords = $container.find(".keywords");
            iconBrowser.modal.find(".keyword-menu .keywords")
                .replaceWith($keywords.clone());
        } else {
            iconBrowser.modal.find(".keyword-menu .active")
                .removeClass("active");
        }

        // selected element in the keyword menu (can't use cached query because
        // we may have replaced the keyword-menu element)
        iconBrowser.modal.find(".keyword-menu .keyword")
            .filter(function() {
                return $(this).text() == iconBrowser.selectedKeyword;
            })
            .addClass("active");
    },
    updateOwner: function(e) {
        // hackety hack -- being triggered on both 'close' and 'close.fndtn.reveal'; just want once
        if (e.namespace === "") return;

        if (this.selectedKeyword) {
            this.element
                .val(this.selectedKeyword)
                .triggerHandler("change");
        }

        this.close();
    },
    close: function() {
        this.modal.foundation('reveal', 'close');
    },
    filter: function(e) {
        console.log("filter");
        var val = $(e.target).val().toLocaleUpperCase();

        if ( ! this.originalElement ) {
            this.originalElement = $("#js-icon-browser-content");
            this.originalElementContainer = this.originalElement.parent();
            this.originalElement.detach();
        } else {
            $("#js-icon-browser-content").remove();
        }


        var $filtered = this.originalElement.clone(true);
        $filtered
            .find("li").each(function(i, item) {
                console.log("item", item, $(this).data("keywords"), val);
                if ( $(this).data("keywords").indexOf(val) == -1
                    && $(this).data("comment").indexOf(val) == -1
                    && $(this).data("alt").indexOf(val) == -1 ) {

                    $(this).remove();
                }
            }).end()
        .appendTo(this.originalElementContainer);

        var $visible = $("#js-icon-browser-content li:visible");
        if ( $visible.length == 1 )
            this.doSelect($visible, null, true);
    },
    resetFilter: function() {
        $("#js-icon-browser-search").val("");
        if ( this.originalElement ) {
            $("#js-icon-browser-content").detach();
            this.originalElementContainer.append(this.originalElement);
        }

        this.originalElement = null;
        this.originalElementContainer = null;
    }
};

function Options(modal, prefs) {
    $.extend(this, {
        modal: modal
    });
    $("#js-icon-browser-meta-toggle a")
        .click(this.toggleMetaText.bind(this))
        .filter(prefs.metatext ? "[data-action='text']" : "[data-action='no-text']")
            .triggerHandler("click", true);

    $("#js-icon-browser-size-toggle a")
        .click(this.toggleIconSize.bind(this))
        .filter(prefs.smallicons ? "[data-action='small']" : "[data-action='large']")
            .triggerHandler("click", true);
}

function toggleLinkState($el, init) {
    $el.addClass("inactive-toggle")
        .siblings()
            .removeClass("inactive-toggle");
}

Options.prototype = {
    toggleMetaText: function(e, init) {
        e.preventDefault();

        var $link = $(e.target);
        if ( $link.data("action") === "text" ) {
            this.modal.removeClass("no-meta");
            if ( !init ) this.save( "metatext", true );
        } else {
            this.modal.addClass("no-meta");
            if ( !init ) this.save( "metatext", false );
        }

        toggleLinkState($link);
    },
    toggleIconSize: function(e, init) {
        e.preventDefault();

        var $link = $(e.target);
        if ( $link.data("action") === "large" ) {
            this.modal.removeClass("small-icons");
            $("#js-icon-browser-content ul").attr("class",
                "small-block-grid-2 medium-block-grid-4 large-block-grid-6");

            if ( !init ) this.save( "smallicons", false );
        } else {
            this.modal.addClass("small-icons");
            $("#js-icon-browser-content ul").attr("class",
                "small-block-grid-1 medium-block-grid-2 large-block-grid-3");

            if ( !init ) this.save( "smallicons", true );
        }

        toggleLinkState($link);
    },
    save: function(option, value) {
        var params = {};
        params[option] = value;

        // this is a best effort thing, so be silent about success/error
        $.post( "/__rpc_iconbrowser_save", params );
    }
};

$.fn.extend({
    iconBrowser: function(options) {

        return $(this).each(function(){
            var defaults = {
                // triggerSelector: "#icon-browse-button, #icon-preview",
                // modalId: "icon-browser",
                // preferences: { metatext: true, smallicons: false }
            };

            new IconBrowser($(this), $.extend({}, defaults, options));
        });

    }
});

})(jQuery);
