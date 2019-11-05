(function($) {

function MoodTheme($el) {
    var moodTheme = this;
    moodTheme.init();
}

MoodTheme.prototype = {
        init: function () {
            var moodTheme = this;
            $('#moodtheme_dropdown').change(function(e) {
                moodTheme.previewMoodTheme(e);
            });
        },
        previewMoodTheme: function (event) {
            event.preventDefault();
            var moodTheme = this;
            var moodthemeid = $('#moodtheme_dropdown').val();

            $.ajax({
              type: "POST",
              url: "/__rpc_moodtheme",
              data: {
                     preview_moodthemeid: moodthemeid,
                     },
              success: function( data ) { $( ".moodtheme-preview" ).html(data);
                                        },
              dataType: "html"
            });

            return false
        }
    };

    $.fn.extend({
    moodTheme: function() {
        new MoodTheme( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $(".appwidget-journaltitles").moodTheme();
});