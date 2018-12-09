var ContextualPopup = new Object;

ContextualPopup.popupDelay  = 500;
ContextualPopup.hideDelay   = 250;
ContextualPopup.disableAJAX = false;
ContextualPopup.debug       = false;

ContextualPopup.cachedResults   = {};
ContextualPopup.currentRequests = {};
ContextualPopup.mouseInTimer    = null;
ContextualPopup.mouseOutTimer   = null;
ContextualPopup.currentId       = null;
ContextualPopup.hourglass       = null;
ContextualPopup.elements        = {};

ContextualPopup.setup = function () {
    // don't do anything if no remote
    if (!Site || !Site.ctx_popup) return;

    var userElements = [];

    // attach to all ljuser head icons
    if (Site.ctx_popup_userhead) {
        var ljusers = DOM.getElementsByTagAndClassName(document, 'span', "ljuser");

        ljusers.forEach(function (ljuser) {
            var nodes = ljuser.getElementsByTagName("img");
            for (var i=0; i < nodes.length; i++) {
                var node = nodes.item(i);

                // if the parent (a tag with link to userinfo) has userid in its URL, then
                // this is an openid user icon and we should use the userid
                var parent = node.parentNode;
                var userid;
                if (parent && parent.href && (userid = parent.href.match(/\?userid=(\d+)/i)))
                    node.userid = userid[1];
                else
                    node.username = ljuser.getAttribute("lj:user");

                if (!node.username && !node.userid) continue;

                userElements.push(node);
                DOM.addClassName(node, "ContextualPopup");

            }
        });
    };

    // attach to all userpics
    if (Site.ctx_popup_icons) {
        var images = document.getElementsByTagName("img") || [];
        var old_icon_url = 'www\\.dreamwidth\\.org/userpic';
        var url_prefix = "(^" + Site.iconprefix + "|" + old_icon_url + ")";
        var re = new RegExp( url_prefix + "/\\d+\/\\d+$" );
        Array.prototype.forEach.call(images, function (image) {
            // if the image url matches a regex for userpic urls then attach to it
            if (image.src.match(re)) {
                image.up_url = image.src;
                DOM.addClassName(image, "ContextualPopup");
                userElements.push(image);
           }
        });
    };

    var ctxPopupId = 1;
    userElements.forEach(function (userElement) {
        ContextualPopup.elements[ctxPopupId + ""] = userElement;
        userElement.ctxPopupId = ctxPopupId++;
    });

    DOM.addEventListener(document.body, "mousemove", ContextualPopup.mouseOver.bindEventListener());
}

ContextualPopup.isCtxPopElement = function (ele) {
    return (ele && DOM.getAncestorsByClassName(ele, "ContextualPopup", true).length);
}

ContextualPopup.mouseOver = function (e) {
    var target = e.target;
    var ctxPopupId = target.ctxPopupId;

    // if the ctxpopup class isn't fully loaded and set up yet,
    // skip the event handling for now
    if (!eval("ContextualPopup") || !ContextualPopup.isCtxPopElement) return;

    // did the mouse move out?
    if (!target || !ContextualPopup.isCtxPopElement(target)) {
        if (ContextualPopup.mouseInTimer) {
            window.clearTimeout(ContextualPopup.mouseInTimer);
            ContextualPopup.mouseInTimer = null;
        };

        if (ContextualPopup.ippu) {
            if (ContextualPopup.mouseInTimer || ContextualPopup.mouseOutTimer) return;

            ContextualPopup.mouseOutTimer = window.setTimeout(function () {
                ContextualPopup.mouseOut(e);
            }, ContextualPopup.hideDelay);
            return;
        }
    }

    // we're inside a ctxPopElement, cancel the mouseout timer
    if (ContextualPopup.mouseOutTimer) {
        window.clearTimeout(ContextualPopup.mouseOutTimer);
        ContextualPopup.mouseOutTimer = null;
    }

    if (!ctxPopupId)
    return;

    var cached = ContextualPopup.cachedResults[ctxPopupId + ""];

    // if we don't have cached data background request it
    if (!cached) {
        ContextualPopup.getInfo(target);
    }

    // start timer if it's not running
    if (! ContextualPopup.mouseInTimer && (! ContextualPopup.ippu || (
                                                                      ContextualPopup.currentId &&
                                                                      ContextualPopup.currentId != ctxPopupId))) {
        ContextualPopup.mouseInTimer = window.setTimeout(function () {
            ContextualPopup.showPopup(ctxPopupId);
        }, ContextualPopup.popupDelay);
    }
}

