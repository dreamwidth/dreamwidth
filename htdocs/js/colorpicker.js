
// A nutty little DHTML Color Picker
// By Martin Atkins aka Mart

var colpic_imgprefix = '/img';

// spawnPicker - create a picker window
function spawnPicker(dataobject, displayobject, des, altdisplay) {
    var wname = 'colorpick_' + Unique.id(); // Unique.id() replaced dataobject.name;
    var p = window.open('', wname, 'width=560,height=450');
    var d = p.document;

    // declare the data storage object in the picker's scope
    d.write('<script language="JavaScript"> var picker = new Object; </script>');

    var dat = p.picker;
    dat.dataobject = dataobject;
    dat.displayobject = displayobject;
    dat.current = ''+dataobject.value;
    dat.r = 0;
    dat.g = 0;
    dat.b = 0;
    dat.h = 0;
    dat.s = 0;
    dat.v = 0;

    // Copy some functions into the picker's scope so events can hit them
    p._HSVtoRGB = _HSVtoRGB;
    p._varstoform = _varstoform;
    p.setBGColor = setBGColor;
    p.findel = findel;

    d.write("<title>"+des+"</title>");
    _createInterface(p);
    d.close();

    findel('spectrum',d).onclick=function(evt) {
        if (! evt) { evt = p.event; }
        var x, y;
        if (evt.offsetX != null) {
            x = evt.offsetX;
            y = evt.offsetY;
        } else if (evt.pageX != null) {
            x = evt.pageX - 6;
            y = evt.pageY - 6;
        } else if (evt.clientX != null) {
            x = evt.clientX - 6;
            y = evt.clientY - 6;
        } else {
            p.alert('Your mouseclick could not be handled. Sorry.');
        }
//        var x = evt.offsetX || (evt.pageX ? evt.pageX - 6 : false) || (evt.clientX - 6);
//        var y = evt.offsetY || (evt.pageY ? evt.pageX - 6 : false) || (evt.clientY - 6);
        p.picker.h = Math.abs(p.Math.floor(x / 2) % 256);
        p.picker.s = Math.abs(y % 255);
        p._HSVtoRGB(p);
        p._varstoform(p);
    };
    findel('brightness',d).onclick=function(evt) {
        if (! evt) { evt = p.event; }
        p.picker.v = Math.abs((evt.offsetY || (evt.pageY - 6)) % 255);
        p._HSVtoRGB(p);
        p._varstoform(p);
    };

    findel('btnCancel',d).onclick=function() {
        p.close();
    };

    findel('btnOK',d).onclick=function() {
        dataobject.value=p.picker.current;
        p.setBGColor(displayobject,p.picker.current);
        if (altdisplay) {
            findel(altdisplay.obj).style[altdisplay.attrib] = p.picker.current;
        }
        p.close();
    };

    // The crosshair prevents clicks under it, so fake events for it
    findel('crosshair',d).onclick=function(evt) {
        if (! evt) { evt = p.event; }
        var fakeevt = new Object;
        fakeevt.pageX = evt.pageX;
        fakeevt.pageY = evt.pageY;
        fakeevt.clientX = evt.clientX;
        fakeevt.clientY = evt.clientY;
        findel('spectrum',p.document).onclick(fakeevt);
    };

    findel('fr',d).onchange=
    findel('fg',d).onchange=
    findel('fb',d).onchange=function() {
        dat.r = Math.abs(findel('fr',d).value % 256);
        dat.g = Math.abs(findel('fg',d).value % 256);
        dat.b = Math.abs(findel('fb',d).value % 256);

        _RGBtoHSV(p);
        _varstoform(p);
    }

    findel('fh',d).onchange=
    findel('fs',d).onchange=
    findel('fv',d).onchange=function() {
        dat.h = Math.abs(findel('fh',d).value % 255);
        dat.s = Math.abs(findel('fs',d).value % 256);
        dat.v = Math.abs(findel('fv',d).value % 256);

        _HSVtoRGB(p);
        _varstoform(p);
    }

    _setcolor(p,dat.current);

    return false;
}

function setBGColor(displayobject, colorstring) {
    displayobject.style.backgroundColor = colorstring;
}
function setBGColorWithId(displayobject, elementId) {
    displayobject.style.backgroundColor = document.getElementById(elementId).value;
}

