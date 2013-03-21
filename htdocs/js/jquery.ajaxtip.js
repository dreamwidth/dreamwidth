(function($) {
$.widget("dw.ajaxtip", $.ui.tooltip, {
    options: {
        content: undefined,
        items: "*",

        loadingContent: undefined,

        tooltipClass: "ajaxtip",
        position: {
            my: "left top+10",
            at: "left bottom",
            collision: "flipfit flipfit"
        }
    },
    _create: function() {
        // we override completely because we want to control what events trigger this widget
        var self = this;

        // attach (and remove) custom handlers
        this._on({
            ajaxtipopen: function (event, ui) {
                self._on( ui.tooltip, {
                    // we want to bind the events to the tooltip
                    // but we want close() to use this.element
                    // so we have to call this.close() ourselves
                    mouseleave: function() { self.close(); },
                    focusout: function() { self.close(); }
                });
            },
            ajaxtipclose: function(event, ui) {
                self._off( ui.tooltip, "mouseleave focusout" );
            }
        });

        this.tooltips = {};
        this.requests = [];
    },
    // close everything except the target (if it was a tooltip)
    closeinactive: function($target) {
        var target_id = $target.attr( "id" );
        if ( ! this.tooltips[target_id] ) {
            this.close();
        }
    },
    error: function(msg) {
        this.option("content", msg);
        this.open();
    },
    success: function(msg) {
        var self = this;
        self.option("content", msg);
        self.open();

        // this is only a confirmation message. We can fade away quickly
        window.setTimeout( function() { self.close(); }, 1500 );
    },
    abort: function () {
        var self = this;
        if ( self.requests.length ) {
            $.each( self.requests, function (i, req) {
                req.abort();
            });
            self.requests = [];
        }
    },
    load: function(args) {
        /* opts is an object (or array of objects) containing overrides:
         *
         * endpoint : name of the endpoint we wish to use (not the URL)
         *
         * ajax     : options for the AJAX call, in case you want to override the defaults
         *            Here are the moste useful ones:
         *
         *    type      : POST or GET
         *    data      : any additional data to pass to the request
         *                 e.g., POST parameters
         *    context   : the context used for "this" in the callbacks
         *
         *    success   : success callback
         *    error     : error callback
         */

        var self = this;

        // abort and remove any old requests
        self.abort();

        if ( self.options.loadingContent ) {
            self.option("content", self.options.loadingContent);
            self.open();
        }

        $.each( $.isArray( args ) ? args : [ args ], function (i, opts) {
            var endpoint_url = $.endpoint( opts["endpoint"] );

            var deferred = $.ajax( $.extend({
                url : endpoint_url,
                context: self,

                dataType: "json"
            }, opts.ajax ));
            self.requests.push( deferred );

            deferred.fail(function(jqxhr, status, error) {
                if ( status !== "abort" &&          // "abort" status means we cancelled the ajax request
                        ( error && jqxhr.status )   // empty error / status means we probably cilcked
                                                    // away from the page before the ajax request was completed
                    ) {
                    self.error( "Error contacting server: " + error );
                }
            });

            if ( ! self.options.loadingContent ) {
                 // now add the throbber. It will be removed automatically
                $(self.element).throbber( deferred );
            }
        } );

        // clean out requests queue once all requests have successfully completed
        $.when.apply( $, self.requests ).done(function() {
            self.requests = [];
        });

    }
});

$.extend( $.dw.ajaxtip, {
    closeall: function(e) {
        $(":dw-ajaxtip").ajaxtip( "closeinactive", $(e.target).closest(".ajaxtip") );
    }
});
})(jQuery, Site);

jQuery(function($) {
    $(document).click(function(e) {
        $.dw.ajaxtip.closeall(e);
    });
});
