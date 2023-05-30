LJ_IPPU = new Class ( IPPU, {
  init: function(title) {
    if (!title)
      title = "";

    if ( LJ_IPPU.superClass.init )
        LJ_IPPU.superClass.init.apply(this, []);

    this.uniqId = this.generateUniqId();
    this.cancelThisFunc = this.cancel.bind(this);

    this.setTitle(title);
    this.setTitlebar(true);
    this.setTitlebarClass("lj_ippu_titlebar");

    this.addClass("lj_ippu");
    this.setAutoCenterCallback(IPPU.center);
    this.setDimensions(400, "auto");
    //this.setOverflow("hidden");

    this.setFixedPosition(true);
    this.setClickToClose(true);
    this.setAutoHideSelects(true);
 },

  setTitle: function (title) {
    var titlebarContent = "\
      <div style='float:right; padding-right: 8px'>" +
      "<img src='" + Site.imgprefix + "/CloseButton.gif' width='15' height='15' id='" + this.uniqId + "_cancel' /></div>" + title;

    LJ_IPPU.superClass.setTitle.apply(this, [titlebarContent]);
    
      
  },

  generateUniqId: function() {
    var theDate = new Date();
    return "lj_ippu_" + theDate.getHours() + theDate.getMinutes() + theDate.getMilliseconds();
  },

  show: function() {
    LJ_IPPU.superClass.show.apply(this);
    var setupCallback = this.setup_lj_ippu.bind(this);
    window.setTimeout(setupCallback, 300);
  },

  setup_lj_ippu: function (evt) {
    var cancelCallback = this.cancelThisFunc;
   //DOM.addEventListener($(this.uniqId + "_cancel"), "click", cancelCallback, true);
   document.getElementById(this.uniqId + "_cancel").onclick = function(){
	    cancelCallback();
	    
    };
  },

  hide: function() {
    LJ_IPPU.superClass.hide.apply(this);
  }
} );

// Class method to show a popup to show a note to the user
// note = message to show
// underele = element to display the note underneath
LJ_IPPU.showNote = function (note, underele, timeout, style) {
    var noteElement = document.createElement("div");
    noteElement.innerHTML = note;

    return LJ_IPPU.showNoteElement(noteElement, underele, timeout, style);
};

LJ_IPPU.showErrorNote = function (note, underele, timeout) {
    return LJ_IPPU.showNote(note, underele, timeout, "ErrorNote");
};

LJ_IPPU.showNoteElement = function (noteEle, underele, timeout, style) {
    var notePopup = new IPPU();
    notePopup.init();

    var inner = document.createElement("div");
    DOM.addClassName(inner, "Inner");
    inner.appendChild(noteEle);
    notePopup.setContentElement(inner);

    notePopup.setTitlebar(false);
    notePopup.setFadeIn(true);
    notePopup.setFadeOut(true);
    notePopup.setFadeSpeed(4);
    notePopup.setDimensions("auto", "auto");
    if (!style) style = "Note";
    notePopup.addClass(style);

    var dim;
    if (underele) {
        // pop up the box right under the element
        dim = DOM.getAbsoluteDimensions(underele);
        if (!dim) return;
    }

    var bounds = DOM.getClientDimensions();
    if (!bounds) return;

    if (!dim) {
        // no element specified to pop up on, show in the middle
        // notePopup.setModal(true);
        // notePopup.setOverlayVisible(true);
        notePopup.setAutoCenter(true, true);
        notePopup.show();
    } else {
        // default is to auto-center, don't want that
        notePopup.setAutoCenter(false, false);
        notePopup.setLocation(dim.absoluteLeft, dim.absoluteBottom + 4);
        notePopup.show();

        var popupBounds = DOM.getAbsoluteDimensions(notePopup.getElement());
        if (popupBounds.absoluteRight > bounds.x) {
            notePopup.setLocation(bounds.x - popupBounds.offsetWidth - 30, dim.absoluteBottom + 4);
        }
    }

    notePopup.setClickToClose(true);
    notePopup.moveForward();

    if (! defined(timeout)) {
        timeout = 5000;
    }

    if (timeout) {
        window.setTimeout(function () {
            if (notePopup)
                notePopup.hide();
        }, timeout);
    }

    return notePopup;
};

LJ_IPPU.textPrompt = function (title, prompt, callback) {
    title += '';
    var notePopup = new LJ_IPPU(title);

    var inner = document.createElement("div");
    DOM.addClassName(inner, "ljippu_textprompt");

    // label
    if (prompt)
        inner.appendChild(_textDiv(prompt));

    // text field
    var field = document.createElement("textarea");
    DOM.addClassName(field, "htmlfield");
    field.cols = 40;
    field.rows = 5;
    inner.appendChild(field);

    // submit btn
    var btncont = document.createElement("div");
    DOM.addClassName(btncont, "submitbtncontainer");
    var btn = document.createElement("input");
    DOM.addClassName(btn, "submitbtn");
    btn.type = "button";
    btn.value = "Insert";
    btncont.appendChild(btn);
    inner.appendChild(btncont);

    notePopup.setContentElement(inner);

    notePopup.setAutoCenter(true, true);
    notePopup.setDimensions("60%", "auto");
    notePopup.show();
    field.focus();

    DOM.addEventListener(btn, "click", function (e) {
        notePopup.hide();
        if (callback)
            callback.apply(null, [field.value]);
    });
}
