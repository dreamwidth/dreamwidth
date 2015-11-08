(function($,Site){

if ( ! window.LJ_cmtinfo ) LJ_cmtinfo = {};

$.widget("dw.trackbutton", {
options: {},
_toggleSubscriptions: function(subInfo,subs) {
    var self = this;
    subInfo["subid"] = Number(subInfo["subid"]);

    var data = [];
    if ((subInfo["subid"] && ! subs["newComments"])
        || (! subInfo["subid"] && subs["newComments"])) {
        data.push( self._toggleSubscription(subInfo, "newComments") );
    }

    subInfo["newentry_subid"] = Number(subInfo["newentry_subid"]);
    if ((subInfo["newentry_subid"] && ! subs["newEntry"])
        || (! subInfo["newentry_subid"] && subs["newEntry"])) {

        var newEntrySubInfo = new Object(subInfo);
        newEntrySubInfo["subid"] = Number(subInfo["newentry_subid"]);
        data.push(self._toggleSubscription(newEntrySubInfo, "newEntry"));
    }

    if ( data.length ) {
        self.element.ajaxtip() // init
        .ajaxtip("load", data );
    }
},

_toggleSubscription: function(subInfo, type) {
    var self = this;

    var action;
    var params = {
        auth_token: type === "newEntry" ? subInfo.newentry_token : subInfo.auth_token
    };

    if (Number(subInfo.subid)) {
        // subscription exists
        action = "delsub";
        params.subid = subInfo.subid;
    } else {
        // create a new subscription
        action = "addsub";

        var param_keys;
        if (type === "newEntry") {
            params.etypeid = subInfo.newentry_etypeid;
            param_keys = ["journalid"];
        } else {
            param_keys = ["journalid", "arg1", "arg2", "etypeid"];
        }

        // get necessary AJAX parameters
        $.each(param_keys,(function (index,param) {
            if (Number(subInfo[param]))
                params[param] = parseInt(subInfo[param], 10);
        }));
    }
    params.action = action;

    var $clicked = self.element;
    return {
        endpoint: "esn_subs",
        ajax: {
            type: "POST",

            context: self,

            data: params,

            success: function( data, status, jqxhr ) {
                if (data.error) {
                    $clicked.ajaxtip("error", data.error);
                } else if (data.success) {
                    if (data.msg)
                        $clicked.ajaxtip("success", data.msg);

                    if (data.subscribed) {
                        if (data.subid)
                            $clicked.attr("lj_subid", data.subid);
                        if (data.newentry_subid)
                            $clicked.attr("lj_newentry_subid", data.newentry_subid);
                    } else {  // deleted subscription
                        if (data.event_class == "LJ::Event::JournalNewComment")
                            $clicked.attr("lj_subid", 0);
                        if (data.event_class == "LJ::Event::JournalNewEntry")
                            $clicked.attr("lj_newentry_subid", 0);
                    }
                    if (data.auth_token)
                        $clicked.attr("lj_auth_token", data.auth_token);
                    if (data.newentry_token)
                        $clicked.attr("lj_newentry_token", data.newentry_token);


                    var state = data.subscribed ? "on" : "off";

                    // update tracking icons if we've modified tracking for comments
                    // to this entry (versus new entries to this journal)
                    if ( data.event_class == "LJ::Event::JournalNewComment" ) {
                        var dtalkid = $clicked.attr("lj_dtalkid");
                        if ( dtalkid ) {
                            if (!data.subscribed) {
                                // show new state of this comment:
                                // "off" by default if no parents are being tracked,
                                // otherwise set state to "parent", which is equivalent to "on"
                                var $parentBtn;
                                var parent_dtalkid = dtalkid;
                                var cmtInfo = LJ_cmtinfo[dtalkid+""];

                                while ( $parentBtn = self._getParentButton(parent_dtalkid) ) {
                                    parent_dtalkid = $parentBtn.attr("lj_dtalkid");
                                    if ( ! parent_dtalkid ) break;

                                    if (! Number($parentBtn.attr("lj_subid"))) continue;
                                    state = "parent";
                                    break;
                                }
                            }
                            this._updateThread(dtalkid, state);
                        } else {
                            this._updateButton(self.element,state);
                        }
                    }
                }
            }
        }
    };
},

// given a dtalkid, find the track button for its parent comment (if any)
_getParentButton: function(dtalkid) {
    var cmt = LJ_cmtinfo[dtalkid+""];
    if ( ! cmt ) return null;

    var parent_dtalkid = cmt.parent;
    if ( ! parent_dtalkid ) return null;

    return $("#lj_track_btn_" + parent_dtalkid);
},

_updateButton: function($button,state) {
    var uri;
    switch(state) {
        case "on":
        case "parent":
            uri = "/silk/entry/untrack.png";
            break;
        case "off":
            uri = "/silk/entry/track.png";
            break;
        default:
            alert("Unknown tracking state " + state);
            break;
    }

    if ( $button.has("img") ) {
        $button.find("img").attr("src", Site.imgprefix + uri);
    } else {
        var swapName = $button.html();
        $button.html($button.attr("js_swapname"));
        $button.attr("js_swapname", swapName);
    }
},

_updateThread: function(dtalkid, state) {
    var self = this;
    var $btn = $("#lj_track_btn_" + dtalkid);
    if ( ! $btn.length ) return;

    var cmtInfo = LJ_cmtinfo[dtalkid + ""];
    if (! cmtInfo) return;

    // subscription already exists on this button, don't mess with it
    if (Number($btn.attr("lj_subid")) && state != "on")
        return;

    if (cmtInfo.rc && cmtInfo.rc.length) {
        // update children
        $.each(cmtInfo.rc, function (i,child_dtalkid) {
            window.setTimeout(function () {
                var threadState;
                switch (state) {
                case "on":
                    threadState = "parent";
                    break;
                case "off":
                    threadState = "off";
                    break;
                case "parent":
                    threadState = "parent";
                    break;
                default:
                    $btn.ajaxtip("error", "Unknown tracking state " + state)
                    break;
                }
                self._updateThread(child_dtalkid, threadState);
            }, 300);
        });
    }

    self._updateButton($btn,state);
},

_create: function() {
    if (! Site || ! Site.has_remote) return;

    var self = this;
    var $ele = self.element;
    if ($ele.attr("lj_subid") === undefined || $ele.attr("lj_journalid") === undefined ) return;

    $ele.click( function(e) {
        // don't show the popup if we want to open it in a new tab (ctrl+click or cmd+click)
        if (e.ctrlKey || e.metaKey) return;

        // e.which == 1 is a left click. We don't want to handle anything else
        if (e.which != 1) return;

        e.preventDefault();
        e.stopPropagation();

        var btnInfo = {};
        var args = ['arg1', 'arg2', 'etypeid', 'newentry_etypeid', 'newentry_token', 'newentry_subid',
         'journalid', 'subid', 'auth_token'];
        $.each( args, function (index, arg) {
            btnInfo[arg] = $ele.attr("lj_" + arg);
        });


        var $dlg = $("<div class='trackdialog'></div>");
        var TrackCheckbox = function (title, checked) {
            var uniqueid = "newentrytrack" + Unique.id();
            var $checkbox = $("<input></input>",
                { "type": "checkbox", "id": uniqueid, "checked": checked });
            var $checkContainer = $("<div></div>")
                .append( $checkbox, $("<label></label>", { "for": uniqueid }).html(title) )
                .appendTo( $dlg );

            return $checkbox;
        };

        // is the user already tracking new entries by this user / new comments on this entry?
        var trackingNewEntries  = Number(btnInfo['newentry_subid']) ? true : false;
        var trackingNewComments = Number(btnInfo['subid']) ? true : false;

        var $newEntryTrackBtn;
        var $commentsTrackBtn;

        if (Number($ele.attr("lj_dtalkid"))) {
            // this is a thread tracking button
            // always checked: either because they're subscribed, or because
            // they're going to subscribe.
            $commentsTrackBtn = TrackCheckbox("someone replies in this comment thread", true);
        } else {
            // entry tracking button
            var journal = LJ_cmtinfo["journal"] || $ele.attr("journal") || Site.currentJournal;
            if ( journal ) {
                $newEntryTrackBtn = TrackCheckbox( journal + " posts a new entry", trackingNewEntries );
            }
            $commentsTrackBtn = TrackCheckbox("someone comments on this post", trackingNewComments);
        }

        $dlg.dialog({
            title: "Email me when",
            dialogClass: "track-dialog",
            position: {
                my: "center bottom",
                at: "right top",
                of: this,
                collision: "fit fit"
            },
            buttons: {
                "Save Changes": function() {
                    $(this).dialog( "close" );
                    self._toggleSubscriptions(btnInfo,{
                        newEntry: $newEntryTrackBtn ? $newEntryTrackBtn.is(":checked") : false,
                        newComments: $commentsTrackBtn.is(":checked")
                    });
                },
                "More Options": function() {
                    document.location = $ele.attr("href");
                }
            },
            width: 500
        });
    });
}

});

})(jQuery,window.Site||{});

jQuery(function($){
    $("a.TrackButton").trackbutton();
    $(document.body).delegate("*","updatedcontent.comment", function(e) {
        e.stopPropagation();
        $("a.TrackButton",this).trackbutton();
    });
});
