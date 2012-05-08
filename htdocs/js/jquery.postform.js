(function($) {
$.postForm = {

init: function(formData) {
    if ( ! formData ) formData = {};

    // icon
    function initIcons() {
        var $preview = $("#icon_preview");
        if ( $preview.has(".noicon").length > 0 ) return;

        var $select = $("#iconselect");
        if ( $select.length == 0 ) return;

        $preview.prepend("<ul class='icon-functions'><li><button id='icon_browser_link' class='ui-button ui-state-default'>browse</button></li><li><button id='icon_random_link' class='ui-button ui-state-default'>random</button></li></ul>");

        function update_icon_preview() {
            var icons = formData.icons;
            if ( !icons ) return;

            if ( this.selectedIndex != null && icons[this.selectedIndex] ) {
                if ( icons[this.selectedIndex].src ) {
                    if ( $("#icon_preview_image").length == 0 ) {
                        $("#icon_preview .icon").append("<img id='icon_preview_image' />");
                    }

                    $("#icon_preview .icon img").attr({
                        "src": icons[this.selectedIndex].src,
                        "alt": icons[this.selectedIndex].alt
                    });
                } else {
                    $("#icon_preview_image").remove();
                }
            }
        }
        if ( $.fn.iconselector ) {
            $select.iconselector( { onSelect: update_icon_preview, selectorButtons: "#icon_preview .icon img, #icon_browser_link" } );
        } else {
            $("#icon_browser_link").remove();
        }
        $select.iconrandom( { handler: update_icon_preview, trigger: "#icon_random_link" } );
        $select.change(update_icon_preview)
            .triggerHandler( "change" );

        $("#post_entry").bind( "journalselect", function( e, journal ) {
            if ( journal.name && journal.isremote ) {
                $("#icons_component").not(".inactive_component").slideDown()
            } else {
                $("#icons_component").not(".inactive_component").slideUp()
            }
        });
    }

    // date
    function initDisplayDate() {
        function zeropad(num) { return num < 10 ? "0" + num : num }

        // initialize date to current system time
        function updateDateOnInputFields(date) {
            if (!date) date = new Date();
            $("#entrytime").val( $.datepicker.formatDate("yy-mm-dd", date) );
            $("#entrytime_hr").val(zeropad(date.getHours()));
            $("#entrytime_min").val(zeropad(date.getMinutes()));

            $("#trust_datetime").val(1);
        }

        if ( $("#trust_datetime").val() != 1 ) updateDateOnInputFields();
        $("#entrytime_auto_update").click(function() {
            var fields = "#entrytime, #entrytime_hr, #entrytime_min, #entrytime_display_container button, #entrytime_container button";
            var containers = "#entrytime_display_container, #entrytime_container";
            if ( $(this).is(":checked") ) {
                $(fields).attr("disabled", true);
                $(containers).addClass("ui-state-disabled");
            } else {
                $(fields).attr("disabled", false);
                $(containers).removeClass("ui-state-disabled");
            }
        });

        $("#post_entry").submit(function() {
            if ( $("#entrytime_auto_update").is(":checked") )
                updateDateOnInputFields();
        });


        $.datepicker.setDefaults({
            autoSize: true,
            dateFormat: $.datepicker.ISO_8601,
            showButtonPanel: true,

            showOn: 'button',
            buttonText: 'Pick date',

            onClose: function(dateText) {
                var $this = $(this);
                // if we have previously tweaked this value, don't override
                if ($this.data("customized")) return;

                var now = new Date();
                $this.siblings(".time_hr").val(zeropad(now.getHours()));
                $this.siblings(".time_min").val(zeropad(now.getMinutes()));

                $this.focus();
            }
        });

        var $editbutton = $("<button type='button' id='entrytime_container_edit' class='ui-state-default ui-corner-all ui-icon ui-icon-pencil'>edit</button>").click(function(e) {
            $(this).hide();

            $("#entrytime_display_container").hide();
            $("#entrytime_container").show();

            e.preventDefault();
            e.stopPropagation();
        });

        var $datedisplay_edit = $("<span id='entrytime_display_edit'></span>").append($editbutton);
        var $datedisplay_date = $("<span id='entrytime_display_date'></span>")
            .text($("#entrytime").val());
        var $datedisplay_time = $("<span id='entrytime_display_time'></span>")
            .text(" " + $("#entrytime_hr").val()+":"+$("#entrytime_min").val());

        $("<div id='entrytime_display_container'></div>")
            .append($datedisplay_edit, $datedisplay_date, $datedisplay_time)
            .insertBefore("#entrytime_container");
        $("#entrytime_container").hide();

        $("#entrytime").datepicker()
                // take the button and put it before the textbox
                .next()
                    .insertBefore("#entrytime")
                    .addClass("ui-state-default ui-corner-all ui-icon ui-icon-calendar");

        // constrain format/value of date & time
        $("#entrytime").change(function() {
            // detect if there's an error in what we typed
            // This uses internal datepicker functions.
            var inst = $.datepicker._getInst(this);
            try {
                $.datepicker.parseDate($.datepicker._get(inst, 'dateFormat'),
                   $(this).val() || "", $.datepicker._getFormatConfig(inst));
            } catch(event) {
                // nothing right now, but eventually want an error message
            }
        });

        $(".time_container")
            .addClass("time_container_with_picker")
            .find(".time_hr")
                .one( "change", function() {
                    $(this).siblings(".hasDatepicker").data("customized", true);
                })
                .change(function() {
                    var val = parseInt($(this).val());
                    if ( isNaN(val) || val != $(this).val() || val <= 0 ) $(this).val("0");
                    else if ( val > 23 ) $(this).val(23);
                })
                .end()
            .find(".time_min")
                .one( "change", function() {
                    $(this).siblings(".hasDatepicker").data("customized", true);
                })
                .change(function() {
                    var val = parseInt($(this).val());
                    if ( isNaN(val) || val != $(this).val() || val <= 0 ) $(this).val("00");
                    else if ( val > 59 ) $(this).val(59);
                });
    }

    // currents
    function initCurrents() {
        var $moodSelect = $("#current_mood");
        var $customMood = $("#current_mood_other");

        function _mood() {
            var selectedMood = $moodSelect.val();
            return moodpics[selectedMood] ? moodpics[selectedMood] : ["", ""];
        }

        var updatePreview = function() {
            var moodpics = formData.moodpics;
            if ( ! moodpics ) return;

            $("#moodpreview_image").fadeOut("fast", function() {
                var $this = $(this);
                $this.empty();

                var mood = _mood();
                if ( mood[1] !== "" ) {
                    $this.append($("<img />",{ src: mood[1], width: mood[2], height: mood[3]}))
                         .fadeIn();
                }
            });
        }

        var updatePreviewText = function () {
            var customMoodText = $customMood.val();
            if ( ! customMoodText ) {
                var mood = _mood();
                customMoodText = mood[0];
            }
            $("#moodpreview .moodpreview_text").text( customMoodText );

        }

        // initialize...
        var moodpics = formData.moodpics;
        if( moodpics ) {
            $moodSelect
                .change(updatePreview)
                .change(updatePreviewText)
                .closest("p").append("<div id='moodpreview'>"
                        + "<div id='moodpreview_image'></div>"
                        + "<div class='moodpreview_text'></div>"
                        + "</div>");

            $customMood.change(updatePreviewText);

            updatePreview();
            updatePreviewText();
        }
    }

    // tags
    function initTags() {
        $("#post_entry").one("journalselect", function(e, journal) {

            var $taglist = $("#taglist");

            var options = {
                grow: true,
                maxlength: 40
            }

            if ( journal.name ) {
                options.populateSource = Site.siteroot + "/tools/endpoints/gettags?user=" + journal.name;
                options.populateId = journal.name;
            }

            $taglist.autocompletewithunknown(options);

            if ( journal.name )
                $taglist.tagselector({fallbackLink: "#taglist_link"});

            $("#post_entry").bind("journalselect", function(e, journal) {
                if ( journal.name ) {
                    $taglist.autocompletewithunknown( "populate",
                        Site.siteroot + "/tools/endpoints/gettags?user=" + journal.name, journal.name );
                } else {
                    $taglist.autocompletewithunknown( "clear" )
                }
            })
        });
    }

    // journal listeners
    function initJournalSelect() {
        $("#usejournal").change(function() {
            var $this = $(this);
            var journal, iscomm;
            if ( $this.is("select") ) {
                var $option = $("option:selected", this);
                journal = $option.text();
                iscomm  = $option.val() !== "";
            } else {
                journal = $this.val();
                iscomm = journal !== $("#poster_remote").val();
            }
            $(this).trigger( "journalselect", {"name":journal, "iscomm":iscomm, isremote: true});
        });
        $("#postas_usejournal, #post_username").change(function() {
            var journal, iscomm;
            var postas = $.trim($("#post_username").val());
            journal = $.trim($("#postas_usejournal").val()) || postas;
            iscomm = journal !== postas;
            console.log(journal, postas)
            $(this).trigger( "journalselect", {"name":journal, "iscomm":iscomm, isremote: false});
        });
        $("#post_as_other").click(function() {
            $("#post_entry").trigger( "journalselect", { name: undefined, iscomm: false, isremote: true } );
        })
        $("#post_as_remote").click(function() {
            $("#usejournal").triggerHandler("change");
        })
        $("#post_to").radioreveal({ radio: "post_as_remote" })
        $("#post_login").radioreveal({ radio: "post_as_other" });
    }

    // access
    function initAccess() {
        $("#custom_access_groups").hide();
        $("#security").change( function() {
            if ( $(this).val() == "custom" )
                $("#custom_access_groups").slideDown();
            else
                $("#custom_access_groups").slideUp();
        }).triggerHandler("change");

        function adjustSecurityDropdown(data) {
            if ( ! data ) return;

            var $security = $("#security");
            var oldval = $security.val();
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
                    $security.find("option[value='public']").attr("disabled", "disabled");
                } else if ( data.ret['minsecurity'] == 'private' ) {
                    $security.find("option[value='public'],option[value='access'],option[value='custom']")
                        .attr("disabled", "disabled");
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

        $("#post_entry").bind( "journalselect", function(e, journal) {
            var anon = ! journal.name
            if ( anon || journal.iscomm || ! journal.isremote )
                $("#custom_access_groups").slideUp();

            var $security = $("#security");
            if ( $security.length > 0 ) {
              if ( anon ) {
                adjustSecurityDropdown({})
              } else {
                $.getJSON( Site.siteroot + "/tools/endpoints/getsecurityoptions",
                    { "user": journal.name }, adjustSecurityDropdown);
            }
          }
        });
    }

    function initCrosspost() {
        $("#crosspost_component").crosspost();
        $("#post_entry").bind("journalselect", function(e, journal) {
            if ( journal.name && journal.isremote )
                $("#crosspost_component").crosspost("toggle", "community", ! journal.iscomm, true);
            else
                $("#crosspost_component").crosspost("toggle", "unknown", false, true);
        });
    }

    function initPostButton() {
        $("#submit_entry").data("label",$("#submit_entry").val());
        $("#post_entry").bind("journalselect", function(e, journal) {
            var $submit = $("#submit_entry");
            if ( journal.iscomm && journal.name )
                $submit.val( $submit.data("label") + ": " + journal.name);
            else
                $submit.val($submit.data("label"));
        });

        if ( $("#login_chal").length == 1 )
            $("#post_entry").submit( function(e) { if ( ! $("#login_response").val() ) { sendForm(this.id) } } );
    }

    function initToolbar() {
        $("#preview_button").click(function(e) {
            var form = e.target.form;
            var action = form.action;
            var target = form.target;

            var $password = $(form).find("input[type='password']:enabled");
            $password.attr("disabled","disabled");

            form.action = "/entry/preview";
            form.target = 'preview';
            window.open( '', 'preview', 'width=760,height=600,resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
            form.submit();

            form.action = action;
            form.target = target;
            $password.removeAttr("disabled");
            e.preventDefault();
        });

        $("#spellcheck_button").click(function(e) {
            $(this.form).data("skipchecks", "spellcheck");
        });

        $("#post_options").click(function(e){
            e.preventDefault();

            var $settings = $("#settings-tools");
            var $settingsform = $settings.children("form:visible");
            if ( $settingsform.length > 0 ) {
                $settingsform.trigger("settings.cancel")
            } else {
                var $img = $(this).find("img");
                var oldsrc = $img.attr("src");
                $img.attr("src", $.throbber.src );
                $settings.load(Site.siteroot + "/__rpc_entryoptions", function(html,status,jqxhr) {
                    $img.attr("src", oldsrc);
                })
            }
        });

        $.fx.off = formData.minAnimation;
    }

    // set up...
    initIcons();
    initDisplayDate();
    initCurrents();
    initTags();
    initJournalSelect();
    initAccess();
    initPostButton();
    initCrosspost();
    initToolbar();

    $.getJSON("/__rpc_entryformcollapse", null, function(data) {
        var xhr = this;
        $.ui.collapsible.cache = data;
        // make all components collapsible
        $("#post_entry .component").collapsible({ /*expanded: expanded[val],*/
            parseid: function() { return this.attr("id").replace("_component","") },
            endpointurl: xhr.url,
            trigger: "h3" });
    })


    // trigger all handlers associated with a journal selection
    if ( $("#usejournal").length == 1 ) {
        $("#usejournal").triggerHandler("change");
    } else {
        // not logged in and no usejournal
        $("#post_entry").trigger( "journalselect", { name: undefined, iscomm: false, isremote: true } );
    }
} }
})(jQuery);

jQuery(function($) {
    $("#nojs").val(0);
    $.postForm.init(window.postFormInitData);
    $("body").delegate( "button", "hover", function() {
		    $(this).toggleClass("ui-state-hover");
        }
    );
});
