var ESN = new Object();

LiveJournal.register_hook("page_load", function () {
  ESN.initCheckAllBtns();
  ESN.initEventCheckBtns();
  ESN.initTrackBtns();
});

// When page loads, set up "check all" checkboxes
ESN.initCheckAllBtns = function () {
  var ntids  = $("ntypeids");
  var catids = $("catids");

  if (!ntids || !catids)
    return;

  ntidList  = ntids.value;
  catidList = catids.value;

  if (!ntidList || !catidList)
    return;

  ntids  = ntidList.split(",");
  catids = catidList.split(",");

  catids.forEach( function (catid) {
    ntids.forEach( function (ntypeid) {
      var className = "SubscribeCheckbox-" + catid + "-" + ntypeid;

      var cab = new CheckallButton();
      cab.init({
        "class": className,
          "button": $("CheckAll-" + catid + "-" + ntypeid),
          "parent": $("CategoryRow-" + catid)
          });
    });
  });
}

// set up auto show/hiding of notification methods
ESN.initEventCheckBtns = function () {
  var viewObjects = document.getElementsByTagName("*");
  var boxes = DOM.filterElementsByClassName(viewObjects, "SubscriptionInboxCheck") || [];

  boxes.forEach( function (box) {
    DOM.addEventListener(box, "click", ESN.eventChecked.bindEventListener());
  });
}

ESN.eventChecked = function (evt) {
  var target = evt.target;
  if (!target)
    return;

  var parentRow = DOM.getFirstAncestorByTagName(target, "tr", false);

  var viewObjects = parentRow.getElementsByTagName("*");
  var boxes = DOM.filterElementsByClassName(viewObjects, "NotificationOptions") || [];

  boxes.forEach( function (box) {
    box.style.visibility = target.checked ? "visible" : "hidden";
  });
}

// attach event handlers to all track buttons
ESN.initTrackBtns = function () {
    // don't do anything if no remote
    if (!Site || !Site.has_remote) return;

    // attach to all ljuser head icons
    var trackBtns = DOM.getElementsByTagAndClassName( document, "a", "TrackButton" );

    Array.prototype.forEach.call(trackBtns, function (trackBtn) {
        if (!trackBtn || !trackBtn.getAttribute) return;

        if (!trackBtn.getAttribute("lj_subid") && !trackBtn.getAttribute("lj_journalid")) return;

        DOM.addEventListener(trackBtn, "click",
                             ESN.trackBtnClickHandler.bindEventListener(trackBtn));
    });
};

ESN.trackBtnClickHandler = function (evt) {
    var trackBtn = evt.target;
    if ( ! trackBtn ) return true;

    // don't show the popup if we want to open it in a new tab (ctrl+click or cmd+click)
    if (evt && (evt.ctrlKey || evt.metaKey)) return false;

    trackBtn.isIcon = false;

    if ( trackBtn.tagName.toLowerCase() == "img" ) {
        trackBtn = trackBtn.parentNode;
        trackBtn.isIcon = true;
    }

    Event.stop(evt);

    var btnInfo = {};

    ['arg1', 'arg2', 'etypeid', 'newentry_etypeid', 'newentry_token', 'newentry_subid',
     'journalid', 'subid', 'auth_token'].forEach(function (arg) {
        btnInfo[arg] = trackBtn.getAttribute("lj_" + arg);
    });

    // pop up little dialog to either track by inbox/email or go to more options
    var dlg = document.createElement("div");
    var title = _textDiv("Email me when");
    DOM.addClassName(title, "track_title");
    dlg.appendChild(title);

    var TrackCheckbox = function (title, checked) {
        var checkContainer = document.createElement("div");

        var newCheckbox = document.createElement("input");
        newCheckbox.type = "checkbox";
        newCheckbox.id = "newentrytrack" + Unique.id();
        var newCheckboxLabel = document.createElement("label");
        newCheckboxLabel.setAttribute("for", newCheckbox.id);
        newCheckboxLabel.innerHTML = title;

        checkContainer.appendChild(newCheckbox);
        checkContainer.appendChild(newCheckboxLabel);
        dlg.appendChild(checkContainer);

        newCheckbox.checked = checked ? true : false;

        return newCheckbox;
    };

    // global trackPopup so we can only have one
    if (ESN.trackPopup) {
        ESN.trackPopup.hide();
        ESN.trackPopup = null;
    }

    var saveChangesBtn = document.createElement("input");
    saveChangesBtn.type = "button";
    saveChangesBtn.value = "Save Changes";
    DOM.addClassName(saveChangesBtn, "track_savechanges");

    var trackingNewEntries  = Number(btnInfo['newentry_subid']) ? 1 : 0;
    var trackingNewComments = Number(btnInfo['subid']) ? 1 : 0;

    var newEntryTrackBtn;
    var commentsTrackBtn;

    if (Number(trackBtn.getAttribute("lj_dtalkid"))) {
        // this is a thread tracking button
        // always checked: either because they're subscribed, or because
        // they're going to subscribe.
        commentsTrackBtn = TrackCheckbox("someone replies in this comment thread", 1);
    } else {
        // entry tracking button
        var journal; 
        
        if ( typeof LJ_cmtinfo !== 'undefined' ) {
            journal = LJ_cmtinfo["journal"];
        } else if ( typeof trackBtn.getAttribute( "journal" ) != "undefined" ) {
            journal = trackBtn.getAttribute( "journal" );
        } else if ( typeof Site !== 'undefined' ) {
            journal = Site.currentJournal;
        }

        if ( journal ) {
            newEntryTrackBtn = TrackCheckbox( journal + " posts a new entry", trackingNewEntries );
        }
        commentsTrackBtn = TrackCheckbox("someone comments on this post", trackingNewComments);
    }

    DOM.addEventListener(saveChangesBtn, "click", function () {
        ESN.toggleSubscriptions(btnInfo, evt, trackBtn, {
            newEntry: newEntryTrackBtn ? newEntryTrackBtn.checked : false,
            newComments: commentsTrackBtn.checked
        });
        if (ESN.trackPopup) ESN.trackPopup.hide();
    });

    var btnsContainer = document.createElement("div");
    DOM.addClassName(btnsContainer, "track_btncontainer");
    dlg.appendChild(btnsContainer);

    btnsContainer.appendChild(saveChangesBtn);

    var custTrackLink = document.createElement("a");
    custTrackLink.href = trackBtn.href;
    btnsContainer.appendChild(custTrackLink);
    custTrackLink.innerHTML = "More Options";
    DOM.addClassName(custTrackLink, "track_moreopts");

    ESN.trackPopup = new LJ_IPPU.showNoteElement(dlg, trackBtn, 0);

    DOM.addEventListener(custTrackLink, "click", function (evt) {
        Event.stop(evt);
        document.location.href = trackBtn.href;
        if (ESN.trackPopup) ESN.trackPopup.hide();
        return false;
    });

    return false;
}

