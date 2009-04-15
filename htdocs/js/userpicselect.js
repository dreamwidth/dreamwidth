UserpicSelect = new Class (LJ_IPPU, {
  init: function () {
    UserpicSelect.superClass.init.apply(this, ["Choose Userpic"]);

    this.setDimensions("550px", "441px");

    this.selectedPicid = null;
    this.displayPics = null;
    this.dataLoaded = false;
    this.imgScale = 1;

    this.picSelectedCallback = null;

    var template = new Template( UserpicSelect.top );
    var templates = { body: template };
    this.setContent(template.exec( new Template.Context( {}, templates ) ));
    this.setHiddenCallback(this.hidden.bind(this));
  },

  show: function() {
    UserpicSelect.superClass.show.apply(this, []);

    if (!this.dataLoaded) {
      this.setStatus("Loading...");
      this.loadPics();
      this.dataLoaded = true;
    } else {
      this.redraw();
    }
  },

  // hide the hourglass when window is closed
  hidden: function () {
    if (this.hourglass)
      this.hourglass.hide();
  },

  // set a callback to be called when the "select" button is clicked
  setPicSelectedCallback: function (callback) {
    this.picSelectedCallback = callback;
  },

  // called when the "select" button is clicked
  closeButtonClicked: function (evt) {
      if (this.picSelectedCallback) {
          var selectedKws = [];
          if (this.selectedPicid) {
              var kws = this.pics.pics[this.selectedPicid+""].keywords;
              if (kws && kws.length) selectedKws = kws;
          }

          this.picSelectedCallback(this.selectedPicid, selectedKws);
      }

    this.hide();
  },

  setStatus: function(status) {
      this.setField({'status': status});
  },

  setField: function(vars) {
    var template = new Template( UserpicSelect.dynamic );
    var userpics_template = new Template( UserpicSelect.userpics );

    var templates = {
      body: template,
      userpics: userpics_template
    };

    if (!vars.pics)
      vars.pics = this.pics || {};

    if (!vars.status)
      vars.status = "";

    vars.imgScale = this.imgScale;

    $("ups_dynamic").innerHTML = (template.exec( new Template.Context( vars, templates ) ));

    if (!vars.pics.ids)
      return;

    // we redrew the window so reselect the current selection, if any
    if (this.selectedPicid)
      this.selectPic(this.selectedPicid);

    var ST = new SelectableTable();
    ST.init({
        "table": $("ups_userpics_t"),
            "selectedClass": "ups_selected_cell",
            "selectableClass": "ups_cell",
            "multiple": false,
            "selectableItem": "cell"
            });

    var self = this;

    ST.addWatcher(function (data) {
        var selectedCell = data[0];

        if (!selectedCell) {
            // clear selection
            self.selectPic(null);
        } else {
            // find picid and select it
            var parentCell = DOM.getFirstAncestorByClassName(selectedCell, "ups_cell", true);
            if (!parentCell) return;

            var picid = parentCell.getAttribute("lj_ups:picid");
            if (!picid) return;

            self.selectPic(picid);
        }
    });

    DOM.addEventListener($("ups_closebutton"), "click", this.closeButtonClicked.bindEventListener(this));

    // set up image scaling buttons
    var scalingSizes = [3,2,1];
    var baseSize = 25;
    var scalingBtns = $("ups_scaling_buttons");
    this.scalingBtns = [];

    if (scalingBtns) {
        scalingSizes.forEach(function (scaleSize) {
            var scaleBtn = document.createElement("img");

            scaleBtn.style.width = scaleBtn.width = scaleBtn.style.height = scaleBtn.height = baseSize - scaleSize * 5;

            scaleBtn.src = Site.imgprefix + "/imgscale.png";
            DOM.addClassName(scaleBtn, "ups_scalebtn");

            self.scalingBtns.push(scaleBtn);

            DOM.addEventListener(scaleBtn, "click", function (evt) {
                Event.stop(evt);

                self.imgScale = scaleSize;
                self.scalingBtns.forEach(function (otherBtn) {
                    DOM.removeClassName(otherBtn, "ups_scalebtn_selected");
                });

                DOM.addClassName(scaleBtn, "ups_scalebtn_selected");

                self.redraw();
            });

            scalingBtns.appendChild(scaleBtn);

            if (self.imgScale == scaleSize)
                DOM.addClassName(scaleBtn, "ups_scalebtn_selected");
        });
    }
  },

  kwmenuChange: function(evt) {
    this.selectPic($("ups_kwmenu").value);
  },

  selectPic: function(picid) {
    if (this.selectedPicid) {
        DOM.removeClassName($("ups_upicimg" + this.selectedPicid), "ups_selected");
        DOM.removeClassName($("ups_cell" + this.selectedPicid), "ups_selected_cell");
    }

    this.selectedPicid = picid;

    if (picid) {
        // find the current pic and cell
        var picimg =  $("ups_upicimg" + picid);
        var cell   =  $("ups_cell" + picid);

        if (!picimg || !cell)
            return;

        // hilight the userpic
        DOM.addClassName(picimg, "ups_selected");

        // hilight the cell
        DOM.addClassName(cell, "ups_selected_cell");

        // enable the select button
        $("ups_closebutton").disabled = false;

        // select the current selectedPicid in the dropdown
        this.setDropdown();
    } else {
        $("ups_closebutton").disabled = true;
    }
  },

  // filter by keyword/comment
  filterPics: function(evt) {
    var searchbox = $("ups_search");

    if (!searchbox)
      return;

    var filter = searchbox.value.toLocaleUpperCase();
    var pics = this.pics;

    if (!filter) {
      this.setPics(pics);
      return;
    }

    // if there is a filter and there is selected text in the field assume that it's
    // inputcomplete text and ignore the rest of the selection.
    if (searchbox.selectionStart && searchbox.selectionStart > 0)
      filter = searchbox.value.substr(0, searchbox.selectionStart).toLocaleUpperCase();

    var newpics = {
      "pics": [],
      "ids": []
    };

    for (var i=0; i<pics.ids.length; i++) {
      var picid = pics.ids[i];
      var pic = pics.pics[picid];

      if (!pic)
        continue;

      for (var j=0; j < pic.keywords.length; j++) {
        var kw = pic.keywords[j];

        var piccomment = "";
        if (pic.comment)
          piccomment = pic.comment.toLocaleUpperCase();

        if(kw.toLocaleUpperCase().indexOf(filter) != -1 || // matches a keyword
           (piccomment && piccomment.indexOf(filter) != -1) || // matches comment
           (pic.keywords.join(", ").toLocaleUpperCase().indexOf(filter) != -1)) { // matches comma-seperated list of keywords

          newpics.pics[picid] = pic;
          newpics.ids.push(picid);
          break;
        }
      }
    }

    if (this.pics != newpics)
      this.setPics(newpics);

    // if we've filtered down to one pic and we don't currently have a selected pic, select it
    if (newpics.ids.length == 1 && !this.selectedPicid)
      this.selectPic(newpics.ids[0]);
  },

  setDropdown: function(pics) {
    var menu = $("ups_kwmenu");

    for (var i=0; i < menu.length; i++)
      menu.remove(i);

    menu.length = 0;

    if (!pics)
      pics = this.pics;

    if (!pics || !pics.ids)
      return;

    for (var i=0; i < pics.ids.length; i++) {
      var picid = pics.ids[i];
      var pic = pics.pics[picid];

      if (!pic)
        continue;

      var sel = false;
      var self = this;

      pic.keywords.forEach(function (kw) {
          // add to dropdown
          var picopt = document.createElement("option");
          picopt.text = kw;
          picopt.value = picid;

          if (! sel) {
              picopt.selected = self.selectedPicid ? self.selectedPicid == picid : false;
              sel = picopt.selected;
          }

          Try.these(
                    function () { menu.add(picopt, 0); },    // everything else
                    function () { menu.add(picopt, null); }  // IE
                    );
      });
    }
  },

  picsReceived: function(picinfo) {
    if (picinfo && picinfo.alert) { // got an error
      this.handleError(picinfo.alert);
      return;
    }

    if (!picinfo || !picinfo.ids || !picinfo.pics || !picinfo.ids.length)
      return;

    var piccount = picinfo.ids.length;

    // force convert integers to strings
    for (var i=0; i < piccount; i++) {
      var picid = picinfo.ids[i];

      var pic = picinfo.pics[picid];

      if (!pic)
        continue;

      if (pic.comment)
        pic.comment += "";

      for (var j=0; j < pic.keywords.length; j++)
        pic.keywords[j] += "";
    }

    // set default scaling size based on how many pics there are
    if (piccount < 30) {
        this.imgScale = 1;
    } else if (piccount < 60) {
        this.imgScale = 2;
    } else {
        this.imgScale = 3;
    }

    this.pics = picinfo;

    this.setPics(picinfo);
    this.redraw();

    if (this.hourglass)
      this.hourglass.hide();
  },

  redraw: function () {
    this.setStatus();

    if (!this.pics)
      return;

    this.setPics(this.pics);

    if (this.hourglass)
      this.hourglass.hide();

    var keywords = [], comments = [];
    for (var i=0; i < this.pics.ids.length; i++) {
      var picid = this.pics.ids[i];
      var pic = this.pics.pics[picid];

      for (var j=0; j < pic.keywords.length; j++)
        keywords.push(pic.keywords[j]);

      comments.push(pic.comment);
    }

    var searchbox = $("ups_search");
    var compdata = new InputCompleteData(keywords.concat(comments));
    var whut = new InputComplete(searchbox, compdata);

    DOM.addEventListener(searchbox, "keydown",  this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "keyup",    this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "focus",    this.filterPics.bind(this));

    try {
      searchbox.focus();
    } catch(e) {}

    DOM.addEventListener($("ups_kwmenu"), "change", this.kwmenuChange.bindEventListener(this));
  },

  setPics: function(pics) {
    if (this.displayPics == pics)
      return;

    this.displayPics = pics;

    this.setField({'pics': pics});
    this.setDropdown(pics);
  },

  handleError: function(err) {
    log("Error: " + err);
    this.hourglass.hide();
  },

  loadPics: function() {
    this.hourglass = new Hourglass($("ups_userpics"));
    var reqOpts = {};
    reqOpts.url = Site.currentJournal ? "/" + Site.currentJournal + "/__rpc_userpicselect" : "/__rpc_userpicselect";
    reqOpts.onData = this.picsReceived.bind(this);
    reqOpts.onError = this.handleError.bind(this);
    HTTPReq.getJSON(reqOpts);
  }
});

