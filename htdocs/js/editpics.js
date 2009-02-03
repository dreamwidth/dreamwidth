var uptrack; // our Perlbal upload tracker object, if defined
var uploadInProgress = false;
var pbar = new LJProgressBar();

function submitForm () {
  if (uptrack) uptrack.stopTracking();

  uploadInProgress = true;

  var frm = $("uploadPic");
  var postgoto = $("go_to");

  if (!frm || !postgoto) return;

  // to $POST{'go_to'} value of "jscallup" means our iframe returns a javascript
  // document that calls up to us to tell us it's done.
  postgoto.value = "jscallup";

  frm.target = "upiframe";
  uptrack = new UploadTracker(frm, uploadCallback);

  $("uploadStatus").innerHTML = "Uploading, please wait...";
  $("progressBar").style.display = "block";
  $("uploadStatus").style.display = "block";
  return true;
}

// called from iframe's content (manage/uploaded) on complete, after
// uptrackWebUpload.pm redirects the iframe there:
function onUploadComplete (gotoUrl) {
  if (!uploadInProgress) return; // silly IE, caching the iframe's content

  if (uptrack) uptrack.stopTracking();

  if (pbar)
    pbar.setIndefinite(true);

  $("uploadStatus").innerHTML = "Upload complete.";

  window.location = gotoUrl;
}

// called by the perlbal upload tracker library
function uploadCallback (data) {
  if (! (data && data.total)) return;
  if (pbar) {
    pbar.setMax(data.total);
    pbar.setValue(data.done);
  }
  var percent = Math.floor(data.done/data.total*100);
  var status = Math.floor(data.done / 1024) + " kB / " + Math.floor(data.total / 1024) + " kB, " + percent + "% complete";
  $("uploadStatus").innerHTML = status;
}

function setup () {
  if (!$("progressBar"))
    return;

  if (pbar)
    pbar.init($("progressBar"));

  $("progressBar").className="lj_progresscontainer";
}

function editpicsInit() {
    if ($("upload_desc_link")) {
        $("upload_desc_link").style.display = 'block';
        $("upload_desc").style.display = 'none';
    }

    if ($("upload_desc_photo_link")) {
        $("upload_desc_photo_link").style.display = 'block';
        $("upload_desc_photo").style.display = 'none';
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
  if (document.forms.uploadPic.make_default instanceof HTMLInputElement) {
    value = document.forms.uploadPic.make_default.checked;
    document.forms.uploadPic.make_default.type = "radio";
    document.forms.uploadPic.make_default.checked = value;
  }

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
  }

  removeFromTag = document.getElementById("multi_insert");
  removeElement = document.getElementById("additional_upload_" + removeIndex);
  removeFromTag.removeChild(removeElement);
  maxcounter++;
  if (counter < maxcounter) {
    unhideUploadButtons();
  }

  if (document.forms.uploadPic.make_default instanceof HTMLInputElement) {
    value = document.forms.uploadPic.make_default.checked;
    document.forms.uploadPic.make_default.type = "checkbox";
    document.forms.uploadPic.make_default.checked = value;
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

DOM.addEventListener(window, "load", setup);
