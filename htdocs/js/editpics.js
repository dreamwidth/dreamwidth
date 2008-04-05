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

DOM.addEventListener(window, "load", setup);
