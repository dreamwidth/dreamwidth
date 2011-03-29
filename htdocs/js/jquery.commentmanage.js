(function($) {
$.extractParams = function(url) {
    if ( ! $.extractParams.cache )
        $.extractParams.cache = {};

    if ( url in $.extractParams.cache )
        return $.extractParams.cache[url];

    var search = url.indexOf( "?" );
    if ( search == -1 ) {
        $.extractParams.cache[url] = {};
        return $.extractParams.cache[url];
    }

    var params = decodeURI( url.substring( search + 1 ) );
    if ( ! params ) {
        $.extractParams.cache[url] = {};
        return $.extractParams.cache[url];
    }

    var paramsArray = params.split("&");
    var params = {};
    for( var i = 0; i < paramsArray.length; i++ ) {
        var p = paramsArray[i].split("=");
        var key = p[0];
        var value = p.length < 2 ? undefined : p[1];
        params[key] = value;
    }

    $.extractParams.cache[url] = params;
    return params;
};

$.widget("dw.moderate", {
    options: {
        journal: undefined,
        form_auth: undefined,

        endpoint: "__rpc_talkscreen",
    },
    _updateLink: function(newData) {
        this.element.attr("href", newData.newurl);

        var params = $.extractParams(newData.newurl);
        this.linkdata = {
            id: params.talkid,
            action: params.mode,
            journal: params.journal
        };

        var image = this.element.find('img[src="'+newData.oldimage+'"]');

        if ( image.length == 0 ) {
            this.element.text(newData.newalt);
        } else {
            image.attr({
                title: newData.newalt,
                alt: newData.newalt,
                src: newData.newimage
            });
        }
    },

    _abort: function(reason, ditemid) {
        ditemid = ditemid || this.linkdata.id;
        this.element.ajaxtip({namespace:"moderate"})
            .ajaxtip( "abort", "Error moderating comment #" + ditemid + ". " + reason);
    },

    _create: function() {
        var self = this;

        var params = $.extractParams(this.element.attr("href"));
        this.linkdata = {
            id: params.talkid || "",
            action: params.mode,
            journal: params.journal
        };

        this.element.click(function(e) {
            e.preventDefault();
            e.stopPropagation();

            if (!self.options.form_auth || ! self.options.journal
                || !self.linkdata.id || !self.linkdata.action || !self.linkdata.journal) {
                self._abort( "Not enough context available." );
                return;
            }
            if ( self.linkdata.journal != self.options.journal ) {
                self._abort( "Journal in link does not match expected journal.");
                return;
            }
            var tomod = $("#cmt" + self.linkdata.id);
            if( tomod.length == 0 ) {
                self._abort("Cannot moderate comment which is not visible on this page.");
                return;
            }

            var posturl = "/" + self.options.journal + "/" + self.options.endpoint
                        + "?jsmode=1&json=1&mode=" + self.linkdata.action;

            self.element
                .ajaxtip({
                    namespace: "moderate",
                })
                .ajaxtip("load", {
                    url: posturl,
                    data: {
                        talkid  : self.linkdata.id,
                        journal : self.options.journal,

                        confirm : "Y",
                        lj_form_auth: self.options.form_auth
                    },
                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            self.element.ajaxtip( "error", "Error while trying to " + self.linkdata.action + ": " + data.error )
                        } else {
                            self.element.ajaxtip("success",data.msg);
                            self._updateLink(data);
                        }
                        self._trigger( "complete" );
                    },
                    error: function( jqxhr, status, error ) {
                        self.element.ajaxtip( "error", "Error contacting server. " + error);
                        self._trigger( "complete" );
                    }
                });
        });
    }
});

