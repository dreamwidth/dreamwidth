function setup () {
  DOM.addEventListener($("radio_url"), "click", selectUrlUpload);
  DOM.addEventListener($("radio_file"), "click", selectFileUpload);
  DOM.addEventListener($("urlpic_0"), "keypress", keyPressUrlUpload);
  DOM.addEventListener($("userpic_0"), "change", keyPressFileUpload);
}

function editiconsInit() {
    if ($("upload_desc_link")) {
        $("upload_desc_link").style.display = 'block';
        $("upload_desc").style.display = 'none';
    }
}

function toggleElement(elementId) {
    var el = $(elementId);
    if (el && el.style.display == 'block') {
        el.style.display = 'none';
    } else {
        el.style.display = 'block';
    }
}

// keeps track of maximum number of uploads alowed
var counter = 1;
var maxcounter;
var ep_labels = {};
var allowComments = false;
var allowDescriptions = false;

function addNewUpload(uploadType) {
  updateMakeDefaultType(true);

  insertIntoTag = document.getElementById("multi_insert");
  insertElement = document.createElement("p");
  insertElement.setAttribute("id", "additional_upload_" + counter);
  insertElement.setAttribute("class", "pkg");

  newPicHTML = "<input type='button' value='" + ep_labels.remove + "' onclick='javascript:removeAdditionalUpload(" + counter + ");' /><br/>\n";

  if (uploadType == 'file') {
    newPicHTML += "<label class='left' for='userpic_" + counter + "'>From <u>F</u>ile:</label>";
    newPicHTML += "<input type='file' class='file' name='userpic_" + counter + "' id='userpic_" + counter + "' size='22' />";
  } else if (uploadType == 'url') {
    newPicHTML += "<label class='left' for='urlpic_'" + counter + ">";
    newPicHTML += ep_labels.fromurl + '</label>';
    newPicHTML += '<input type="text" name="urlpic_' + counter + '" id="urlpic_' + counter + '" class="text" />';
  }
  newPicHTML += "<label class='left' for='keywords_" + counter + "'>" + ep_labels.keywords + "</label><input type='text' name='keywords_" + counter + "' id='keywords_" + counter + "' class='text' />";
  if (allowComments) {
    newPicHTML += "<label class='left' for='comments_" + counter + "'>" + ep_labels.comment + "</label><input type='text' maxlength='120' name='comments_" + counter + "' id='comments_" + counter + "' class='text' />";
  }
  if (allowDescriptions) {
    newPicHTML += "<label class='left' for='descriptions_" + counter + "'>" + ep_labels.description +"</label><input type='text' maxlength='120' name='descriptions_" + counter + "' id='descriptions_" + counter + "' class='text' />";
  }
  newPicHTML += "<br/><input type='radio' accesskey='" + ep_labels.makedefaultkey + "' value='" + counter + "' name='make_default' id='make_default_" + counter + "' /><label for='make_default_" + counter + "'>" + ep_labels.makedefault + "</label>\n";

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

  removeFromTag = document.getElementById("multi_insert");
  removeElement = document.getElementById("additional_upload_" + removeIndex);
  removeFromTag.removeChild(removeElement);
  maxcounter++;
  if (counter < maxcounter) {
    unhideUploadButtons();
  }

}

function hideUploadButtons() {
  buttonsElement = document.getElementById("multi_insert_buttons");
  buttonsElement.style.display = 'none';
}

function unhideUploadButtons() {
  buttonsElement = document.getElementById("multi_insert_buttons");
  buttonsElement.style.display = 'block';
}

function addNoDefaultButton() {
  buttonsElement = document.getElementById("no_default_insert");
  insertElement = document.createElement("p");
  insertElement.setAttribute("id", "make_default_none");
  insertElement.setAttribute("class", "pkg");

  newPicHTML = "<input type='radio' accesskey='" + ep_labels.makedefaultkey +"' value='-1' name='make_default' id='make_default_button_none' /><label for='make_default_button_none'>" + ep_labels.keepdefault + "</label>\n";
  insertElement.innerHTML = newPicHTML;
  buttonsElement.appendChild(insertElement);
}

function removeNoDefaultButton() {
  removeFromTag = document.getElementById("no_default_insert");
  removeElement = document.getElementById("make_default_none");
  removeFromTag.removeChild(removeElement);
}

function selectUrlUpload() {
  $("userpic_0").disabled = true;
  $("urlpic_0").disabled = false;
}

function selectFileUpload() {
  $("urlpic_0").disabled = true;
  $("userpic_0").disabled = false;
}

function keyPressUrlUpload() {
  $("radio_url").checked =true;
  selectUrlUpload();
}

function keyPressFileUpload() {
  $("radio_file").checked =true;
  selectFileUpload();
}

function updateMakeDefaultType(multi) {
  var makeDefaultInput = $('make_default_0');

  if (makeDefaultInput != null) {
    // see if we're already correct
    if ((multi && makeDefaultInput.type != "radio") || (! multi && makeDefaultInput.type != "checkbox")) {
      var containerElement = $('main_make_default');

      value = makeDefaultInput.checked;
      if (multi) {
        containerElement.innerHTML = containerElement.innerHTML.replace(/checkbox/, "radio");
      } else {
        containerElement.innerHTML = containerElement.innerHTML.replace(/radio/, "checkbox");
      }
      $('make_default_0').checked = value;
    }
  }
}

document.addEventListener("DOMContentLoaded", setup);
