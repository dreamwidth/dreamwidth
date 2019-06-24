var regsel;
var borderOn = false;

function onRegionChange (c) {
    updatePreview(c);
}

function onRegionChanged (c) {
    if (!c.x2 && !c.y2) return;

    updatePreview(c);

    $("x1").value = c.x1;
    $("y1").value = c.y1;
    $("x2").value = c.x2;
    $("y2").value = c.y2;
}

function updatePreview (c) {
    var w = c.x2 - c.x1, h = c.y2 - c.y1;

    var upp = $("userpicpreview");

    var newsizes = getSizedCoords(100, w, h);

    var zoomw = 1/(w/origW);
    var zoomh = 1/(h/origH);

    var nw = Math.floor(newsizes[0] * zoomw);
    var nh = Math.floor(newsizes[1] * zoomh);

    upp.width = nw;
    upp.height = nh;

    var zoomx = nw/origW;
    var zoomy = nh/origH;

    $("prevcon").style.width = Math.floor(newsizes[0]) + "px";
    $("prevcon").style.height = Math.floor(newsizes[1]) + "px";

    var nl = zoomx * c.x1;
    var nt = zoomy * c.y1;

    upp.style.marginLeft = "-" + Math.floor(nl) + "px";
    upp.style.marginTop = "-" + Math.floor(nt) + "px";
}

function setConstrain () {
    if(!regsel) return;
    var checked = $('constrain').checked;
    regsel.keepSquare(checked);
    regsel.setBottomRight(regsel.brx, regsel.bry, checked);
    regsel.fireOnRegionChanged();
}

function getSizedCoords (newsize, w, h) {
    var nw, nh;

    if (h > w) {
        nh = newsize;
        nw = newsize * w/h;
    } else {
        nw = newsize;
        nh = newsize * h/w;
    }
    return [nw, nh];
}

function toggleBorder (evt) {
    if (borderOn) {
        $("prevcon").style.border = "1px solid transparent";
        borderOn = false;
    } else {
        $("prevcon").style.border = "1px solid #000000";
        borderOn = true;
    }
}

// This setup actually does need to be on the load event.
DOM.addEventListener(window, "load", function () {
    if (!origW || !origH)
        return;

    $("userpic").style.display = "";

    regsel = new ImageRegionSelect({src: $("userpic"),
        onRegionChange:  onRegionChange,
        onRegionChanged: onRegionChanged
    });

    var imageDimensions = getSizedCoords(scaledSizeMax, origW, origH);
    origW = imageDimensions[0];
    origH = imageDimensions[1];
    var w = origW;
    var h = origH;

    $("picContainer").style.width = w + "px";
    $("picContainer").style.height = h + "px";

    var x1 = 20, y1 = 20, x2 = w - 20, y2 = h - 20;
    regsel.setTopLeft(x1, y1);
    regsel.setBottomRight(x2, y2);
    regsel.fireOnRegionChanged();

    regsel.keepSquare(false);

    $("createbtn").disabled = false;

    DOM.addEventListener($("borderToggle"), "change", toggleBorder.bindEventListener());
});
