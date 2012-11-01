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
    var re = new RegExp( "^" + Site.iconprefix + "/\\d+\/\\d+$" );
    $("img[src^='"+Site.iconprefix+"']",context).each(function() {
        var $icon = $(this);
        if (this.src.match(re)) {
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
    trigger.addClass("ContextualPopup");

    trigger.hoverIntent( {
        // how long before the popup fades out automatically once you've moved away
        timeout: 1500,

        over: function() {
            // if ( self.cachedResults ) {
            //     self._renderPopup();
            //     self._trigger("complete");
            //     return;
            // }

            trigger.ajaxtip({
                content: function ( callback ) {
                    callback("Hover Menu");
                },
                // called after the popup is opened
                open: function(event, ui) {
                    var ns = event.handleObj.namespace;
                    var $trigger = $(this);
                    ui.tooltip.promise().done(function() {
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
                    ui.tooltip.one( "mouseover." +ns, function() {
                        // event from $.fn.hoverIntent
                        $trigger.data( "popup-persist", true );
                    } );
                },
                // called after the popup has closed
                close: function(event, ui) {
                    // cleanup
                    ui.tooltip.off( "mouseover." + event.handleObj.namespace );
                }
            }).ajaxtip( "open" );

                // .ajaxtip( "load", {
                //     endpoint: "ctxpopup",

                //     ajax: {
                //         context: self,

                //         data: {
                //             "user": opts.username || "",
                //             "userid": opts.userid || 0,
                //             "userpic_url": opts.icon_url || "",
                //             "mode": "getinfo"
                //         },

                //         success: function( data, status, jqxhr ) {
                //             if ( data.error ) {
                //                 if ( data.noshow )
                //                     trigger.ajaxtip( "close" );
                //                 else
                //                     trigger.ajaxtip( "error", data.error )
                //             } else {
                //                 this.cachedResults = data;
                //                 this._renderPopup();

                //                 // expire cache after 5 minutes
                //                 setTimeout(function() {
                //                     self.cachedResults = null;
                //                 }, 60 * 5 * 1000);
                //             }
                //         }
                //     }
                // });
        },
        out: function(e) {
            var persist = trigger.data("popup-persist");
            if ( ! persist ) {
                trigger.ajaxtip( "close" );
            }
            trigger.removeData("popup-persist");
        }
    } );
},

_renderPopup: function() {
    var self = this;
    var $trigger = this.element;
    var opts = self.options;
    var data = self.cachedResults;

    if ( data && ( !data.username || !data.success || data.noshow ) ) {
        return undefined;
    }

    var userpic_html = "";
    var content_html = [];

    if ( data.url_userpic ) {
        userpic_html = '<div class="Userpic">' +
                        '<a href="' + data.url_allpics + '">'  +
                            '<img src="' + data.url_userpic + '"' +
                                ' width="' + data.usepric_w + '"' +
                                ' height="' + data.userpic_h + '"' +
                                ' />' +
                        '</a>' +
                        '</div>';
    }

    // var username = data.display_username;
    // var $relation = $("<div class='Relation'></div>");
    // var strings = {
    //     member: "You are a member of " + username,
    //     watching: "You have subscribed to " + username,
    //     watched_by: username + " has subscribed to you",
    //     mutual_watch: username + " and you have mutual subscriptions",
    //     trusting: "You have granted access to " + username,
    //     trusted_by: username + " has granted access to you",
    //     mutual_trust: username + " and you have mutual access",
    //     self: "This is you"
    // };
    // if ( data.is_comm ) {
    //     var rels = [];
    //     if (data.is_member) rels.push(strings.member);
    //     if (data.is_watching) rels.push(strings.watching);

    //     $relation.html(rels.length > 0 ? rels.join("<br />") : username);
    // } else if (data.is_syndicated ) {
    //     $relation.html(data.is_watching ? strings.watching : username);
    // } else if (data.is_requester) {
    //     $relation.html( strings.self );
    // } else {
    //     var rels = [];
    //     if ( data.is_trusting && data.is_trusted_by )
    //         rels.push(strings.mutual_trust);
    //     else if ( data.is_trusting )
    //         rels.push(strings.trusting);
    //     else if ( data.is_trusted_by )
    //         rels.push(strings.trusted_by);

    //     if ( data.is_watching && data.is_watched_by )
    //         rels.push(strings.mutual_watch);
    //     else if ( data.is_watching )
    //         rels.push(strings.watching);
    //     else if ( data.is_watched_by )
    //         rels.push(strings.watched_by);

    //     $relation.html(rels.length > 0 ? rels.join("<br />") : username);
    // }
    // $content.append($relation);

    // if ( data.is_logged_in && data.is_comm ) {
    //     var $membership = $("<span></span>");
    //     if ( ! data.is_closed_membership || data.is_member ) {
    //         var $membershiplink = $("<a></a>");
    //         var membership_action = data.is_member ? "leave" : "join";

    //         if ( data.is_member )
    //             $membershiplink.attr("href" , data.url_leavecomm ).html("Leave");
    //         else
    //             $membershiplink.attr("href", data.url_joincomm ).html("Join community");

    //         if ( ! opts.disableAJAX ) {
    //             $membershiplink.click(function(e) {
    //                 e.stopPropagation(); e.preventDefault();
    //                 self._changeRelation(data, membership_action, this, e);
    //             });
    //         }

    //         $membership.append($membershiplink);
    //     } else {
    //         $membership.html("Community closed");
    //     }
    //     $content.append($membership, "<br />"   );
    // }

    // var links = [];
    // if ( data.is_logged_in && ( data.is_person || data.is_identity ) && data.can_message ) {
    //     var $sendmessage = $("<a></a>", { href: data.url_message }).html("Send message");
    //     links.push($("<span></span>").append($sendmessage));
    // }

    // // relationships
    // if ( data.is_logged_in && ! data.is_requester ) {
    //     if ( ! data.is_trusting ) {
    //         if ( data.is_person || data.other_is_identity ) {
    //             var $addtrust = $("<a></a>", { href: data.url_addtrust } ).html("Grant access");
    //             links.push($("<span class='AddTrust'></span>").append($addtrust));

    //             if( ! opts.disableAJAX ) {
    //                 $addtrust.click(function(e) {
    //                     e.stopPropagation(); e.preventDefault();
    //                     self._changeRelation(data, "addTrust", this, e);
    //                 });
    //             }
    //         }
    //     } else {
    //         if ( data.is_person || data.other_is_identity ) {
    //             var $removetrust = $("<a></a>", { href: data.url_addtrust } ).html("Remove access");
    //             links.push($("<span class='RemoveTrust'></span>").append($removetrust));

    //             if( ! opts.disableAJAX ) {
    //                 $removetrust.click(function(e) {
    //                     e.stopPropagation(); e.preventDefault();
    //                     self._changeRelation(data, "removeTrust", this, e);
    //                 });
    //             }
    //         }
    //     }

    //     if ( !data.is_watching && !data.other_is_identity ) {
    //         var $addwatch = $("<a></a>", { href: data.url_addwatch } ).html("Subscribe");
    //         links.push($("<span class='AddWatch'></span>").append($addwatch));

    //         if( ! opts.disableAJAX ) {
    //             $addwatch.click(function(e) {
    //                 e.stopPropagation(); e.preventDefault();
    //                 self._changeRelation(data, "addWatch", this, e);
    //             });
    //         }
    //     } else if ( data.is_watching ) {
    //         var $removewatch = $("<a></a>", { href: data.url_addwatch } ).html("Remove subscription");
    //         links.push($("<span class='RemoveWatch'></span>").append($removewatch));

    //         if( ! opts.disableAJAX ) {
    //             $removewatch.click(function(e) {
    //                 e.stopPropagation(); e.preventDefault();
    //                 self._changeRelation(data, "removeWatch", this, e);
    //             });
    //         }
    //     }
    //     $relation.addClass("RelationshipStatus");
    // }

    // // FIXME: double-check this when vgifts come out
    // if ( ( data.is_person || data.is_comm ) && ! data.is_requester && data.can_receive_vgifts ) {
    //     var $sendvgift = $("<a></a>", { href: Site.siteroot + "/shop/vgift?to=" + data.username })
    //         .html("Send a virtual gift");
    //     links.push($("<span></span").append($sendvgift));
    // }

    // if ( data.is_logged_in && ! data.is_requester && ! data.is_syndicated ) {
    //     if ( data.is_banned ) {
    //         var $unbanlink = $("<a></a>", { href: Site.siteroot + "/manage/banusers" });
    //         $unbanlink.html( data.is_comm ? "Unban community" : "Unban user" );
    //         if( ! opts.disableAJAX ) {
    //             $unbanlink.click(function(e) {
    //                 e.stopPropagation(); e.preventDefault();
    //                 self._changeRelation(data, "setUnban", this, e);
    //             });
    //         }
    //         links.push($("<span class='SetUnban'></span>").append($unbanlink));

    //     } else {
    //         var $banlink = $("<a></a>", { href: Site.siteroot + "/manage/banusers" });
    //         $banlink.html( data.is_comm ? "Ban community" : "Ban user" );
    //         if( ! opts.disableAJAX ) {
    //             $banlink.click(function(e) {
    //                 e.stopPropagation(); e.preventDefault();
    //                 self._changeRelation(data, "setBan", this, e);
    //             });
    //         }
    //         links.push($("<span class='SetBan'></span>").append($banlink));
    //     }
    // }

    // var linkslength = links.length;
    // $.each(links,function(index) {
    //     $content.append(this);
    //     $content.append("<br>");
    // });

    // $("<span>View: </span>").appendTo($content);
    // if ( data.is_person || data.is_comm || data.is_syndicated ) {
    //     var $journallink = $("<a></a>", {href: data.url_journal});
    //     if (data.is_person)
    //         $journallink.html("Journal");
    //     else if ( data.is_comm )
    //         $journallink.html("Community");
    //     else if ( data.is_syndicated )
    //         $journallink.html("Feed");

    //     $content.append(
    //             $journallink,
    //             $("<span> | </span>"),
    //             $("<a></a>", { href: data.url_profile} ).html("Profile")
    //     );
    // }

    // $content.append($("<div class='ljclear'>&nbsp;</div>"));

    var content = '<div class="Content"></div>';
    var inner = '<div class="Inner">' + userpic_html + content + '</div>';

    this.element
        .ajaxtip( "open" )
        .ajaxtip( "option", "content", inner );
    // this.element.ajaxtip("show")
    // this.element
    //     .ajaxtip("widget")
    //         .addClass("ContextualPopup")
    //         .empty().append($inner);
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
