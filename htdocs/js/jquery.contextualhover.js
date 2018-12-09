(function($, Site){
var document = window.document;

$.fn.contextualhoversetup = function() {
    if (!Site || !Site.ctx_popup) return;

    this.each(function() {
        if (Site.ctx_popup_userhead)
            _initUserhead(this);

        if (Site.ctx_popup_icons)
            _initIcons(this);
    });
};

function _initUserhead(context) {
    $("span.ljuser",context).each(function() {
        var $usertag = $(this);

        $("img", $usertag).each(function() {
            // if the parent (a tag with link to userinfo) has userid in its URL, then
            // this is an openid user icon and we should use the userid
            var $head = $(this);
            var href = $head.parent("a").attr("href");
            var data = {};
            var userid;
            if (href && (userid = href.match(/\?userid=(\d+)/i)))
                data.userid = userid[1];
            else
                data.username = $usertag.attr("lj:user");
            if ( !data.username && !data.userid ) return;

            data.type = "user";
            $head.contextualhover( data );
        });
    });
}

function _initIcons(context) {
    var old_icon_url = 'www\\.dreamwidth\\.org/userpic';
    var url_prefix = "(^" + Site.iconprefix + "|" + old_icon_url + ")";
    var re = new RegExp( url_prefix + "/\\d+\/\\d+$" );
    $("img[src^='"+Site.iconprefix+"'],img[src*='"+old_icon_url+"']",context).each(function() {
        var $icon = $(this);
        if (!$icon.data("no-ctx") && this.src.match(re)) {
            $icon.contextualhover({ "icon_url": this.src, type: "icon" });
        }
    });
}

})(jQuery, Site);

/* The contextual hover menu

    appears:
        - when you hover over the trigger a short period of time
        - NOT if you merely pass the mouse over the trigger

    lingers:
        - as long as the mouse is over the trigger
        - if you move the mouse from the trigger to the contextual popup
        - as long as the mouse is over the tooltip
        - NOT if you move the mouse away from the trigger before the popup is fully visible
        - NOT if you move the mouse away from the trigger before the ajax request is done

    disappears:
        - when you move the mouse over then out of the contextual popup
        - a short time after you move the mouse out of the trigger
            (only if you don't then move it to the popup)
 */

$.widget("dw.contextualhover", {
options: {
    disableAJAX: false,

    username: undefined,
    userid: undefined,
    icon_url: undefined,
    type: undefined // icon or user(head)
},
_create: function() {
    var self = this;
    var opts = self.options;

    if ( opts.type == "icon" ) {
        var parent = self.element.parent("a");
        if ( parent.length > 0 )
            self.element = parent;
    }
    var trigger = self.element;
    trigger.addClass("ContextualPopup-trigger");

    trigger.hoverIntent( {
        // how long before the popup fades out automatically once you've moved away
        timeout: 1500,

        over: function() {
            if ( self.cachedResults ) {
                self._renderPopup();
                return;
            }

            trigger.ajaxtip({
                tooltipClass: "ContextualPopup",
                loadingContent: "<img src='" + $.throbber.src + "' alt='Loading' />",

                // called after the popup is opened
                open: function(event, ui) {
                    var ns = event.handleObj.namespace;
                    var $trigger = $(this);
                    var $tooltip = ui.tooltip;
                    $tooltip.promise().done(function() {
                        // turn off the mouseleave/focusout events which close the popup immediately
                        // but only once fade in is done and popup is fully visible
                        // this is both a technical limitation
                        // (the callback fires before the events are registered in tooltip)
                        // and desired behavior
                        // (if the tooltip isn't fully visible yet, but they've moved away, assume they don't want it)
                        $trigger.off( "mouseleave." + ns + " focusout." + ns );
                    });

                    // the popup will also fade away after a short delay
                    // once you've moved your mouse away from the trigger
                    // this is to prevent the annoying behavior of the popup never going away
                    // HOWEVER we want to ignore the timeout if we've moused over the popup at any point
                    // so record if this has happened
                    $tooltip.one( "mouseover." +ns, function() {
                        // event from $.fn.hoverIntent
                        $trigger.data( "popup-persist", true );
                    } )

                    // attach listeners to links for dynamic actions
                    .on( "click", "a[data-dw-ctx-action]", function(e){
                        e.stopPropagation();
                        e.preventDefault();

                        self._changeRelation( $(this) );
                    });
                },
                // called after the popup has closed
                close: function(event, ui) {
                    // cleanup
                    ui.tooltip.off( "mouseover." + event.handleObj.namespace );
                }
            }).ajaxtip( "load", {

                endpoint: "ctxpopup",

                ajax: {
                    context: self,

                    data: {
                        "user": opts.username || "",
                        "userid": opts.userid || 0,
                        "userpic_url": opts.icon_url || "",
                        "mode": "getinfo"
                    },

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            if ( data.noshow ) {
                                trigger.ajaxtip( "close" );
                            } else {
                                trigger.ajaxtip( "error", data.error );
                            }
                        } else {
                            this.cachedResults = data;
                            this._renderPopup();

                            // expire cache after 5 minutes
                            setTimeout(function() {
                                self.cachedResults = null;
                            }, 60 * 5 * 1000);

                        }
                    }
                }
            });
        },
        out: function(e) {
            var persist = trigger.data("popup-persist");
            if ( ! persist ) {
                trigger.ajaxtip( "abort" );
                trigger.ajaxtip( "close" );
            }
            trigger.removeData("popup-persist");
        }
    } );
},

