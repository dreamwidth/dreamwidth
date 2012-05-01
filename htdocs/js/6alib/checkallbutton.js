/*
  This is a class which you can attach to a checkbox element.
  When that element is clicked, it will toggle every checkbox
  with a specified classname to be the same as the checkbox that was
  clicked.

  $Id: checkallbutton.js 69 2006-07-14 22:38:26Z mischa $
*/

CheckallButton = new Class(Object, {

  // opts:
  //  class => what class all of the checkboxes have
  //  button => the "check all" button element
  //  parent => [optional] only check boxes that are children of this element
  init: function (opts) {
    if ( CheckallButton.superClass.init ) {
        CheckallButton.superClass.init.apply(arguments);
    }

    this.button = opts["button"];
    this.className = opts["class"];
    this.parent = opts["parent"];
    this.attachEvents();
  },

  attachEvents: function () {
    if (!this.button || !this.className)
      return;

    DOM.addEventListener(this.button, "click", this.buttonClicked.bindEventListener(this));
  },

  buttonClicked: function (e) {
    if (!this.button || !this.className)
      return;

    var parent = this.parent;
    if (!parent)
      parent = document;

    var viewObjects = parent.getElementsByTagName("*");
    var boxes = DOM.filterElementsByClassName(viewObjects, this.className) || [];

    var checkallBox = this.button;

    for (var i = 0; i < boxes.length; i++) {
      var box = boxes[i];

      if (!box)
        continue;

      if (box.checked == checkallBox.checked) continue;

      // send a "clicked" event to the checkbox
      try {
          // w3c
          var evt = document.createEvent("MouseEvents");
          evt.initMouseEvent("click", true, false, window,
                             0, 0, 0, 0, 0, false, false, false, false, 0, null);
          box.dispatchEvent(evt);
      } catch (e) {
          try {
              // ie
              box.click();
          } catch (e2) { }
      }
    }
  }
});
