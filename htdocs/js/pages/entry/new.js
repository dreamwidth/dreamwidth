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
                    .after("<div id='js-moodpreview' class='moodpreview'>"
                        + "<div class='moodpreview-text'></div>"
                        + "<div class='moodpreview-image'></div>"
                        + "</div>");

            $customMood.change(updatePreviewText);

            updatePreview();
            updatePreviewText();
        }
    };

    var initSecurity = function($form, security_options, opts) {
        var $custom_groups = $("#js-custom-groups");
        var $custom_access_group_members = $("#js-custom-group-members");
        var $custom_edit_button = $('<button class="secondary" data-reveal-id="js-custom-groups" aria-label="Edit custom entries">Edit</button>');
        var $security_select = $("#js-security");

        // create an "edit custom groups" button
        $security_select.closest(".fancy-select")
                .after($custom_edit_button);

        // show the custom groups modal
        var rememberInitialValue = !opts.spellcheck;
        $security_select.change( function(e, init) {
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
        function updatePostingMembers(e, useCached) {
            var members_data = []
            var requests = []

            if(useCached && $custom_access_group_members.data("fetched")) return;
            $custom_access_group_members.data("fetched", true);

            $custom_groups.find(":checkbox").each(function() {
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
        }
        $custom_groups.find("input[name=custom_bit]").click(updatePostingMembers);
        $(document).on('open.fndtn.reveal', "#js-custom-groups", updatePostingMembers.bind(undefined, undefined, true));


        // update the options when journal changes
        function adjustSecurityDropdown(data) {
            if ( !data ) return;

            function createOption(option) {
                var security = security_options[option];
                var img = security.image ? security.image.src +
                        ":" + security.image.width +
                        ":" + security.image.height : "";

                return '<option value="' + security.value + '"' +
                    ' data-fancyselect-img="' + img + '"' +
                    ' data-fancyselect-format="' + security.format + '"' +
                    '>' + security.label + '</option>';
            }

            var $security = $("#js-security");
            var oldval = $security.data("lastselected");
            var rank = { "public": "0", "access": "1", "private": "2", "custom": "3" };

            $security.empty();
            if ( data.ret ) {
                if ( data.ret["minsecurity"] == "friends" ) data.ret["minsecurity"] = "access";

                var opts;
                if ( data.ret['is_comm'] ) {
                    opts = [
                        createOption( "public" ),
                        createOption( "members" )
                    ];

                    if ( data.ret['can_manage'] )
                        opts.push( createOption( "admin" ) );
                } else {
                    opts = [
                        createOption( "public" ),
                        createOption( "access" ),
                        createOption( "private" )
                    ];

                    if ( data.ret['friend_groups_exist'] )
                        opts.push( createOption( "custom" ) );
                }
                $security.append(opts.join(""));

                // select the minsecurity value and disable the values with lesser security
                $security.val(rank[oldval] >= rank[data.ret['minsecurity']] ? oldval : data.ret['minsecurity']);
                if ( data.ret['minsecurity'] == 'access' ) {
                    $security.find("option[value='public']").prop("disabled", true);
                } else if ( data.ret['minsecurity'] == 'private' ) {
                    $security.find("option[value='public'],option[value='access'],option[value='custom']")
                        .prop("disabled", true);
                }

                $security.trigger( "change" );
            } else {
                $security
                    .append([
                        createOption( "public" ),
                        createOption( "access" ),
                        createOption( "private" )
                    ].join(""))
                    .val(oldval)
                    .trigger( "change" );
            }

        }

        $form.bind( "journalselect", function(e, journal) {
            var anon = ! journal.name;
            if ( $security_select.length > 0 ) {
                if ( anon ) {
                    // no custom groups
                    adjustSecurityDropdown({})
                } else if ( ! opts.edit ) {
                    $.getJSON( Site.siteroot + "/__rpc_getsecurityoptions",
                    { "user": journal.name }, adjustSecurityDropdown);
                }
            }
        } );
    };

    var initJournal = function($form) {
        $("#js-usejournal").change(function() {
            var $usejournal = $(this);
            var journal, iscomm;
            if ( $usejournal.is("select") ) {
                var $option = $usejournal.find("option:selected");
                journal = $option.text();
                iscomm  = $option.val() !== "";
            } else {
                journal = $usejournal.val();
                iscomm = journal !== $("#js-remote").val();
            }

            $form.data( "journal", journal )
                .trigger( "journalselect",
                {
                    "name": journal,
                    "iscomm": iscomm,
                    isremote: true
                });
        });
    };

    var initIcons = function($form, icons, iconBrowserOptions) {
        var $preview = $( "#js-icon-preview" );
        if ( $preview.is(".no-icon") ) return;

        var $select = $("#js-icon-select");

        function buttonHTML(id, text, columnClass) {
            return '<div class="columns medium-6 ' + columnClass + '">' +
                "<button id='" + id + "' class='small secondary button'>" + text + "</button>" +
                '</div>'
        }
        $select.closest('.row')
                .after('<div class="row">' +
                    buttonHTML('js-icon-browse', 'browse', '') +
                    buttonHTML('js-icon-random', 'random', 'end') +
                    '</div>');

        function update_icon_preview() {
            if ( !icons ) return;

            if ( this.selectedIndex != null && icons[this.selectedIndex] ) {
                if ( icons[this.selectedIndex].src ) {
                    $("#js-icon-preview-image").attr({
                        "src": icons[this.selectedIndex].src,
                        "alt": icons[this.selectedIndex].alt
                    });
                }
            }
        }

        $select
            .iconrandom( { trigger: "#js-icon-random" } )
            .change( update_icon_preview )
            .triggerHandler( "change" );

        if ( $.fn.iconBrowser ) {
            if ( ! iconBrowserOptions ) iconBrowserOptions = {};
            $select.iconBrowser({
                triggerSelector: "#js-icon-preview, #js-icon-browse",
                modalId: "js-icon-browser",
                preferences: iconBrowserOptions
            });
        } else {
            $("#js-icon-browse").remove();
        }
    };

    var initSlug = function($form, $dateElement) {
        var $slug = $("#js-entry-slug");
        var $slugBase = $("#js-slug-base");

        var slug = $slug.val(), base_url = '';

        // Takes an input string and sluggifies it. If you update this, please
        // also update LJ::canonicalize_slug in cgi-bin/LJ/Web.pm.
        function toSlug(inp) {
            return inp
                    .trim()
                    .replace(/\s+/g, "-")
                    .replace(/[^a-z0-9_-]/gi, "")
                    .replace(/-+/g, "-")
                    .replace(/^-|-$/g, "")
                    .toLowerCase();
        }

        function updateSlugBase() {
            var dval = $dateElement.val().replace(/-/g, '/');

            $slugBase.text(base_url + "/" + dval + "/");
        }

        $slug.change(function(e) {
            slug = toSlug($slug.val());
            $slug.val(slug);

            updateSlugBase();
            e.preventDefault();
        });

        $dateElement.change(function(e) {
            updateSlugBase();
        });

        $form.bind('journalselect', function(evt, journal) {
            base_url = 'http://' + journal.name + '.' + Site.user_domain;
            updateSlugBase();
        });

        updateSlugBase();
    };

    var initTags = function($form) {
        $form.one("journalselect", function(e, journal) {
            var $taglist = $("#js-taglist");

            var options = {
                grow: true,
                maxlength: 40
            }

            if ( journal.name ) {
                options.populateSource = Site.siteroot + "/__rpc_gettags?user=" + journal.name;
                options.populateId = journal.name;
            }

            $taglist.autocompletewithunknown(options);

            if ( journal.name )
                $taglist.tagBrowser({fallbackLink: "#js-taglist-link"});

            $form.bind("journalselect", function(e, journal) {
                if ( journal.name ) {
                    $taglist.autocompletewithunknown( "populate",
                        Site.siteroot + "/__rpc_gettags?user=" + journal.name, journal.name );
                } else {
                    $taglist.autocompletewithunknown( "clear" )
                }
            })
        });
    };

    var init = function(formData) {
        $("#nojs").val(0);

        if ( ! formData ) formData = {};
        var entryForm = $("#js-post-entry");

        initMainForm(entryForm);

        initCurrents(entryForm, formData.moodpics);
        initSecurity(entryForm, formData.security, { spellcheck: formData.did_spellcheck, edit: formData.edit } );
        initJournal(entryForm);
        initIcons(entryForm, formData.icons, formData.iconBrowser);
        initSlug(entryForm, $("#entrytime"));
        initTags(entryForm);


        $("#js-usejournal").triggerHandler("change");
    };

    return {
        init: init
    };
})(jQuery);

jQuery(function($) {
    postForm.init(window.postFormInitData);
});