_addRelationStatus: function( string ) {
    this._rel_html.push( "<div>" + string + "</div>");
},

_addAction: function( url, text, action ) {
    action = !! action ? ' data-dw-ctx-action="' + action + '"' : "";
    this._actions_html.push( '<li><a href="' + url+ '"' + action + '>' + text + '</a></li>' );
},
_addText: function( text ) {
    this._actions_html.push( '<div>' + text + '</div>' );
},

_renderPopup: function() {
    var self = this;
    var $trigger = this.element;
    var opts = self.options;
    var data = self.cachedResults;
    this._actions_html = [];
    this._rel_html = [];

    if ( data && ( !data.username || !data.success || data.noshow ) ) {
        return undefined;
    }

    var userpic_html = "";

    if ( data.url_userpic ) {
        userpic_html = '<div class="Userpic">' +
                        '<a href="' + data.url_allpics + '">'  +
                            '<img src="' + data.url_userpic + '"' +
                                ' width="' + data.userpic_w + '"' +
                                ' height="' + data.userpic_h + '"' +
                                ' />' +
                        '</a>' +
                        '</div>';
    }

    var username = data.display_username;
    var rel_strings = {
        member: "You are a member of " + username,
        watching: "You have subscribed to " + username,
        watched_by: username + " has subscribed to you",
        mutual_watch: username + " and you have mutual subscriptions",
        trusting: "You have granted access to " + username,
        trusted_by: username + " has granted access to you",
        mutual_trust: username + " and you have mutual access",
        self: "This is you"
    };

    if ( data.is_comm ) {
        if (data.is_member) this._addRelationStatus(rel_strings.member);
        if (data.is_watching) this._addRelationStatus(rel_strings.watching);

    } else if (data.is_syndicated ) {
        this._addRelationStatus( data.is_watching ? rel_strings.watching : username );
    } else if (data.is_requester) {
        this._addRelationStatus( rel_strings.self );
    } else {
        if ( data.is_trusting && data.is_trusted_by )
            this._addRelationStatus( rel_strings.mutual_trust );
        else if ( data.is_trusting )
            this._addRelationStatus( rel_strings.trusting );
        else if ( data.is_trusted_by )
            this._addRelationStatus( rel_strings.trusted_by );

        if ( data.is_watching && data.is_watched_by )
            this._addRelationStatus( rel_strings.mutual_watch );
        else if ( data.is_watching )
            this._addRelationStatus( rel_strings.watching );
        else if ( data.is_watched_by )
            this._addRelationStatus( rel_strings.watched_by );
    }

    if ( ! this._rel_html.length )
        this._addRelationStatus( username );

    if ( data.is_person || data.is_comm || data.is_syndicated ) {
        var journal_text = "";
        if (data.is_person)
            journal_text ="View journal";
        else if ( data.is_comm )
            journal_text = "View community";
        else if ( data.is_syndicated )
            journal_text = "View feed";

        this._addAction( data.url_journal, journal_text );
        this._addAction( data.url_profile, "View profile" );
    }

    if ( data.is_logged_in && ( data.is_person || data.is_identity ) && data.can_message ) {
        this._addAction( data.url_message, "Send message" );
    }

    if ( data.is_logged_in && data.is_comm ) {
        if ( ! data.is_closed_membership || data.is_member ) {
            if ( data.is_member )
                this._addAction( data.url_leavecomm, "Leave", "leave" );
            else if ( data.is_invited )
                this._addAction( data.url_acceptinvite, "Accept invitation", "accept");
            else
                this._addAction( data.url_joincomm, "Join community", "join" );
        } else {
            this._addRelationStatus( "Community closed" );
        }
    }

    if ( ( data.is_person || data.is_comm ) && ! data.is_requester && data.can_receive_vgifts ) {
        this._addAction( data.url_vgift, "Send virtual gift" );
    }

    if ( data.is_logged_in && ! data.is_requester ) {
        if ( ! data.is_trusting ) {
            if ( data.is_person || data.other_is_identity ) {
                this._addAction( data.url_addtrust, "Grant access", "addTrust" );
            }
        } else {
            if ( data.is_person || data.other_is_identity ) {
                this._addAction( data.url_addtrust, "Remove access", "removeTrust" );
            }
        }

        if ( !data.is_watching && !data.other_is_identity ) {
            this._addAction( data.url_addwatch, "Subscribe", "addWatch" );
        } else if ( data.is_watching ) {
            this._addAction( data.url_addwatch, "Remove subscription", "removeWatch" );
        }
    }

    if ( data.is_logged_in && ! data.is_requester && ! data.is_syndicated && ! data.is_comm ) {
        if ( data.is_banned ) {
            this._addAction( Site.siteroot + "/manage/banusers",
                "Unban user", "setUnban" );
        } else {
            this._addAction( Site.siteroot + "/manage/banusers",
                "Ban user", "setBan" );
            var $banlink = $("<a></a>", { href: Site.siteroot + "/manage/banusers" });
        }
    }

    var content = '<div class="Content">' +
                    '<div class="Relation">' + this._rel_html.join( "" ) + '</div>' +
                    '<div class="Actions"><ul>' + this._actions_html.join("") + '</ul></div>' +
                  '</div>';

    this.element
        .ajaxtip( "option", "content", userpic_html + content )
        .ajaxtip( "open" );
},

