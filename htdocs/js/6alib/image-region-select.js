/*
  Copyright (c) 2006, Six Apart, Ltd.
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met:

  * Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the following disclaimer
  in the documentation and/or other materials provided with the
  distribution.

  * Neither the name of "Six Apart" nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

/* ***************************************************************************

  Class: ImageRegionSelect

  About:

  Constructor:

*************************************************************************** */

var ImageRegionSelect = new Class( Object, {
    init: function () {
        var self = this;

	if (arguments.length != 1) {
            alert("Bogus args");
            return;
        }

	var opts = arguments[0];
        ["onRegionChange",
         "onRegionChanged",
         "onClick",
         "onDebug",
         ].forEach(function (v) {
            self[v] = opts[v];
        });

        if (opts.src && typeof opts.src == 'object') {
            this.imgEle = opts.src;
        } else {
            this.imgEle = $(opts.src);
        }

	var imgEle = this.imgEle;

        if (!imgEle) {
            this.error = "no image element";
            return;
        }

        var w = imgEle.width;
        var h = imgEle.height;
        this.width = w;
        this.height = h;

        this.keepSquareAspect = false;

        var containerDiv = this.containerDiv = document.createElement("div");
        //containerDiv.style.border = "2px solid red";
        containerDiv.style.width = w + "px";
        containerDiv.style.height = h + "px";
        containerDiv.style.background = "yellow";
        containerDiv.style.position = "relative";
        containerDiv.style.cursor = "crosshair";

        imgEle.parentNode.replaceChild(containerDiv, imgEle);
        containerDiv.appendChild(imgEle);
        imgEle.style.position = "absolute";
        imgEle.style.top = "0px";
        imgEle.style.left = "0px";

        // IE-specific attribute to disable the on-image toolbar:
        imgEle.setAttribute("galleryimg", "no");

        // make the black and white dotted ants
        var makeAnts = function (color) {
            var ele = document.createElement("div");
            ele.style.position = "absolute";
            ele.style.top  = "0px";
            ele.style.left = "0px";
            ele.style.width = w + "px";
            ele.style.height = h + "px";
            ele.style.border = "2px dashed " + color;
            containerDiv.appendChild(ele);
            return ele;
        };
        this.ants1 = makeAnts("white");
        this.ants2 = makeAnts("black");

        var coverNode = document.createElement("div");
        coverNode.style.width = w + "px";
        coverNode.style.height = h + "px";
        //coverNode.style.border = "2px solid green";
        coverNode.style.position = "absolute";
        coverNode.style.top = "0px";
        coverNode.style.left = "0px";
        containerDiv.appendChild(coverNode);

        // setup event handlers
        var eatEvent = function (e) {
            e = Event.prep(e);
            return e.stop();
        };
        imgEle.onmousemove       = eatEvent;
        containerDiv.onmousemove = eatEvent;
        containerDiv.onmousedown = ImageRegionSelect.containerMouseDown.bindEventListener(this);

        this.setEnabled(true);
        this.reset();
    },

    fireOnRegionChanged: function () {
        if (!this.onRegionChanged) return;
        this.onRegionChanged(this.getSelectedRegion());
    },

    getSelectedRegion: function () {
        return {
            x1: this.tlx,
            y1: this.tly,
            x2: this.brx,
            y2: this.bry
        };
    },

    setEnabled: function (onoff) {
        this.enabled = onoff;
        [this.ants1, this.ants2].forEach(function (ele) { ele.style.display = onoff ? "block" : "none"; });
    },

    dbg: function (msg) {
	if (this.onDebug)
           this.onDebug(msg);
    },

    reset: function () {
        this.tlx = 0;
        this.brx = this.width;
        this.tly = 0;
        this.bry = this.height;
        this.adjustAnts();
        this.fireOnRegionChanged();
    },

    handleClick: function (e) {
        if (! this.enabled) return;

        e = Event.prep(e);
        var pos = this.relPos(e);

        if (this.onClick) {
            this.onClick(pos);  // contains .x and .y
        }
    },

    relPos: function (e) {
        e = Event.prep(e);
        var loc    = DOM.getAbsoluteCursorPosition(e);
        var ctrDim = DOM.getAbsoluteDimensions(this.containerDiv);
        return {x: loc.x - ctrDim.absoluteLeft,
                       y: loc.y - ctrDim.absoluteTop };
    },

    sortPoints: function () {
        var t;
        if (this.tlx > this.brx) {
            t = this.tlx;
            this.tlx = this.brx;
            this.brx = t;
        }

        if (this.tly > this.bry) {
            t = this.tly;
            this.tly = this.bry;
            this.bry = t;
        }
    },

    setTopLeft: function (x, y) {
        if (! this.enabled) return;

        x = max(0, min(x, this.width));
        y = max(0, min(y, this.height));
        this.tlx = x;
        this.tly = y;
        this.adjustAnts();
    },

    setBottomRight: function (x, y, isShift) {
        if (! this.enabled) return;

        x = max(0, min(x, this.width));
        y = max(0, min(y, this.height));

        if (isShift) {
            var dx = Math.abs(this.tlx - x);
            var dy = Math.abs(this.tly - y);
            var d = max(dx, dy);

            this.brx = min(this.tlx + ((x > this.tlx) ? 1 : -1) * d, this.width);
            this.bry = min(this.tly + ((y > this.tly) ? 1 : -1) * d, this.height);
            if (this.brx < 0) this.brx = 0;
            if (this.bry < 0) this.bry = 0;
        } else {
            this.brx = x;
            this.bry = y;
        }
        this.adjustAnts();
    },

    adjustAnts: function () {
        if (! this.enabled) return;

        var minx = min(this.tlx, this.brx);
        var miny = min(this.tly, this.bry);
        var width = max(4, Math.abs(this.brx - this.tlx));
        var height = max(4, Math.abs(this.bry - this.tly));

        if (this.onRegionChange) {
            this.onRegionChange({
                x1: minx,
                y1: miny,
                x2: minx + width,
                y2: miny + height
            });
        }

        this.ants1.style.left = minx + "px";
        this.ants1.style.top = miny + "px";
        this.ants1.style.width = width + "px";
        this.ants1.style.height = height + "px";

        this.ants2.style.left = (minx + 2) + "px";
        this.ants2.style.top = (miny + 2) + "px";
        this.ants2.style.width = (width - 4) + "px";
        this.ants2.style.height = (height - 4) + "px";
    },

    keepSquare: function (keepSquareAspect) {
      this.keepSquareAspect = keepSquareAspect;
    },

    dummy: 1
});

