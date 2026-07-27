// Icon management page (/manage/icons): upload-form behaviors.
//
// Uses plain DOM APIs only. This is a Foundation page, where the global $ is
// jQuery and the legacy 6alib helpers are not loaded.
//
// Each upload row has a "Upload file" button (which opens a hidden file input)
// and an "or enter URL" text field. A hidden src_N field records which source
// the row uses; the server processes only the matching input per row. The page
// supplies its labels and upload limit via window.editiconsConfig.

// counter: how many extra upload slots we've created so far.
// maxcounter: the maximum number of upload slots allowed (from config).
var counter = 1;
var maxcounter;

function ep_config() {
    return window.editiconsConfig || { labels: {} };
}

function setup() {
    maxcounter = ep_config().maxcounter;
    bindUploadRow(0);
    editiconsInit();
}

function editiconsInit() {
    var link = document.getElementById("upload_desc_link");
    if (link) {
        document.getElementById("upload_desc").style.display = 'none';
    }
}

function toggleElement(elementId) {
    var el = document.getElementById(elementId);
    if (!el) return;
    el.style.display = (el.style.display == 'block') ? 'none' : 'block';
}

// Wire up a row's file-button + URL field so they keep the row's src_N in sync.
function bindUploadRow(n) {
    var file = document.getElementById("userpic_" + n);
    var url = document.getElementById("urlpic_" + n);
    if (file) file.addEventListener("change", function () { selectFile(n); });
    if (url) {
        url.addEventListener("focus", function () { selectUrl(n); });
        url.addEventListener("input", function () { selectUrl(n); });
    }
    // Sync src_N to any value already present (form re-render after a
    // validation error, or browser autofill) so it isn't stuck on "file".
    if (url && url.value) selectUrl(n);
    else if (file && file.files && file.files.length) selectFile(n);
}

// Open the (hidden) file picker for a row.
function chooseFile(n) {
    var file = document.getElementById("userpic_" + n);
    if (file) file.click();
}

// A file was chosen: mark the row as a file upload and show the filename.
function selectFile(n) {
    var file = document.getElementById("userpic_" + n);
    var src = document.getElementById("src_" + n);
    var name = document.getElementById("filename_" + n);
    if (src) src.value = "file";
    if (name && file && file.files && file.files.length) {
        name.textContent = file.files[0].name;
    }
}

// The URL field is being used: mark the row as a URL upload.
function selectUrl(n) {
    var src = document.getElementById("src_" + n);
    var name = document.getElementById("filename_" + n);
    if (src) src.value = "url";
    if (name) name.textContent = "";
}

function addNewUpload() {
    var labels = ep_config().labels || {};
    updateMakeDefaultType(true);
    var n = counter;

    var block = document.createElement("div");
    block.setAttribute("id", "additional_upload_" + n);
    block.setAttribute("class", "additional_upload");

    var html = "<hr class='hr' />";
    html += "<div class='upload_source'>";
    html += "<button type='button' class='button secondary upload_file_btn' onclick='chooseFile(" + n + ")'>" + labels.file + "</button>";
    html += "<input type='file' class='upload_file_input' name='userpic_" + n + "' id='userpic_" + n + "' />";
    html += "<span class='upload_filename' id='filename_" + n + "'></span>";
    html += "<label class='upload_or' for='urlpic_" + n + "'>" + labels.orurl + "</label>";
    html += "<input type='text' class='text upload_url' name='urlpic_" + n + "' id='urlpic_" + n + "' />";
    html += "<input type='hidden' name='src_" + n + "' id='src_" + n + "' value='file' />";
    html += "<button type='button' class='button tiny secondary additional_remove' onclick='removeAdditionalUpload(" + n + ")'>" + labels.remove + "</button>";
    html += "</div>";
    html += fieldRow("keywords", n, labels.keywords, 0);
    if (ep_config().allowComments) html += fieldRow("comments", n, labels.comment, 120);
    if (ep_config().allowDescriptions) html += fieldRow("descriptions", n, labels.description, 300);
    html += "<p class='pkg additional_default'><input type='radio' value='" + n + "' name='make_default' id='make_default_" + n + "' /> <label class='inline' for='make_default_" + n + "'>" + labels.makedefault + "</label></p>";

    block.innerHTML = html;
    document.getElementById("multi_insert").appendChild(block);
    bindUploadRow(n);

    counter++;
    if (counter >= maxcounter) hideUploadButtons();
    if (document.forms.uploadPic.make_default.length == 2) addNoDefaultButton();
}

function fieldRow(name, n, label, maxlen) {
    var ml = maxlen ? " maxlength='" + maxlen + "'" : "";
    return "<p class='pkg additional_field'>"
        + "<label class='inline' for='" + name + "_" + n + "'>" + label + "</label> "
        + "<input type='text'" + ml + " class='text' name='" + name + "_" + n + "' id='" + name + "_" + n + "' />"
        + "</p>";
}

function removeAdditionalUpload(removeIndex) {
    if (document.forms.uploadPic.make_default.length == 3) {
        removeNoDefaultButton();
        updateMakeDefaultType(false);
    }
    var wrap = document.getElementById("multi_insert");
    var el = document.getElementById("additional_upload_" + removeIndex);
    if (el) wrap.removeChild(el);
    maxcounter++;
    if (counter < maxcounter) unhideUploadButtons();
}

function hideUploadButtons() {
    document.getElementById("multi_insert_buttons").style.display = 'none';
}

function unhideUploadButtons() {
    document.getElementById("multi_insert_buttons").style.display = 'inline-block';
}

function addNoDefaultButton() {
    var labels = ep_config().labels || {};
    var buttonsElement = document.getElementById("no_default_insert");
    var insertElement = document.createElement("p");
    insertElement.setAttribute("id", "make_default_none");
    insertElement.setAttribute("class", "pkg");
    insertElement.innerHTML = "<input type='radio' accesskey='" + labels.makedefaultkey + "' value='-1' name='make_default' id='make_default_button_none' /> <label class='inline' for='make_default_button_none'>" + labels.keepdefault + "</label>";
    buttonsElement.appendChild(insertElement);
}

function removeNoDefaultButton() {
    var removeFromTag = document.getElementById("no_default_insert");
    var removeElement = document.getElementById("make_default_none");
    if (removeElement) removeFromTag.removeChild(removeElement);
}

function updateMakeDefaultType(multi) {
    var makeDefaultInput = document.getElementById('make_default_0');
    if (makeDefaultInput != null) {
        if ((multi && makeDefaultInput.type != "radio") || (!multi && makeDefaultInput.type != "checkbox")) {
            var containerElement = document.getElementById('main_make_default');
            var value = makeDefaultInput.checked;
            if (multi) {
                containerElement.innerHTML = containerElement.innerHTML.replace(/checkbox/, "radio");
            } else {
                containerElement.innerHTML = containerElement.innerHTML.replace(/radio/, "checkbox");
            }
            document.getElementById('make_default_0').checked = value;
        }
    }
}

// This file loads at the end of the body; register for DOMContentLoaded, but
// guard against the already-loaded case so init is robust.
if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setup);
} else {
    setup();
}