// if the popup was not closed by us catch it and handle it
ContextualPopup.popupClosed = function () {
    ContextualPopup.mouseOut();
}

ContextualPopup.mouseOut = function (e) {
    if (ContextualPopup.mouseInTimer)
        window.clearTimeout(ContextualPopup.mouseInTimer);
    if (ContextualPopup.mouseOutTimer)
        window.clearTimeout(ContextualPopup.mouseOutTimer);

    ContextualPopup.mouseInTimer = null;
    ContextualPopup.mouseOutTimer = null;
    ContextualPopup.currentId = null;

    ContextualPopup.hidePopup();
}

ContextualPopup.showPopup = function (ctxPopupId) {
    if (ContextualPopup.mouseInTimer) {
        window.clearTimeout(ContextualPopup.mouseInTimer);
    }
    ContextualPopup.mouseInTimer = null;

    if (ContextualPopup.ippu && (ContextualPopup.currentId && ContextualPopup.currentId == ctxPopupId)) {
        return;
    }

    ContextualPopup.currentId = ctxPopupId;

    ContextualPopup.constructIPPU(ctxPopupId);

    var ele = ContextualPopup.elements[ctxPopupId + ""];
    var data = ContextualPopup.cachedResults[ctxPopupId + ""];

    if (! ele || (data && data.noshow)) {
        return;
    }

    if (ContextualPopup.ippu) {
        var ippu = ContextualPopup.ippu;
        // default is to auto-center, don't want that
        ippu.setAutoCenter(false, false);

        // pop up the box right under the element
        var dim = DOM.getAbsoluteDimensions(ele);
        if (!dim) return;

        var bounds = DOM.getClientDimensions();
        if (!bounds) return;

        // hide the ippu content element, put it on the page,
        // get its bounds and make sure it's not going beyond the client
        // viewport. if the element is beyond the right bounds scoot it to the left.

        var popEle = ippu.getElement();
        popEle.style.visibility = "hidden";
        ContextualPopup.ippu.setLocation(dim.absoluteLeft, dim.absoluteBottom);

        // put the content element on the page so its dimensions can be found
        ContextualPopup.ippu.show();

        var ippuBounds = DOM.getAbsoluteDimensions(popEle);
        if (ippuBounds.absoluteRight > bounds.x) {
            ContextualPopup.ippu.setLocation(bounds.x - ippuBounds.offsetWidth - 30, dim.absoluteBottom);
        }

        // finally make the content visible
        popEle.style.visibility = "visible";
    }
}

ContextualPopup.constructIPPU = function (ctxPopupId) {
    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.hide();
        ContextualPopup.ippu = null;
    }

    var ippu = new IPPU();
    ippu.init();
    ippu.setTitlebar(false);
    ippu.setFadeOut(true);
    ippu.setFadeIn(true);
    ippu.setFadeSpeed(15);
    ippu.setDimensions("auto", "auto");
    ippu.addClass("ContextualPopup");
    ippu.setCancelledCallback(ContextualPopup.popupClosed);
    ContextualPopup.ippu = ippu;

    ContextualPopup.renderPopup(ctxPopupId);
}

