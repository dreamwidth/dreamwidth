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
        },

        // TODO:
        // allow multiple ajaxtip requests, even if we're not done processing the previous
        multiple: false
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
    },
    error: function(msg) {
        this.option("content", msg);
        this.open();
    },
    load: function(opts) {
        /* opts contains overrides
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
        var endpoint_url = $.endpoint( opts["endpoint"] );

        var self = this;

        if ( self.cur_req ) {
            self.cur_req.abort();
        }

        var deferred = $.ajax( $.extend({
            url : endpoint_url,
            context: self,

            dataType: "json"
        }, opts.ajax ));
        self.cur_req = deferred;

        // now add the throbber. It will be removed automatically
        $(self.element).throbber( deferred );

        self.option( "content", function(setContent) {
            deferred.done(function() {
                // setContent();
            });

            deferred.fail(function(jqxhr, status, error) {
                // "abort" status means we cancelled the ajax request
                if ( status !== "abort" ) {
                    setContent( "Error contacting server: " + error );
                }
            });
        });
    }
});

/* 3.4k compressed
$.widget("dw.ajaxtipold", $.ui.tooltip, {
    _create: function() {
        self.element
            .bind("ajaxresult"+ns, function(e) {
                var tip = self.element.data("tooltip").getTip()
                     .addClass("ajaxresult-" + e.ajaxresult.status);
                if ( e.ajaxresult.message ) tip.text(e.ajaxresult.message);
            })
            .tooltip($.extend({
                onBeforeShow: function(e) {
                    var tooltipAPI = this;
                    var tip = tooltipAPI.getTip();
                    tip.removeClass("ajaxresult ajaxresult-success ajaxresult-error")
                        .appendTo("body");
                    if ( ! tip.data( "boundclose" ) ) {
                        tip.bind( "close", function () {

                            // abort any existing request
                            var xhr = tip.data( "xhr" );
                            if ( xhr ) xhr.abort();

                            // hide any currently shown ones
                            tooltipAPI.hide();
                        } );
                        tip.data( "boundclose", true );
                    }

                    if ( self.options.content && ! this.inprogress ){
                        tip.html(self.options.content)
                    } else {
                        tip.empty().append($("<img />", { src: Site.imgprefix + "/ajax-loader.gif" }))
                            .addClass("ajaxresult")
                    }

                    tip.css({position: "absolute", top: "", left: ""})
                    self._reposition( tip );
                }
            },  self.options.tooltip));
    },
    _init: function() {
        if(this.options.content)
            this.element.data("tooltip").show()
    },
});
*/
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
