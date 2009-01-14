var PageNotice = new Object();

PageNotice.init = function () {
    if (!$('dismiss_notice')) return;

    DOM.addEventListener($('dismiss_notice'), "click", PageNotice.dismissNotice);
}

PageNotice.dismissNotice = function () {
    if (!$('notice_key')) return;

    HTTPReq.getJSON({
        url: LiveJournal.getAjaxUrl("dismisspagenotice"),
        method: "GET",
        data: HTTPReq.formEncoded({ notice_key: $('notice_key').value }),
        onData: function (data) {
            if (data.success && data.success == 1) {
                if ($('page_notice') && $('page_notice').parentNode) {
                    $('page_notice').parentNode.style.display = "none";
                }
            }
        },
        onError: function (msg) { }
    });
}

LiveJournal.register_hook("page_load", PageNotice.init);
