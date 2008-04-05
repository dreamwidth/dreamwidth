/*
  Helper functions for the s1/s2/customize/style/whatever frontend

  tabclick_init: On window load, change the links of the tabs to the current page
                 and add onclick event handlers that save the current tab

  tabclick_save: when navigating away from the current tab by clicking another tag,
                 save the contents of the current tab

*/
var form_changed = false;

function form_change () {
    if (form_changed == true) { return; }
    form_changed = true;
}

function tabclick_save(e) {
    $("action:redir").value = this.id;
    var confirmed = false;
    if (form_changed == false) {
        return true;
    } else {
        confirmed = confirm("Save your settings?");
    }
    if (confirmed) {
        Event.stop(e);
        $("display_form").submit();
    }
}

function comment_options_toggle() {
    var inputs = $("comment_options").getElementsByTagName("input");
    var selects = $("comment_options").getElementsByTagName("select");
    var disabled = $("opt_showtalklinks").checked ? false : true;
    var color = $("opt_showtalklinks").checked ? "#000000" : "#999999";

    $("comment_options").style.color = color;
    for (var i = 0; i < inputs.length; i++) {
        inputs[i].disabled = disabled;
    }
    for (var i = 0; i < selects.length; i++) {
        selects[i].disabled = disabled;
    }

}

function s1_customcolors_toggle() {
    if ($("themetype:custom").checked) {
        $("s1_customcolors").style.display = "block";
    }
    if ($("themetype:system").checked) {
        $("s1_customcolors").style.display = "none";
    }
}

function populate_form_select(selectid, options) {
    $(selectid).options.length = 0;
    if (options[0].value == undefined) { // in case we get passed the options as hashes
        for(i = 0; i < options.length; i+=2) {
            $(selectid).options[i/2] = new Option(options[i+1],options[i]);
        }
    } else {
        for(i = 0; i < options.length; i++) {
            $option = new Option(options[i].text,options[i].value);
            $option.disabled = options[i].disabled;
            if ($option.disabled) {
                $option.style.color = "#999"; // IE doesn't support the disabled attribute on option tags
            }
            $(selectid).options[i] = $option;
        }
    }
}

function s2_layout_update_children() {
    $('display_form').style.cursor = "wait";
    var authas = $('authas:user').value;
    var s2_layoutid = $('s2_layoutid').options[$('s2_layoutid').options.selectedIndex].value;
    $('s2_themeid_preview_link').href = "/customize/themes.bml?journal=" + authas + "&layout=" + s2_layoutid;
    HTTPReq.getJSON({
           url: "/tools/endpoints/gets2layoutchildren.bml?authas=" + authas + "&s2_layoutid=" + s2_layoutid,
           onData: function (data) {
             populate_form_select('s2_themeid', data.themes);
             populate_form_select('s2_langcode', data.langs);
             $('display_form').style.cursor = "auto";
           },
           onError: function (msg) { }
    });
}

function customize_init() {
    /* Capture onclicks on the tab links to confirm form saving */
    var links = $('Tabs').getElementsByTagName('a');
    for (var i = 0; i < links.length; i++) {
        if (links[i].href != "") {
            DOM.addEventListener(links[i], "click", tabclick_save.bindEventListener(links[i]));
        }
    }

    /* Register all form changes to confirm them later */
    var selects = $('display_form').getElementsByTagName('select');
    for (var i = 0; i < selects.length; i++) {
        DOM.addEventListener(selects[i], "change", form_change);
    }
    var inputs = $('display_form').getElementsByTagName('input');
    for (var i = 0; i < inputs.length; i++) {
        DOM.addEventListener(inputs[i], "change", form_change);
    }
    var textareas = $('display_form').getElementsByTagName('textarea');
    for (var i = 0; i < textareas.length; i++) {
        DOM.addEventListener(textareas[i], "change", form_change);
    }

    /* Hide/show the custom colors for S1 */
    var s1_customcolors = $("s1_customcolors");
    if (s1_customcolors) {
        s1_customcolors_toggle();
        DOM.addEventListener($("themetype:custom"), "change", s1_customcolors_toggle);
        DOM.addEventListener($("themetype:system"), "change", s1_customcolors_toggle);
    }
    /* Hide/show the comment options */
    var opt_showtalklinks = $("opt_showtalklinks");
    if (opt_showtalklinks) {
        comment_options_toggle();
        DOM.addEventListener(opt_showtalklinks, "change", comment_options_toggle);
    }
    /* Update the S2 themes and languages for the selected layout */
    var s2_layoutid = $("s2_layoutid");
    if (s2_layoutid) {
        DOM.addEventListener(s2_layoutid, "change", s2_layout_update_children);
    }
}
DOM.addEventListener(window, "load", customize_init);
