// Icon management page (/manage/icons): upload-form behaviors.
//
// Uses plain DOM APIs only. This is a Foundation page, where the global $ is
// jQuery and the legacy 6alib helpers (DOM, the getElementById-style $, etc.)
// are not loaded -- the previous helper-based version of this file silently
// failed to initialize there, breaking the file/URL toggles and the
// "add another upload" buttons.
//
// The page supplies its labels and upload limit via an inline <script> that
// sets window.editiconsConfig before this file runs at the end of the body.

// counter: how many extra upload slots we've created so far.
// maxcounter: the maximum number of upload slots allowed (from config).
var counter = 1;
var maxcounter;

function ep_config() {
    return window.editiconsConfig || { labels: {} };
}

function ep_bind(id, eventName, fn) {
    var el = document.getElementById(id);
    if (el) el.addEventListener(eventName, fn);
}

function setup() {
    maxcounter = ep_config().maxcounter;

    ep_bind("radio_url", "click", selectUrlUpload);
    ep_bind("radio_file", "click", selectFileUpload);
    ep_bind("urlpic_0", "keypress", keyPressUrlUpload);
    ep_bind("userpic_0", "change", keyPressFileUpload);

    editiconsInit();
}

function editiconsInit() {
    var link = document.getElementById("upload_desc_link");
    if (link) {
        link.style.display = 'block';
        document.getElementById("upload_desc").style.display = 'none';
    }
}

function toggleElement(elementId) {
    var el = document.getElementById(elementId);
    if (!el) return;
    el.style.display = (el.style.display == 'block') ? 'none' : 'block';
}

function addNewUpload(uploadType) {
  var labels = ep_config().labels || {};
  updateMakeDefaultType(true);

  var insertIntoTag = document.getElementById("multi_insert");
  var insertElement = document.createElement("p");
  insertElement.setAttribute("id", "additional_upload_" + counter);
  insertElement.setAttribute("class", "pkg");

  var newPicHTML = "<input type='button' value='" + labels.remove + "' onclick='javascript:removeAdditionalUpload(" + counter + ");' /><br/>\n";

  if (uploadType == 'file') {
    newPicHTML += "<label class='left' for='userpic_" + counter + "'>" + labels.fromfile + "</label>";
    newPicHTML += "<input type='file' class='file' name='userpic_" + counter + "' id='userpic_" + counter + "' size='22' />";
  } else if (uploadType == 'url') {
    newPicHTML += "<label class='left' for='urlpic_" + counter + "'>";
    newPicHTML += labels.fromurl + '</label>';
    newPicHTML += '<input type="text" name="urlpic_' + counter + '" id="urlpic_' + counter + '" class="text" />';
  }
  newPicHTML += "<label class='left' for='keywords_" + counter + "'>" + labels.keywords + "</label><input type='text' name='keywords_" + counter + "' id='keywords_" + counter + "' class='text' />";
  if (ep_config().allowComments) {
    newPicHTML += "<label class='left' for='comments_" + counter + "'>" + labels.comment + "</label><input type='text' maxlength='120' name='comments_" + counter + "' id='comments_" + counter + "' class='text' />";
  }
  if (ep_config().allowDescriptions) {
    newPicHTML += "<label class='left' for='descriptions_" + counter + "'>" + labels.description +"</label><input type='text' maxlength='120' name='descriptions_" + counter + "' id='descriptions_" + counter + "' class='text' />";
  }
  newPicHTML += "<br/><input type='radio' accesskey='" + labels.makedefaultkey + "' value='" + counter + "' name='make_default' id='make_default_" + counter + "' /><label for='make_default_" + counter + "'>" + labels.makedefault + "</label>\n";

  insertElement.innerHTML = newPicHTML;
  insertIntoTag.appendChild(insertElement);
  counter++;
  if (counter >= maxcounter) {
    hideUploadButtons();
  }

  if (document.forms.uploadPic.make_default.length == 2) {
    addNoDefaultButton();
  }

}

function removeAdditionalUpload(removeIndex) {
  if (document.forms.uploadPic.make_default.length == 3) {
    removeNoDefaultButton();
    updateMakeDefaultType(false);
  }

  var removeFromTag = document.getElementById("multi_insert");
  var removeElement = document.getElementById("additional_upload_" + removeIndex);
  removeFromTag.removeChild(removeElement);
  maxcounter++;
  if (counter < maxcounter) {
    unhideUploadButtons();
  }

}

function hideUploadButtons() {
  document.getElementById("multi_insert_buttons").style.display = 'none';
}

function unhideUploadButtons() {
  document.getElementById("multi_insert_buttons").style.display = 'block';
}

function addNoDefaultButton() {
  var labels = ep_config().labels || {};
  var buttonsElement = document.getElementById("no_default_insert");
  var insertElement = document.createElement("p");
  insertElement.setAttribute("id", "make_default_none");
  insertElement.setAttribute("class", "pkg");

  insertElement.innerHTML = "<input type='radio' accesskey='" + labels.makedefaultkey +"' value='-1' name='make_default' id='make_default_button_none' /><label for='make_default_button_none'>" + labels.keepdefault + "</label>\n";
  buttonsElement.appendChild(insertElement);
}

function removeNoDefaultButton() {
  var removeFromTag = document.getElementById("no_default_insert");
  var removeElement = document.getElementById("make_default_none");
  removeFromTag.removeChild(removeElement);
}

function selectUrlUpload() {
  document.getElementById("userpic_0").disabled = true;
  document.getElementById("urlpic_0").disabled = false;
}

function selectFileUpload() {
  document.getElementById("urlpic_0").disabled = true;
  document.getElementById("userpic_0").disabled = false;
}

function keyPressUrlUpload() {
  document.getElementById("radio_url").checked = true;
  selectUrlUpload();
}

function keyPressFileUpload() {
  document.getElementById("radio_file").checked = true;
  selectFileUpload();
}

function updateMakeDefaultType(multi) {
  var makeDefaultInput = document.getElementById('make_default_0');

  if (makeDefaultInput != null) {
    // see if we're already correct
    if ((multi && makeDefaultInput.type != "radio") || (! multi && makeDefaultInput.type != "checkbox")) {
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

// This file loads at the end of the body, so the DOM is normally still parsing
// when it runs; register for DOMContentLoaded. Guard against the already-loaded
// case so initialization is robust regardless of where the file ends up.
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setup);
} else {
  setup();
}
