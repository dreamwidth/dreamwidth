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
            this.imgEle = document.getElementById(opts.src);
        }

	var imgEle = this.imgEle;

        if (!imgEle) {
            this.error = "no image element";
            return;
        }

        this.width = imgEle.naturalWidth;
        this.height = imgEle.naturalHeight;

        this.keepSquareAspect = false;

        var containerDiv = this.containerDiv = document.createElement("div");
        containerDiv.style.position = "relative";
        containerDiv.style.cursor = "crosshair";
        containerDiv.style.touchAction = "none";
        containerDiv.style.userSelect = "none";

        imgEle.parentNode.replaceChild(containerDiv, imgEle);
        containerDiv.appendChild(imgEle);
        imgEle.draggable = false;
        imgEle.style.display = "block";
        imgEle.style.width = "100%";
        imgEle.style.height = "auto";

        // make the black and white dotted ants
        var makeAnts = function (parent, color) {
            var ele = document.createElement("div");
            ele.style.position = "absolute";
            ele.style.pointerEvents = "none";
            ele.style.boxSizing = "border-box";
            ele.style.border = "2px dashed " + color;
            parent.appendChild(ele);
            return ele;
        };
        this.ants1 = makeAnts(containerDiv, "white");
        this.ants2 = makeAnts(this.ants1, "black");
        this.ants2.style.inset = "0";

        containerDiv.addEventListener("pointerdown", this.startDrag.bind(this));
        containerDiv.addEventListener("pointermove", this.updateDrag.bind(this));
        containerDiv.addEventListener("pointerup", this.endDrag.bind(this));
        containerDiv.addEventListener("pointercancel", this.cancelDrag.bind(this));
        containerDiv.addEventListener("lostpointercapture", this.cancelDrag.bind(this));

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

        var pos = this.relPos(e);

        if (this.onClick) {
            this.onClick(pos);  // contains .x and .y
        }
    },

    relPos: function (event) {
        var bounds = this.containerDiv.getBoundingClientRect();
        return {
            x: Math.round((event.clientX - bounds.left) * this.width / bounds.width),
            y: Math.round((event.clientY - bounds.top) * this.height / bounds.height)
        };
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
            var xDirection = x >= this.tlx ? 1 : -1;
            var yDirection = y >= this.tly ? 1 : -1;
            var size = Math.min(
                Math.max(Math.abs(this.tlx - x), Math.abs(this.tly - y)),
                xDirection > 0 ? this.width - this.tlx : this.tlx,
                yDirection > 0 ? this.height - this.tly : this.tly
            );
            this.brx = this.tlx + xDirection * size;
            this.bry = this.tly + yDirection * size;
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
        var width = Math.abs(this.brx - this.tlx);
        var height = Math.abs(this.bry - this.tly);

        if (this.onRegionChange) {
            this.onRegionChange({
                x1: minx,
                y1: miny,
                x2: minx + width,
                y2: miny + height
            });
        }

        this.ants1.style.left = (100 * minx / this.width) + "%";
        this.ants1.style.top = (100 * miny / this.height) + "%";
        this.ants1.style.width = (100 * width / this.width) + "%";
        this.ants1.style.height = (100 * height / this.height) + "%";
    },

    keepSquare: function (keepSquareAspect) {
      this.keepSquareAspect = keepSquareAspect;
    },

    startDrag: function (event) {
        if (!this.enabled || this.drag || !event.isPrimary || event.button !== 0) return;
        this.drag = {
            pointerId: event.pointerId,
            clientX: event.clientX,
            clientY: event.clientY,
            anchor: this.relPos(event),
            previous: this.getSelectedRegion(),
            started: false
        };
        this.containerDiv.setPointerCapture(event.pointerId);
        event.preventDefault();
    },

    updateDrag: function (event) {
        var drag = this.drag;
        if (!drag || drag.pointerId !== event.pointerId) return;
        if (!drag.started) {
            if (Math.abs(event.clientX - drag.clientX) < 10 &&
                Math.abs(event.clientY - drag.clientY) < 10) return;
            drag.started = true;
            this.setTopLeft(drag.anchor.x, drag.anchor.y);
        }
        var point = this.relPos(event);
        this.setBottomRight(point.x, point.y, event.shiftKey || this.keepSquareAspect);
    },

    endDrag: function (event) {
        var drag = this.drag;
        if (!drag || drag.pointerId !== event.pointerId) return;
        this.updateDrag(event);
        if (!drag.started) {
            this.drag = null;
            this.handleClick(event);
        } else if (this.tlx === this.brx || this.tly === this.bry) {
            this.cancelDrag(event);
        } else {
            this.drag = null;
            this.sortPoints();
            this.fireOnRegionChanged();
        }
    },

    cancelDrag: function (event) {
        var drag = this.drag;
        if (!drag || drag.pointerId !== event.pointerId) return;
        this.drag = null;
        this.tlx = drag.previous.x1;
        this.tly = drag.previous.y1;
        this.brx = drag.previous.x2;
        this.bry = drag.previous.y2;
        this.adjustAnts();
    }
});