ContextualPopup.renderPopup = function (ctxPopupId) {
    var ippu = ContextualPopup.ippu;

    if (!ippu)
    return;

    if (ctxPopupId) {
        var data = ContextualPopup.cachedResults[ctxPopupId];

        if (!data) {
            ippu.setContent("<div class='Inner'>Loading...</div>");
            return;
        } else if (!data.username || !data.success || data.noshow) {
            ippu.hide();
            return;
        }

        var username = data.display_username;

        var inner = document.createElement("div");
        DOM.addClassName(inner, "Inner");

        var content = document.createElement("div");
        DOM.addClassName(content, "Content");

        var bar = document.createElement("span");
        bar.innerHTML = "&nbsp;| ";

        // userpic
        if (data.url_userpic) {
            var userpicContainer = document.createElement("div");
            var userpicLink = document.createElement("a");
            userpicLink.href = data.url_allpics;
            var userpic = document.createElement("img");
            userpic.src = data.url_userpic;
            userpic.width = data.userpic_w;
            userpic.height = data.userpic_h;

            userpicContainer.appendChild(userpicLink);
            userpicLink.appendChild(userpic);
            DOM.addClassName(userpicContainer, "Userpic");

            inner.appendChild(userpicContainer);
        }

        inner.appendChild(content);

        // relation
        var relation = document.createElement("div");
        if (data.is_comm) {
            var m_label = "";
            var w_label = "";

            if (data.is_member)
                m_label = "You are a member of " + username;

            if (data.is_watching)
                w_label = "You have subscribed to " + username;

            if (m_label && w_label)
                relation.innerHTML = m_label + "<br />" + w_label;
            else if (m_label || w_label)
                relation.innerHTML = m_label + w_label;
            else
                relation.innerHTML = username;
        } else if (data.is_syndicated) {
            if (data.is_watching)
                relation.innerHTML = "You have subscribed to " + username;
            else
                relation.innerHTML = username;
        } else {
            if (data.is_requester) {
                relation.innerHTML = "This is you";
            } else {
                var t_label = "";
                var w_label = "";

                if (data.is_trusting && data.is_trusted_by)
                    t_label = username + " and you have mutual access";
                else if (data.is_trusting)
                    t_label = "You have granted access to " + username;
                else if (data.is_trusted_by)
                    t_label = username + " has granted access to you";

                if (data.is_watching && data.is_watched_by)
                    w_label = username + " and you have mutual subscriptions";
                else if (data.is_watching)
                    w_label = "You have subscribed to " + username;
                else if (data.is_watched_by)
                    w_label = username + " has subscribed to you";

                if (t_label && w_label)
                    relation.innerHTML = t_label + "<br />" + w_label;
                else if (t_label || w_label)
                    relation.innerHTML = t_label + w_label;
                else
                    relation.innerHTML = username;
            }
        }
        DOM.addClassName(relation, "Relation");
        content.appendChild(relation);

        // add site-specific content here
        var extraContent = LiveJournal.run_hook("ctxpopup_extrainfo", data);
        if (extraContent) {
            content.appendChild(extraContent);
        }

        // member of community
        if (data.is_logged_in && data.is_comm) {
            var membership      = document.createElement("span");

            if (!data.is_closed_membership || data.is_member) {
                var membershipLink  = document.createElement("a");

                var membership_action;

                if (data.is_member) {
                    membershipLink.href = data.url_leavecomm;
                    membershipLink.innerHTML = "Leave";
                    membership_action = "leave";
                } else if (data.is_invited) {
                    membershipLink.href = data.url_acceptinvite;
                    membershipLink.innerHTML = "Accept invitation";
                    membership_action = "accept";
                } else {
                    membershipLink.href = data.url_joincomm;
                    membershipLink.innerHTML = "Join community";
                    membership_action = "join";
                }

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(membershipLink, "click", function (e) {
                        Event.prep(e);
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, membership_action, e); });
                }

                membership.appendChild(membershipLink);
            } else {
                membership.innerHTML = "Community closed";
            }
            content.appendChild(membership);
        }

        // send message
        var message;
        if ( data.is_logged_in && ( data.is_person || data.is_identity ) && data.can_message ) {
            message = document.createElement("span");

            var sendmessage = document.createElement("a");
            sendmessage.href = data.url_message;
            sendmessage.innerHTML = "Send message";

            message.appendChild(sendmessage);
            content.appendChild(message);

            if (data.is_requester)
                content.appendChild(document.createElement("br"));
        }

        if ((data.is_person || data.is_comm) && !data.is_requester && data.can_receive_vgifts) {
            var vgift = document.createElement("span");

            var sendvgift = document.createElement("a");
            sendvgift.href = data.url_vgift;
            sendvgift.innerHTML = "Send virtual gift";

            vgift.appendChild(sendvgift);

            if ( (data.is_logged_in && data.is_comm) || message )
                content.appendChild(document.createElement("br"));

            content.appendChild(vgift);
        }

        // relationships
        var trust;
        var watch;
        if (data.is_logged_in && ! data.is_requester) {
            if (!data.is_trusting) {
                // add trust link
                var addTrust = document.createElement("span");
                var addTrustLink = document.createElement("a");
                addTrustLink.href = data.url_addtrust;

                if (data.is_person || data.other_is_identity) {
                    trust = document.createElement("span");
                    addTrustLink.innerHTML = "Grant access";
                }

                addTrust.appendChild(addTrustLink);
                DOM.addClassName(addTrust, "AddTrust");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(addTrustLink, "click", function (e) {
                        Event.prep(e);
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "addTrust", e); });
                }

                if (trust)
                    trust.appendChild(addTrust);
            } else {
                // remove trust link
                var removeTrust = document.createElement("span");
                var removeTrustLink = document.createElement("a");
                removeTrustLink.href = data.url_addtrust;

                if (data.is_person || data.other_is_identity) {
                    trust = document.createElement("span");
                    removeTrustLink.innerHTML = "Remove access";
                }

                removeTrust.appendChild(removeTrustLink);
                DOM.addClassName(removeTrust, "RemoveTrust");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(removeTrustLink, "click", function (e) {
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "removeTrust", e); });
                }

                if (trust)
                    trust.appendChild(removeTrust);
            }

            if (!data.is_watching && !data.other_is_identity) {
                // add watch link
                var addWatch = document.createElement("span");
                var addWatchLink = document.createElement("a");
                addWatchLink.href = data.url_addwatch;

                watch = document.createElement("span");
                addWatchLink.innerHTML = "Subscribe";

                addWatch.appendChild(addWatchLink);
                DOM.addClassName(addWatch, "AddWatch");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(addWatchLink, "click", function (e) {
                        Event.prep(e);
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "addWatch", e); });
                }

                watch.appendChild(addWatch);
            } else if (data.is_watching) {
                // remove watch link
                var removeWatch = document.createElement("span");
                var removeWatchLink = document.createElement("a");
                removeWatchLink.href = data.url_addwatch;

                watch = document.createElement("span");
                removeWatchLink.innerHTML = "Remove subscription";

                removeWatch.appendChild(removeWatchLink);
                DOM.addClassName(removeWatch, "RemoveWatch");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(removeWatchLink, "click", function (e) {
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "removeWatch", e); });
                }

                watch.appendChild(removeWatch);
            }

            DOM.addClassName(relation, "RelationshipStatus");
        }

        // add a bar between stuff if we have community actions
        if ((data.is_logged_in && data.is_comm) || (message && (trust || watch)))
            content.appendChild(document.createElement("br"));

        if (trust)
            content.appendChild(trust);

        if (trust && watch)
            content.appendChild(document.createElement("br"));

        if (watch)
            content.appendChild(watch);

        // ban / unban

        var ban;
        if (data.is_logged_in && ! data.is_requester && ! data.is_syndicated && ! data.is_comm ) {
            ban = document.createElement("span");

            if(!data.is_banned) {
                // if user not banned - show ban link
                var setBan = document.createElement("span");
                var setBanLink = document.createElement("a");

                setBanLink.href = window.Site.siteroot + '/manage/banusers';

                if (data.is_comm) {
                    setBanLink.innerHTML = 'Ban community';
                } else {
                    setBanLink.innerHTML = 'Ban user';
                }

                setBan.appendChild(setBanLink);

                DOM.addClassName(setBan, "SetBan");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(setBanLink, "click", function (e) {
                        Event.prep(e);
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "setBan", e); });
                }

                ban.appendChild(setBan);



            } else {
                // if user banned - show unban link
                var setUnban = document.createElement("span");
                var setUnbanLink = document.createElement("a");
                setUnbanLink.href = window.Site.siteroot + '/manage/banusers';
                setUnbanLink.innerHTML = 'Unban user';
                setUnban.appendChild(setUnbanLink);

                DOM.addClassName(setUnban, "SetUnban");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(setUnbanLink, "click", function (e) {
                        Event.prep(e);
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "setUnban", e); });
                }

                ban.appendChild(setUnban);

            }
        }

        if(ban) {
            content.appendChild(document.createElement("br"));
            content.appendChild(ban);
        }


        // break
        if ( (data.is_logged_in && !data.is_requester) || trust || watch )
            content.appendChild(document.createElement("br"));

        // view label
        var viewLabel = document.createElement("span");
        viewLabel.innerHTML = "View: ";
        content.appendChild(viewLabel);

        // journal
        if (data.is_person || data.is_comm || data.is_syndicated) {
            var journalLink = document.createElement("a");
            journalLink.href = data.url_journal;

            if (data.is_person)
                journalLink.innerHTML = "Journal";
            else if (data.is_comm)
                journalLink.innerHTML = "Community";
            else if (data.is_syndicated)
                journalLink.innerHTML = "Feed";

            content.appendChild(journalLink);
            content.appendChild(bar.cloneNode(true));
        }

        // profile
        var profileLink = document.createElement("a");
        profileLink.href = data.url_profile;
        profileLink.innerHTML = "Profile";
        content.appendChild(profileLink);



        // clearing div
        var clearingDiv = document.createElement("div");
        DOM.addClassName(clearingDiv, "ljclear");
        clearingDiv.innerHTML = "&nbsp;";
        content.appendChild(clearingDiv);

        ippu.setContentElement(inner);
    }
}

