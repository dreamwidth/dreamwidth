/*
    js/nav-jquery.js

    Tropospherical and Gradation Horizontal Navigation JavaScript

    Authors:
        Mark Smith <mark@dreamwidth.org>

    Copyright (c) 2009 by Dreamwidth Studios, LLC.

    This program is free software; you may redistribute it and/or modify it under
    the same terms as Perl itself.  For a copy of the license, please reference
    'perldoc perlartistic' or 'perldoc perlgpl'.
*/

jQuery( function($) {

    // used below
    var hideNavs = function() {
        $( '.topnav' ).removeClass( 'hover' );
        $( '.subnav' ).removeClass( 'hover' );
    };

    // add event listeners to the top nav items
    $( '.topnav' )

        .mouseover( function() {
            hideNavs();
            $( this ).addClass( 'hover' );
        } )

        .mouseout( function() {
            hideNavs();
        } );
} );
