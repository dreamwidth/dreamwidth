/*

  quickupdate.js

  JS relating to the Quick Update widget.

  Authors:
       Chris Boyle <chris@boyle.name>

  Copyright (c) 2018 by Dreamwidth Studios, LLC.

  This program is free software; you may redistribute it and/or modify it under
  the same terms as Perl itself.  For a copy of the license, please reference
  'perldoc perlartistic' or 'perldoc perlgpl'.

*/


jQuery( function( $ ) {
    var security = $( '#security' );
    var usejournal = $( '#usejournal' );

    security.find( 'option' ).each( function() {
        $( this ).data( 'journallabel', $( this ).text() );
    } );

    usejournal.change( function() {
        var journal = $( this ).find( 'option:selected' );
        var min = journal.data( 'minsecurity' );
        var isComm = journal.data( 'iscomm' );

        function tooPublic( actual ) {
            return min && actual && ( ( min == 'private' && actual != 'private' )
                    || ( min == 'friends' && actual == 'public' ) );
        }

        if ( tooPublic( security.val() ) ) {
            security.val( min );
        }

        security.find( 'option' ).each( function() {
            var opt = $( this );
            opt.prop( 'disabled', tooPublic( opt.val() ) );

            // 'friends' and 'private' are labelled differently for communities
            if ( isComm && opt.data( 'commlabel' ) ) {
                opt.text( opt.data( 'commlabel' ) );
            } else if ( opt.data( 'journallabel' ) ) {
                opt.text( opt.data( 'journallabel' ) );
            }
        } );
    } );

    usejournal.trigger( 'change' );
} );