// ajax request to change relation
ContextualPopup.changeRelation = function (info, ctxPopupId, action, evt) {
    if (!info) return true;

    if ( action == "setBan" || action == "setUnban" ) {
       var username = info.display_name;
       var message = action == "setUnban" ? "Are you sure you wish to unban " + username + "?"
                                          : "Are you sure you wish to ban " + username + "?";
       if ( ! confirm( message ) )
           return false;
    };

    var postData = {
        "target": info.username,
        "action": action
    };

    // get the authtoken
    var authtoken = info[action + "_authtoken"];
    if (!authtoken) log("no auth token for action" + action);
    postData.auth_token = authtoken;

    // needed on journal subdomains
    var url = LiveJournal.getAjaxUrl("changerelation");

    // callback from changing relation request
    var changedRelation = function (data) {
        if ( action == "setBan" || action == "setUnban" ) {
           var username = info.display_name;
           var message = action == "setUnban" ? "Are you sure you wish to unban " + username + "?"
                                              : "Are you sure you wish to ban " + username + "?";
           if ( confirm( message ) ) {
              return action;
           } else { return false; };
        };

        if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

        if (data.error) {
            ContextualPopup.showNote(data.error, ctxPopupId);
            return;
        }

        if (data.note)
        ContextualPopup.showNote(data.note, ctxPopupId);

        if (!data.success) return;

        if (ContextualPopup.cachedResults[ctxPopupId + ""]) {
            var updatedProps = ["is_trusting", "is_watching", "is_member", "is_banned"];
            updatedProps.forEach(function (prop) {
                ContextualPopup.cachedResults[ctxPopupId + ""][prop] = data[prop];
            });
        }

        // if the popup is up, reload it
        ContextualPopup.renderPopup(ctxPopupId);
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "url": url,
        "onError": ContextualPopup.gotError,
        "onData": changedRelation
    };

    // do hourglass at mouse coords
    var mouseCoords = DOM.getAbsoluteCursorPosition(evt);
    if (!ContextualPopup.hourglass && mouseCoords) {
        ContextualPopup.hourglass = new Hourglass();
        ContextualPopup.hourglass.init(null, "lj_hourglass");
        ContextualPopup.hourglass.add_class_name("ContextualPopup"); // so mousing over hourglass doesn't make ctxpopup think mouse is outside
        ContextualPopup.hourglass.hourglass_at(mouseCoords.x, mouseCoords.y);
    }

    HTTPReq.getJSON(opts);

    return false;
}

