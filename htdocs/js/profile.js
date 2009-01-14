var Profile = new Object();

Profile.init = function () {
    // collapse any section that the user has set to collapse
    HTTPReq.getJSON({
        url: LiveJournal.getAjaxUrl("profileexpandcollapse"),
        method: "GET",
        data: HTTPReq.formEncoded({ mode: "load" }),
        onData: function (data) {
            if (data.headers) {
                data.headers.forEach(function (header) {
                    var headerid = header + "_header";
                    if ($(headerid)) {
                        Profile.expandCollapse(headerid, false);
                    }
                });
            }
        },
        onError: function (msg) { }
    });

    // add event listeners to all of the headers
    var headers = DOM.getElementsByClassName(document, "expandcollapse");
    headers.forEach(function (header) {
        DOM.addEventListener(header, "click", function (evt) { Profile.expandCollapse(header.id, true) });
    });
}

Profile.expandCollapse = function (headerid, should_save) {
    var self = this;
    var bodyid = headerid.replace(/header/, 'body');
    var arrowid = headerid.replace(/header/, 'arrow');

    // figure out whether to expand or collapse
    var expand = !DOM.hasClassName($(headerid), 'on');

    if (expand) {
        // expand
        DOM.addClassName($(headerid), 'on');
        if ($(arrowid)) { $(arrowid).src = Site.imgprefix + "/profile_icons/arrow-down.gif"; }
        if ($(bodyid)) { $(bodyid).style.display = "block"; }
    } else {
        // collapse
        DOM.removeClassName($(headerid), 'on');
        if ($(arrowid)) { $(arrowid).src = Site.imgprefix + "/profile_icons/arrow-right.gif"; }
        if ($(bodyid)) { $(bodyid).style.display = "none"; }
    }

    // save the user's expand/collapse status
    if (should_save) {
        HTTPReq.getJSON({
            url: LiveJournal.getAjaxUrl("profileexpandcollapse"),
            method: "GET",
            data: HTTPReq.formEncoded({ mode: "save", header: headerid, expand: expand }),
            onData: function (data) { },
            onError: function (msg) { }
        });
    }
}

LiveJournal.register_hook("page_load", Profile.init);
