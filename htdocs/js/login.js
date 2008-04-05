// add chal/resp auth to the "login" form if it exists
// this requires md5.js
LiveJournal.setUpLoginForm = function () {
    var loginForms = DOM.getElementsByTagAndClassName(document, "form", "lj_login_form") || [];

    for (var i=0; i<loginForms.length; i++) {
        var loginForm = loginForms[i];
        DOM.addEventListener(loginForm, "submit", LiveJournal.loginFormSubmitted.bindEventListener(loginForm));
    }
}

// When the login form is submitted, compute the challenge response and clear out the plaintext password field
LiveJournal.loginFormSubmitted = function (evt) {
    var loginform = evt.target;
    if (! loginform)
        return true;

    var chal_field = LiveJournal.loginFormGetField(loginform, "lj_login_chal");
    var resp_field = LiveJournal.loginFormGetField(loginform, "lj_login_response");
    var pass_field = LiveJournal.loginFormGetField(loginform, "lj_login_password");

    if (! chal_field || ! resp_field || ! pass_field)
        return true;

    var pass = pass_field.value;
    var chal = chal_field.value;
    var res = MD5(chal + MD5(pass));
    resp_field.value = res;
    pass_field.value = "";  // dont send clear-text password!
    return true;
}

LiveJournal.loginFormGetField = function (loginform, field) {
    var formChildren = loginform.getElementsByTagName("input");
    var loginFields = DOM.filterElementsByClassName(formChildren, field);
    return loginFields[0];
};

LiveJournal.register_hook("page_load", LiveJournal.setUpLoginForm);
