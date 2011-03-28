(function($) {
$.widget("dw.ajaxtip", {
    options: {
        content: undefined
    },
    _namespace: function() {
        return this.options.namespace ? "."+this.options.namespace : "";
    },
    _create: function() {
        var self = this;
        var ns = self._namespace();

        var tipcontainer = $("<div class='ajaxtooltip' style='display: none'></div>")
                        .click(function(e) {e.stopPropagation()})

        self.element
            .after(tipcontainer)
            .bind("ajaxresult"+ns, function(e) {
                self.element.data("tooltip").getTip()
                     .addClass("ajaxresult-" + e.ajaxresult.status)
                     .text(e.ajaxresult.message)
            })
            .tooltip({
                predelay: 0,
                delay: 1500,
                events: {
                    def: "ajaxstart"+ns+",ajaxresult"+ns,
                    tooltip: "mouseover,mouseleave"
                },
                position: "bottom center",
                relative: true,
                effect: "fade",

                onBeforeShow: function(e) {
                    var tip = this.getTip();
                    tip.removeClass("ajaxresult ajaxresult-success ajaxresult-error");

                    if ( self.options.content && ! this.inprogress ){
                        tip.html(self.options.content)
                    } else {
                        tip.empty().append($("<img />", { src: Site.imgprefix + "/ajax-loader.gif" }))
                            .addClass("ajaxresult")
                    }
                }
            })
            .dynamic({ classNames: "tip-top tip-right tip-bottom tip-left" });
    },
    _init: function() {
        if(this.options.content)
            this.element.data("tooltip").show()
    },
    widget: function() {
        return this.element.data("tooltip").getTip();
    },
    cancel: function() {
        var tip = this.element.data("tooltip");
        if( tip && tip.isShown() ) tip.hide();
     },
    load: function(opts) {
        var self = this;

        var tip = self.element.data("tooltip");
        if( tip ) {
            if( tip.inprogress ) return;
            if( tip.isShown() ) tip.hide();
        }

        tip.inprogress = true;
        self.element.trigger("ajaxstart" + self._namespace());

        $.ajax({
            type: "POST",
            url : opts.url,
            data: opts.data,

            dataType: "json",
            complete: function() {
                self.element.data("tooltip").inprogress = false;
            },
            success: opts.success,
            error: opts.error
        });
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

$.extend( $.dw.ajaxtip, {
    closeall: function() {
        $(".ajaxtooltip:visible").each(
            function(){
                var tip = $(this).prev().data("tooltip");
                if ( !tip.inprogress ) tip.hide()
            })
    }
})
})(jQuery);

jQuery(function($) {
    $(document).click(function() {
        $.dw.ajaxtip.closeall();
    });
});
