/*
  IPPU methods:
     init([innerHTML]) -- takes innerHTML as optional argument
     show() -- shows the popup
     hide() -- hides popup
     cancel() -- hides and calls cancel callback

  Content setters:
     setContent(innerHTML) -- set innerHTML
     setContentElement(element) -- adds element as a child of the popup

   Accessors:
     getElement() -- returns popup DIV element
     visible() -- returns whether the popup is visible or not

   Titlebar:
     setTitlebar(show) -- true: show titlebar / false: no titlebar
     setTitle(title) -- sets the titlebar text
     getTitlebarElement() -- returns the titlebar element
     setTitlebarClass(className) -- set the class of the titlebar

   Styling:
     setOverflow(overflow) -- sets ele.style.overflow to overflow
     addClass(className) -- adds class to popup
     removeClass(className) -- removes class to popup

   Browser Hacks:
     setAutoHideSelects(autohide) -- when the popup is shown should it find all the selects
                                on the page and hide them (and show them again) (for IE)

   Positioning/Sizing:
     setLocation(left, top) -- set popup location: will be pixels if units not specified
     setLeft(left) -- set left location
     setTop(top)   -- set top location
     setDimensions(width, height) -- set popup dimensions: will be pixels if units not specified
     setAutoCenter(x, y) -- what dimensions to auto-center
     center() -- centers popup on screen
     centerX() -- centers popup horizontally
     centerY() -- centers popup vertically
     setFixedPosition(fixed) -- should the popup stay fixed on the page when it scrolls?
     centerOnWidget(widget) -- center popup on this widget
     setAutoCenterCallback(callback) -- calls callback with this IPPU instance as a parameter
                                        for auto-centering. Some common built-in class methods
                                        you can use as callbacks are:
                                        IPPU.center
                                        IPPU.centerX
                                        IPPU.centerY

     moveForward(amount) -- increases the zIndex by one or amount if specified
     moveBackward(amount) -- decreases the zIndex by one or amount if specified

   Modality:
     setClickToClose(clickToClose) -- if clickToClose is true, clicking outside of the popup
                                      will close it
     setModal(modality) -- If modality is true, then popup will capture all mouse events
                     and optionally gray out the rest of the page. (overrides clickToClose)
     setOverlayVisible(visible) -- If visible is true, when this popup is on the page it
                                   will gray out the rest of the page if this is modal

   Callbacks:
     setCancelledCallback(callback) -- call this when the dialog is closed through clicking
                                       outside, titlebar close button, etc...
     setHiddenCallback(callback) -- called when the dialog is closed in any fashion

   Fading:
     setFadeIn(fadeIn) -- set whether or not to automatically fade the ippu in
     setFadeOut(fadeOut) -- set whether or not to automatically fade the ippu out
     setFadeSpeed(secs) -- sets fade speed

  Class Methods:
   Handy callbacks:
     IPPU.center
     IPPU.centerX
     IPPU.centerY
   Browser testing:
     IPPU.isIE() -- is the browser internet exploder?
     IPPU.ieSafari() -- is this safari?

////////////////////


ippu.setModalDenialCallback(IPPU.cssBorderFlash);


   private:
    Properties:
     ele -- DOM node of div
     shown -- boolean; if element is in DOM
     autoCenterX -- boolean; auto-center horiz
     autoCenterY -- boolean; auto-center vertical
     fixedPosition -- boolean; stay in fixed position when browser scrolls?
     titlebar -- titlebar element
     title -- string; text to go in titlebar
     showTitlebar -- boolean; whether or not to show titlebar
     content -- DIV containing user's specified content
     clickToClose -- boolean; clicking outside popup will close it
     clickHandlerSetup -- boolean; have we set up the click handlers?
     docOverlay -- DIV that overlays the document for capturing clicks
     modal -- boolean; capture all events and prevent user from doing anything
                       until dialog is dismissed
     visibleOverlay -- boolean; make overlay slightly opaque
     clickHandlerFunc -- function; function to handle document clicks
     resizeHandlerFunc -- function; function to handle document resizing
     autoCenterCallback -- function; what callback to call for auto-centering
     cancelledCallback -- function; called when dialog is cancelled
     setAutoHideSelects -- boolean; autohide all SELECT elements on the page when popup is visible
     hiddenSelects -- array; SELECT elements that have been hidden
     hiddenCallback -- funciton; called when dialog is hidden
     fadeIn, fadeOut, fadeSpeed -- fading settings
     fadeMode -- current fading mode (in, out) if there is fading going on

    Methods:
     updateTitlebar() -- create titlebar if it doesn't exist,
                         hide it if titlebar == false,
                         update titlebar text
     updateContent() -- makes sure all currently specified properties are applied
     setupClickCapture() -- if modal, create document-sized div overlay to capture click events
                            otherwise install document onclick handler
     removeClickHandlers() -- remove overlay, event handlers
     clickHandler() -- event handler for clicks
     updateOverlay() -- if we have an overlay, make sure it's where it should be and (in)visible
                        if it should be
     autoCenter() -- centers popup on screen according to autoCenterX and autoCenterY
     hideSelects() -- hide all select element on page
     showSelects() -- show all selects
     _hide () -- actually hides everything, called by hide(), which does fading if necessary
*/

