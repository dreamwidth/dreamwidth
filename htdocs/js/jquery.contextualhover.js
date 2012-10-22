(function($, Site){

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
    var re = new RegExp( "^" + Site.iconprefix + "/\\d+\/\\d+$" );
    $("img[src^='"+Site.iconprefix+"']",context).each(function() {
        var $icon = $(this);
        if (this.src.match(re)) {
            $icon.contextualhover({ "icon_url": this.src, type: "icon" });
        }
    });
}

})(jQuery, Site);

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
        var parent = self.element.parent("a")
        if ( parent.length > 0 )
            self.element = parent;
    }

    var trigger = self.element;
    trigger.addClass("ContextualPopup");

    var action = $.fn.hoverIntent ? "hoverIntent" : "hover";
    trigger[action](
    function() {
        if ( self.cachedResults ) {
            self._renderPopup();
            self._trigger("complete");
            return;
        }

        trigger.ajaxtip({ namespace: "contextualpopup", persist: true })
            .ajaxtip( "load", {
                endpoint: "ctxpopup",
                formmethod: "GET",
                context: self,
                data: {
                    "user": opts.username || "",
                    "userid": opts.userid || 0,
                    "userpic_url": opts.icon_url || "",
                    "mode": "getinfo"
                },
                success: function( data, status, jqxhr ) {
                    if ( data.error ) {
                        if ( data.noshow )
                            trigger.ajaxtip( "cancel" );
                        else
                            trigger.ajaxtip( "error", data.error )
                    } else {
                        self.cachedResults = data;
                        self._renderPopup();

                        // expire cache after 5 minutes
                        setTimeout(function() {
                            self.cachedResults = null;
                        }, 60 * 5 * 1000);
                    }
                    self._trigger("complete");
                }
            });
    },
    function() {
    }
    )
},

