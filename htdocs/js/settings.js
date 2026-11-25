var Settings = window.Settings || {};

Settings.init = function () {
    var form = document.getElementById('settings_form');
    if (!form) return;

    Settings.form_changed = false;

    // Capture navigation before the browser follows the link.  The legacy
    // handler submitted without cancelling the click, racing the save against
    // navigation; modern settings pages must make that choice deterministic.
    var links = document.getElementsByTagName('a');
    for (var i = 0; i < links.length; i++) {
        if (links[i].href) {
            links[i].addEventListener('click', Settings.navclick_save, false);
        }
    }

    var fields = form.querySelectorAll('select, input, textarea');
    for (var j = 0; j < fields.length; j++) {
        fields[j].addEventListener('change', Settings.form_change, false);
    }
};

Settings.navclick_save = function (evt) {
    if (!Settings.form_changed) return true;

    var confirmMsg = Settings.confirm_msg || window.SettingsConfirmMsg || 'Save your changes?';
    // Always consume the navigation once a dirty form has been detected.  On
    // cancel we stay on the page; on accept the form submission is the only
    // navigation, so a tab click cannot discard the submitted values.
    evt.preventDefault();
    evt.stopPropagation();
    if (window.confirm(confirmMsg)) {
        document.getElementById('settings_form').submit();
    }
    return false;
};

Settings.form_change = function () {
    Settings.form_changed = true;
};

if (window.LiveJournal && LiveJournal.register_hook) {
    LiveJournal.register_hook('page_load', Settings.init);
} else if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', Settings.init, false);
} else {
    Settings.init();
}
