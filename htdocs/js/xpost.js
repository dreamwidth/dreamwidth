// class representing a crosspost account
XPostAccount = new Class(Object, {
    init: function (acctid) {
      this.acctid = acctid;
      this.checkboxTag = $("prop_xpost_" + acctid);
      this.chalField = $("prop_xpost_chal_" + acctid);
      this.statusField = $("prop_xpost_pwstatus_" + acctid);
      this.respField = $("prop_xpost_resp_" + acctid);
      this.passField = $("prop_xpost_password_" + acctid);
      this.pwSpan = $("prop_xpost_pwspan_" + acctid);
      DOM.addEventListener(this.checkboxTag, 'change', this.checkboxChanged.bindEventListener(this));
      this.checkboxChanged();
      this.clearSettings();
    },

    checkboxChanged: function(evt) {
      if (this.passField != null) {
        if (this.checkboxTag.checked) {
          this.pwSpan.style.display='inline';
        } else {
          this.pwSpan.style.display='none';
        }

      }
    },

    setDisabled: function(disabled) {
      this.checkboxTag.disabled = disabled;
      if (this.passField != null) {
        this.passField.disabled = disabled;
      }
    },

    clearSettings: function () {
      this.failed = false;
      this.locked = false;
    },

    clearPassword: function () {
      if (this.passField != null) {
        this.passField.value = "";
      }
    },

    /**
     * does an ajax call for challenge/response, so if we have an xpost account
     * where we're not saving the password, we can avoid sending the password
     * in plaintext.  also checks to see if a required password is not filled
     * in.
     *
     * returns true if this account requires a password and some work has
     * to be done, false if this account doesn't need a password to be
     * provided in the form.
     */
    doChallengeResponse: function () {
      var xpost_button = $("prop_xpost_check");

      // check to see if we need to do a challenge/response for this.
      if ((! this.locked) && this.chalField != null
            && this.checkboxTag != null && this.checkboxTag.checked
            && xpost_button != null && xpost_button.checked) {
        this.locked = true;

        if (this.passField == null || this.passField.value == null || this.passField.value == "") {
          this.setError(xpostPwRequired);
          this.failed = true;
          this.locked = false;
          return true;
        }
        this.setMessage(xpostCheckingMessage + "<input type='button' onclick='XPostAccount.cancelSubmit()' value='" + xpostCancelLabel + "'/>");

        var opts = {
          "async": true,
          "method": "GET",
          "url": window.parent.Site.siteroot + "/__rpc_extacct_auth?acctid=" + this.acctid,
          "onError": this.gotError.bind(this),
          "onData": this.gotInfo.bind(this)
        };
        window.parent.HTTPReq.getJSON(opts);

        return true;
      }
      return false;
    },

    gotError: function (err) {
      if (this.locked) {
        this.setError(err);
        this.failed = true;
        this.locked = false;
        XPostAccount.checkComplete();
      }
      return;
    },

    gotInfo: function (data) {
      if (this.locked) {
        if (data.error) {
          this.setError(data.error);
          this.failed = true;
          this.locked = false;
          XPostAccount.checkComplete();
          return;
        }

        this.statusField.innerHTML = "";
        if (!data.success) return;

        var pass = this.passField.value;
        var res = MD5(data.challenge + MD5(pass));
        this.respField.value = res;
        this.chalField.value = data.challenge;

        this.failed = false;
        this.locked = false;
        XPostAccount.checkComplete();
      }
    },

    setMessage: function(message) {
      if (this.statusField != null) {
        this.statusField.innerHTML=message;
      }
    },

    setError: function(message) {
      this.setMessage("<span style='color: red;'>" + message + "</span>");
    }

});

XPostAccount.xpostButtonUpdated = function () {
  var xpost_button = $("prop_xpost_check");
  var allunchecked = true;
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    XPostAccount.accounts[i].setDisabled(! xpost_button.checked);
    allunchecked = allunchecked && ! XPostAccount.accounts[i].checkboxTag.checked;
  }
  if (allunchecked && xpost_button.checked) {
    for (var i=0; i < XPostAccount.accounts.length; i++) {
      XPostAccount.accounts[i].checkboxTag.checked = true;
    }
  }
}

XPostAccount.xpostAcctUpdated = function () {
  var xpost_button = $("prop_xpost_check");
  var allunchecked = true;
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    allunchecked = allunchecked && ! XPostAccount.accounts[i].checkboxTag.checked;
  }
  xpost_button.checked = ! allunchecked;
  xpost_button.disabled = allunchecked;
}

