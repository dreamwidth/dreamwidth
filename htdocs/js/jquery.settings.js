(function($) {
    $.fn.relatedSetting = function() {
        this.bind('setting_change', function(e) {
            var $this = $(this);

            var toggleOn = $this.data("related-setting-on");
            var selected = ($this.val() === toggleOn);
            var $related = $("#"+$this.data("related-setting-id"))

            $related.toggle(selected);
        });

        this
            .change(function(e) { $(this).trigger('setting_change')} )
            .trigger('setting_change');

        return this;
    };
})(jQuery);

jQuery(function($) {
    $('.js-related-setting').relatedSetting();
});
