var Settings = new Object();

Settings.init = function () {
    if (!$('settings_form')) return;

    Settings.form_changed = false;

    // capture onclicks on all links to confirm form saving
    var links = document.getElementsByTagName('a');
    for (var i = 0; i < links.length; i++) {
        if (links[i].href != "") {
            DOM.addEventListener(links[i], "click", function (evt) { Settings.navclick_save(evt) })
        }
    }

    // register all form changes to confirm them later
    var selects = $('settings_form').getElementsByTagName('select');
    for (var i = 0; i < selects.length; i++) {
        DOM.addEventListener(selects[i], "change", function (evt) { Settings.form_change() });
    }
    var inputs = $('settings_form').getElementsByTagName('input');
    for (var i = 0; i < inputs.length; i++) {
        DOM.addEventListener(inputs[i], "change", function (evt) { Settings.form_change() });
    }
    var textareas = $('settings_form').getElementsByTagName('textarea');
    for (var i = 0; i < textareas.length; i++) {
        DOM.addEventListener(textareas[i], "change", function (evt) { Settings.form_change() });
    }
}

Settings.navclick_save = function (evt) {
    var confirmed = false;

    if (Settings.form_changed == false) {
        return true;
    } else {
        var confirm_msg = "Save your changes?";
        if (Settings.confirm_msg) { confirm_msg = Settings.confirm_msg };

        confirmed = confirm(confirm_msg);
    }

    if (confirmed) {
        $('settings_form').submit();
    }
}

Settings.form_change = function () {
    if (Settings.form_changed == true) { return; }
    Settings.form_changed = true;
}

LiveJournal.register_hook("page_load", Settings.init);
