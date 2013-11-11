var Site;
if (! Site) Site = new Object();

// called by S2:
function setStyle (did, attr, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    if (de.style)
        de.style[attr] = val
}

// called by S2:
function setInner (did, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.innerHTML = val;
}

// called by S2:
function hideElement (did) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.style.display = 'none';
}

// called by S2:
function setAttr (did, attr, classname) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.setAttribute(attr, classname);
}

function getXTR () {
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
}

function positionedOffset(element) {
  var valueT = 0, valueL = 0;
  do {
    valueT += element.offsetTop  || 0;
    valueL += element.offsetLeft || 0;
    element = element.offsetParent;
    if (element) {
      if (element.tagName.toUpperCase() == 'BODY') break;
      var p = DOM.getStyle(element, 'position');
      if (p !== 'static') break;
    }
  } while (element);
  return {x: valueL, y:valueT};
}

// push new element 'ne' after sibling 'oe' old element
function addAfter (oe, ne) {
    if (oe.nextSibling) {
        oe.parentNode.insertBefore(ne, oe.nextSibling);
    } else {
        oe.parentNode.appendChild(ne);
    }
}

// hsv to rgb
// h, s, v = [0, 1), [0, 1], [0, 1]
// r, g, b = [0, 255], [0, 255], [0, 255]
function hsv_to_rgb (h, s, v)
{
    if (s == 0) {
	v *= 255;
	return [v,v,v];
    }

    h *= 6;
    var i = Math.floor(h);
    var f = h - i;
    var p = v * (1 - s);
    var q = v * (1 - s * f);
    var t = v * (1 - s * (1 - f));

    v = Math.floor(v * 255 + 0.5);
    t = Math.floor(t * 255 + 0.5);
    p = Math.floor(p * 255 + 0.5);
    q = Math.floor(q * 255 + 0.5);

    if (i == 0) return [v,t,p];
    if (i == 1) return [q,v,p];
    if (i == 2) return [p,v,t];
    if (i == 3) return [p,q,v];
    if (i == 4) return [t,p,v];
    return [v,p,q];
}

// stops the bubble
function stopBubble (e) {
    if (e.stopPropagation)
        e.stopPropagation();
    if ("cancelBubble" in e)
        e.cancelBubble = true;
}

// stops the bubble, as well as the default action
function stopEvent (e) {
    stopBubble(e);
    if (e.preventDefault)
        e.preventDefault();
    if ("returnValue" in e)
        e.returnValue = false;
    return false;
}

function scrollTop () {
    if (window.innerHeight)
        return window.pageYOffset;
    if (document.documentElement && document.documentElement.scrollTop)
        return document.documentElement.scrollTop;
    if (document.body)
        return document.body.scrollTop;
}

function scrollLeft () {
    if (window.innerWidth)
        return window.pageXOffset;
    if (document.documentElement && document.documentElement.scrollLeft)
        return document.documentElement.scrollLeft;
    if (document.body)
        return document.body.scrollLeft;
}

function getElementPos (obj)
{
    var pos = new Object();
    if (!obj)
        return null;

    var it;

    it = obj;
    pos.x = 0;
    if (it.offsetParent) {
	while (it.offsetParent) {
	    pos.x += it.offsetLeft;
	    it = it.offsetParent;
	}
    }
    else if (it.x)
	pos.x += it.x;

    it = obj;
    pos.y = 0;
    if (it.offsetParent) {
	while (it.offsetParent) {
	    pos.y += it.offsetTop;
	    it = it.offsetParent;
	}
    }
    else if (it.y)
	pos.y += it.y;

    return pos;
}

// returns the mouse position of the event, or failing that, the top-left
// of the event's target element.  (or the fallBack element, which takes
// precendence over the event's target element if specified)
function getEventPos (e, fallBack)
{
    var pos = { x:0, y:0 };

    if (!e) var e = window.event;
    if (e.pageX && e.pageY) {
        // useful case (relative to document)
        pos.x = e.pageX;
        pos.y = e.pageY;
    }
    else if (e.clientX && e.clientY) {
        // IE case (relative to viewport, so need scroll info)
        pos.x = e.clientX + scrollLeft();
        pos.y = e.clientY + scrollTop();
    } else {
        var targ = fallBack || getTarget(e);
        var pos = getElementPos(targ);
    }
    return pos;
}

