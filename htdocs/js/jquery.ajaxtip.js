(function($) {
$.widget("dw.ajaxtip", $.ui.tooltip, {
    options: {
        content: undefined,
        items: "*",

        tooltipClass: "ajaxtooltip ajaxtip",
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
                ui.tooltip.on( "mouseleave focusout", function() {
                    self.close();
                } );
            },
            ajaxtipclose: function(event, ui) {
                ui.tooltip.off( "mouseleave mouseout" );
            }
        });

        this.tooltips = {};
        this.requests = [];
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
        if ( self.requests.length ) {
            $.each( self.requests, function (i, req) {
                req.abort();
            });
            self.requests = [];
        }

        $.each( $.isArray( args ) ? args : [ args ], function (i, opts) {
            var endpoint_url = $.endpoint( opts["endpoint"] );

            var deferred = $.ajax( $.extend({
                url : endpoint_url,
                context: self,

                dataType: "json"
            }, opts.ajax ));
            self.requests.push( deferred );

            // now add the throbber. It will be removed automatically
            $(self.element).throbber( deferred );

            deferred.fail(function(jqxhr, status, error) {
                // "abort" status means we cancelled the ajax request
                if ( status !== "abort" ) {
                    self.error( "Error contacting server: " + error );
                }
            });
        } );

        // clean out requests queue once all requests have successfully completed
        $.when.apply( $, self.requests ).done(function() {
            self.requests = [];
        })

    }
});

// TODO: make this work
$.extend( $.dw.ajaxtip, {
    closeall: function(e) {
        $(".ajaxtip:visible").each(
            function(){
                var $this = $(this);

                if ( e && e.target && $this.has( e.target ).length > 0 ) {
                    // clicked inside this popup; do nothing
                } else {
                    $(this).trigger("close");
                }
            });
    }
});
})(jQuery, Site);

jQuery(function($) {
    $(document).click(function(e) {
        $.dw.ajaxtip.closeall(e);
    });
});
