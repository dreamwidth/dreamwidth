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

$.throbber = {
  src: Site.imgprefix + "/ajax-loader.gif",
  error: Site.imgprefix + "/silk/site/error.png"
};

$.endpoint = function(action){
  return ( Site && Site.currentJournal ) ? "/" + Site.currentJournal + "/__rpc_" + action : "/__rpc_" + action;
};

$.fn.throbber = function(jqxhr) {
    var $this = $(this);

    var marginLeft = "";
    var extraPadding = "18px";
    var top = "";
    if ( ! $this.data( "throbber" ) ) {
        if ( $this.is("input, button") ) {
            extraPadding = "10px;"
            marginLeft = "-24px";
            top = ($this.height() / 2) + "px";
        } else  {
            extraPadding = "18px";
            marginLeft = "-16px";
        }

        $this.css( "padding-right", "+=" + extraPadding );
    }


    var $throbber = $("<span class='throbber'></span>").css({
            "position": "absolute",
            "display": "inline-block",
            "marginLeft": marginLeft,
            "width": "16px",
            "height": "16px",
            "top": top,
            "background": "url('" + $.throbber.src + "') no-repeat"
        });
    $this
        .after($throbber)
        .data("throbber", true);


    jqxhr.then(function() {
        $throbber.remove();
        $this
            .css( "padding-right", "-=" + extraPadding )
            .data("throbber", false)
    }, function() {
        $throbber.css( "backgroundImage", "url('" + $.throbber.error + "')" );
    });

    return $this;
};

Unique = {
    count: 0,

    id: function() {
        return ++this.count;
    }
}

;
