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

    DOM.addEventListener($('create_user'), "blur", CreateAccount.eventHideTip.bindEventListener("create_user"));
    DOM.addEventListener($('create_email'), "blur", CreateAccount.eventHideTip.bindEventListener("create_email"));
    DOM.addEventListener($('create_password1'), "blur", CreateAccount.eventHideTip.bindEventListener("create_password1"));
    DOM.addEventListener($('create_password2'), "blur", CreateAccount.eventHideTip.bindEventListener("create_password1"));
    DOM.addEventListener($('create_bday_mm'), "blur", CreateAccount.eventHideTip.bindEventListener("create_bday_mm"));
    DOM.addEventListener($('create_bday_dd'), "blur", CreateAccount.eventHideTip.bindEventListener("create_bday_mm"));
    DOM.addEventListener($('create_bday_yyyy'), "blur", CreateAccount.eventHideTip.bindEventListener("create_bday_mm"));

    if (!$('username_check')) return;
    if (!$('username_error')) return;

    DOM.addEventListener($('create_user'), "blur", CreateAccount.checkUsername);
    //$("terms-news").style.width = ($("create_email").offsetWidth + 25) + "px";
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

    var drop, tipleft, arrowdrop, text, relCont;
    drop = 0;
    tipleft = $("create_email").offsetWidth + 25;
    relCont = $("relative-container");
    // Create the location for the tooltip
    if (id == "create_bday_mm") {
        text = CreateAccount.birthdate;
        drop = CreateAccount.findHeight($("create_bday_mm")) - CreateAccount.findHeight(relCont);
    } else if (id == "create_email") {
        text = CreateAccount.email;
        drop = CreateAccount.findHeight($("create_email")) - CreateAccount.findHeight(relCont);
    } else if (id == "create_password1") {
        text = CreateAccount.password;
        drop = CreateAccount.findHeight($("create_password1")) - CreateAccount.findHeight(relCont);
    } else if (id == "create_user") {
        text = CreateAccount.username;
        drop = CreateAccount.findHeight($("create_user")) - CreateAccount.findHeight(relCont);
    }
    //drop = CreateAccount.findHeight($( id ));

    var out_box=$('tips-box-container'),box = $('tips_box'), box_arr = $('tips_box_arrow');
    if (box && box_arr) {
        box.innerHTML = text;
        box.style.display = "block";
        box_arr.style.display = "block";
        box.style.visibility = "visible";
        box_arr.style.visibility = "visible";
        out_box.style.left = tipleft + "px";
        box_arr.style.top = "3px";
        out_box.style.top = drop + "px";
    }
}

CreateAccount.hideTip = function (id) {
    if (!id) return;

    // Set the tip to the empty string instead of just relying
    // on CSS to maximize accessibility
    $('tips_box').style.visibility = "hidden";
    $('tips_box').innerHTML = "";
    $('tips_box_arrow').style.visibility= "hidden";
}

CreateAccount.findHeight = function (obj){
    //adapted from QuirksMode "Find Position": http://www.quirksmode.org/js/findpos.html
    var curTop;
    curTop = 0;
    if ( obj.offsetParent ) {
        do {
            curTop += obj.offsetTop;
        } while (obj = obj.offsetParent);
    }
    return curTop;
}

CreateAccount.checkUsername = function () {
    if ($('create_user').value == "") return;

    HTTPReq.getJSON({
        url: "/tools/endpoints/checkforusername?user=" + $('create_user').value,
        method: "GET",
        onData: function (data) {
            if (data.error) {
                if ($('username_error_main')) $('username_error_main').style.display = "none";

                $('username_error_inner').innerHTML = data.error;
                $('username_check').style.display = "none";
                $('username_error').style.display = "inline";
                $('create_user').setAttribute("aria-invalid", "true");
            } else {
                if ($('username_error_main')) $('username_error_main').style.display = "none";

                $('username_error').style.display = "none";
                $('username_check').style.display = "inline";
                $('create_user').setAttribute("aria-invalid", "false");
            }
            CreateAccount.showTip(CreateAccount.id); // recalc
        },
        onError: function (msg) { }
    }); 
}

LiveJournal.register_hook("page_load", CreateAccount.init);