var curPopup = null;
var curPopup_id = 0;

function killPopup () {
    if (!curPopup)
        return true;

    var popup = curPopup;
    curPopup = null;

    var opp = 1.0;

    var fade = function () {
        opp -= 0.15;

        if (opp <= 0.1) {
            popup.parentNode.removeChild(popup);
        } else {
            popup.style.filter = "alpha(opacity=" + Math.floor(opp * 100) + ")";
            popup.style.opacity = opp;
            window.setTimeout(fade, 20);
        }
    };
    fade();

    return true;
}

var pendingReqs = new Object ();

function deleteComment (ditemid) {

    var hasopt = function (opt) {
        var el = document.getElementById("ljpopdel" + ditemid + opt);
        if (!el) return false;
        if (el.checked) return true;
        return false;
    };
    var opt_delthread = hasopt("thread");
    var opt_ban = hasopt("ban");
    var opt_spam = hasopt("spam");

    killPopup();

    var todel = document.getElementById("cmt" + ditemid);

    var col = 0;
    var pulse = 0;
    var is_deleted = 0;
    var is_error = 0;

    var xtr = getXTR();
    if (! xtr) {
        alert("JS_ASSERT: no xtr now, but earlier?");
        return false;
    }
    pendingReqs[ditemid] = xtr;

    var state_callback = function () {
        if (xtr.readyState != 4)
             return;

        if (xtr.status == 200) {
            var val = eval(xtr.responseText);
            is_deleted = val;
            if (! is_deleted) is_error = 1;
        } else {
            alert("Error contacting server to delete comment.");
            is_error = 1;
        }
    };

    var error_callback = function () {
        alert("Error deleting " + ditemid);
        is_error = 1;
    };

    xtr.onreadystatechange = state_callback;
    // Set to LJ_cmtinfo[ditemid].postedin on /comments/posted if comment was posted in a journal other than the user's
    var posted_in = LJ_cmtinfo[ditemid].postedin || LJ_cmtinfo.journal;
    xtr.open("POST", "/" + LJ_cmtinfo.journal + "/__rpc_delcomment?mode=js&journal=" + posted_in + "&id=" + ditemid, true); 
    var postdata = "confirm=1";
    if (opt_ban) postdata += "&ban=1";
    if (opt_spam) postdata += "&spam=1";
    if (opt_delthread) postdata += "&delthread=1";
    if (LJ_cmtinfo.form_auth) postdata += "&lj_form_auth=" + LJ_cmtinfo.form_auth;

    xtr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xtr.send(postdata);

    var flash = function () {
        var rgb = hsv_to_rgb(0, Math.cos((pulse + 1) / 2), 1);
        pulse += 3.14159 / 5;
        var color = "rgb(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ")";

        todel.style.border = "2px solid " + color;
        if (is_error) {
            todel.style.border = "";
            // and let timer expire
        } else if (is_deleted) {
            removeComment(ditemid, opt_delthread);
        } else {
            window.setTimeout(flash, 50);
        }
    };

    window.setTimeout(flash, 5);
}

function removeComment (ditemid, killChildren) {
    var todel = document.getElementById("cmt" + ditemid);
    if (todel) {
        todel.style.display = 'none';

        var userhook = window["userhook_delete_comment_ARG"];
        if (userhook)
            userhook(ditemid);
    }
    if (killChildren) {
        var com = LJ_cmtinfo ? LJ_cmtinfo[ditemid] : null;
        for (var i = 0; i < com.rc.length; i++) {
            removeComment(com.rc[i], true);
        }
    }
}

function docClicked (e) {
  if (curPopup)
    killPopup();

  // we didn't handle anything, who are we kidding
}

