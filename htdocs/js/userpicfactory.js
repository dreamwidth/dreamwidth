var regsel;
var origW, origH;
var borderOn = false;

function onRegionChange (c) {
    updatePreview(c);
}

function onRegionChanged (c) {
    if (!c.x2 && !c.y2) return;

    updatePreview(c);

    document.getElementById("x1").value = c.x1;
    document.getElementById("y1").value = c.y1;
    document.getElementById("x2").value = c.x2;
    document.getElementById("y2").value = c.y2;
}

function updatePreview (c) {
    var w = c.x2 - c.x1, h = c.y2 - c.y1;
    if (w <= 0 || h <= 0) return;

    var upp = document.getElementById("userpicpreview");

    var newsizes = getSizedCoords(100, w, h);

    var zoomw = 1/(w/origW);
    var zoomh = 1/(h/origH);

    var nw = Math.floor(newsizes[0] * zoomw);
    var nh = Math.floor(newsizes[1] * zoomh);

    upp.width = nw;
    upp.height = nh;

    var zoomx = nw/origW;
    var zoomy = nh/origH;

    var preview = document.getElementById("prevcon");
    preview.style.width = Math.floor(newsizes[0]) + "px";
    preview.style.height = Math.floor(newsizes[1]) + "px";

    var nl = zoomx * c.x1;
    var nt = zoomy * c.y1;

    upp.style.marginLeft = "-" + Math.floor(nl) + "px";
    upp.style.marginTop = "-" + Math.floor(nt) + "px";
}

function setConstrain () {
    if(!regsel) return;
    var checked = document.getElementById("constrain").checked;
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

function toggleBorder () {
    var preview = document.getElementById("prevcon");
    if (borderOn) {
        preview.style.border = "1px solid transparent";
        borderOn = false;
    } else {
        preview.style.border = "1px solid #000000";
        borderOn = true;
    }
}

// This setup actually does need to be on the load event.
window.addEventListener("load", function () {
    var image = document.getElementById("userpic");
    if (!image || !image.naturalWidth || !image.naturalHeight) return;

    origW = image.naturalWidth;
    origH = image.naturalHeight;
    var container = document.getElementById("picContainer");
    var heightLimitedWidth = 75 * origW / origH;
    container.style.width = "min(" + origW + "px, " + heightLimitedWidth + "vh)";
    container.hidden = false;

    regsel = new ImageRegionSelect({src: image,
        onRegionChange:  onRegionChange,
        onRegionChanged: onRegionChanged
    });

    var insetX = Math.min(20, Math.floor(origW / 4));
    var insetY = Math.min(20, Math.floor(origH / 4));
    regsel.setTopLeft(insetX, insetY);
    regsel.setBottomRight(origW - insetX, origH - insetY);
    regsel.fireOnRegionChanged();

    regsel.keepSquare(false);

    document.getElementById("createbtn").disabled = false;

    document.getElementById("borderToggle").addEventListener("change", toggleBorder);
});
