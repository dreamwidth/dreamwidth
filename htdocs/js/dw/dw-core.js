/*
    js/dw/dw-core.js
   
    This is the core JavaScript module that gives us the main DW object we use
    to do most of the site actions.
   
    Authors:
         Mark Smith <mark@dreamwidth.org>
   
    Copyright (c) 2009 by Dreamwidth Studios, LLC.
   
    This program is free software; you may redistribute it and/or modify it under
    the same terms as Perl itself.  For a copy of the license, please reference
    'perldoc perlartistic' or 'perldoc perlgpl'.
   
*/

var DW = new Object();

// usage: DW.whenPageLoaded( function() { do something; } );
//
// this function will register a callback to be called as soon as the
// page has finished loading.  note that if the page has already loaded
// your callback will be dispatched immediately.
DW.whenPageLoaded = function(fn) {
    if ( DW._pageLoaded )
        return fn();
    DW._pageLoadCBs.push( fn );
};

/*****************************************************************************
 * INTERNAL FUNCTIONS BELOW HERE
 *****************************************************************************/

// internal variable setup
DW._pageLoaded = false;
DW._pageLoadCBs = [];

// called when the page has finished loading
DW._pageIsLoaded = function() {
    for ( cb in DW._pageLoadCBs )
        DW._pageLoadCBs[cb]();
    DW._pageLoadCBs = [];
    DW._pageLoaded = true;
};

// now register with jQuery so we know when things are ready to go
$(document).ready(function() {
    DW._pageIsLoaded();
});
