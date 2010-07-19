/*
    js/shop/creditcard.js

    Credit Card page JavaScript

    Authors:
        Mark Smith <mark@dreamwidth.org>

    Copyright (c) 2010 by Dreamwidth Studios, LLC.

    This program is free software; you may redistribute it and/or modify it under
    the same terms as Perl itself.  For a copy of the license, please reference
    'perldoc perlartistic' or 'perldoc perlgpl'.
*/

// called when we need to update the state of the various
// selection boxes and widgets we use... nothing amazing
function shop_cc_ShowHideBoxes() {

    if ( $('#country').val() == 'US' ) {
        $('#usstate').show();
        $('#otherstate').hide();

    } else {
        $('#usstate').hide();
        $('#otherstate').show();
    }
}

DW.whenPageLoaded( function() {
    shop_cc_ShowHideBoxes();

    $('#country').change( shop_cc_ShowHideBoxes );
} );