ImageRegionSelect.containerMouseDown = function (e) {
    //this.dbg("onKeyDown, code="+code+", shift="+e.shiftKey);

    e = Event.prep(e);
    var dpos = this.relPos(e);
    var self = this;

    var ctrDiv = this.containerDiv;
    var did_topleft = false;
    var imgEle = this.imgEle;

    var isClose = function (pos) {
        // this looks stupid, but it's the only way that'll work:  I tried
        // to just return the expression in the if block, but it wasn't working.
        // not sure what I'm not understanding here.  --brad
        if (Math.abs(pos.x - dpos.x) < 10 &&
            Math.abs(pos.y - dpos.y) < 10) {
                return true;
            } else {
                return false;
            }
    };


    // IE's onmousemove event comes in from a different place than the mousedown/up.
    // whatever.
    imgEle.onmousemove = ctrDiv.onmousemove = function (emove) {
        emove = Event.prep(emove);
        var mpos = self.relPos(emove);

        var isShift = emove.shiftKey || self.keepSquareAspect;
        //log(trackerPlane + ":  mouse move");

        if (did_topleft) {
            self.setBottomRight(mpos.x, mpos.y, isShift);
        } else if (! isClose(mpos)) {
            did_topleft = true;
            self.setTopLeft(dpos.x, dpos.y);
            self.setBottomRight(mpos.x, mpos.y, isShift);
        }

        return emove.stop();
    };

    ctrDiv.onmouseup = function (eup) {
        eup = Event.prep(eup);
        var upos = self.relPos(eup);

        ctrDiv.onmousemove = null;
        ctrDiv.onmouseup   = null;
        imgEle.onmousemove = null;

        if (!did_topleft) {
            self.handleClick(eup);
            return eup.stop();
        }

        self.sortPoints();

        self.fireOnRegionChanged();

        return eup.stop();

    };

    return e.stop();
};