_renderPopup: function() {
    var self = this;
    var opts = self.options;
    var data = self.cachedResults;

    if ( data && ( !data.username || !data.success || data.noshow ) ) {
        this.element.ajaxtip("cancel");
    }

    var $inner = $("<div class='Inner'></div>");
    var $content = $("<div class='Content'></div>");

    if ( data.url_userpic ) {
        var $link = $("<a></a>", { href: data.url_allpics });
        var $icon = $("<img>", { src: data.url_userpic }).attr({width: data.userpic_w, height: data.userpic_h});
        var $container = $("<div class='Userpic'></div>").append($link.append($icon));

        $inner.append($container);
    }

    $inner.append($content);

    var username = data.display_username;
    var $relation = $("<div class='Relation'></div>");
    var strings = {
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
        var rels = [];
        if (data.is_member) rels.push(strings.member);
        if (data.is_watching) rels.push(strings.watching);

        $relation.html(rels.length > 0 ? rels.join("<br />") : username);
    } else if (data.is_syndicated ) {
        $relation.html(data.is_watching ? strings.watching : username);
    } else if (data.is_requester) {
        $relation.html( strings.self );
    } else {
        var rels = [];
        if ( data.is_trusting && data.is_trusted_by )
            rels.push(strings.mutual_trust);
        else if ( data.is_trusting )
            rels.push(strings.trusting);
        else if ( data.is_trusted_by )
            rels.push(strings.trusted_by);

        if ( data.is_watching && data.is_watched_by )
            rels.push(strings.mutual_watch);
        else if ( data.is_watching )
            rels.push(strings.watching);
        else if ( data.is_watched_by )
            rels.push(strings.watched_by);

        $relation.html(rels.length > 0 ? rels.join("<br />") : username);
    }
    $content.append($relation);

    if ( data.is_logged_in && data.is_comm ) {
        var $membership = $("<span></span>");
        if ( ! data.is_closed_membership || data.is_member ) {
            var $membershiplink = $("<a></a>");
            var membership_action = data.is_member ? "leave" : "join";

            if ( data.is_member )
                $membershiplink.attr("href" , data.url_leavecomm ).html("Leave");
            else
                $membershiplink.attr("href", data.url_joincomm ).html("Join community");

            if ( ! opts.disableAJAX ) {
                $membershiplink.click(function(e) {
                    e.stopPropagation(); e.preventDefault();
                    self._changeRelation(data, membership_action, this, e);
                });
            }

            $membership.append($membershiplink);
        } else {
            $membership.html("Community closed");
        }
        $content.append($membership, "<br />"   );
    }

    var links = [];
    if ( data.is_logged_in && ( data.is_person || data.is_identity ) && data.can_message ) {
        var $sendmessage = $("<a></a>", { href: data.url_message }).html("Send message");
        links.push($("<span></span>").append($sendmessage));
    }

    // relationships
    if ( data.is_logged_in && ! data.is_requester ) {
        if ( ! data.is_trusting ) {
            if ( data.is_person || data.other_is_identity ) {
                var $addtrust = $("<a></a>", { href: data.url_addtrust } ).html("Grant access");
                links.push($("<span class='AddTrust'></span>").append($addtrust));

                if( ! opts.disableAJAX ) {
                    $addtrust.click(function(e) {
                        e.stopPropagation(); e.preventDefault();
                        self._changeRelation(data, "addTrust", this, e);
                    });
                }
            }
        } else {
            if ( data.is_person || data.other_is_identity ) {
                var $removetrust = $("<a></a>", { href: data.url_addtrust } ).html("Remove access");
                links.push($("<span class='RemoveTrust'></span>").append($removetrust));

                if( ! opts.disableAJAX ) {
                    $removetrust.click(function(e) {
                        e.stopPropagation(); e.preventDefault();
                        self._changeRelation(data, "removeTrust", this, e);
                    });
                }
            }
        }

        if ( !data.is_watching && !data.other_is_identity ) {
            var $addwatch = $("<a></a>", { href: data.url_addwatch } ).html("Subscribe");
            links.push($("<span class='AddWatch'></span>").append($addwatch));

            if( ! opts.disableAJAX ) {
                $addwatch.click(function(e) {
                    e.stopPropagation(); e.preventDefault();
                    self._changeRelation(data, "addWatch", this, e);
                });
            }
        } else if ( data.is_watching ) {
            var $removewatch = $("<a></a>", { href: data.url_addwatch } ).html("Remove subscription");
            links.push($("<span class='RemoveWatch'></span>").append($removewatch));

            if( ! opts.disableAJAX ) {
                $removewatch.click(function(e) {
                    e.stopPropagation(); e.preventDefault();
                    self._changeRelation(data, "removeWatch", this, e);
                });
            }
        }
        $relation.addClass("RelationshipStatus");
    }

    // FIXME: double-check this when vgifts come out
    if ( ( data.is_person || data.is_comm ) && ! data.is_requester && data.can_receive_vgifts ) {
        var $sendvgift = $("<a></a>", { href: Site.siteroot + "/shop/vgift?to=" + data.username })
            .html("Send a virtual gift");
        links.push($("<span></span").append($sendvgift));
    }

    if ( data.is_logged_in && ! data.is_requester && ! data.is_syndicated ) {
        if ( data.is_banned ) {
            var $unbanlink = $("<a></a>", { href: Site.siteroot + "/manage/banusers" });
            $unbanlink.html( data.is_comm ? "Unban community" : "Unban user" );
            if( ! opts.disableAJAX ) {
                $unbanlink.click(function(e) {
                    e.stopPropagation(); e.preventDefault();
                    self._changeRelation(data, "setUnban", this, e);
                });
            }
            links.push($("<span class='SetUnban'></span>").append($unbanlink));

        } else {
            var $banlink = $("<a></a>", { href: Site.siteroot + "/manage/banusers" });
            $banlink.html( data.is_comm ? "Ban community" : "Ban user" );
            if( ! opts.disableAJAX ) {
                $banlink.click(function(e) {
                    e.stopPropagation(); e.preventDefault();
                    self._changeRelation(data, "setBan", this, e);
                });
            }
            links.push($("<span class='SetBan'></span>").append($banlink));
        }
    }

    var linkslength = links.length;
    $.each(links,function(index) {
        $content.append(this);
        $content.append("<br>");
    });

    $("<span>View: </span>").appendTo($content);
    if ( data.is_person || data.is_comm || data.is_syndicated ) {
        var $journallink = $("<a></a>", {href: data.url_journal});
        if (data.is_person)
            $journallink.html("Journal");
        else if ( data.is_comm )
            $journallink.html("Community");
        else if ( data.is_syndicated )
            $journallink.html("Feed");

        $content.append(
                $journallink,
                $("<span> | </span>"),
                $("<a></a>", { href: data.url_profile} ).html("Profile")
        );
    }

    $content.append($("<div class='ljclear'>&nbsp;</div>"));

    this.element.ajaxtip("show")
    this.element
        .ajaxtip("widget")
            .removeClass("ajaxresult ajaxtooltip").addClass("ContextualPopup")
            .empty().append($inner);
},

_changeRelation: function(info, action, link, e) {
    if ( !info ) return;
    var self = this;
    var $link = $(link);

    $link.ajaxtip({namespace: "changerelation"}).ajaxtip("load", {
        endpoint: "changerelation",
        context: self,
        data: {
            target: info.username,
            action: action,
            auth_token: info[action+"_authtoken"]
        },
        success: function( data, status, jqxhr ) {
            if ( data.error ) {
                $link.ajaxtip( "error", data.error )
            } else if ( ! data.success ) {
                $link.ajaxtip( "error", "Did not change relation successfully" );
                self._renderPopup(data);
            } else {
                if ( self.cachedResults ) {
                    var updatedProps = [ "is_trusting", "is_watching", "is_member", "is_banned" ];
                    $.each(updatedProps,function(){
                        self.cachedResults[this]=data[this];
                    });
                }
                $link.ajaxtip( "cancel" );
                self._renderPopup();
            }
            self._trigger("complete");
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
