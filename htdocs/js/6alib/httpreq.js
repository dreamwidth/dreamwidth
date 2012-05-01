var HTTPReq = new Object;

HTTPReq.create = function () {
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

// opts:
// url, onError, onData, method (GET or POST), data
// url: where to get/post to
// onError: callback on error
// onData: callback on data received
// method: HTTP method, GET by default
// data: what to send to the server (urlencoded)
HTTPReq.getJSON = function (opts) {
    var req = HTTPReq.create();
    if (! req) {
        if (opts.onError) opts.onError("noxmlhttprequest");
        return;
    }

    var state_callback = function () {
        if (req.readyState != 4) return;

        if (req.status != 200) {
            if (opts.onError) opts.onError(req.status ? "status: " + req.status : "no data");
            return;
        }

        var resObj;
        var e;
        try {
            eval("resObj = " + req.responseText + ";");
        } catch (e) {
        }

        if (e || ! resObj) {
            if (opts.onError)
                opts.onError("Error parsing response: \"" + req.responseText + "\"");

            return;
        }

        if (opts.onData)
            opts.onData(resObj);
    };

    req.onreadystatechange = state_callback;

    var method = opts.method || "GET";
    var data = opts.data || null;

    var url = opts.url;
    if (opts.method == "GET" && opts.data) {
        url += url.match(/\?/) ? "&" : "?";
        url += opts.data
    }

    url += url.match(/\?/) ? "&" : "?";
    url += "_rand=" + Math.random();

    req.open(method, url, true);

    // we should send null unless we're in a POST
    var to_send = null;

    if (method.toUpperCase() == "POST") {
        req.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        to_send = data;
    }

    req.send(to_send);
};

HTTPReq.formEncoded = function (vars) {
    var enc = [];
    var e;
    for (var key in vars) {
        try {
            if (!vars.hasOwnProperty(key))
                continue;
            enc.push(encodeURIComponent(key) + "=" + encodeURIComponent(vars[key]));
        } catch( e ) {}
    }
    return enc.join("&");

};