// Templates
UserpicSelect.top = "\
      <div class='ups_search'>\
       <span class='ups_searchbox'>\
         Search: <input type='text' id='ups_search'>\
         Select: <select id='ups_kwmenu'><option value=''></option></select>\
         </span>\
      </div>\
      <div id='ups_dynamic'></div>";

UserpicSelect.dynamic = "\
       [# if (status) { #] <div class='ups_status'>[#| status #]</div> [# } #]\
         <div class='ups_userpics' id='ups_userpics'>\
           [#= context.include( 'userpics' ) #]\
           &nbsp;\
         </div>\
      <div class='ups_closebuttonarea'>\
       <input type='button' id='ups_closebutton' value='Select' disabled='true'  />\
       <span id='ups_scaling_buttons'>\
       </span>\
      </div>";

UserpicSelect.userpics = "\
[# if(pics && pics.ids) { #] \
     <table class='ups_table' cellpadding='0' cellspacing='0' id='ups_userpics_t'> [# \
       var rownum = 0; \
       for (var i=0; i<pics.ids.length; i++) { \
          var picid = pics.ids[i]; \
          var pic = pics.pics[picid]; \
\
          if (!pic) \
            continue; \
\
          var pickws = pic.keywords; \
          if (i%2 == 0) { #] \
            <tr class='ups_row ups_row[#= rownum++ % 2 + 1 #]'> [# } #] \
\
            <td class='ups_cell'  \
                           lj_ups:picid='[#= picid #]' id='ups_cell[#= picid #]'> \
              <div class='ups_container'> \
              <img src='[#= pic.url #]' width='[#= finiteInt(pic.width/imgScale) #]' \
                 alt='[#= pic.alt #]' \
                 height='[#= finiteInt(pic.height/imgScale) #]' id='ups_upicimg[#= picid #]' class='ups_upic' /> \
               </div> \
\
              <b>[#| pickws.join(', ') #]</b> \
             [# if(pic.comment) { #]<br/>[#= pic.comment #][# } #] \
              <div class='ljclear'>&nbsp;</div>\
            </td> \
\
            [# if (i%2 == 1 || i == pics.ids.length - 1) { #] </tr> [# } \
        } #] \
     </table> \
  [# } #] \
";

// Copied here from entry.js
function insertViewThumbs() {
    var lj_userpicselect = $('lj_userpicselect');
    lj_userpicselect.innerHTML = 'View Thumbnails';
}

