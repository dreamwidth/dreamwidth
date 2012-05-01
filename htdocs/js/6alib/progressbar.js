/*
  Javascript progress bar class

  To use: create a div you wish to be the progress bar, and
  instantiate a ProgressBar with the div element

  To style it you need to define several classes, a container class which
  defines the progress bar container, an indefinite class which has your
  "barber shop" background tile, and an overlay class which defines the look
  of the progress bar.

  requires core.js, dom.js
*/

ProgressBar = new Class ( Object, {
  init: function (pbar) {
    this.max = 0;
    this.value = 0;
    this.pbar = pbar; // container
    this.containerClassName = "";
    this.indefiniteClassName = "";
    this.overlayClassName = "";
    this.indefinite = 1;
    this.overlay = null;
    this.update();
  },

  setContainerClassName: function (classname) {
    if (!this.pbar)
      return;

    DOM.removeClassName(this.pbar, classname);
    this.containerClassName = classname;
    this.update();
  },

  setIndefiniteClassName: function (classname) {
    this.indefiniteClassName = classname;
    this.update();
  },

  setOverlayClassName: function (classname) {
    this.overlayClassName = classname;
    this.update();
  },

  setWidth: function (w) {
    if (!this.pbar)
      return;

    if (w+0 == w)
      DOM.setWidth(this.pbar, w);
    else
      this.pbar.style.width = w;
  },

  setMax: function (max) {
    this.max = max;
    this.update();
  },

  setValue: function (value) {
    this.value = value;
    this.indefinite = false;
    this.update();
  },

  setIndefinite: function (indef) {
    this.indefinite = indef;
    this.update();
  },

  max: function () {
    return this.max;
  },

  value: function () {
    return this.value;
  },

  hide: function () {
    if (!this.pbar)
      return;

    this.pbar.style.display = "none";
  },

  show: function () {
    if (!this.pbar)
      return;

    this.pbar.style.display = "";
  },

  update: function () {
    if (!this.pbar)
      return;

    DOM.addClassName(this.pbar, this.containerClassName);

    // definite or indefinite bar?
    if (this.indefinite || this.value < 0) {
      // barber shop
      // is there an overlay? if so, kill it
      if (this.overlay) {
        this.overlay.parentNode.removeChild(this.overlay);
        this.overlay = null;
      }

      // set the indefinite class
      DOM.addClassName(this.pbar, this.indefiniteClassName);
      return;
    }

    DOM.removeClassName(this.pbar, this.indefiniteClassName);

    var overlay = this.overlay;

    // does the progress bar container have the overlay?
    if (!this.overlay) {
      overlay = document.createElement("div");

      if (!overlay)
        return;

      this.pbar.appendChild(overlay);
    }

    DOM.addClassName(overlay, this.overlayClassName);

    var dim = DOM.getAbsoluteDimensions(this.pbar);
    var pct = this.value/this.max;
    var oldWidth = dim.absoluteRight - dim.absoluteLeft;
    var newWidth = oldWidth * pct;
    DOM.setWidth(overlay, newWidth);
    DOM.setHeight(overlay, dim.absoluteBottom - dim.absoluteTop);

    this.overlay = overlay;
  }
});
