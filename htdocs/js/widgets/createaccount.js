var CreateAccount = new Object();

CreateAccount.init = function () {
    if (!$('create_user')) return;
    if (!$('create_email')) return;
    if (!$('create_password1')) return;
    if (!$('create_bday_mm')) return;
    if (!$('create_bday_dd')) return;
    if (!$('create_bday_yyyy')) return;

    DOM.addEventListener($('create_user'), "focus", CreateAccount.showTip.bindEventListener("create_user"));
    DOM.addEventListener($('create_email'), "focus", CreateAccount.showTip.bindEventListener("create_email"));
    DOM.addEventListener($('create_password1'), "focus", CreateAccount.showTip.bindEventListener("create_password1"));
    DOM.addEventListener($('create_password2'), "focus", CreateAccount.showTip.bindEventListener("create_password1"));
    DOM.addEventListener($('create_bday_mm'), "focus", CreateAccount.showTip.bindEventListener("create_bday_mm"));
    DOM.addEventListener($('create_bday_dd'), "focus", CreateAccount.showTip.bindEventListener("create_bday_mm"));
    DOM.addEventListener($('create_bday_yyyy'), "focus", CreateAccount.showTip.bindEventListener("create_bday_mm"));

    if (!$('username_check')) return;
    if (!$('username_error')) return;

    DOM.addEventListener($('create_user'), "blur", CreateAccount.checkUsername);
}

CreateAccount.showTip = function (evt) {
    var id = this + "";

    var x = DOM.findPosX($(id));
    var y = DOM.findPosY($(id));

    var text;
    if (id == "create_bday_mm") {
        text = CreateAccount.birthdate;
    } else if (id == "create_email") {
        text = CreateAccount.email;
    } else if (id == "create_password1") {
        text = CreateAccount.password;
    } else if (id == "create_user") {
        text = CreateAccount.username;
    }

    if ($('tips_box') && $('tips_box_arrow')) {
        // Firefox on Mac and IE6 need to be over to the right more than other browsers
        var browser = new BrowserDetectLite();
        var x_offset = 0;
        if (browser.isGecko && browser.isMac) {
            x_offset = 100;
        } else if (browser.isIE6x) {
            x_offset = 50;
        }

        $('tips_box').innerHTML = text;

        $('tips_box').style.left = x + 160 + x_offset + "px";
        $('tips_box').style.top = y - 188 + "px";
        $('tips_box').style.display = "block";

        $('tips_box_arrow').style.left = x + 149 + x_offset + "px";
        $('tips_box_arrow').style.top = y - 183 + "px";
        $('tips_box_arrow').style.display = "block";
    }
}

CreateAccount.checkUsername = function () {
    if ($('create_user').value == "") return;

    HTTPReq.getJSON({
        url: "/tools/endpoints/checkforusername.bml?user=" + $('create_user').value,
        method: "GET",
        onData: function (data) {
            if (data.error) {
                if ($('username_error_main')) $('username_error_main').style.display = "none";

                $('username_error_inner').innerHTML = data.error;
                $('username_check').style.display = "none";
                $('username_error').style.display = "inline";
            } else {
                if ($('username_error_main')) $('username_error_main').style.display = "none";

                $('username_error').style.display = "none";
                $('username_check').style.display = "inline";
            }
        },
        onError: function (msg) { }
    }); 
}

LiveJournal.register_hook("page_load", CreateAccount.init);
