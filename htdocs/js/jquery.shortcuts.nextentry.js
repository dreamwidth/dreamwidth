(function($) {
    // keyboard/touch shortcut to move between entries/top-level comments.
    // also reacts to clicking anchor tags or buttons with a dw_toNextEntry
    // or dw_toPrevEntry class.
    $(document).ready(function() {
        dw_register_shortcut("nextEntry", nextPageEntry);
        dw_register_shortcut("prevEntry", prevPageEntry);
    });

    $(document).on("click", ".dw_toNextEntry", function(event) {
        event.preventDefault();
        nextPageEntry();
    });

    $(document).on("click", ".dw_toPrevEntry", function(event) {
        event.preventDefault();
        prevPageEntry();
    });

    function scrollToEntry(entry) {
        var top = entry.offset().top;
        $('html,body').animate({ scrollTop: top }, 'slow');
    }

    // this scrolls to the previous entry/comment that's scrolled off, or
    // the top of the page if there are no previous entries
    function prevPageEntry() {
        // default is the top of the page
        var scrollTo = null;
        var scrollCurrent = $(window).scrollTop();
        var elements = getScrollableElements();
        for (var i=0; i < elements.length; i++) {
            var el = $(elements[i]);
            if (el.offset().top < scrollCurrent && el.is(':visible')){
                scrollTo = el;
            } else {
                break;
            }
        }
        if (scrollTo != null) {
            scrollToEntry(scrollTo);
        } else {
            $('html,body').animate({ scrollTop: 0 }, 'slow');
        }
    }

    // This scrolls to the next entry/comment where the top of the entry is
    // more than 50px past the top of the viewport
    function nextPageEntry() {
        var scrollPoint = $(window).scrollTop() + 50;
        var elements = getScrollableElements();
        var el;
        for (var i=0; i<elements.length; i++) {
            el = $(elements[i]);
            if (el.offset().top >= scrollPoint && el.is(':visible')){
                scrollToEntry(el);
                return;
            }
        }
        // if we got here, then scroll to the bottom of the page
        $('html,body').animate( { scrollTop: $(document).height() - $(window).height() }, 'slow');
    }

    // returns the scrollable elements for this page--entries if an entry
    // page, top-level comments if a comment page
    function getScrollableElements() {
        var entities = $("div.entry-wrapper");
        if (entities.length > 1) {
            return entities;
        }
        var comments = $("#comments .comment-depth-1 > .dwexpcomment");
        return comments;
    }
})(jQuery);
