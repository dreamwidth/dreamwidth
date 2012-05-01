////// public interface:

function UploadTracker (formele, cb) {
    this.form      = formele;
    this.callback = cb;
    this.session  = UploadTracker._generateSession();
    this.stopped  = false;

    var action = this.form.action;
    if (action.match(/\bclient_up_sess=(\w+)/)) {
        action = action.replace(/\bclient_up_sess=(\w+)/, "client_up_sess=" + this.session);
    } else {
        action += (action.match(/\?/) ? "&" : "?");
        action += "client_up_sess=" + this.session;
    }
    this.form.action = action;

    this._startCheckStatus();
}


// method to stop tracking a form's upload status
UploadTracker.prototype.stopTracking = function () {
    this.stopped = true;
};


// private implementation details:
UploadTracker._XTR = function () {
    var xtr;
    var ex;

    if (typeof(XMLHttpRequest) != "undefined") {
        xtr = new XMLHttpRequest();
    } else {
        try {
            xtr = new ActiveXObject("Msxml2.XMLHTTP.4.0");
        } catch (ex) {
            try {
                xtr = new ActiveXObject("Msxml2.XMLHTTP");
            } catch (ex) {
            }
        }
    }

    // let me explain this.  Opera 8 does XMLHttpRequest, but not setRequestHeader.
    // no problem, we thought:  we'll test for setRequestHeader and if it's not present
    // then fall back to the old behavior (treat it as not working).  BUT --- IE6 won't
    // let you even test for setRequestHeader without throwing an exception (you need
    // to call .open on the .xtr first or something)
    try {
        if (xtr && ! xtr.setRequestHeader)
            xtr = null;
    } catch (ex) { }

    return xtr;
};


UploadTracker._generateSession = function () {
    var str = Math.random() + "";
    return curSession = str.replace(/[^\d]/, "");
};


UploadTracker.prototype._startCheckStatus = function () {
    var uptrack = this;
    if (uptrack.stopped) return true;

    var xtr = UploadTracker._XTR();
    if (!xtr) return;

    var callback = function () {
        if (xtr.readyState != 4) return;
        if (uptrack.stopped)     return;

        if (xtr.status == 200) {
            var val;
            eval("val = " + xtr.responseText + ";");
            uptrack.callback(val);
        }
        setTimeout(function () { uptrack._startCheckStatus(); }, 1000);
    };

    xtr.onreadystatechange = callback;
    xtr.open("GET", "/__upload_status?client_up_sess=" + uptrack.session + "&rand=" + Math.random());
    xtr.send(null);
}
