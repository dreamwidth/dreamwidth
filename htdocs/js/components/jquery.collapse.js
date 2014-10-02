(function($) {

function Collapsible($el, options) {
    var self = this;

    var $trigger = $el.find(options.triggerSelector)
        .wrap("<button class='collapse-trigger theme-color-on-hover fi-icon--with-fallback' />");
    $trigger.append("<span class='fi-icon' aria-hidden='true'></span><span class='collapse-trigger-action fi-icon--fallback'></span>");

    var $target = $el.find(options.targetSelector);
    $target.addClass("collapse-target")
        .attr("id", "collapse-target-" + $el.data("collapse"));
    $trigger.attr("aria-controls", $target.attr("id"));

    $.extend(this, {
        strings: options.strings,
        endpointUrl: options.endpointUrl,
        isExpanded: $el.data("collapse-state") === "collapsed" ? false : true,

        element: $el,
        target: $target,
        trigger: $trigger,
        triggerIcon: $trigger.find(".fi-icon"),
        triggerAction: $trigger.find(".collapse-trigger-action")
    });

    // we disable animation effects on page load but want the original
    // value once we start clicking
    var fx = $.fx.off;
    $.fx.off = true;
    if (this.isExpanded) {
        this.expand(true);
    } else {
        this.collapse(true);
    }
    $.fx.off = fx;

    $el.on("click", ".collapse-trigger", function(e) {
        e.preventDefault();
        self.toggle();
    });
}

Collapsible.prototype = {
    toggle: function() {
        if(this.isExpanded) {
            this.collapse();
        } else {
            this.expand();
        }

        if ( this.endpointUrl ) {
            $.getJSON(this.endpointUrl,
                { "id": this.element.data("collapse"),
                  "expand": this.isExpanded
                });
        }

    },

    expand: function(initial) {
        var self = this;

        this.target.slideDown(function() {
            self.triggerIcon
                .removeClass("fi-plus")
                .addClass("fi-minus");
            self.triggerAction.text(self.strings.collapse);
        });

        this.isExpanded = true;
        this.trigger.attr("aria-expanded", this.isExpanded);

        // trigger styling immediately
        this.element
            .removeClass("collapse-collapsed")
            .addClass("collapse-expanded");
    },

    collapse: function() {
        var self = this;

        this.target.slideUp(function() {
            self.triggerIcon
                .removeClass("fi-minus")
                .addClass("fi-plus");
            self.triggerAction.text(self.strings.expand);

            // trigger styling after it's collapsed
            self.element
                .removeClass("collapse-expanded")
                .addClass("collapse-collapsed");
        });

        this.isExpanded = false;
        this.trigger.attr("aria-expanded", this.isExpanded);
    }
};

$.fn.extend({
    collapse: function(options) {
        if (!options) options = {};

        return $(this).find("[data-collapse]").each(function(){
            new Collapsible($(this), {
                triggerSelector: options.trigger || ":header:first",
                targetSelector:  options.target || ".inner",
                strings: { expand: "Expand", collapse: "Collapse" },
                endpointUrl: options.endpointUrl
            });
        });
    }
});

})(jQuery);