// toggles subscriptions
ESN.toggleSubscriptions = function (subInfo, evt, btn, subs) {
    subInfo["subid"] = Number(subInfo["subid"]);
    if ((subInfo["subid"] && ! subs["newComments"])
        || (! subInfo["subid"] && subs["newComments"])) {
        ESN.toggleSubscription(subInfo, evt, btn, "newComments");
    }

    subInfo["newentry_subid"] = Number(subInfo["newentry_subid"]);
    if ((subInfo["newentry_subid"] && ! subs["newEntry"])
        || (! subInfo["newentry_subid"] && subs["newEntry"])) {
            var newentrySubInfo = new Object(subInfo);
            newentrySubInfo["subid"] = Number(btn.getAttribute("lj_newentry_subid"));
            ESN.toggleSubscription(newentrySubInfo, evt, btn, "newEntry");
    }
};

// (Un)subscribes to an event
ESN.toggleSubscription = function (subInfo, evt, btn, sub) {
    var action = "";
    var params = {
        auth_token: sub == "newEntry" ? subInfo.newentry_token : subInfo.auth_token
    };

    if (Number(subInfo.subid)) {
        // subscription exists
        action = "delsub";
        params.subid = subInfo.subid;
    } else {
        // create a new subscription
        action = "addsub";

        var param_keys;
        if (sub == "newEntry") {
            params.etypeid = subInfo.newentry_etypeid;
            param_keys = ["journalid"];
        } else {
            param_keys = ["journalid", "arg1", "arg2", "etypeid"];
        }

        param_keys.forEach(function (param) {
            if (Number(subInfo[param]))
                params[param] = parseInt(subInfo[param], 10);
        });
    }

    params.action = action;

    var reqInfo = {
        "method": "POST",
        "url":    LiveJournal.getAjaxUrl('esn_subs'),
        "data":   HTTPReq.formEncoded(params)
    };

    var gotInfoCallback = function (info) {
        if (! info) return LJ_IPPU.showNote("Error changing subscription", btn);

        if (info.error) return LJ_IPPU.showNote(info.error, btn);

        if (info.success) {
            if (info.msg)
                LJ_IPPU.showNote(info.msg, btn);

            if (info.subscribed) {
                if (info.subid)
                    DOM.setElementAttribute(btn, "lj_subid", info.subid);
                if (info.newentry_subid)
                    DOM.setElementAttribute(btn, "lj_newentry_subid", info.newentry_subid);

                DOM.setElementAttribute(btn, "title", 'Untrack This');

                // update subthread tracking icons
                var dtalkid = btn.getAttribute("lj_dtalkid");
                if ( dtalkid ) {
                    ESN.updateThreadIcons(dtalkid, "on");
                } else { // not thread tracking button
                    if ( ! btn.isIcon ) {
                        var swapName = btn.innerHTML;
                        btn.innerHTML = btn.getAttribute( "js_swapname" );
                        DOM.setElementAttribute( btn, "js_swapname", swapName );
                    } else {
                        btn.firstChild.src = Site.imgprefix + "/silk/entry/untrack.png";
                    }
                }
            } else {
                if (info["event_class"] == "LJ::Event::JournalNewComment")
                    DOM.setElementAttribute(btn, "lj_subid", 0);
                else if (info["event_class"] == "LJ::Event::JournalNewEntry")
                    DOM.setElementAttribute(btn, "lj_newentry_subid", 0);

                DOM.setElementAttribute(btn, "title", 'Track This');

                // update subthread tracking icons
                var dtalkid = btn.getAttribute("lj_dtalkid");
                if (dtalkid) {
                    // set state to "off" if no parents tracking this,
                    // otherwise set state to "parent"
                    var state = "off";
                    var parentBtn;
                    var parent_dtalkid = dtalkid;
                    while (parentBtn = ESN.getThreadParentBtn(parent_dtalkid)) {
                        parent_dtalkid = parentBtn.getAttribute("lj_dtalkid");
                        if (! parent_dtalkid) {
                            log("could not find parent_dtalkid");
                            break;
                        }

                        if (! Number(parentBtn.getAttribute("lj_subid")))
                            continue;
                        state = "parent";
                        break;
                    }

                    ESN.updateThreadIcons(dtalkid, state);

                } else {
                    // not thread tracking button
                    if ( ! btn.isIcon ) {
                        var swapName = btn.innerHTML;
                        btn.innerHTML = btn.getAttribute( "js_swapname" );
                        DOM.setElementAttribute( btn, "js_swapname", swapName );
                    } else {
                        btn.firstChild.src = Site.imgprefix + "/silk/entry/track.png";
                    }
                }
            }
            if (info.auth_token)
                DOM.setElementAttribute(btn, "lj_auth_token", info.auth_token);
            if (info.newentry_token)
                DOM.setElementAttribute(btn, "lj_newentry_token", info.newentry_token);
        }
    };

    reqInfo.onData = gotInfoCallback;
    reqInfo.onError = function (err) { LJ_IPPU.showNote("Error: " + err) };

    HTTPReq.getJSON(reqInfo);
};

