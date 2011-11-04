(function($){

var skipChecks = 0;
var $accounts;

$.widget("dw.crosspostaccount", {
options: {
    mainCheckbox: undefined,
    locked: false,          // account is currently processing authentication
    failed: false,          // account has failed authentication
    strings: {
        passwordRequired: "Password required",
        authenticating: "Authenticating...",
        cancel: "Cancel"
    }
},

_create: function() {
    var self = this;
    var $checkbox = self.element;

    self.$container = $checkbox.siblings(".crosspost_password_container");
    if ( self.$container.length > 0 )
        self.needsPassword = true;
    else
        self.needsPassword = false;

    $checkbox.change(function() {
        var $this = $(this);
        self.$container
            .fadeToggle($this.is(":checked"));
    })

    self.$container.toggle($checkbox.is(":checked"));
},

_findPasswordElements: function() {
    if ( ! this.needsPassword || this.foundPasswordElements ) return;

    this.$chal = this.$container.find("input.crosspost_chal");
    this.$resp = this.$container.find("input.crosspost_resp");
    this.$status = this.$container.find(".crosspost_password_status");
    this.$password = this.$container.find(".crosspost_password");

    this.foundPasswordElements = true;
},

_error: function( errMsg ) {
    this.$container.addClass("error");
    return this._message(errMsg).wrapInner("<span class='error-msg'></span>");
},
_message: function ( msg ) {
    if ( msg == null || msg == "" )
        return this._clearMessage();
    return this.$status.html(msg).fadeIn();
},
_clearMessage: function() {
    this.$container.removeClass("error");
    return this.$status.fadeOut(null, function(){$(this).empty()});
},

needsChalResp: function() {
    return this.needsPassword && this.element.is(":checked");
},

doChallengeResponse: function() {
    var self = this;
    var $main = $(self.options.mainCheckbox);

    if ( ! self.needsPassword ) return;
    self._findPasswordElements();

    if ( ! self.options.locked && self.$chal.length > 0
            && self.element.add($main).is(":checked") )
    {
        self.options.locked = true;
        if ( self.$password.val() == null || self.$password.val() == "" ) {
            self._error(self.options.strings.passwordRequired);
            self.options.failed = true;
            self.options.locked = false;

            self._trigger("chalrespcomplete");
            return;
        }

        self._message(self.options.strings.authenticating + "<button type='button' class='cancelCrosspostAuth ui-state-default'>"+self.options.strings.cancel+"</button>")
            .find(".cancelCrosspostAuth").click(function() {
                self._clearMessage();
                self.cancel();
            });


        $.getJSON("/__rpc_extacct_auth", {"acctid": self.element.val()}, function(data) {
            if ( self.options.locked ) {
                if ( data.error ) {
                    self._error(data.error);
                    self.options.failed = true;
                    self.options.locked = false;

                    self._trigger("chalrespcomplete");
                    return;
                }

                self._clearMessage();
                if ( !data.success ) { self._trigger("chalrespcomplete"); return; }

                var pass = self.$password.val();
                var res = MD5(data.challenge + MD5(pass));
                self.$resp.val(res);
                self.$chal.val(data.challenge);

                self.options.failed = false;
                self.options.locked = false;
                self._trigger("chalrespcomplete");
            }
        });
    }
},

cancel: function() {
    this.options.failed = false;
    this.options.locked = false;

    this._trigger( "cancel" );
},

submit: function() {
    if (this.needsPassword)
        this.$password.val("");
}

});

$.widget("dw.crosspost", {
options: {
    strings: {
        crosspostDisabled: {
            community: "Community entries cannot be crossposted.",
            draft: "Draft entries cannot be crossposted."
        }
    }
},

_create: function() {
    function crosspostAccountUpdated() {
        var $crosspost_entry = $("#crosspost_entry");
        var allUnchecked = ! $accounts.is(":checked");
        if ( allUnchecked ) {
            $crosspost_entry.removeAttr("checked").attr("disabled","disabled");
        } else {
            $crosspost_entry.removeAttr("disabled").attr("checked","checked");
        }
    };

    $accounts = $("#crosspost_accounts input[name='crosspost']")
        .crosspostaccount({ mainCheckbox: "#crosspost_entry" })
        .change(crosspostAccountUpdated)
        .bind("crosspostaccountcancel", function() {
            $(this).closest("form").find("input[type='submit']")
                .removeAttr("disabled").removeClass("ui-state-disabled");
        })
        .bind("crosspostaccountchalrespcomplete", function () {
            // use an array intead of $.each so that we can return out of the function
            for ( var i = 0; i < $accounts.length;  i++ ) {
                if ( $accounts.eq(i).crosspostaccount( "option", "locked" ) ) return false;
            }

            var acctErr = false;
            $accounts.each(function(){
                if ($(this).crosspostaccount("option", "failed") ) {
                    acctErr = true;
                    return false; // this just breaks us out of the each
                }
            });

            var $form = $(this).closest("form");
            if ( acctErr ) {
                $accounts.crosspostaccount( "cancel" );
            } else {
                $accounts.crosspostaccount( "submit" );
                $form.unbind("submit", this._checkSubmit).submit();
            }

            $form.find("input[type='submit']")
                .removeAttr("disabled").removeClass("ui-state-disabled");
        })

    crosspostAccountUpdated();

    $("#crosspost_entry").change(function() {
        var do_crosspost_entry = $(this).is(":checked");
        var $inputs = $("#crosspost_accounts").find("input");

        if ( do_crosspost_entry ) {
            $inputs.removeAttr("disabled")

            var $checkboxes = $inputs.filter("[name='crosspost']");
            if ( ! $checkboxes.is(":checked") )
                $checkboxes.attr("checked", "checked")
        } else {
            $inputs.attr("disabled", "disabled")
        }
    });

    $(this.element).closest("form").submit(this._checkSubmit);
},

// When the form is submitted, compute the challenge response and clear out the plaintext password field
_checkSubmit: function (e) {
    var $target = $(e.target);
    if ( ! skipChecks && ! $target.data("preventedby") && ! $target.data("skipchecks") ) {
        $(this).find("input[type='submit']").attr("disabled","disabled").addClass("ui-state-disabled");

        var needChalResp = false;
        $accounts.each(function() {
            var ret = $(this).crosspostaccount( "needsChalResp" );
            needChalResp = needChalResp || ret;
        });

        if ( needChalResp ) {
            e.preventDefault();
            e.stopPropagation();
            $accounts.crosspostaccount("doChallengeResponse");
        }
    }
},

// to display or not to display the crosspost accounts
toggle: function(why, allowThisCrosspost, animate) {
    var self = this;
    var $crosspost_entry = $("#crosspost_entry");

    var msg_class = "crosspost_msg";
    var msg_id = msg_class + "_" + why;
    var $msg = $("#"+msg_id);

    if( allowThisCrosspost ) {
        $msg.remove();
    } else if ( $msg.length == 0 && self.options.strings.crosspostDisabled[why] ) {
        var $p = $("<p></p>", { "class": msg_class, "id": msg_id }).text(self.options.strings.crosspostDisabled[why]);
        $p.insertBefore("#crosspost_accounts");
    }

    var allowCrosspost = (allowThisCrosspost && $(msg_class).length == 0 );

    // preserve existing disabled state if crosspost allowed
    var allUnchecked = ! $accounts.is(":checked")
    if ( ! allowCrosspost || allUnchecked )
        $crosspost_entry.attr("disabled", "disabled")
    else
        $crosspost_entry.removeAttr("disabled")

    var enableAccountCheckboxes = allowCrosspost && ( allUnchecked || $crosspost_entry.is(":checked") );

    if (enableAccountCheckboxes)
        $accounts.removeAttr("disabled");
    else
        $accounts.attr("disabled", "disabled");

    if ( allowCrosspost ) {
        skipChecks = false;
        $("#crosspost_accounts, #crosspost_component h4").slideDown()
            .siblings("p").hide();
    } else {
        skipChecks = true;
        $("#crosspost_accounts, #crosspost_component h4").hide()
            .siblings("p").slideDown();
    }
}

});

})(jQuery);
