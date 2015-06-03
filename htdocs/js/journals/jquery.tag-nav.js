(function($) {
    function expanded($trigger) {
        $trigger.attr("aria-expanded", "true");
        $trigger.attr("alt", "Hide tag navigation");
        $trigger.attr("src", Site.imgprefix + "/silk/site/delete.png");
    }

    function collapsed($trigger) {
        $trigger.attr("aria-expanded", "false");
        $trigger.attr("alt", "Show tag navigation");
        $trigger.attr("title", "Tag navigation: Select this button, then a tag, then use the arrows displayed to navigate through entries with that tag.");
        $trigger.attr("src", Site.imgprefix + "/silk/site/add.png");
    }

    $.fn.tagnav = function() {
        this.each(function() {
            var $tagText = $(this);
            var $tagNavTrigger = $("<input class='tag-nav-trigger' type='image' />");
            $tagText.after($tagNavTrigger);
            collapsed($tagNavTrigger);

            var $container = $tagNavTrigger.parent(".tag");

            var $dlg;
            $tagNavTrigger.click(function(e){
                e.stopPropagation();
                e.preventDefault();

                if ( ! $dlg ) {
                    $dlg = $("<span>" +
                                "<input type='image' src='" + Site.imgprefix + "/silk/entry/previous.png' alt='Previous selected tag' title='Previous selected tag' data-dir='prev' />" +
                                "<input type='image' src='" + Site.imgprefix + "/silk/entry/next.png' alt='Next selected tag' title='Next selected tag' data-dir='next' />" +
                            "</span>");
                    $dlg.dialog({
                        autoOpen: false,
                        dialogClass: 'tag-nav-actions tag-nav-none-selected',
                        position: {
                            my: "center top",
                            at: "center bottom",
                            of: this,
                            collision: "flipfit"
                        },
                        width: "auto",
                        open: function(e, ui) {
                            $tagNavTrigger.next("ul").addClass("tag-nav-active");
                        },
                        close: function(e, ui) {
                            $tagNavTrigger.next("ul").removeClass("tag-nav-active");
                        }
                    });

                    $dlg.on("click", "input[data-dir]", function(e) {
                        e.stopPropagation();
                        e.preventDefault();

                        var params = [  "dir="          + $(this).data("dir"),
                                        "itemid="       + $tagText.data("ditemid"),
                                        "journal="      + $tagText.data("journal"),
                                        "redir_key="    + encodeURIComponent( $container.find(".tag-nav-selected").text() )
                                    ];
                        var url = Site.siteroot + "/go?" + params.join("&");
                        document.location.href=url;
                    });
                }

                if ( $dlg.dialog( "isOpen" ) ) {
                    $dlg.dialog( "close" );
                    collapsed($tagNavTrigger);
                } else {
                    $dlg.dialog( "open" );
                    expanded($tagNavTrigger);
                }
            });

            $container.on("click", ".tag-nav-active a", function(e) {
                e.stopPropagation();
                e.preventDefault();


                if( $(this).is(".tag-nav-selected") ) {
                    $(this).removeClass("tag-nav-selected");

                    $dlg.parent().addClass("tag-nav-none-selected");
                } else {
                    $container.find(".tag-nav-selected").removeClass("tag-nav-selected");
                    $(this).addClass("tag-nav-selected");

                    $dlg.parent().removeClass("tag-nav-none-selected");
                }
            })
        });

        return this;
    };
})(jQuery);

jQuery(document).ready(function() {
    $(".tag-text[data-journal]").tagnav();
});

// we do this later, because we want to make sure the whole page is loaded
// properly, so the position is calculated accurately
var hash = location.hash;
if ( hash.indexOf( "#tagnav-" ) == 0 ) {
    $(window).load(function() {
        var tagnav_tag = decodeURI(hash.slice(8));

        $(".tag-nav-trigger").click();
        $(".tag a").filter(function() {
            var text = $(this).text();
            return text === tagnav_tag || text.replace(' ', '+') === tagnav_tag;
        }).click();
    })
}
