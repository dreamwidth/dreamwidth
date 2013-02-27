(function($){

$.widget("dw.sticky", {
options: {
    strings: {
        stickyDisabled: {
            community: "Community entries cannot be stickied.",
            draft: "Draft entries cannot be stickied."
        }
    }
},

// to display or not to display the sticky options
toggle: function(why, allowThisSticky, animate) {
    var self = this;

    var msg_class = "sticky_msg";
    var msg_id = msg_class + "_" + why;
    var $msg = $("#"+msg_id);

    if( allowThisSticky ) {
        $msg.remove();
	$("#sticky_options").slideDown();
    } else if ( $msg.length == 0 && self.options.strings.stickyDisabled[why] ) {
        var $p = $("<p></p>", { "class": msg_class, "id": msg_id }).text(self.options.strings.stickyDisabled[why]);
        $p.insertBefore("#sticky_options");
	$("#sticky_options").hide();
  }

}


});

})(jQuery);
