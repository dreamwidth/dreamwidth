/*
  Tropospherical "What is Dreamwidth?" box

  Authors:
      Sophie Hamilton <sophie-dw@theblob.org>

  Copyright (c) 2009 by Dreamwidth Studios, LLC.

  This program is NOT free software or open-source; you can use it as an
  example of how to implement your own site-specific extensions to the
  Dreamwidth Studios open-source code, but you cannot use it on your site
  or redistribute it, with or without modifications.
*/

var nocreatejs = false;
var createboxmaincontent = "";

var loadfunction = function() {
    createboxmaincontent = document.getElementById('intro-create-content').innerHTML;
};

if (window.addEventListener) {
  window.addEventListener('load', loadfunction, false);
}
else if (window.attachEvent) {
  window.attachEvent('onload', loadfunction);
}
else {
  // be safe and disable the whole thing
  nocreatejs = true;
}

function displayCreateDiv(divname) {
    var content = "";
    var setfocuson = "";
    if (divname == "main") {
        content = createboxmaincontent;
    }
    else if (divname == "invite") {
        content = '\n \
        <h1>' + ml.joinheading + '</h1>\n \
        <p>' + ml.entercode + '</p>\n \
        <form method="get" action="' + siteroot + '/create" id="intro-create-form">\n \
            <input type="text" name="code" id="intro-create-invite" size="' + invitelength + '" maxlength="' + invitelength + '">\n \
            <input type="submit" value="' + ml.usecode + '" id="intro-create-submit">\n \
            <button type="button" id="intro-create-cancel" onClick="return displayCreateDiv(&quot;main&quot;);">' + ml.cancel + '</button>\n \
        </form>\n';
        setfocuson = "intro-create-invite";
    }
    document.getElementById("intro-create-content").innerHTML = content;
    if (setfocuson != "") { document.getElementById(setfocuson).focus(); }
    return false;
}
