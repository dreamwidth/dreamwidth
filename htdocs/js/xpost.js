LiveJournal.xpostButtonUpdated = function () {
  var xpost_button = document.getElementById("prop_xpost_check");
  var xpost_checkboxes = DOM.getElementsByTagAndClassName(document, "input", "xpost_acct_checkbox") || [];
  for (var i=0; i < xpost_checkboxes.length; i++) {
    xpost_checkboxes[i].disabled = ! xpost_button.checked;
  }
}

LiveJournal.updateXpostFromJournal = function (user) {
  // only allow crossposts to the user's own journal
  var journal = document.updateForm.usejournal.value;
  var allowXpost = (journal == '' || user == journal);

  var xpost_button = document.getElementById("prop_xpost_check");
  xpost_button.disabled = ! allowXpost;
  var xpost_checkboxes = DOM.getElementsByTagAndClassName(document, "input", "xpost_acct_checkbox") || [];
  for (var i=0; i < xpost_checkboxes.length; i++) {
    xpost_checkboxes[i].disabled = ! allowXpost;
  }

  var xpostdiv = document.getElementById('xpostdiv');
  if (allowXpost) {
    xpostdiv.style.display = 'block';
  } else {
    xpostdiv.style.display = 'none';
  }

}

LiveJournal.confirmDelete = function (confMessage, xpostConfMessage) {
  // basic confirm
  var conf = confirm(confMessage);
  if (conf) {
    // check to see if we have any crossposts selected
    var xpost_button = document.getElementById("prop_xpost_check");
    if (xpost_button != null && xpost_button.checked) {
      var xpost_checkboxes = DOM.getElementsByTagAndClassName(document, "input", "xpost_acct_checkbox") || [];
      var showconf2 = false;
      for (var i=0; ! showconf2 && i < xpost_checkboxes.length; i++) {
        showconf2 = xpost_checkboxes[i].checked;
      }
      if (showconf2) {
        conf = confirm(xpostConfMessage);
      }
    }
  }
  return conf;
}

// NOTE:  this functionality is disabled; for now, we're requiring passwords
// for external accounts.

// add chal/resp auth to the "login" form if it exists
// this requires md5.js
LiveJournal.setUpXpostForm = function () {
  var updateForm = document.getElementById('updateForm');
  DOM.addEventListener(updateForm, "submit", LiveJournal.xpostFormSubmitted.bindEventListener(updateForm));

}

// When the form is submitted, compute the challenge response and clear out the plaintext password field
LiveJournal.xpostFormSubmitted = function (evt) {
  var updateForm = evt.target;
  if (! updateForm)
    return true;

  var xpost_fields = DOM.getElementsByTagAndClassName(document, "input", "xpost_chal") || [];
  for (var i=0; i < xpost_fields.length; i++) {
    var chal_field = xpost_fields[i];
    if (chal_field.value != null && chal_field.value != "") {
      var acctid = chal_field.id.substring(16);

      var resp_field = document.getElementById("prop_xpost_resp_" + acctid);
      var pass_field = document.getElementById("prop_xpost_password_" + acctid);

      if (chal_field && resp_field && pass_field) {
        //LiveJournal.getChallenge(username, acctid, resp_field, pass_field);
      }
    }
  }
  return false;
}

LiveJournal.getChallenge = function(username, acctid, resp_field, pass_field) {

  var url = window.parent.Site.siteroot + "/__rpc_extacct_auth?username=" + username + "&acctid=" + acctid;

  var gotError = function(err) {
    alert(err+' '+username);
    return;
  }

  var gotInfo = function (data) {
    if (data.error) {
      alert(data.error + ' ' + username);
      return;
    }

    if (!data.success) return;

    var pass = pass_field.value;
    var res = MD5(data.challenge + MD5(pass));
    resp_field.value = res;
    pass_field.value = "";  // dont send clear-text password!
  }

  var opts = {
    "async": false,
    "method": "GET",
    "url": url,
    "onError": gotError,
    "onData": gotInfo
  };

  window.parent.HTTPReq.getJSON(opts);
}

// disabled for now.
//LiveJournal.register_hook("page_load", LiveJournal.setUpXpostForm);
