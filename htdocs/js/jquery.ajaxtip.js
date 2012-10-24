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
        $(self.element).throbber(deferred);

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
        var tipcontainer = $("<div class='ajaxtooltip ajaxtip' style='display: none'></div>")
                        .click(function(e) {e.stopPropagation()})

        if ( self.options.persist ) {
            $(self.element).attr("type", "persistent").bind("mouseout"+self._namespace(), function(e) {
                self.element.trigger("tooltipout" + self._namespace());
            } )
        }

        self.element
            .after(tipcontainer)
            .bind("ajaxresult"+ns, function(e) {
                var tip = self.element.data("tooltip").getTip()
                     .addClass("ajaxresult-" + e.ajaxresult.status);
                if ( e.ajaxresult.message ) tip.text(e.ajaxresult.message);
            })
            .tooltip($.extend({
                predelay: 0,
                delay: 1500,
                events: {
                    // just fade away after a preset period
                    def       : "ajaxstart"+ns+", tooltipout"+ns+" ajaxresult"+ns,
                    // persist until the user takes some action (including moving the mouse away from trigger)
                    persistent: "ajaxstart"+ns+", tooltipout"+ns,
                    widget    : "ajaxstart"+ns+", ajaxresult"+ns,
                    tooltip   : "mouseover,mouseleave"
                },
                relative: true,
                effect: "fade",
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
                },
                onShow: function(e) {
                    self._reposition( this.getTip() );
                }
            },  self.options.tooltip));
    },
    _init: function() {
        if(this.options.content)
            this.element.data("tooltip").show()
    },
    _reposition: function( tip ) {
        tip.position({ my: "left top", at: "left bottom", of: this.element, collision: "fit"})
    },

    widget: function() {
        return this.element.data("tooltip").getTip();
    },
    cancel: function() {
        var tip = this.element.data("tooltip");
        if( tip && tip.isShown() ) tip.hide();
     },
    show: function() {
        var tip = this.element.data("tooltip");
        tip.show();
        this.success((no msg));
    },
    load: function(opts) {
        var self = this;

        var tip = self.element.data("tooltip");
        if( tip && ! opts.multiple ) {
            if( tip.inprogress ) return;
            if( tip.isShown() ) tip.hide();
            tip.inprogress = true;
        }

        self.element.trigger("ajaxstart" + self._namespace());


        var xhr = $.ajax({
            type: opts.formmethod || "POST",
            url : opts.endpoint ? self._endpointurl( opts.endpoint) : opts.url,
            data: opts.data,
            context: opts.context,

            dataType: "json",
            complete: function() {
                var tip = self.element.data("tooltip");
                if ( tip ) {
                    tip.inprogress = false;
                    var tipele = tip.getTip();
                    self._reposition( tipele );
                    tipele.removeData("xhr");
                }
            },
            success: opts.success,
            error: opts.error ? opts.error : function( jqxhr, status, error ) {
                if ( status == "abort" )
                    this.element.ajaxtip("cancel");
                else
                    this.element.ajaxtip( "error", "Error contacting server. " + error);

                this._trigger( "complete" );
            }
        });

        if ( tip ) tip.getTip().data( "xhr", xhr );
    },
    success: function(msg) {
        this.element.trigger({ type: "ajaxresult"+this._namespace(),
                                ajaxresult: { message: msg, status: "success" } })
    },
    error: function(msg) {
        this.element.trigger({ type: "ajaxresult"+this._namespace(),
                                ajaxresult: { message: msg, status: "error" } })
    },
    abort: function(msg) {
        this.element.data("tooltip").show();
        this.element.trigger({ type: "ajaxresult"+this._namespace(),
                                ajaxresult: { message: msg, status: "error" } })
    }
});
*/
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
