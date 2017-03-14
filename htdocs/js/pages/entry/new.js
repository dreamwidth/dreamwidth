var postForm = (function($) {
    function hasRemote() {
        return $("#js-remote").val() === "" ? false : true;
    }

    var initMainForm = function($form) {
        $form.collapse({ endpointUrl: hasRemote() ? "/__rpc_entryformcollapse" : "" });
        $form.fancySelect();
    };

    var initToolbar = function($form, minAnimation) {
        $("#js-entry-settings").find("a").click(function(e) {
            e.preventDefault();

            var $link = $(this);

            var $settings = $("#js-settings-panel");
            var $settingsForm = $settings.children( "form:visible" );

            if ( $settingsForm.length > 0 ) {
                $settingsForm.trigger( "settings.cancel" )
                $settings.slideUp();
            } else {
                $link.addClass( "spinner" );
                $settings.load(Site.siteroot + "/__rpc_entryoptions", function(html,status,jqxhr) {
                    $(this).slideDown();
                    $link.removeClass( "spinner" );
                })
            }
        });

        $.fx.off = minAnimation;
    };

    var initButtons = function($form, $crosspost, strings) {
        function openPreview(e) {
            var form = e.target.form;
            var action = form.action;
            var target = form.target;

            var $password = $(form).find( "input[type='password']:enabled" );
            $password.prop( "disabled", true );

            form.action = "/entry/preview";
            form.target = 'preview';
            window.open( '',
                'preview',
                'width=760,height=600,resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes'
            );
            form.submit();

            form.action = action;
            form.target = target;
            $password.prop( "disabled", false );
            e.preventDefault();
        }

        function handleSpellcheck(e) {
            $(this.form).data( "skipchecks", "spellcheck" );
        }

        function handleDelete(e) {
            $(this.form).data( "skipchecks", "delete" );

            var do_delete = confirm( strings.delete_confirm );
            if ( do_delete ) {
                do_delete = $crosspost.crosspost( "confirmDelete", strings.delete_xposts_confirm );
            }

            if ( ! do_delete ) {
                e.preventDefault();
            }
        }

        function handleLoginModal(e) {
            var $modal = $("#js-post-entry-login");

            $form.find("input[name=username]").val( $modal.find("input[name=username]").val() );
            $form.find("input[name=password]").val( $modal.find("input[name=password]").val() );
            $modal.find("input[name=password]").val("")
            if ( $modal.find("input[name=remember_me]").is(":checked") ) {
                $form.find("input[name=remember_me]").val(1);
            }


            $form.submit();
        }

        $("#js-preview-button").click(openPreview);
        $("#js-spellcheck-button").click(handleSpellcheck);
        $("#js-delete-button").click(handleDelete);

        if ( ! hasRemote() ) {
            $("input[name='action:post']").attr("data-reveal-id", "js-post-entry-login");

            $("#js-post-entry-login").find("input[type=submit]").click(handleLoginModal);
            $form.hashpassword();
        }
    };

    var initCommunitySection = function($form) {
        $form.on("journalselect-full", function(e, journal) {
            if ( journal.name && journal.isremote ) {
                if ( journal.iscomm && journal.canManage) {
                    $(".community-administration").show();
                } else {
                    $(".community-administration").hide();
                }
            }
        });
    }

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

        function saveCurrentGroups() {
            $custom_groups.data( "original_data", $custom_groups.find("input[name=custom_bit]").serializeArray() );
        }

        function onOpen() {
            updatePostingMembers(undefined, true);
            saveCurrentGroups();
        }

        function close(e) {
            e.preventDefault();

            // hide the modal (retains current state)
            $custom_groups.foundation('reveal', 'close');
            $custom_groups.detach().appendTo(".components.js-only");
        }

        function cancel() {
            // reset to initial selected custom groups
            var data = $custom_groups.data("original_data");
            var groups = {};
            for ( var i = 0; i < data.length; i++ ) {
                groups[data[i].value] = true;
            }

            $custom_groups.find("input[name=custom_bit]").each(function(i, elem) {
                if (groups[elem.value]) {
                    $(elem).prop("checked", "checked")
                } else {
                    $(elem).removeProp("checked");
                }
            });
        }

        $custom_groups.find("input[name=custom_bit]").click(updatePostingMembers);
        $(document).on('open.fndtn.reveal', "#js-custom-groups", onOpen);
        $("#js-custom-groups-select").click(close);
        $custom_groups.find(".close-reveal-modal").click(cancel);


        // update the options when journal changes
        function adjustSecurityDropdown(data, journal) {
            if ( !data ) return;

            if ( journal && data.ret ) {
                $form.trigger( "journalselect-full", $.extend( {}, journal, {
                    canManage: data.ret.can_manage
                }) );
            }

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
            var oldval = $security.closest('select').find('option').filter(':selected').val();
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
                    { "user": journal.name }, function(data) { adjustSecurityDropdown(data, journal) } );
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
                iscomm = $usejournal.data( "is-comm" ) ? true : false;
            }

            var journalData = {
                    "name": journal,
                    "iscomm": iscomm,
                    isremote: hasRemote()
            };

            $form.data( "journal", journal )
                .trigger( "journalselect", journalData );

            var dataAttribute = $usejournal.attr( "data-is-admin" );
            if ( dataAttribute !== undefined ) {
                var isAdmin = dataAttribute === "1" ? true : false;
                $form.trigger( "journalselect-full", $.extend( journalData, { canManage: isAdmin } ) );
                $usejournal.removeAttr("data-is-admin");
            }
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
            base_url = 'http://' + (journal.name || "[journal]") + '.' + Site.user_domain;
            updateSlugBase();
        });

        updateSlugBase();
    };

    var initTags = function($form) {
        $form.one("journalselect", function(e, journal) {
            var $taglist = $("#js-taglist");
            var canGetTags = hasRemote() && journal.name;

            var options = {
                grow: true,
                maxlength: 40
            }

            if ( canGetTags ) {
                options.populateSource = Site.siteroot + "/__rpc_gettags?user=" + journal.name;
                options.populateId = journal.name;
            }

            $taglist.autocompletewithunknown(options);

            if ( canGetTags )
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

    var initDate = function($form) {
        function zeropad(num) { return num < 10 ? "0" + num : num }
        function padAll(text, sep) {
            return $.map( text.split(sep), function(value, index) {
                return zeropad(parseInt(value, 10));
            } ).join(sep);
        }

        $("#js-entrytime-date").pickadate({
            editable: true,
            format: 'yyyy-mm-dd',

            trigger: document.getElementById("js-entrytime-date-button"),
            container: '.displaydate-component .picker-output',

            klass: {
                picker: 'picker picker--date',

                navPrev: 'picker__nav--prev fi-icon fi-arrow-left',
                navNext: 'picker__nav--next fi-icon fi-arrow-right',

                buttonClear: 'picker__button--clear secondary',
                buttonToday: 'picker__button--today',
                buttonClose: 'picker__button--close secondary'
            }
        }).change(function(e) {
            var picker = $(e.target).pickadate('picker');
            var oldValue = picker.get('select', 'yyyy-mm-dd');
            var newValue = padAll(picker.get('value'), '-');

            if ( oldValue !== newValue ) {
                picker.set('select', newValue);
            }
        });

        $("#js-entrytime-time").pickatime({
            editable: true,
            format: "HH:i",
            interval: 1,
            max: 1439,

            trigger: document.getElementById("js-entrytime-time-button"),
            container: '.displaydate-component .picker-output'

        }).change(function(e) {
            var picker = $(e.target).pickatime('picker');
            var oldValue = picker.get('select', 'HH:i');
            var newValue = picker.get('value');

            if ( oldValue !== newValue ) {
                // tweak interval so that we don't round off to the nearest interval
                // when setting the value
                picker.set('interval', 1);
                picker.set('select', newValue);
                picker.set('interval', 30);
            }
        });

        function setTimeToNow() {
            var now = new Date();

            var date =  [ now.getFullYear(),
                            zeropad(now.getMonth() + 1),
                            zeropad(now.getDate())
                        ].join("-");
            $("#js-entrytime-date").val(date).trigger("change");

            var time = [ zeropad(now.getHours()), zeropad(now.getMinutes()) ];
            $("#js-entrytime-time").val(time).trigger("change");

            $("#js-trust-datetime").val(1);
        }

        if ( $("#js-trust-datetime").val() != 1 ) {
            setTimeToNow();
        }

        $("#js-entrytime-autoupdate").click(function() {
            var $inputs = $(".displaydate-component .inner").find("input[type=text], button");
            $inputs.prop("disabled", $(this).is(":checked"));
        });
        $form.submit(function() {
            if ( $("#js-entrytime-autoupdate").is(":checked") ) {
                setTimeToNow();

                var $inputs = $(".displaydate-component .inner").find("input[type=text], button");
                $inputs.prop("disabled", false);
            }
        });
    };

    var initCrosspost = function($form) {
        if ( ! $.fn.crosspost ) {
            return;
        }

        function setLastVisible() {
            $(".crosspost-component")
                .find(".last-visible")
                    .removeClass("last-visible")
                .end()
                .find(".row:visible:last")
                    .addClass("last-visible");
        }

        var $crosspost = $(".crosspost-component");
        $crosspost.crosspost();

        $crosspost.find("input[type=checkbox]").change(setLastVisible);
        setLastVisible();

        $form.bind("journalselect", function(e, journal) {
            if ( journal.name && journal.isremote )
                $crosspost.crosspost("toggle", "community", ! journal.iscomm, true);
            else
                $crosspost.crosspost("toggle", "unknown", false, true);
        });
    };

    var initSticky = function($form) {
        $form.bind("journalselect-full", function(e, journal) {
            if ( journal.name && journal.isremote ) {
                if ( journal.iscomm ) {
                    $(".components-columns .sticky-component:not(.inactive-component)").hide();
                } else {
                    $(".components-columns  .sticky-component:not(.inactive-component)").show();
                }

                $(".sticky-component")
                    .filter(":visible")
                        .find("input").removeAttr("disabled")
                    .end().end()
                    .filter(":not(:visible)")
                        .find("input").attr("disabled", "");
            }
        });

    };

    var init = function(formData) {
        $("#nojs").val(0);

        if ( ! formData ) formData = {};
        var entryForm = $("#js-post-entry");

        initMainForm(entryForm);
        initToolbar(entryForm, formData.minAnimation);
        initButtons(entryForm, $( ".crosspost-component" ), formData.strings);
        initCommunitySection(entryForm);

        initCurrents(entryForm, formData.moodpics);
        initSecurity(entryForm, formData.security, { spellcheck: formData.did_spellcheck, edit: formData.edit } );
        initJournal(entryForm);
        initIcons(entryForm, formData.icons, formData.iconBrowser);
        initSlug(entryForm, $("#js-entrytime-date"));
        initTags(entryForm);
        initDate(entryForm);
        initCrosspost(entryForm);
        initSticky(entryForm);

        $("#js-usejournal").triggerHandler("change");
        $("#js-entrytime-autoupdate").triggerHandler("click");
    };

    return {
        init: init
    };
})(jQuery);

jQuery(function($) {
    postForm.init(window.postFormInitData);
});