// create a little popup to notify the user of something
ContextualPopup.showNote = function (note, ctxPopupId) {
    var ele;

    if (ContextualPopup.ippu) {
        // pop up the box right under the element
        ele = ContextualPopup.ippu.getElement();
    } else {
        if (ctxPopupId) {
            var ele = ContextualPopup.elements[ctxPopupId + ""];
        }
    }

    LJ_IPPU.showNote(note, ele);
}

ContextualPopup.hidePopup = function (ctxPopupId) {
    if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

    // destroy popup for now
    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.hide();
        ContextualPopup.ippu = null;
    }
}

// do ajax request of user info
ContextualPopup.getInfo = function (target) {
    var ctxPopupId = target.ctxPopupId;
    var username = target.username;
    var userid = target.userid;
    var up_url = target.up_url;

    if (!ctxPopupId)
    return;

    if (ContextualPopup.currentRequests[ctxPopupId + ""]) {
        return;
    }

    ContextualPopup.currentRequests[ctxPopupId] = 1;

    if (!username) username = "";
    if (!userid) userid = 0;
    if (!up_url) up_url = "";

    var params = HTTPReq.formEncoded ({
        "user": username,
            "userid": userid,
            "userpic_url": up_url,
            "mode": "getinfo"
    });

    // needed on journal subdomains
    var url = LiveJournal.getAjaxUrl("ctxpopup");
    var url = Site.currentJournal ? "/" + Site.currentJournal + "/__rpc_ctxpopup" : "/__rpc_ctxpopup";

    // got data callback
    var gotInfo = function (data) {
        if (ContextualPopup && ContextualPopup.hourglass) ContextualPopup.hideHourglass();

        ContextualPopup.cachedResults[ctxPopupId] = data;

        if (data.error) {
            if (data.noshow) return;

            ContextualPopup.showNote(data.error, ctxPopupId);
            return;
        }

        if (data.note)
        ContextualPopup.showNote(data.note, data.ctxPopupId);

        ContextualPopup.currentRequests[ctxPopupId] = null;

        ContextualPopup.renderPopup(ctxPopupId);

        // expire cache after 5 minutes
        setTimeout(function () {
            ContextualPopup.cachedResults[ctxPopupId] = null;
        }, 60 * 1000);
    };

    HTTPReq.getJSON({
        "url": url,
            "method" : "GET",
            "data": params,
            "onData": gotInfo,
            "onError": ContextualPopup.gotError
            });
}

ContextualPopup.hideHourglass = function () {
    if (ContextualPopup.hourglass) {
        ContextualPopup.hourglass.hide();
        ContextualPopup.hourglass = null;
    }
}

ContextualPopup.gotError = function (err) {
    if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

    if (ContextualPopup.debug)
        ContextualPopup.showNote("Error: " + err);
}

// when page loads, set up contextual popups
LiveJournal.register_hook("page_load", ContextualPopup.setup);