XPostAccount.updateXpostFromJournal = function (user) {
  // only allow crossposts to the user's own journal
  var journal = document.updateForm.usejournal.value;
  var allowXpost = (journal == '' || user == journal);

  var xpost_button = $("prop_xpost_check");
  // preserve existing disabled state if xpost allowed
  var allunchecked = true;
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    allunchecked = allunchecked && ! XPostAccount.accounts[i].checkboxTag.checked;
  }
  xpost_button.disabled = (! allowXpost || allunchecked);
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    // preserve existing disabled state if xpost allowed
    XPostAccount.accounts[i].setDisabled(! allowXpost || (! xpost_button.checked && ! allunchecked));
  }

  var xpostdiv = $('xpostdiv');
  if (allowXpost) {
    XPostAccount.skipChecks = false;
    xpostdiv.style.display = 'block';
  } else {
    XPostAccount.skipChecks = true;
    xpostdiv.style.display = 'none';
  }
}

XPostAccount.confirmDelete = function (confMessage, xpostConfMessage) {
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

XPostAccount.loadAccounts = function () {
  XPostAccount.skipChecks = false;
  XPostAccount.accounts = new Array();
  var xpost_fields = DOM.getElementsByTagAndClassName(document, "input", "xpost_acct_checkbox") || [];
  for (var i=0;  i < xpost_fields.length; i++) {
    XPostAccount.accounts[i] = new XPostAccount(xpost_fields[i].id.substring(11));
  }
}

// add chal/resp auth to the update form if it exists
// this requires md5.js
XPostAccount.setUpXpostForm = function () {
  var updateForm = document.getElementById('updateForm');
  if ( ! updateForm ) return;

  DOM.addEventListener(updateForm, "submit", XPostAccount.xpostFormSubmitted.bindEventListener(updateForm));

  var domObjects = document.getElementsByTagName("input");
  var submitButtons = DOM.filterElementsByClassName(domObjects, "xpost_submit") || [];
  for (var i = 0; i < submitButtons.length; i++) {
    DOM.addEventListener(submitButtons[i], "click", XPostAccount.saveSubmitValue.bindEventListener(submitButtons[i]));
  }

  XPostAccount.loadAccounts();
  XPostAccount.xpostAcctUpdated();
  XPostAccount.updateXpostFromJournal(xpostUser);
}

/**
 *  Saves the value for the submit button selected.
 */
XPostAccount.saveSubmitValue = function () {
  XPostAccount.submitName = this.name;
}

// When the form is submitted, compute the challenge response and clear out the plaintext password field
XPostAccount.xpostFormSubmitted = function (evt) {
  var updateForm = evt.target;

  if (! updateForm)
    return true;

  if (! XPostAccount.skipChecks) {

    var preventDefault = false;
    for (var i = 0; i < XPostAccount.accounts.length; i++) {
      if (XPostAccount.accounts[i].doChallengeResponse()) {
        preventDefault = true;
      }
    }

    if (preventDefault) {
      XPostAccount.setSubmitDisabled(true);
      evt.stop();
      XPostAccount.checkComplete();
    }
  }
}

XPostAccount.checkComplete = function() {
  // check to see if all of our accounts are complete
  for (var i=0; i < XPostAccount.accounts.length; i++) {
    if (XPostAccount.accounts[i].locked) {
      return false;
    }
  }

  // all complete; see if there's an error.
  var acctErr = false;
  for (var i=0; i < XPostAccount.accounts.length; i++) {
    if (XPostAccount.accounts[i].failed) {
      acctErr = true;
    }
  }

  if (acctErr) {
    XPostAccount.doCancel();
  } else {
    XPostAccount.doFormSubmit();
  }
}

// called when a user manually aborts an auth request attempt.
XPostAccount.cancelSubmit = function() {
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    XPostAccount.accounts[i].setMessage("");
  }
  XPostAccount.doCancel();
}

// cancels the submit attempt; called either when the user hits cancel,
// or when one of the auth challenge requests fails
XPostAccount.doCancel = function() {
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    XPostAccount.accounts[i].clearSettings();
  }
  XPostAccount.setSubmitDisabled(false);
}

XPostAccount.doSpellcheck = function() {
  XPostAccount.skipChecks = true;
}

// does the actual form submit after all ofthe validation and auth requests
// have taken place
XPostAccount.doFormSubmit = function() {
  var updateForm = document.getElementById('updateForm');
  updateForm.onsubmit = null;
  // clear out the pw fields.
  for (var i = 0; i < XPostAccount.accounts.length; i++) {
    XPostAccount.accounts[i].clearPassword();
  }
  // we can't properly emulate pressing the submit button, so instead include
  // the value here.
  updateForm['submit_value'].value = XPostAccount.submitName;
  updateForm.submit();

  return false;
}

// sets the disabled status of all xpost_submit buttons.
XPostAccount.setSubmitDisabled = function(value) {
  var domObjects = document.getElementsByTagName("input");
  var submitButtons = DOM.filterElementsByClassName(domObjects, "xpost_submit") || [];
  for (var i = 0; i < submitButtons.length; i++) {
    submitButtons[i].disabled=value;
  }
}

LiveJournal.register_hook("page_load", XPostAccount.setUpXpostForm);
