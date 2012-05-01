// LiveJournal javascript standard interface routines

// create a little animated hourglass at (x,y) with a unique-ish ID
// returns the element created
Hourglass = new Class( Object, {
  init: function(widget, classname) {
    this.ele = document.createElement("img");
    if (!this.ele) return;

    var imgprefix = Site ? Site.imgprefix : '';

    this.ele.src = imgprefix ? imgprefix + "/hourglass.gif" : "/img/hourglass.gif";
    this.ele.style.position = "absolute";

    DOM.addClassName(this.ele, classname);

    if (widget)
      this.hourglass_at_widget(widget);
  },

  hourglass_at: function (x, y) {
    this.ele.width = 17;
    this.ele.height = 17;
    this.ele.style.top = (y - 8) + "px";
    this.ele.style.left = (x - 8) + "px";

    // unique ID
    this.ele.id = "lj_hourglass" + x + "." + y;

    document.body.appendChild(this.ele);
  },

  add_class_name: function (classname) {
      if (this.ele)
      DOM.addClassName(this.ele, classname);
  },

  hourglass_at_widget: function (widget) {
    var dim = DOM.getAbsoluteDimensions(widget);
    var x = dim.absoluteLeft;
    var y = dim.absoluteTop;
    var w = dim.absoluteRight - x;
    var h = dim.absoluteBottom - y;
    if (w && h) {
      x += w/2;
      y += h/2;
    }
    this.hourglass_at(x, y);
  },

  hide: function () {
    if (this.ele) {
      try {
        document.body.removeChild(this.ele);
      } catch (e) {}
    }
  }

} );
