(function($) {
$.fn.ultrafocus = function( focus, blur ) {
    return $(this)
        .focus(focus)
        .blur(blur)
        .hover(focus, blur);
}

$.widget("ui.collapsible", {
    _init: function() {
        var self = this;
        var $trigger = $(self.element).find(self.options.trigger).eq(0);

        // no appropriate trigger element found; nothing to do here
        if ( $trigger.length == 0 )
            return self;

        var opts = self.options;
        self._target = $(opts.target, self.element)
        self._trigger = $trigger;

        self._target.attr("aria-live","polite").filter(":not([id])").attr("id", "collapsibletarget_" + self.element.attr("id"))
        self._trigger.attr("aria-controls", self._target.attr("id"))
        self.element.data("collapsibleid", $.proxy(opts.parseid, self.element)());

        $trigger.ultrafocus(function() {
            $(this).addClass(opts.triggerHoverClass);
        }, function() {
            $(this).removeClass(opts.triggerHoverClass);
        })
        .addClass(opts.triggerClass)
        .append("<span class='ui-icon'></span>")
        .wrapInner($("<a href='#'></a>").attr({ href: "#" }))
        .click(function(e) {
            var clicked = this;
            e.preventDefault();

            if ( opts.endpointurl ) {
                $.getJSON(opts.endpointurl,
                    {"id": self.element.data("collapsibleid"), "expand": !$(self._target).is(":visible")})
            }

            self._target.slideToggle(null, $.proxy(self, "_update") );
        });

        if ( opts.endpointurl && $.ui.collapsible.cache[self.element.data("collapsibleid")]) {
            self._target.hide();
        }

        self._update();
    },
    _update: function() {
        var self = this;
        var open = $(self._target).is(":visible");
        self._trigger.find('.ui-icon')
            .toggleClass('ui-icon-minus', open).toggleClass('ui-icon-plus', !open)
            .text(open? self.options.strings.collapse : self.options.strings.expand)
    },
    options: {
        strings: { expand: "Expand", collapse: "Collapse" },
        trigger: ":header:first",     // selector of element to click to trigger collapse
        triggerClass: "collapsible_trigger ui-state-default",
        triggerHoverClass: "ui-state-hover",
        parseid: function() { return this.attr("id") },
        target: ".inner" // selector of element to collapse
    }
});
})(jQuery);
