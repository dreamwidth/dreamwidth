(function($) {
$.fn.commentmanagesetup = function() {
    if ( $.isEmptyObject(window.LJ_cmtinfo) ) return;
    this.each(function() {
        $('a', this)
            .filter("[href^='"+Site.siteroot+"/talkscreen']")
                .moderate({
                    journal: LJ_cmtinfo.journal,
                    form_auth: LJ_cmtinfo.form_auth,
                    is_inbox: LJ_cmtinfo.is_inbox
                })
                .end()
            .filter("[href^='"+Site.siteroot+"/delcomment']")
                .delcomment({
                    journal: LJ_cmtinfo.journal,
                    form_auth: LJ_cmtinfo.form_auth,
                    cmtinfo: LJ_cmtinfo,
                    is_inbox: LJ_cmtinfo.is_inbox
                })
    });
};

$.widget("dw.moderate", {
    options: {
        journal: undefined,
        form_auth: undefined,
        is_inbox: undefined,

        endpoint: "talkscreen"
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
        this.element.ajaxtip().ajaxtip( "error", "Error moderating comment #" + ditemid + ". " + reason);
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
            if ( self.linkdata.journal != self.options.journal && !self.options.is_inbox) {
                self._abort( "Journal in link does not match expected journal.");
                return;
            }
            var tomod = $("#cmt" + self.linkdata.id);
            if( tomod.length == 0 ) {
                self._abort("Cannot moderate comment which is not visible on this page.");
                return;
            }

            var endpoint = self.options.endpoint +
                "?jsmode=1&json=1&mode=" + self.linkdata.action;

            self.element
                .ajaxtip() // init
                .ajaxtip( "load", {
                    endpoint: endpoint,

                    ajax: {
                        type: "POST",

                        context: self,

                        data: {
                            talkid  : self.linkdata.id,
                            journal : self.options.journal,

                            confirm : "Y",
                            lj_form_auth: self.options.form_auth
                        },

                        success: function( data, status, jqxhr ) {
                            if ( data.error ) {
                                this.element.ajaxtip( "error", "Error while trying to " + this.linkdata.action + ": " + data.error );
                            } else {
                                this.element.ajaxtip( "success", data.msg );
                                this._updateLink(data);
                            }
                            self._trigger( "complete" );
                        }
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
        is_inbox: undefined,

        endpoint: "delcomment"
    },

    _abort: function(reason, ditemid) {
        ditemid = ditemid || this.linkdata.id;
        this.element.ajaxtip() // init
            .ajaxtip( "error", "Error deleting comment #" + ditemid + ". " + reason );
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

            var endpoint = self.options.endpoint +
                "?"+$.param({ mode: "js", json: 1, journal: self.options.journal, id: self.linkdata.id});

            var postdata = { confirm: 1 };
            if($("#popdel"+self.linkdata.id+"ban").is(":checked")) postdata["ban"] = 1;
            if($("#popdel"+self.linkdata.id+"spam").is(":checked")) postdata["spam"] = 1;
            if($("#popdel"+self.linkdata.id+"thread").is(":checked")) postdata["delthread"] = 1;
            if(self.options.form_auth) postdata["lj_form_auth"] = self.options.form_auth;

            self.element.ajaxtip()
                .ajaxtip( "load", {
                    endpoint: endpoint,
                    ajax: {
                        type: "POST",
                        context: self,

                        data: postdata,

                        success: function( data, status, jqxhr ) {
                            if ( data.error ) {
                                this.element.ajaxtip( "error", "Error while trying to delete comment: " + data.error );
                            } else {
                                this.element.ajaxtip( "success", data.msg );
                                removecomment(this.linkdata.id, postdata["delthread"]);
                            }
                            self._trigger( "complete" );
                        }
                    }
                });
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
            if ( self.linkdata.journal != self.options.journal && !self.options.is_inbox ) {
                self._abort( "Journal in link does not match expected journal.");
                return;
            }

            if ( e.shiftKey ) {
                deletecomment();
                return;
            }


            var $deleteDialog = function() {
                var canAdmin = cmtinfo["canAdmin"];
                var canSpam = cmtinfo["canSpam"];

                var _checkbox = function(action, label) {
                    var prefix = "popdel"+self.linkdata.id;
                    return "<li><input type='checkbox' value='"+action+"' id='"+prefix+action+"'>" +
                        "<label for='"+prefix+action+"'>"+label+"</label></li>";
                };

                var form = $("<form></form>");
                var checkboxes = [];

                if(remote !== "" && cmtdata.u !== "" && cmtdata.u !== remote && canAdmin) {
                    checkboxes.push(_checkbox( "ban", "Ban <strong>"+cmtdata.u+"</strong> from commenting" ));
                }

                if(remote !== "" && cmtdata.u !== remote && canSpam) {
                    checkboxes.push(_checkbox( "spam", "Mark this comment as spam" ));
                }

                if(cmtdata.rc && cmtdata.rc.length && canAdmin){
                    checkboxes.push(_checkbox( "thread", "Delete thread (all subcomments)" ));
                }

                $("<ul>").append(checkboxes.join("")).appendTo(form);
                $("<p class='detail'>shift-click to delete without options</p>").appendTo(form);

                return form;
            }();

            $deleteDialog.dialog({
                title: "Delete Comment",
                position: {
                    my: "center bottom",
                    at: "right top",
                    of: this,
                    collision: "fit fit"
                },
                buttons: {
                    "Delete": function() {
                        $(this).dialog( "close" );
                        deletecomment();
                    }
                },
                dialogClass: "popdel",
                maxWidth: "80%",
                width: 500
            });
        });
    }
});

})(jQuery);

jQuery(function($) {
    $(document).commentmanagesetup();
    $(document.body).delegate("*","updatedcontent.comment", function(e) {
        e.stopPropagation();
        $(this).commentmanagesetup();
    });

});
