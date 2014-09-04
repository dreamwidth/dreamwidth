var postForm = (function($) {
    var initCollapsible = function() {
        $("#post_entry").collapse({ endpointUrl: "/__rpc_entryformcollapse" });
    };

    var initCurrents = function(moodpics) {
        var $moodSelect = $("#js-current-mood");
        var $customMood = $("#js-current-mood-other");

        function _mood() {
            var selectedMood = $moodSelect.val();
            return moodpics[selectedMood] ? moodpics[selectedMood] : ["", ""];
        }

        var updatePreview = function() {
            if ( ! moodpics ) return;

            $("#js-moodpreview .moodpreview-image").fadeOut("fast", function() {
                var $this = $(this);
                $this.empty();

                $("#js-moodpreview")
                    .removeClass("columns medium-4")
                    .prev()
                        .removeClass("medium-8");

                var mood = _mood();
                if ( mood[1] !== "" ) {
                    $this.append($("<img />",{ src: mood[1], width: mood[2], height: mood[3]}))
                         .fadeIn();

                    $("#js-moodpreview")
                        .addClass("columns medium-4")
                        .prev()
                            .addClass("columns medium-8");
                }
            });
        }

        var updatePreviewText = function () {
            var customMoodText = $customMood.val();
            if ( ! customMoodText ) {
                var mood = _mood();
                customMoodText = mood[0];
            }
            $("#js-moodpreview .moodpreview-text").text( customMoodText );

        }

        // initialize...
        if( moodpics ) {
            $moodSelect
                .change(updatePreview)
                .change(updatePreviewText)
                .closest(".columns")
                    .after("<div id='js-moodpreview'>"
                        + "<div class='moodpreview-text'></div>"
                        + "<div class='moodpreview-image'></div>"
                        + "</div>");

            $customMood.change(updatePreviewText);

            updatePreview();
            updatePreviewText();
        }
    };

    var init = function(formData) {
        $("#nojs").val(0);

        if ( ! formData ) formData = {};
        initCollapsible();

        initCurrents(formData.moodpics);

    };

    return {
        init: init
    };
})(jQuery);

jQuery(function($) {
    postForm.init(window.postFormInitData);
});