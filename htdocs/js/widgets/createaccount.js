var CreateAccount = new Object();

CreateAccount.init = function () {
    if (!$('create_user')) return;
    if (!$('create_email')) return;
    if (!$('create_password1')) return;
    if (!$('create_bday_mm')) return;
    if (!$('create_bday_dd')) return;
    if (!$('create_bday_yyyy')) return;

    CreateAccount.bubbleid = "";

    DOM.addEventListener($('create_user'), "focus", CreateAccount.eventShowTip.bindEventListener("create_user"));
    DOM.addEventListener($('create_email'), "focus", CreateAccount.eventShowTip.bindEventListener("create_email"));
    DOM.addEventListener($('create_password1'), "focus", CreateAccount.eventShowTip.bindEventListener("create_password1"));
    DOM.addEventListener($('create_password2'), "focus", CreateAccount.eventShowTip.bindEventListener("create_password1"));
    DOM.addEventListener($('create_bday_mm'), "focus", CreateAccount.eventShowTip.bindEventListener("create_bday_mm"));
    DOM.addEventListener($('create_bday_dd'), "focus", CreateAccount.eventShowTip.bindEventListener("create_bday_mm"));
    DOM.addEventListener($('create_bday_yyyy'), "focus", CreateAccount.eventShowTip.bindEventListener("create_bday_mm"));

    if (CreateAccount.alt_layout) {
        DOM.addEventListener($('create_user'), "blur", CreateAccount.eventHideTip.bindEventListener("create_user"));
        DOM.addEventListener($('create_email'), "blur", CreateAccount.eventHideTip.bindEventListener("create_email"));
        DOM.addEventListener($('create_password1'), "blur", CreateAccount.eventHideTip.bindEventListener("create_password1"));
        DOM.addEventListener($('create_password2'), "blur", CreateAccount.eventHideTip.bindEventListener("create_password1"));
        DOM.addEventListener($('create_bday_mm'), "blur", CreateAccount.eventHideTip.bindEventListener("create_bday_mm"));
        DOM.addEventListener($('create_bday_dd'), "blur", CreateAccount.eventHideTip.bindEventListener("create_bday_mm"));
        DOM.addEventListener($('create_bday_yyyy'), "blur", CreateAccount.eventHideTip.bindEventListener("create_bday_mm"));
    }

    if (!$('username_check')) return;
    if (!$('username_error')) return;

    DOM.addEventListener($('create_user'), "blur", CreateAccount.checkUsername);
}

CreateAccount.eventShowTip = function () {
    var id = this + "";
    CreateAccount.id = id;
    CreateAccount.showTip(id);
}

CreateAccount.eventHideTip = function () {
    var id = this + "";
    CreateAccount.id = id;
    CreateAccount.hideTip(id);
}

CreateAccount.showTip = function (id) {
    if (!id) return;

    if (CreateAccount.alt_layout) {
        CreateAccount.bubbleid = id.replace(/create/, 'bubble');
        if ($(CreateAccount.bubbleid)) {
            $(CreateAccount.bubbleid).style.visibility = "visible";
        }
    } else {
        var y = DOM.findPosY($(id)), text;

        if (id == "create_bday_mm") {
            text = CreateAccount.birthdate;
        } else if (id == "create_email") {
            text = CreateAccount.email;
        } else if (id == "create_password1") {
            text = CreateAccount.password;
        } else if (id == "create_user") {
            text = CreateAccount.username;
        }

        var box = $('tips_box'), box_arr = $('tips_box_arrow');
        if (box && box_arr) {
            box.innerHTML = text;

            box.style.top = y - 260 + "px";
            box.style.display = "block";

            box_arr.style.top = y - 255 + "px";
            box_arr.style.display = "block";
        }
    }
}

CreateAccount.hideTip = function (id) {
    if (!id) return;

    if (CreateAccount.alt_layout) {
        if ($(CreateAccount.bubbleid)) {
            $(CreateAccount.bubbleid).style.visibility = "hidden";
        }
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
            CreateAccount.showTip(CreateAccount.id); // recalc
        },
        onError: function (msg) { }
    }); 
}

LiveJournal.register_hook("page_load", CreateAccount.init);
