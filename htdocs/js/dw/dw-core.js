/*
    js/dw/dw-core.js
   
    This is the core JavaScript module that gives us utility functions used throughout the site
   
    Authors:
         Mark Smith <mark@dreamwidth.org>
         Afuna <coder.dw@afunamatata.com>
   
    Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
   
    This program is free software; you may redistribute it and/or modify it under
    the same terms as Perl itself.  For a copy of the license, please reference
    'perldoc perlartistic' or 'perldoc perlgpl'.
   
*/

var DW = new Object();

$.extractParams = function(url) {
    if ( ! $.extractParams.cache )
        $.extractParams.cache = {};

    if ( url in $.extractParams.cache )
        return $.extractParams.cache[url];

    var search = url.indexOf( "?" );
    if ( search == -1 ) {
        $.extractParams.cache[url] = {};
        return $.extractParams.cache[url];
    }

    var params = decodeURI( url.substring( search + 1 ) );
    if ( ! params ) {
        $.extractParams.cache[url] = {};
        return $.extractParams.cache[url];
    }

    var paramsArray = params.split("&");
    var params = {};
    for( var i = 0; i < paramsArray.length; i++ ) {
        var p = paramsArray[i].split("=");
        var key = p[0];
        var value = p.length < 2 ? undefined : p[1];
        params[key] = value;
    }

    $.extractParams.cache[url] = params;
    return params;
};