function createDeleteFunction (ae, dItemid) {
    return function (e) {
        if (!e) e = window.event;
        var FS = arguments.callee;

        var finalHeight = 100;

        if (e.shiftKey || (curPopup && curPopup_id != dItemid)) {
            killPopup();
        }

        var doIT = 0;
        // immediately delete on shift key
        if (e.shiftKey) {
            doIT = 1;
        } else {
            if (! LJ_cmtinfo)
                return true;

            var com = LJ_cmtinfo[dItemid];
            var remoteUser = LJ_cmtinfo["remote"];
            if (!com || !remoteUser)
                return true;
            var canAdmin = LJ_cmtinfo["canAdmin"];
            var canSpam = LJ_cmtinfo["canSpam"];

            var clickTarget = getTarget(e);

            var pos = getEventPos(e);
            var pos_offset = positionedOffset(ae)
            var diff_x = DOM.findPosX(ae) - pos_offset.x
            var diff_y = DOM.findPosY(ae) - pos_offset.y

            var lx = pos.x - diff_x + 5 - 250;
            if (lx < 5) lx = 5;
            var de;

            if (curPopup && curPopup_id == dItemid) {
                de = curPopup;
                de.style.left = lx + "px";
                de.style.top = (pos.y - diff_y + 5) + "px";
                return stopEvent(e);
            }

            de = document.createElement("div");
            de.style.textAlign = "left";
            de.className = 'cmtmanage';
            de.style.height = "10px";
            de.style.overflow = "hidden";
            de.style.position = "absolute";
            de.style.left = lx + "px";
            de.style.top = (pos.y - diff_y + 5) + "px";
            de.style.width = "250px";
            de.style.zIndex = 3;
            regEvent(de, "click", function (e) {
                e = e || window.event;
                stopBubble(e);
                return true;
            });

            var inHTML = "<form style='display: inline' id='ljdelopts" + dItemid + "'><span style='font-face: Arial; font-size: 8pt'><b>Delete comment?</b><br />";
            var lbl;
            if (remoteUser != "" && com.u != "" && com.u != remoteUser && canAdmin) {
                lbl = "ljpopdel" + dItemid + "ban";
                inHTML += "<input type='checkbox' value='ban' id='" + lbl + "'> <label for='" + lbl + "'>Ban <b>" + com.u + "</b> from commenting</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (remoteUser != "" && remoteUser != com.u && canSpam) {
                lbl = "ljpopdel" + dItemid + "spam";
                inHTML += "<input type='checkbox' value='spam' id='" + lbl + "'> <label for='" + lbl + "'>Mark this comment as spam</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (com.rc && com.rc.length && canAdmin) {
                lbl = "ljpopdel" + dItemid + "thread";
                inHTML += "<input type='checkbox' value='thread' id='" + lbl + "'> <label for='" + lbl + "'>Delete thread (all subcomments)</label><br />";
            } else {
                finalHeight -= 15;
            }
            inHTML += "<input type='button' value='Delete' onclick='deleteComment(" + dItemid + ");' /> <input type='button' value='Cancel' onclick='killPopup()' /></span><br /><span style='font-face: Arial; font-size: 8pt'><i>shift-click to delete without options</i></span></form>";
            de.innerHTML = inHTML;

            // we do this so keyboard tab order is correct:
            addAfter(ae, de);

            curPopup = de;
            curPopup_id = dItemid;

            var height = 10;
            var grow = function () {
                height += 7;
                if (height > finalHeight) {
                    de.style.height = null;
                    de.style.filter = "";
                    de.style.opacity = 1.0;
                } else {
                    de.style.height = height + "px";
                    window.setTimeout(grow, 20);
                }
            };
            grow();

        }

        if (doIT) {
            deleteComment(dItemid);
        }

        return stopEvent(e);
    }
}

function poofAt (pos) {
    var de = document.createElement("div");
    de.style.position = "absolute";
    de.style.background = "#FFF";
    de.style.overflow = "hidden";
    var opp = 1.0;

    var top = pos.y;
    var left = pos.x;
    var width = 5;
    var height = 5;
    document.body.appendChild(de);

    var fade = function () {
        opp -= 0.15;
        width += 10;
        height += 10;
        top -= 5;
        left -= 5;

        if (opp <= 0.1) {
            de.parentNode.removeChild(de);
        } else {
            de.style.left = left + "px";
            de.style.top = top + "px";
            de.style.height = height + "px";
            de.style.width = width + "px";
            de.style.filter = "alpha(opacity=" + Math.floor(opp * 100) + ")";
            de.style.opacity = opp;
            window.setTimeout(fade, 20);
        }
    };
    fade();
}