// given a dtalkid, find the track button for its parent comment (if any)
ESN.getThreadParentBtn = function (dtalkid) {
    var cmtInfo = LJ_cmtinfo[dtalkid + ""];
    if (! cmtInfo) {
        log("no comment info");
        return null;
    }

    var parent_dtalkid = cmtInfo.parent;
    if (! parent_dtalkid)
        return null;

    return $("lj_track_btn_" + parent_dtalkid);
};

// update all the tracking icons under a parent comment
ESN.updateThreadIcons = function (dtalkid, tracking) {
    var btn = $("lj_track_btn_" + dtalkid);
    if (! btn) {
        log("no button");
        return;
    }

    var cmtInfo = LJ_cmtinfo[dtalkid + ""];
    if (! cmtInfo) {
        log("no comment info");
        return;
    }

    if (Number(btn.getAttribute("lj_subid")) && tracking != "on") {
        // subscription already exists on this button, don't mess with it
        return;
    }

    if (cmtInfo.rc && cmtInfo.rc.length) {
        // update children
        cmtInfo.rc.forEach(function (child_dtalkid) {
            window.setTimeout(function () {
                var state;
                switch (tracking) {
                case "on":
                    state = "parent";
                    break;
                case "off":
                    state = "off";
                    break;
                case "parent":
                    state = "parent";
                    break;
                default:
                    alert("Unknown tracking state " + tracking);
                    break;
                }
                ESN.updateThreadIcons(child_dtalkid, state);
            }, 300);
        });
    }

    // update icon
    var uri;
    switch (tracking) {
        case "on":
            uri = "/silk/entry/untrack.png";
            break;
        case "off":
            uri = "/silk/entry/track.png";
            break;
        case "parent":
            uri = "/silk/entry/untrack.png";
            break;
        default:
            alert("Unknown tracking state " + tracking);
            break;
    }
    if ( typeof btn.firstChild.tagName != "undefined" && btn.firstChild.tagName.toLowerCase() == "img" ) {
        btn.firstChild.src = Site.imgprefix + uri;
    } else {
        var swapName = btn.innerHTML;
        btn.innerHTML = btn.getAttribute( "js_swapname" );
        DOM.setElementAttribute( btn, "js_swapname", swapName );
    }
        
};
