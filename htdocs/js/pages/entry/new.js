var postForm = (function($) {
    var initCollapsible = function($form) {
        $form.collapse({ endpointUrl: "/__rpc_entryformcollapse" });
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

    function initAccess($form, formData) {
        var $custom_groups = $("#js-custom-groups");
        var $custom_access_group_members = $("#js-custom-group-members");
        var $summary_container = $("#js-custom-groups-summary");
        var $summary_text = $summary_container.find(".summary-text");

        var updateSummary = function() {
            var selected = [];
            $custom_groups.find("input:checked").each(function() {
                selected.push($.trim($(this).next().text()));
            });
            $summary_text.text(selected.join(", "));
        }

        var setLastVisible = function() {
            $("#access-component")
                .find(".last-visible")
                    .removeClass("last-visible")
                .end()
                .find(".row:visible:last")
                    .addClass("last-visible");
        }

        var rememberInitialValue = !formData.did_spellcheck;
        $("#js-security").change( function(e, init) {
            var $this = $(this);
            if ( $this.val() == "custom" ) {
                if ( ! init ) {
                    $custom_groups.foundation('reveal', 'open');
                }
                updateSummary();
                $summary_container.slideDown(setLastVisible);
            } else {
                $summary_container.slideUp(setLastVisible);
            }

            if ( ! init ) {
                $this.data("lastselected",$this.val())
            }
        }).triggerHandler("change", rememberInitialValue);

        $(document).on('close.fndtn.reveal', '[data-reveal]', function () {
            if (this.id === "js-custom-groups") {
                updateSummary();
            }
        } );

        function adjustSecurityDropdown(data) {
            if ( ! data ) return;

            var $security = $("#js-security");
            var oldval = $security.data("lastselected");
            var rank = { "public": "0", "access": "1", "private": "2", "custom": "3" };

            $security.empty();
            if ( data.ret ) {
                if ( data.ret["minsecurity"] == "friends" ) data.ret["minsecurity"] = "access";

                var opts;
                if ( data.ret['is_comm'] ) {
                    opts = [
                        "<option value='public'>Everyone (Public)</option>",
                        "<option value='access'>Members</option>"
                    ];
                    if ( data.ret['can_manage'] )
                        opts.push("<option value='private'>Admin</option>");
                } else {
                    opts = [
                        "<option value='public'>Everyone (Public)</option>",
                        "<option value='access'>Access List</option>",
                        "<option value='private'>Private (Just You)</option>"
                    ];
                    if ( data.ret['friend_groups_exist'] )
                        opts.push("<option value='custom'>Custom</option>");
                }

                $security.append(opts.join("\n"))

                // select the minsecurity value and disable the values with lesser security
                $security.val(rank[oldval] >= rank[data.ret['minsecurity']] ? oldval : data.ret['minsecurity']);
                if ( data.ret['minsecurity'] == 'access' ) {
                    $security.find("option[value='public']").prop("disabled", true);
                } else if ( data.ret['minsecurity'] == 'private' ) {
                    $security.find("option[value='public'],option[value='access'],option[value='custom']")
                        .prop("disabled", true);
                }
            } else {
                // user is not known. no custom groups, no minsecurity
                $security.append([
                    "<option value='public'>Everyone (Public)</option>",
                    "<option value='access'>Access List</option>",
                    "<option value='private'>Private (Just You)</option>"
                ].join("\n"))
                $security.val(oldval);
            }
        }

        $form.bind( "journalselect", function(e, journal) {
            var anon = ! journal.name
            if ( anon || journal.iscomm || ! journal.isremote )
                $summary_container.slideUp(setLastVisible);

            var $security = $("#js-security");
            if ( $security.length > 0 ) {
              if ( anon ) {
                // no custom groups
                adjustSecurityDropdown({})
              } else if ( ! formData.edit ) {
                $.getJSON( Site.siteroot + "/__rpc_getsecurityoptions",
                    { "user": journal.name }, adjustSecurityDropdown);
            }
            $(this).data("journal",journal.name);
          }
        });

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
    }

    var init = function(formData) {
        $("#nojs").val(0);

        if ( ! formData ) formData = {};
        var entryForm = $("#js-post-entry");

        initCollapsible(entryForm);

        initCurrents(entryForm, formData.moodpics);
        initAccess(entryForm, formData);
    };

    return {
        init: init
    };
})(jQuery);

jQuery(function($) {
    postForm.init(window.postFormInitData);
});