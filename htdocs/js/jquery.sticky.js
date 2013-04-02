// Interface Control for the Sticky Entries Module on the Post and Edit pages
//
// Authors: Louise Dennis
//
// Copyright (c) 2013 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

(function($){

var $sticky_checked;
var $is_sticky;

$.widget( "dw.sticky", {
options: {
    strings: {
        stickyDisabled: {
            community: "Only administrators can sticky entries in communities.",
            unknown: "Can not determine sticky permissions for this user and journal.",
            no_admin: "You do not have the persmission to create stickies on this journal.",
            draft: "Draft entries cannot be stickied."
        }
    }
},

_create: function() {
    $sticky_checked = $( "#issticky" ).is(":checked");
    $is_sticky = $( "#issticky" ).is(":checked");
},

toggle_sticky_checked_options: function( sticky_val ) {
    $sticky_checked = sticky_val;
    // $warning has content if the journal sticky information is out of date with the 
    // journal selected for use.
    var $warning = $( "#sticky_msg_warning" );

    if ( $warning.length == 0 ) {
        var $first_unused_sticky = $( "#first_unset_sticky" ).val();
        if ( $first_unused_sticky > 0 && ! $is_sticky )
            $( "#" + $first_unused_sticky + "_sticky_select" ).prop('checked', sticky_val);
        if ( sticky_val )
            $( "#sticky_positions" ).slideDown();
        else 
            $( "#sticky_positions" ).hide();
    }
},

// to display or not to display the sticky options
toggle: function( why, allowThisSticky ) {
    var self = this;

    var msg_class = "sticky_msg";
    var $msg = $( "#"+msg_class );

    if ( allowThisSticky ) {
        $msg.remove();
        if ( $sticky_checked )
           $( "#issticky" ).prop( 'checked', true );
        $( "#sticky_options" ).slideDown();
    } else if ( $msg.length == 0 && self.options.strings.stickyDisabled[why] ) {
        var $p = $( "<p></p>", { "class": msg_class, "id": msg_class } ).text( self.options.strings.stickyDisabled[why] );
        $p.insertBefore( "#sticky_options" );
        $( "#sticky_options" ).hide();
        if ( $sticky_checked )
            $( "#issticky" ).prop( 'checked', false );
    } else if ( self.options.strings.stickyDisabled[why] != $msg.text() ) {
        $msg.remove();
        var $p = $( "<p></p>", { "class": msg_class, "id": msg_class } ).text( self.options.strings.stickyDisabled[why] );
        $p.insertBefore( "#sticky_options" );
        $( "#sticky_options" ).hide();
        if ( $sticky_checked )
            $( "#issticky" ).prop( 'checked', false );
    }

}


});

})(jQuery);