// this belongs somewhere else:
function changeOpac(id, opacity) {
    var e =  $(id);
    if (e && e.style) {
        var object = e.style;
        if (object) {
            //reduce flicker
            if (IPPU.isSafari() && opacity >= 100)
                opacity = 99.99;

            // IE
            if (object.filters)
                object.filters.alpha.opacity = opacity * 100;

            object.opacity = opacity;
        }
    }
}

IPPU = new Class( Object, {
  setFixedPosition: function (fixed) {
    // no fixed position for IE
    if (IPPU.isIE())
      return;

    this.fixedPosition = fixed;
    this.updateContent();
  },

  clickHandler : function (evt) {
    if (!this.clickToClose) return;
    if (!this.visible()) return;

    evt = Event.prep(evt);
    var target = evt.target;
    // don't do anything if inside the popup
    if (DOM.getAncestorsByClassName(target, "ippu", true).length > 0) return;
    this.cancel();
  },

  setCancelledCallback : function (callback) {
    this.cancelledCallback = callback;
  },

  cancel : function () {
    if (this.cancelledCallback)
      this.cancelledCallback();
    this.hide();
  },

  setHiddenCallback: function (callback) {
    this.hiddenCallback = callback;
  },

  setupClickCapture : function () {
    if (!this.visible() || this.clickHandlerSetup){return;}
    if (!this.clickToClose && !this.modal) {return;}

    this.clickHandlerFunc = this.clickHandler.bindEventListener(this);

    if (this.modal) {
      // create document-sized div to capture events
      if (this.overlay) return; // wtf? shouldn't exist yet
      this.overlay = document.createElement("div");
      this.overlay.style.left = "0px";
      this.overlay.style.top = "0px";
      this.overlay.style.margin = "0px";
      this.overlay.style.padding = "0px";
      
      this.overlay.style.backgroundColor = "#000000";
      this.overlay.style.zIndex="900";
      if (IPPU.isIE()){
      		this.overlay.style.filter="progid:DXImageTransform.Microsoft.Alpha(opacity=50)";
		this.overlay.style.position="absolute";
		this.overlay.style.width=document.body.scrollWidth;
		this.overlay.style.height=document.body.scrollHeight;
      }
      else{
      	this.overlay.style.position = "fixed";
      }

      this.ele.parentNode.insertBefore(this.overlay, this.ele);
      this.updateOverlay();

      DOM.addEventListener(this.overlay, "click", this.clickHandlerFunc);
    } else {
      // simple document onclick handler
      DOM.addEventListener(document, "click", this.clickHandlerFunc);
    }

    this.clickHandlerSetup = true;
  },

  updateOverlay : function () {
    if (this.overlay) {
      var cd = DOM.getClientDimensions();
      this.overlay.style.width = (cd.x - 1) + "px";
      if(!IPPU.isIE()){
      	this.overlay.style.height = (cd.y - 1) + "px";
      }	
      if (this.visibleOverlay) {
        this.overlay.backgroundColor = "#000000";
        changeOpac(this.overlay, 0.50);
      } else {
        this.overlay.backgroundColor = "#FFFFFF";
        changeOpac(this.overlay, 0.0);
      }
    }
  },

  resizeHandler : function (evt) {
    this.updateContent();
  },

  removeClickHandlers : function () {
    if (!this.clickHandlerSetup) return;

    var myself = this;
    var handlerFunc = function (evt) {
      myself.clickHandler(evt);
    };

    DOM.removeEventListener(document, "click", this.clickHandlerFunc, false);

    if (this.overlay) {
      DOM.removeEventListener(this.overlay, "click", this.clickHandlerFunc, true);
      this.overlay.parentNode.removeChild(this.overlay);
      this.overlay = undefined;
    }

    this.clickHandlerFunc = undefined;
    this.clickHandlerSetup = false;
  },

  setClickToClose : function (clickToClose) {
    this.clickToClose = clickToClose;

    if (!this.clickHandlerSetup && clickToClose && this.visible()) {
      // popup is already visible, need to set up click handler
      var setupClickCaptureCallback = this.setupClickCapture.bind(this);
      window.setTimeout(setupClickCaptureCallback, 100);
    } else if (!clickToClose && this.clickHandlerSetup) {
      this.removeClickHandlers();
    }

    this.updateContent();
  },

  setModal : function (modal) {
    var changed = (this.modal == modal);

    // if it's modal, we don't want click-to-close
    if (modal)
      this.setClickToClose(false);

    this.modal = modal;
    if (changed) {
      this.removeClickHandlers();
      this.updateContent();
    }
  },

  setOverlayVisible : function (vis) {
    this.visibleOverlay = vis;
    this.updateContent();
  },

  updateContent : function () {
    this.autoCenter();
    this.updateTitlebar();
    this.updateOverlay();
    if (this.titlebar)
      this.setTitlebarClass(this.titlebar.className);

    var setupClickCaptureCallback = this.setupClickCapture.bind(this);
    window.setTimeout(setupClickCaptureCallback, 100);

    if (this.fixedPosition && this.ele.style.position != "fixed")
      this.ele.style.position = "fixed";
    else if (!this.fixedPosition && this.ele.style.position == "fixed")
      this.ele.style.position = "absolute";
  },

  getTitlebarElement : function () {
    return this.titlebar;
  },

  setTitlebarClass : function (className) {
    if (this.titlebar)
      this.titlebar.className = className;
  },

  setOverflow : function (overflow) {
    if (this.ele)
      this.ele.style.overflow = overflow;
  },

  visible : function () {
    return this.shown;
  },

  setTitlebar : function (show) {
    this.showTitlebar = show;

    if (show) {
      if (!this.titlebar) {
        // titlebar hasn't been created. Create it.
        var tbar = document.createElement("div");
        if (!tbar) return;
        tbar.style.width = "100%";

        if (this.title) tbar.innerHTML = this.title;
        this.ele.insertBefore(tbar, this.content);
        this.titlebar = tbar;

      }
    } else if (this.titlebar) {
      this.ele.removeChild(this.titlebar);
      this.titlebar = false;
    }
  },

  setTitle : function (title) {
    this.title = title;
    this.updateTitlebar();
  },

  updateTitlebar : function() {
    if (this.showTitlebar && this.titlebar && this.title != this.titlebar.innerHTML) {
      this.titlebar.innerHTML = this.title;
    }
  },

  addClass : function (className) {
    DOM.addClassName(this.ele, className);
  },

  removeClass : function (className) {
    DOM.removeClassName(this.ele, className);
  },

  setAutoCenterCallback : function (callback) {
    this.autoCenterCallback = callback;
  },

  autoCenter : function () {
    if (!this.visible || !this.visible()) return;

    if (this.autoCenterCallback) {
      this.autoCenterCallback(this);
      return;
    }

    if (this.autoCenterX)
      this.centerX();

    if (this.autoCenterY)
      this.centerY();
  },

  center : function () {
    this.centerX();
    this.centerY();
  },

  centerOnWidget : function (widget, offsetTop, offsetLeft) {
        offsetTop = offsetTop || 0;
        offsetLeft = offsetLeft || 0;
        this.setAutoCenter(false, false);
        this.setAutoCenterCallback(null);
  var wd = DOM.getAbsoluteDimensions(widget);
    var ed = DOM.getAbsoluteDimensions(this.ele);
    var newleft = (wd.absoluteRight - wd.offsetWidth / 2 - ed.offsetWidth / 2) + offsetLeft;
    var newtop = (wd.absoluteBottom - wd.offsetHeight / 2 - ed.offsetHeight / 2) + offsetTop;

        newleft = newleft < 0 ? 0 : newleft;
        newtop  = newtop  < 0 ? 0 : newtop;
    DOM.setLeft(this.ele, newleft);
    DOM.setTop(this.ele, newtop);
  },

  centerX : function () {
    if (!this.visible || !this.visible()) return;

    var cd = DOM.getClientDimensions();
    var newleft = cd.x / 2 - DOM.getDimensions(this.ele).offsetWidth / 2;

    // If not fixed position, center relative to the left of the page
    if (!this.fixedPosition) {
        var wd = DOM.getWindowScroll();
        newleft += wd.left;
    }

   DOM.setLeft(this.ele, newleft);
  },

  centerY : function () {
    if (!this.visible || !this.visible()) return;

    var cd = DOM.getClientDimensions();
    var newtop = cd.y / 2 - DOM.getDimensions(this.ele).offsetHeight / 2;

    // If not fixed position, center relative to the top of the page
    if (!this.fixedPosition) {
        var wd = DOM.getWindowScroll();
        newtop += wd.top;
    }

    DOM.setTop(this.ele, newtop);
  },

  setAutoCenter : function (autoCenterX, autoCenterY) {
    this.autoCenterX = autoCenterX || false;
    this.autoCenterY = autoCenterY || false;

    if (!autoCenterX && !autoCenterY) {
        this.setAutoCenterCallback(null);
        return;
    }

    this.autoCenter();
  },

  setDimensions : function (width, height) {
    width = width + "";
    height = height + "";
    if (width.match(/^\d+$/)) width += "px";
    if (height.match(/^\d+$/)) height += "px";

    this.ele.style.width  = width;
    this.ele.style.height = height;
  },

  moveForward : function (howMuch) {
      if (!howMuch) howMuch = 1;
      if (! this.ele) return;

      this.ele.style.zIndex += howMuch;
  },

  moveBackward : function (howMuch) {
      if (!howMuch) howMuch = 1;
      if (! this.ele) return;

      this.ele.style.zIndex -= howMuch;
  },

  setLocation : function (left, top) {
      this.setLeft(left);
      this.setTop(top);
  },

  setTop : function (top) {
    top = top + "";
    if (top.match(/^\d+$/)) top += "px";
    this.ele.style.top = top;
  },

  setLeft : function (left) {
    left = left + "";
    if (left.match(/^\d+$/)) left += "px";
    this.ele.style.left = left;
  },

  getElement : function () {
    return this.ele;
  },

  setContent : function (html) {
    this.content.innerHTML = html;
  },

  setContentElement : function (element) {
      // remove child nodes
      while (this.content.firstChild) {
          this.content.removeChild(this.content.firstChild);
      };

    this.content.appendChild(element);
  },

  setFadeIn : function (fadeIn) {
      this.fadeIn = fadeIn;
  },

  setFadeOut : function (fadeOut) {
      this.fadeOut = fadeOut;
  },

  setFadeSpeed : function (fadeSpeed) {
      this.fadeSpeed = fadeSpeed;
  },

  show : function () {
    this.shown = true;

    if (this.fadeIn) {
        var opp = 0.01;

        changeOpac(this.ele, opp);
    }

    document.body.appendChild(this.ele);
    this.ele.style.position = "absolute";
    if (this.autoCenterX || this.autoCenterY) this.center();

    this.updateContent();

    if (!this.resizeHandlerFunc) {
      this.resizeHandlerFunc = this.resizeHandler.bindEventListener(this);
      DOM.addEventListener(window, "resize", this.resizeHandlerFunc, false);
    }

    if (this.fadeIn)
        this.fade("in");

    this.hideSelects();
  },

  fade : function (mode, callback) {
      var opp;
      var delta;

      var steps = 10.0;

      if (mode == "in") {
          delta = 1 / steps;
          opp = 0.1;
      } else {
          if (this.ele.style.opacity)
          opp = finiteFloat(this.ele.style.opacity);
          else
          opp = 0.99;

          delta = -1 / steps;
      }

      var fadeSpeed = this.fadeSpeed;
      if (!fadeSpeed) fadeSpeed = 1;

      var fadeInterval = steps / fadeSpeed * 5;

      this.fadeMode = mode;

      var self = this;
      var fade = function () {
          opp += delta;

          // did someone start a fade in the other direction? if so,
          // cancel this fade
          if (self.fadeMode && self.fadeMode != mode) {
              if (callback)
                  callback.call(self, []);

              return;
          }

          if (opp <= 0.1) {
              if (callback)
                  callback.call(self, []);

              self.fadeMode = null;

              return;
          } else if (opp >= 1.0) {
              if (callback)
                  callback.call(self, []);

              self.fadeMode = null;

              return;
          } else {
              changeOpac(self.ele, opp);
              window.setTimeout(fade, fadeInterval);
          }
      };

      fade();
  },

  hide : function () {
    if (! this.visible()) return;

    if (this.fadeOut && this.ele) {
        this.fade("out", this._hide.bind(this));
    } else {
        this._hide();
    }
  },

  _hide : function () {
    if (this.hiddenCallback)
      this.hiddenCallback();

    this.shown = false;
    this.removeClickHandlers();

    if (this.ele)
    document.body.removeChild(this.ele);

    if (this.resizeHandlerFunc)
      DOM.removeEventListener(window, "resize", this.resizeHandlerFunc);

    this.showSelects();
  },

  // you probably want this for IE being dumb
  // (IE thinks select elements are cool and puts them in front of every element on the page)
  setAutoHideSelects : function (autohide) {
    this.autoHideSelects = autohide;
    this.updateContent();
  },

  hideSelects : function () {
    if (!this.autoHideSelects || !IPPU.isIE()) return;
    var sels = document.getElementsByTagName("select");
    var ele;
    for (var i = 0; i < sels.length; i++) {
      ele = sels[i];
      if (!ele) continue;

      // if this element is inside the ippu, skip it
      if (DOM.getAncestorsByClassName(ele, "ippu", true).length > 0) continue;

      if (ele.style.visibility != 'hidden') {
        ele.style.visibility = 'hidden';
        this.hiddenSelects.push(ele);
      }
    }
  },

  showSelects : function () {
    if (! this.autoHideSelects) return;
    var ele;
    while (ele = this.hiddenSelects.pop())
      ele.style.visibility = '';
  },

  init: function (html) {
    var ele = document.createElement("div");
    this.ele = ele;
    this.shown = false;
    this.autoCenterX = false;
    this.autoCenterY = false;
    this.titlebar = null;
    this.title = "";
    this.showTitlebar = false;
    this.clickToClose = false;
    this.modal = false;
    this.clickHandlerSetup = false;
    this.docOverlay = false;
    this.visibleOverlay = false;
    this.clickHandlerFunc = false;
    this.resizeHandlerFunc = false;
    this.fixedPosition = false;
    this.autoCenterCallback = null;
    this.cancelledCallback = null;
    this.autoHideSelects = false;
    this.hiddenCallback = null;
    this.fadeOut = false;
    this.fadeIn = false;
    this.hiddenSelects = [];
    this.fadeMode = null;

    ele.style.position = "absolute";
    ele.style.zIndex   = "1000";

    // plz don't remove thx
    DOM.addClassName(ele, "ippu");

    // create DIV to hold user's content
    this.content = document.createElement("div");

    this.content.innerHTML = html;

    this.ele.appendChild(this.content);
  }
});

// class methods
IPPU.center = function (obj) {
  obj.centerX();
  obj.centerY();
};

IPPU.centerX = function (obj) {
  obj.centerX();
};

IPPU.centerY = function (obj) {
  obj.centerY();
};

IPPU.isIE = function () {
    var UA = navigator.userAgent.toLowerCase();
    if (UA.indexOf('msie') != -1) return true;
    return false;
};

IPPU.isSafari = function () {
    var UA = navigator.userAgent.toLowerCase();
    if (UA.indexOf('safari') != -1) return true;
    return false;
};
