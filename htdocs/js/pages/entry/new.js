var postForm = (function($) {
    var initMainForm = function($form) {
        $form.collapse({ endpointUrl: "/__rpc_entryformcollapse" });
        $form.fancySelect();
    };

    var initCurrents = function($form, moodpics) {
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

    var initSecurity = function($form, formData) {
        var $custom_groups = $("#js-custom-groups");
        var $custom_access_group_members = $("#js-custom-group-members");
        var $custom_edit_button = $('<button class="secondary" data-reveal-id="js-custom-groups" aria-label="Edit custom entries">Edit</button>');

        // create an "edit custom groups" button
        $("#js-security").closest(".fancy-select")
                .after($custom_edit_button);

        // show the custom groups modal
        var rememberInitialValue = !formData.did_spellcheck;
        $("#js-security").change( function(e, init) {
            var $this = $(this);

            if ( $this.val() == "custom" ) {
                if ( !init ) {
                    $custom_groups.foundation('reveal', 'open');
                }
                $custom_edit_button.show();
            } else {
                $custom_edit_button.hide();
            }

            if ( !init ) {
                $this.data("lastselected", $this.val());
            }
        }).triggerHandler("change", rememberInitialValue);

        // update the list of people who can see the entry
        $custom_groups.find("input[name=custom_bit]").click(function(e) {
            var members_data = []
            var requests = []
            $(this).parent().parent().find(":checkbox").each(function() {
                if (this.checked) {
                    requests.push($.getJSON("/__rpc_general?mode=list_filter_members&user=" + $form.data("journal") + "&filterid=" + this.value, function(data) {
                        for ( member in data.filter_members.filterusers) {
                            var the_name = data.filter_members.filterusers[member].fancy_username;
                            var position = members_data.indexOf(the_name);
                            if( position == -1) {
                                members_data.push(the_name);
                            }
                        }
                    }))
                }
            });

            $.when.apply($, requests).done(function() {
                var members_data_list = "";
                members_data.sort();
                for (member in members_data) {
                    members_data_list = members_data_list + "<li>" + members_data[member] + "</li>";
                }
                $custom_access_group_members.html(members_data_list);
            });
        });
    };

    var init = function(formData) {
        $("#nojs").val(0);

        if ( ! formData ) formData = {};
        var entryForm = $("#js-post-entry");

        initMainForm(entryForm);

        initCurrents(entryForm, formData.moodpics);
        initSecurity(entryForm, formData);
    };

    return {
        init: init
    };
})(jQuery);

jQuery(function($) {
    postForm.init(window.postFormInitData);
});