function getTarget (ev) {
    var target;
    if (ev.target)
        target = ev.target;
    else if (ev.srcElement)
        target = ev.srcElement;

    // Safari bug:
    if (target && target.nodeType == 3)
        target = target.parentNode;

    return target;
}

function updateLink (ae, resObj, clickTarget) {
    ae.href = resObj.newurl;
    var userhook = window["userhook_" + resObj.mode + "_comment_ARG"];
    var did_something = 0;

    if (clickTarget && clickTarget.src && clickTarget.src == resObj.oldimage) {
        clickTarget.setAttribute( 'title', resObj.newalt );
        clickTarget.src = resObj.newimage;
        did_something = 1;
    };

    if ( ae && typeof clickTarget == "undefined" ) {
        ae.innerHTML = resObj.newalt;
        did_something = 1;
    }

    if (userhook) {
        userhook(resObj.id);
        did_something = 1;
    }

    // if all else fails, at least remove the link so they're not as confused
    if (! did_something) {
        if (ae && ae.style)
            ae.style.display = 'none';
        if (clickTarget && clickTarget.style)
            clickTarget.style.display = 'none';
    }

}

var tsInProg = new Object();  // dict of { ditemid => 1 }
function createModerationFunction (ae, dItemid) {
    return function (e) {
        if (!e) e = window.event;

        if (tsInProg[dItemid])
            return stopEvent(e);
        tsInProg[dItemid] = 1;

        var clickTarget = getTarget(e);

        var imgTarget;
        var imgs = ae.getElementsByTagName("img");
        if (imgs.length)
            imgTarget = imgs[0]

        if (! clickTarget || typeof(clickTarget) != "object")
            return true;

        var clickPos = getEventPos(e);

        var de = document.createElement("img");
        de.style.position = "absolute";
        de.width = 17;
        de.height = 17;
        de.src = Site.imgprefix + "/hourglass.gif";
        de.style.top = (clickPos.y - 8) + "px";
        de.style.left = (clickPos.x - 8) + "px";
        document.body.appendChild(de);

        var xtr = getXTR();
        var state_callback = function () {
            if (xtr.readyState != 4) return;

            document.body.removeChild(de);
            var rpcRes;

            if (xtr.status == 200) {
                var resObj = eval("resObj = " + xtr.responseText + ";");
                if (resObj) {
                    poofAt(clickPos);
                    updateLink(ae, resObj, imgTarget);
                    tsInProg[dItemid] = 0;

                } else {
                    tsInProg[dItemid] = 0;
                }

            } else {
                alert("Error contacting server.");
                tsInProg[dItemid] = 0;
            }
        };

        xtr.onreadystatechange = state_callback;

        var postUrl = ae.href.replace(/.+talkscreen/, "/" + LJ_cmtinfo.journal + "/__rpc_talkscreen");

        //var postUrl = ae.href;
        xtr.open("POST", postUrl + "&jsmode=1", true);

        var postdata = "confirm=Y&lj_form_auth=" + LJ_cmtinfo.form_auth;

        xtr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xtr.send(postdata);

        return stopEvent(e);
    };
}

function setupAjax () {
    var ct = document.links.length;
    for (var i=0; i<ct; i++) {
        var ae = document.links[i];
        if (ae.href.indexOf("talkscreen") != -1) {
            ae.onclick = createModerationFunction(ae, dItemid);

        } else if (ae.href.indexOf("delcomment") != -1) {

            var findIDre = /id=(\d+)/;
            var reMatch = findIDre.exec(ae.href);
            if (! reMatch) return true;

            var dItemid = reMatch[1];
            var todel = document.getElementById("cmt" + dItemid);
            if (! todel) return true;

            if (LJ_cmtinfo && LJ_cmtinfo.disableInlineDelete) continue;

            ae.onclick = createDeleteFunction(ae, dItemid);
        }

    }
}

function regEvent (target, evt, func) {
    if (! target) return;
    if (target.attachEvent)
        target.attachEvent("on"+evt, func);
    if (target.addEventListener)
        target.addEventListener(evt, func, false);
}

if (document.getElementById && getXTR()) {
       regEvent(window, "load", setupAjax);
	regEvent(document, "click", docClicked);
        document.write("<style> div.cmtmanage { color: #000; background: #e0e0e0; border: 2px solid #000; padding: 3px; }</style>");
}