$.widget("dw.delcomment", {
    options: {
        cmtinfo: undefined,
        journal: undefined,
        form_auth: undefined,

        endpoint: "__rpc_delcomment"
    },

    _abort: function(reason, ditemid) {
        ditemid = ditemid || this.linkdata.id;
        this.element.ajaxtip({namespace:"delcomment"})
            .ajaxtip( "abort", "Error deleting comment #" + ditemid + ". " + reason);
    },

    _create: function() {
        var self = this;

        var params = $.extractParams(this.element.attr("href"));
        this.linkdata = {
            journal: params.journal || "",
            id: params.id || ""
        };

        var cmtinfo = self.options.cmtinfo;
        var cmtdata = cmtinfo ? cmtinfo[this.linkdata.id] : undefined;
        var remote = cmtinfo ? cmtinfo["remote"] : undefined;

        function deletecomment() {
            var todel = self.linkdata.id ? $("#cmt" + self.linkdata.id) : [];
            if( todel.length == 0 ) {
                self._abort("Comment is not visible on this page.");
                return;
            }

            var posturl = "/" + self.options.journal + "/" + self.options.endpoint
                    +"?"+$.param({ mode: "js", json: 1, journal: self.options.journal, id: self.linkdata.id});

            var postdata = { confirm: 1 };
            if($("#popdel"+self.linkdata.id+"ban").is(":checked")) postdata["ban"] = 1;
            if($("#popdel"+self.linkdata.id+"spam").is(":checked")) postdata["spam"] = 1;
            if($("#popdel"+self.linkdata.id+"thread").is(":checked")) postdata["delthread"] = 1;
            if(self.options.form_auth) postdata["lj_form_auth"] = self.options.form_auth;

            self.element
                .ajaxtip("load", {
                    url: posturl,
                    data: postdata,
                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            self.element.ajaxtip( "error", "Error while trying to delete comment: " + data.error )
                        } else {
                            self.element.ajaxtip("success",data.msg);
                            removecomment(self.linkdata.id, postdata["delthread"]);
                        }
                        self._trigger( "complete" );
                    },
                    error: function( jqxhr, status, error ) {
                        self.element.ajaxtip( "error", "Error contacting server. " + error);
                        self._trigger( "complete" );
                    }
                })
        }

        function removecomment(ditemid,killchildren) {
            var todel = $("#cmt" + ditemid);
            if ( todel.length > 0 ) {
                todel.fadeOut(2500);

                if ( killchildren ) {
                    var com = cmtinfo[ditemid];
                    for ( var i = 0; i < com.rc.length; i++ ) {
                        removecomment(com.rc[i], true);
                    }
                }
            } else {
                self._abort( "Child comment is not available on this page", ditemid);
            }
        }

        this.element.click(function(e) {
            e.preventDefault();
            e.stopPropagation();

            if (!cmtinfo || !remote || !self.options.form_auth || !self.options.journal) {
                self._abort( "Not enough context available." );
                return;
            }
            if ( !cmtdata ) {
                self._abort( "Comment is not visible on this page." );
                return;
            }
            if ( self.linkdata.journal != self.options.journal ) {
                self._abort( "Journal in link does not match expected journal.");
                return;
            }

            if ( e.shiftKey ) {
                self.element.ajaxtip({ namespace: "delcomment" })
                deletecomment();
                return;
            }

            self.element
                .ajaxtip({
                    namespace: "delcomment",
                    content: function() {
                        var canAdmin = cmtinfo["canAdmin"];
                        var canSpam = cmtinfo["canSpam"];

                        var form = $("<form class='popup-form'><fieldset><legend>Delete comment?</legend></fieldset></form>");
                        var ul = $("<ul>").appendTo(form.find("fieldset"));

                        if(remote != "" && cmtdata.u != "" && cmtdata.u != remote && canAdmin) {
                            var id = "popdel"+self.linkdata.id+"ban";
                            ul.append($("<li>").append(
                                $("<input>", { type: "checkbox", value: "ban", id: id}),
                                $("<label>", { "for": id }).html("Ban <strong>"+cmtdata.u+"</strong> from commenting")
                            ));
                        }

                        if(remote != "" && cmtdata.u != remote && canSpam) {
                            var id = "popdel"+self.linkdata.id+"spam";
                            ul.append($("<li>").append(
                                $("<input>", { type: "checkbox", value: "spam", id: id}),
                                $("<label>", { "for": id }).text("Mark this comment as spam")
                            ));
                        }

                        if(cmtdata.rc && cmtdata.rc.length && canAdmin){
                            var id = "popdel"+self.linkdata.id+"thread";
                            ul.append($("<li>").append(
                                $("<input>", { type: "checkbox", value: "thread", id: id}),
                                $("<label>", { "for": id }).text("Delete thread (all subcomments)")
                            ));
                        }

                        ul.append($("<li>", { "class": "submit" }).append(
                            $("<input>", { type: "button", value: "Delete"})
                                .click(deletecomment),

                            $("<input>", { type: "button", value: "Cancel" })
                                .click(function(){self.element.ajaxtip("cancel")}),

                            $("<div class='note'>shift-click to delete without options</div>")
                        ));

                        return form;
                }
            });
        });
    }
});

})(jQuery);

jQuery(function($) {
    if ( ! $.isEmptyObject( window.LJ_cmtinfo ) ) {
        $('a')
            .filter("[href^='"+Site.siteroot+"/talkscreen']")
                .moderate({
                    journal: LJ_cmtinfo.journal,
                    form_auth: LJ_cmtinfo.form_auth
                })
                .end()
            .filter("[href^='"+Site.siteroot+"/delcomment']")
                .delcomment({
                    journal: LJ_cmtinfo.journal,
                    form_auth: LJ_cmtinfo.form_auth,
                    cmtinfo: LJ_cmtinfo
                })
    }
});