function findel(id,doc) {
    if (! doc) {
        doc = document;
    }
    return doc.getElementById(id);
}

function _varstoform(p) {
    var d = p.document;
    var dat = p.picker;
    findel("fr",d).value=dat.r;
    findel("fg",d).value=dat.g;
    findel("fb",d).value=dat.b;
    findel("fh",d).value=dat.h;
    findel("fs",d).value=dat.s;
    findel("fv",d).value=dat.v;

    dat.current = "#"+_hex(dat.r)+
                    _hex(dat.g)+
                    _hex(dat.b);
    setBGColor(findel('preview',p.document),dat.current);

    _updatebrightnessgrad(p);
    _placeindicators(p);
}

function _updatebrightnessgrad(p) {
    var grad = findel("brightness",p.document);
    var fbc = new Object;
    fbc.h=p.picker.h;
    fbc.s=p.picker.s;
    fbc.v=255;
    _HSVtoRGB(p,fbc);
    gradclr = _hex(fbc.r)+
              _hex(fbc.g)+
              _hex(fbc.b);
    var newgradurl = "/palimg/colorpicker/longgrad.gif/pg00000000ff"+gradclr.toLowerCase();
    var oldgradurl = grad.src;
    if (oldgradurl != newgradurl) {
        grad.src = newgradurl;
    }
}
function _placeindicators(p) {
    var d = p.document;
    var pointer = findel('pointer',d);
    var crosshair = findel('crosshair',d);
    pointer.style.top = (p.picker.v + 3)+"px";

    crosshair.style.top = (p.picker.s - 1)+"px";
    crosshair.style.left = ((p.picker.h * 2) - 1)+"px";

    pointer.style.display = '';
    crosshair.style.display = '';
}

function _setcolor(p,htmlcolor) {
    p.picker.current = htmlcolor;

    var clrparts = _colorfromstring(htmlcolor);

    p.picker.r = clrparts[1];
    p.picker.g = clrparts[2];
    p.picker.b = clrparts[3];

    _RGBtoHSV(p);
    _varstoform(p);

}

function _RGBtoHSV(p,dat) {
    if (! dat) {
        dat = p.picker;
    }
    var r = dat.r;
    var g = dat.g;
    var b = dat.b;

    r = (r % 256) / 255;
    g = (g % 256) / 255;
    b = (b % 256) / 255;

    var min = 255, max = 0, h, s, v, hi, diff;

    var rgb = new Array(0,r,g,b);
    for (var i = 1; i <= 3; i++) {
        if (rgb[i] > max) {
            max = rgb[i];
            hi = i;
        }
        if (rgb[i] < min) {
            min = rgb[i];
        }
    }
    diff = max - min;
    v = max;
    if (max == 0) {
        s = 0;
    } else {
        s = diff / max;
    }
    if (s == 0) {
        h = 0;
    } else {
        switch (hi) {
            case 1:
                h = (g - b) / diff;
                break;
            case 2:
                h = 2 + (b - r) / diff;
                break;
            case 3:
                h = 4 + (r - g) / diff;
                break;
        }
        h = h / 6;
        if (h < 0) {
            h = h + 1;
        }
    }
    dat.h = Math.floor(h * 255);
    dat.s = Math.floor(s * 255);
    dat.v = Math.floor(v * 255);
}
function _HSVtoRGB(p,dat) {
    if (! dat) {
        dat = p.picker;
    }

    var h = dat.h;
    var s = dat.s;
    var v = dat.v;

    // If value is zero, return black.
    if (v == 0) {
       dat.r =
       dat.g =
       dat.b = 0;
       return;
    }

    // If there's no saturation, return a grey.
    if (s == 0) {
       dat.r =
       dat.g =
       dat.b = v;
       return;
    }

    h = (h % 255) / 255;
    s = (s % 256) / 255;
    v = (v % 256) / 255;

    var t, aa, bb, cc, r, g, b;
    
    t = p.Math.floor(h * 6); // Find which color's range we're in.
    f = (h * 6) - t;
    aa = v * (1 - s);
    bb = v * (1 - s * f);
    cc = v * (1 - (s * (1 - f)));

    switch (t) {
        case 0:
            r=v;
            g=cc;
            b=aa;
            break;
        case 1:
            r=bb;
            g=v;
            b=aa;
            break;
        case 2:
            r=aa;
            g=v;
            b=cc;
            break;
        case 3:
            r=aa;
            g=bb;
            b=v;
            break;
        case 4:
            r=cc;
            g=aa;
            b=v;
            break;
        default:
            r=v;
            g=aa;
            b=bb;
            break;
    }

    dat.r = p.Math.floor(r * 255) % 256;
    dat.g = p.Math.floor(g * 255) % 256;
    dat.b = p.Math.floor(b * 255) % 256;

    return;

}

