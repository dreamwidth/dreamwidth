var AddVerticalEditorials = new Object();

AddVerticalEditorials.init = function () {
    if (!$('vertid')) return;
    if (!$('preview_btn')) return;

    DOM.addEventListener($('vertid'), "change", AddVerticalEditorials.getVerticalURL);
    AddVerticalEditorials.getVerticalURL();

    DOM.addEventListener($('preview_btn'), "click", AddVerticalEditorials.editorialPreview);
}

AddVerticalEditorials.getVerticalURL = function () {
    if ($('vertid').value == 0) return;

    HTTPReq.getJSON({
        url: "/tools/endpoints/getverticalurl.bml?vertid=" + $('vertid').value,
        method: "GET",
        onData: AddVerticalEditorials.storeVerticalURL,
        onError: function (msg) { }
    });
}

AddVerticalEditorials.storeVerticalURL = function (data) {
    if (data.verturl) {
        AddVerticalEditorials.verturl = data.verturl;
    }
}

AddVerticalEditorials.editorialPreview = function () {
    var form = $('editorial_form');
    var action = form.action;

    if (AddVerticalEditorials.verturl) {
        form.action = AddVerticalEditorials.verturl + "?preview=1";
        form.target = 'preview';
        window.open('','preview','width=1024,height=600,resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
        form.submit();
        form.action = action;
        form.target = '_self';
    } else {
        alert("Can't get URL for preview.");
    }

    return false;
}

LiveJournal.register_hook("page_load", AddVerticalEditorials.init);