_changeRelation: function($link) {

    var self = this;
    var info = self.cachedResults;
    if ( !info ) return;

    var action = $link.data( "dw-ctx-action" );

    // stop the popup from wiggling around when a status is removed
    var $popup = $link.closest(".ContextualPopup");
    var $r = $popup.find(".Relation");
    var relheight = $r.height();
    var oldheight = $popup.data( "relheight" );
    if ( ! oldheight ) oldheight = 0;
    if ( relheight > oldheight ) $popup.data("relheight", relheight);

    $link.ajaxtip() // init
    .ajaxtip( "load", {
        endpoint: "changerelation",

        ajax: {
            type: "POST",

            context: self,

            data: {
                target: info.username,
                action: action,
                auth_token: info[action+"_authtoken"]
            },

            beforeSend: function ( jqxhr, data ) {
                if ( action == "setBan" || action == "setUnban" ) {
                    var username = info.display_name;
                    var message = action == "setUnban" ? "Are you sure you wish to unban " + username + "?"
                                                       : "Are you sure you wish to ban " + username + "?";
                    if ( confirm( message ) ) {
                        return action;
                    } else { return false };
                  };
            },

            success: function( data, status, jqxhr ) {
                if ( data.error ) {
                    $link.ajaxtip( "error", data.error );
                } else if ( ! data.success ) {
                    $link.ajaxtip( "error", "Did not change relation successfully" );
                    self._renderPopup();
                } else {
                    if ( self.cachedResults ) {
                        var updatedProps = [ "is_trusting", "is_watching", "is_member", "is_banned" ];
                        $.each(updatedProps,function(){
                            self.cachedResults[this] = data[this];
                        });
                    }
                    self._renderPopup();
                    $popup.find(".Relation").css( "min-height", $popup.data( "relheight" ) );
                }
            }
        }
    });
}

});

jQuery(document).ready(function($){
    $(document).contextualhoversetup();
    $(document.body).delegate( "*", "updatedcontent.entry.poll.comment", function(e) {
        e.stopPropagation();
        $(this).contextualhoversetup();
    });
});
