(function($) {
    $.widget("ui.contextualhover", {
        popupDelay: 500,
        hideDelay: 250,
    });

    var ContextualHover = {
        setup: function() {
            if (!Site || !Site.ctx_popup) return;
            if (Site.ctx_popup_userhead)
                ContextualHover._initUserhead();
    
            if (Site.ctx_popup_icons)
                ContextualHover._initIcons();
        },

        _initUserhead: function() {
            $("span.ljuser").each(function() {
                var $usertag = $(this);
                if ( $usertag.data("userdata") ) return;

                $("img", $usertag).each(function() {
                    // if the parent (a tag with link to userinfo) has userid in its URL, then
                    // this is an openid user icon and we should use the userid
                    var $parent = $(this).parent("a[href]");
                    var data = {};
                    var userid;
                    if (userid = $parent.attr("href").match(/\?userid=(\d+)/i)) 
                        data.userid = userid[1];
                    else
                        data.username = $usertag.attr("lj:user");
                    if ( !data.username && !data.userid ) return;

                    $usertag.data("userdata", data).addClass("ContextualPopup");
                });
            });
        },

        _initIcons: function() {

            $("img[src*='/userpic/']").each(function() {
                if ( $(this).data("icon_url") ) return;
                if (this.src.match(/userpic\..+\/\d+\/\d+/) ||
                    this.src.match(/\/userpic\/\d+\/\d+/)) {
                    $(this).data("icon_url", this.src).addClass("ContextualPopup");
                }
            });
        }
    }

    // for init
    $.extend({ contextualhover: ContextualHover.setup });

})(jQuery);

// initialize on page load
$(function() {
    $.contextualhover();
    $(".ContextualPopup").live("mousemove", function(e){
        console.log(e.target);
    });
});
