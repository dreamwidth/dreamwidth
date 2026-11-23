// js/moodtheme-editor.js
//
// Drives the custom mood theme editor (/manage/moodthemes). Each mood in
// the editor form has a preview image (id NNNimg), a URL field (id NNN),
// width/height fields (NNNw / NNNh), and -- if the mood has a parent -- an
// inherit checkbox (NNNinherit) plus hidden parent/oldinh fields. These
// functions keep the previews and fields in sync and disable the fields of
// moods that inherit from their parent.

// An <img> with no source reports the page URL as its src, so save the page
// URL to compare against when checking whether an image is actually loaded.
var page_url = document.URL;

// Update the preview and size fields for the mood whose URL field just
// changed, as well as those of all moods that inherit from it.
function update_children(id) {
    var url = document.getElementById(id);
    var img = document.getElementById(id + 'img');

    if (url.value == "") return false;

    var newimage = new Image();
    newimage.src = url.value;

    // update itself (a mood with no picture yet has no preview element)
    if (img != undefined) {
        img.src = url.value;
        img.width = newimage.width;
        img.height = newimage.height;
    }

    document.getElementById(id + 'w').value = newimage.width;
    document.getElementById(id + 'h').value = newimage.height;

    // update everything that inherits to match its parent
    var form = document.getElementById('editform');
    for (var z = 0; z < form.elements.length; z++) {
        var inherit = document.getElementById(form[z].id + 'inherit');
        var parent = document.getElementById(form[z].id + 'parent');
        if (parent != undefined && inherit != undefined && inherit.checked == true) {
            var pid = parent.value; // our parent's id
            var oid = form[z].id;   // our id

            // moods with no picture anywhere in their parent chain have no
            // preview image element at all
            var par_img = document.getElementById(pid + 'img');
            if (par_img == undefined || par_img.src == page_url) continue;

            var our_img = document.getElementById(oid + 'img');
            our_img.src = par_img.src;
            our_img.width = par_img.width;
            our_img.height = par_img.height;

            // now copy the image info into the text fields
            document.getElementById(oid).value = par_img.src;
            document.getElementById(oid + 'w').value = par_img.width;
            document.getElementById(oid + 'h').value = par_img.height;
        }
    }
    return false;
}

// Toggling an inherit checkbox: disable or enable the mood's fields, and
// when newly inherited, fill them from the parent.
function enable(id, parent) {
    var check = document.getElementById(id + 'inherit');
    var url = document.getElementById(id);
    var w = document.getElementById(id + 'w');
    var h = document.getElementById(id + 'h');

    var fill = switchdisable(id, check, url, w, h);

    var pi = document.getElementById(parent + 'img');
    if (fill && parent != id && pi != undefined && pi.src != page_url) {
        url.value = pi.src;
        w.value = pi.width;
        h.value = pi.height;
        var i = document.getElementById(id + 'img');
        i.src = pi.src;
        i.width = pi.width;
        i.height = pi.height;
    }
}

// Disable a mood's URL/width/height fields if its inherit checkbox is
// checked, enable them if not; returns whether the fields are now disabled.
function switchdisable(id, check, url, w, h) {
    if (check == undefined) {
        check = document.getElementById(id + 'inherit');
        url = document.getElementById(id);
        w = document.getElementById(id + 'w');
        h = document.getElementById(id + 'h');
    }

    var disabled = check.checked == true;
    url.disabled = disabled;
    w.disabled = disabled;
    h.disabled = disabled;
    return disabled;
}

// On load, disable the fields of every mood that currently inherits.
document.addEventListener('DOMContentLoaded', function () {
    var form = document.getElementById('editform');
    if (form == undefined) return;

    for (var z = 0; z < form.elements.length; z++) {
        var inherit = document.getElementById(form[z].id + 'inherit');
        if (inherit != undefined && inherit.checked == true)
            switchdisable(form[z].id);
    }
});