// Fun with Regular Expressions
function _colorfromstring(strcolor) {
    var clrparts;
    strcolor = strcolor.toLowerCase();
    if ((clrparts = strcolor.match(
        /^#([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])$/
        )) != null) {
        for (var i=1; i<=3; i++) {
            clrparts[i] = parseInt(clrparts[i],16);
        }
        return clrparts;
    } else if ((clrparts = strcolor.match(
        /^rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)\s*$/
        )) != null) {
        for (var i=1; i<=3; i++) {
            if (clrparts[i]<0 || clrparts[i]>255) {
                return [0,0,0,0];
            }
            return clrparts;
        }
    }
    return [0,255,255,255];
}

function _hex(i) {
    var r = '';
    var h = new Array('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

    for (var x = 0; x < 32; x++) {
        if (Math.pow( 16, x + 1 ) > i)
            break;
    }

    for ( var y = x; y >= 0; y-- ) {
        var z = Math.pow( 16, y );
        r += h[ Math.floor ( i / z ) ];
        i = i % z;
    }

    r = ( r.length == 0 ) ? '0' : r;
    while ( r.length < 2 ) {
        r = '0' + r;
    }
    return r
}

function _createInterface(p) {
    var curclr = p.picker.current;
    var d = p.document;
    d.write('<style type="text/css">\n'+
            'body { border: 0; padding: 0; margin: 0; background: ButtonFace; color: ButtonText; font: caption; }\n'+
            'button { width: 5em; margin: 5px;}\n'+
            'img { border: 1px solid #000000; padding: 0; margin: 0; }\n'+
            '</style>');
    d.write('<table cellspacing="5" cellpadding="0" border="0">\n');
    d.write('<tr><td><img src="' + colpic_imgprefix + '/colorpicker/spectrum.png" '+
            'ismap width="512" height="256" id="spectrum"></td>\n');
    d.write('<td><img src="/palimg/colorpicker/longgrad.gif" '+
            'ismap width="25" height="256" id="brightness"></td></tr></table>\n');
    d.write('<form action="about:blank" method="GET" onsubmit="return false;">\n');
    d.write('<center><table cellspacing="5" cellpadding="0" border="0" width="95%">\n');
    d.write('<tr><td rowspan="3"><div id="preview" style="background-color: '+curclr+'; '+
            'border: 1px solid #000000; width: 50px; height: 50px; margin-left: 25%;">&nbsp;</div></td>\n');
    _writeControlRow(d,'Hue','fh');
    _writeControlRow(d,'Red','fr');
    d.write('</tr><tr>\n');
    _writeControlRow(d,'Saturation','fs');
    _writeControlRow(d,'Green','fg');
    d.write('</tr><tr>\n');
    _writeControlRow(d,'Lightness','fv');
    _writeControlRow(d,'Blue','fb');
    d.write('</tr></table></center>\n');
    d.write('<div style="text-align: center;">'+
            '<button id="btnOK">OK</button> <button id="btnCancel">Cancel</button>'+
            '</div>');
    d.write('</form>\n');
    d.write('<img style="position: absolute; display: none; border: 0; left: 0; top: 0;" id="crosshair" src="' + colpic_imgprefix + '/colorpicker/crosshair.gif">\n');
    d.write('<img style="position: absolute; display: none; border: 0; left: 552px; top: 0;" id="pointer" src="' + colpic_imgprefix + '/colorpicker/pointer.gif">\n');
}
function _writeControlRow(doc,caption,name) {
    doc.write('<td align="right" width="25%"><nobr><label accesskey="'+caption.substring(0,1)+'">'+caption+
              ': <input type="text" size="3" maxlength="3" name="'+name+'" id="'+name+'"></label></nobr></td>\n');
}

function colPic_set_imgprefix(prefix) {
    colpic_imgprefix = prefix;
}
