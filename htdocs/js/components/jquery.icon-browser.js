(function($) {

function IconBrowser($el, options) {
    var iconBrowser = this;
    var modalSelector = "#" + options.modalId;
    var scrollPositionDogear;

    $.extend(iconBrowser, {
        element: $el,
        modal: $(modalSelector),
        modalId: options.modalId
    });

    $(options.triggerSelector).attr("data-reveal-id", options.modalId);

    new Options(this.modal, options.preferences);

    $(document)
        .on('open.fndtn.reveal', modalSelector, function(e) {
            // hackety hack -- being triggered on both 'open' and 'open.fndtn.reveal'; just want one
            if (e.namespace === "") return;

            // If the page scrolled sideways, don't put the modal way out in left field.
            iconBrowser.modal.css('left', window.scrollX);

            iconBrowser.loadIcons();
            iconBrowser.registerListeners();
        })
        // Save and restore the scroll position when opening and closing the
        // modal. This is crucial on mobile if you have dozens of icons, because
        // otherwise it'll ditch you miles out into the comment thread, as you
        // wonder where you left your reply form and whether you have enough
        // water to survive the walk back to the gas station.
        .on('opened.fndtn.reveal', modalSelector, function(e) {
            // hackety hack -- being triggered on both 'opened' and 'opened.fndtn.reveal'; just want one
            if (e.namespace === "") return;

            scrollPositionDogear = $(window).scrollTop();
            iconBrowser.modal.removeAttr('tabindex'); // WHY does foundation.reveal set this.
            iconBrowser.focusActive();
        })
        .on('closed.fndtn.reveal', modalSelector, function(e) {
            // hackety hack -- being triggered on both 'closed' and 'closed.fndtn.reveal'; just want one
            if (e.namespace === "") return;

            if ( Math.abs( $(window).scrollTop() - scrollPositionDogear ) > 500 ) {
                $(window).scrollTop(scrollPositionDogear);
            }

            // the browser blew away the user's tab-through position, so restore
            // it on whatever makes most sense to focus. Defaults to the icon
            // menu, since that's what they just indirectly set a value for, but
            // in comment forms we ask to focus the message body instead.
            var $focusTarget = $el;
            if ( options.focusAfterBrowse ) {
                var $altTarget = $( options.focusAfterBrowse ).first();
                if ( $altTarget.length === 1 ) {
                    $focusTarget = $altTarget;
                }
            }
            // Only force-reset the focus if we know it's still wrong! If the
            // user somehow managed to focus something else before this handler
            // fired, don't jerk them around.
            if ( document.activeElement.tagName === 'BODY' ) {
                $focusTarget.focus();
            }
        });
}

IconBrowser.prototype = {
    kwToIcon: {},
    selectedId: undefined,
    selectedKeyword: undefined,
    iconBrowserItems: [],
    iconsList: undefined,
    isLoaded: false,
    listenersRegistered: false,
    loadIcons: function() {
        var iconBrowser = this;
        if ( iconBrowser.isLoaded ) {
            iconBrowser.resetFilter();
            iconBrowser.initializeKeyword();
        } else {
            var searchField = $("#js-icon-browser-search");
            searchField.prop("disabled", true);

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
                // Save it, we'll need it for sorting later.
                iconBrowser.iconsList = $iconslist;
                $iconslist.empty();

                var pics = data.pics;
                $.each(data.ids, function(index,id) {
                    var icon = pics[id];
                    var idstring = "js-icon-browser-icon-"+id;

                    var $img = $("<img />").attr( {
                            src: icon.url,
                            alt: icon.alt,
                            title: icon.keywords.join(', '),
                            height: icon.height,
                            width: icon.width,
                            "class": "th" } )
                        .wrap("<button type='button' class='icon-browser-icon-button'>").parent()
                        .wrap("<a class='color-wrapper'>").parent()
                        .wrap("<div class='icon-browser-icon-image'></div>").parent();
                    var $keywords = "";
                    if ( icon.keywords ) {
                        $keywords = $("<div class='keywords'></div>");

                        $.each(icon.keywords, function(i, kw) {
                            iconBrowser.kwToIcon[kw] = idstring;
                            var kwButton = $("<button type='button' class='keyword'>")
                                .attr('data-kw', kw)
                                .text(kw);
                            $keywords
                                .append( $("<a class='color-wrapper'>").append(kwButton) )
                                .append(document.createTextNode(" "));

                        });
                    }

                    var $meta = $("<div class='icon-browser-item-meta'></div>").append($keywords);
                    var $item = $("<div class='icon-browser-item'></div>").append($img).append($meta);
                    var $listItem = $("<li></li>").append($item)
                        .data( "keywords", icon.keywords.join(" ").toLocaleUpperCase() )
                        .data( "comment", icon.comment.toLocaleUpperCase() )
                        .data( "alt", icon.alt.toLocaleUpperCase() )
                        .data( "defaultkw", icon.keywords[0] )
                        .data( "dateorder", index )
                        .attr( "id", idstring );
                    // Save a reference for easy sorting later
                    iconBrowser.iconBrowserItems.push($listItem);
                });

                // If we're starting in keyword order, do an initial sort so we
                // match the option button state.
                if ( iconBrowser.modal.hasClass('keyword-order') ) {
                    iconBrowser.sortByKeyword();
                }

                // Do the DOM manipulation in one pass.
                $iconslist.append(iconBrowser.iconBrowserItems);

                searchField.prop("disabled", false);

                iconBrowser.initializeKeyword();
            });
            iconBrowser.isLoaded = true;
        }
    },
    deregisterListeners: function() {
        $(document).off('keydown.icon-browser');
    },
    registerListeners: function() {
        $(document).on('keydown.icon-browser', this.keyboardNav.bind(this));

        if ( this.listenersRegistered ) return;

        $("#js-icon-browser-content")
            .on("click", ".icon-browser-item", this.selectByClick.bind(this))
            .on("dblclick", ".icon-browser-item", this.selectByDoubleClick.bind(this));

        $("#js-icon-browser-search").on("keyup click", this.filter.bind(this));
        $("#icon-browser-options-visibility").on("click", this.toggleOptions.bind(this));

        this.modal.on("sortByKeyword.iconbrowser", this.sortByKeyword.bind(this));
        this.modal.on("sortByDate.iconbrowser", this.sortByDate.bind(this));

        $(document)
            .on('closed.fndtn.reveal', '#' + this.modalId, this.deregisterListeners.bind(this));

        this.listenersRegistered = true;
    },
    focusActive: function() {
        if ( this.selectedId ) {
            $('#' + this.selectedId).find("button.icon-browser-icon-button").focus();
        } else {
            $('#js-icon-browser-search').focus();
        }
    },
    keyboardNav: function(e) {
        if ( $(e.target).is('#js-icon-browser-search') ) return;

        if ( e.key === '/' || (! e.key && e.keyCode === 191) ) {
            e.preventDefault();
            $("#js-icon-browser-search").focus();
        }
    },
    selectByClick: function(e) {
        e.stopPropagation();
        e.preventDefault();

        // Some browsers don't focus buttons or role=buttons on click, and we
        // want predictable behavior when people combine click + tab/enter.
        e.target.focus();

        // this may be on either the icon or the keyword
        var container = $(e.target).closest("li");
        var keyword = $(e.target).closest(".keyword");

        // set the active icon and keyword:
        this.doSelect(container, keyword.length > 0 ? keyword.text() : null);

        // confirm and close:
        this.updateOwner.call(this, e);
    },
    selectByDoubleClick: function(e) {
        this.selectByClick.call(this, e);
    },
    initializeKeyword: function() {
        var keyword = this.element.val();
        this.doSelect($("#" + this.kwToIcon[keyword]), keyword);
    },
    doSelect: function($container, keyword) {
        var iconBrowser = this;

        $("#" + iconBrowser.selectedId).find(".th, .keywords a").removeClass("active");

        if ( ! $container || $container.length === 0 ) {
            // more like DON'Tselect.
            iconBrowser.selectedKeyword = undefined;
            iconBrowser.selectedId = undefined;
            return;
        }

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
            .find(".th")
                .addClass("active");
        $container
            .find(".keyword[data-kw='" + iconBrowser.selectedKeyword + "']")
                .closest("a").addClass("active");
    },
    updateOwner: function(e) {
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
    toggleOptions: function() {
        this.modal.toggleClass("show-options");
    },
    sortByKeyword: function() {
        this.iconBrowserItems.sort(function(a, b) {
            var aKW = a.data('defaultkw').toLowerCase();
            var bKW = b.data('defaultkw').toLowerCase();
            if ( aKW < bKW ) {
                return -1;
            }
            if ( aKW > bKW ) {
                return 1;
            }
            return 0;
        });
        this.iconsList.append(this.iconBrowserItems); // updates in-place.
    },
    sortByDate: function() {
        this.iconBrowserItems.sort(function(a, b) {
            var aDate = a.data('dateorder');
            var bDate = b.data('dateorder');
            if ( aDate < bDate ) {
                return -1;
            }
            if ( aDate > bDate ) {
                return 1;
            }
            return 0;
        });
        this.iconsList.append(this.iconBrowserItems); // updates in-place.
    },
    filter: function(e) {
        var val = $(e.target).val().toLocaleUpperCase();

        if ( ! this.contentElement ) {
            this.contentElement = $("#js-icon-browser-content");
        }

        this.contentElement
            .find("li").each(function(i, item) {
                if ( $(this).data("keywords").indexOf(val) == -1
                    && $(this).data("comment").indexOf(val) == -1
                    && $(this).data("alt").indexOf(val) == -1 ) {

                    $(this).css('display', 'none');
                } else {
                    $(this).css('display', ''); // Reason we aren't using .show() is bc it forcibly sets 'display: block'.
                }
            });
    },
    resetFilter: function() {
        $("#js-icon-browser-search").val("");
        $("#js-icon-browser-content li").show();
    }
};

function Options(modal, prefs) {
    $.extend(this, {
        modal: modal
    });
    $("#js-icon-browser-order-option")
        .on('change', this.toggleKeywordOrder.bind(this))
        .find(prefs.keywordorder ? "[value='keyword']" : "[value='date']")
            .prop('checked', true).trigger('change', true);

    $("#js-icon-browser-meta-option")
        .on('change', this.toggleMetaText.bind(this))
        .find(prefs.metatext ? "[value='text']" : "[value='no-text']")
            .prop('checked', true).trigger('change', true);

    $("#js-icon-browser-size-option")
        .on('change', this.toggleIconSize.bind(this))
        .find(prefs.smallicons ? "[value='small']" : "[value='large']")
            .prop('checked', true).trigger('change', true);
}

Options.prototype = {
    toggleKeywordOrder: function(e, init) {
        e.preventDefault();

        if ( e.target.value === "keyword" ) {
            this.modal.addClass("keyword-order");
            this.modal.trigger("sortByKeyword.iconbrowser");
            if ( !init ) this.save( "keywordorder", true );
        } else {
            this.modal.removeClass("keyword-order");
            this.modal.trigger("sortByDate.iconbrowser");
            if ( !init ) this.save( "keywordorder", false );
        }
    },
    toggleMetaText: function(e, init) {
        e.preventDefault();

        if ( e.target.value === "text" ) {
            this.modal.removeClass("no-meta");
            if ( !init ) this.save( "metatext", true );
        } else {
            this.modal.addClass("no-meta");
            if ( !init ) this.save( "metatext", false );
        }
    },
    toggleIconSize: function(e, init) {
        e.preventDefault();

        if ( e.target.value === "large" ) {
            this.modal.removeClass("small-icons");

            if ( !init ) this.save( "smallicons", false );
        } else {
            this.modal.addClass("small-icons");

            if ( !init ) this.save( "smallicons", true );
        }
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
                // focusAfterBrowse: "",
                // preferences: { metatext: true, smallicons: false, keywordorder: false }
            };

            new IconBrowser($(this), $.extend({}, defaults, options));
        });

    }
});

})(jQuery);
