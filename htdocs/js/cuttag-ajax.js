// functions for ajaxifying cut tags

CutTagHandler = new Class(Object, {
    // initializes a new CutTagHandler for the cuttag defined by the
    // given journal, ditemid, and cutid
    init: function(journal, ditemid, cutid) {
      this.identifier = 'cuttag_' + journal + '_' + ditemid + '_' + cutid;
      this.ajaxUrl = "/__rpc_cuttag?journal=" + journal + "&ditemid=" + ditemid + "&cutid=" + cutid;

      this.data = {
        journal: journal,
        ditemid: ditemid,
        cutid: cutid
      };
    },

    // returns if the div controlled by this handler is open
    isOpen: function() {
      return ( DOM.hasClassName( $("div-" + this.identifier), "cuttag-open" ) );
    },

    // opens or closes the controlled div, as appropriate
    toggle: function() {
      if ( this.isOpen() ) {
        this.close();
      } else {
        this.open();
      }
    },

    // closes the controlled div
    close: function() {
      $("img-" + this.identifier).src= Site.imgprefix + "/collapse.gif";
      $("div-" + this.identifier).innerHTML="";
      $("div-" + this.identifier).style.display = "none";
      DOM.removeClassName($("div-" + this.identifier), "cuttag-open");
      $('img-' + this.identifier).alt=collapsed;
      $('img-' + this.identifier).title=collapsed;
    },

    // opens the cut tag inline
    open: function() {
      var opts = {
        "async": true,
        "method": "GET",
        "url": this.ajaxUrl,
        "onData": this.replaceCutTag.bindEventListener(this),
        "onError": this.handleError.bindEventListener(this)
      };

      // ajax call.
      window.parent.HTTPReq.getJSON(opts);
    },

    // callback for the getJSON call.  just throws up the error as an alert.
    handleError: function(err) {
      alert(err);
    },

    // callback for the getJSON call.  if the response is an error, calls
    // handlerObj.handleError(responseObject.error).  otherwise replaces the
    // cut tag with the contents of the cut.
    replaceCutTag: function(resObj) {
      if (resObj.error) {
        this.handleError(resObj.error);
      } else {
        var replaceDiv = $('div-' + this.identifier);
        replaceDiv.innerHTML=resObj.text;
        replaceDiv.style.display="block";

        var closeEnd = document.createElement("span");

        closeEnd.innerHTML = ' <a href="#span-'+this.identifier+'" onclick=" CutTagHandler.toggleCutTag(\''+this.data.journal+'\', \''+this.data.ditemid+'\', \''+this.data.cutid+'\');"><img style="border: 0;" src="' + Site.imgprefix + '/collapse-end.gif" aria-controls="div-cuttag_' + this.identifier + '" alt="' + expanded + '" title="' + expanded + '"/></a>';
        replaceDiv.appendChild(closeEnd);

        DOM.addClassName(replaceDiv, "cuttag-open");
        $('img-' + this.identifier).alt=expanded;
        $('img-' + this.identifier).title=expanded;
        $("img-" + this.identifier).src= Site.imgprefix + "/expand.gif";
        CutTagHandler.initLinks(replaceDiv);
        LiveJournal.initPlaceholders(replaceDiv);
      }
    }
  });

// called by the onclick handler of the anchor tag
CutTagHandler.toggleCutTag = function(journal, ditemid, cutid) {
  try {
    var ctHandler = new CutTagHandler(journal, ditemid, cutid);

    ctHandler.toggle();

    return false;
  } catch (ex) {
    return true;
  }
}

// fills the given tag (a span) with the appropriate <a> and <img> tags
// for the expand/collapse button
CutTagHandler.writeExpandTag = function(tag, journal, ditemid, cutid) {
  var identifier = journal + '_' + ditemid + '_' + cutid;
  tag.style.display = 'inline'
  tag.innerHTML = '<a href="#" onclick="return CutTagHandler.toggleCutTag(\'' + journal + '\', \'' + ditemid + '\', \'' + cutid + '\');" id="cuttag_' + identifier +'" ><img style="border: 0;" id="img-cuttag_' + identifier + '" src="' + Site.imgprefix + '/collapse.gif" aria-controls="div-cuttag_' + identifier + '" alt="' + collapsed + '" title="' + collapsed + '"/></a>';
}


// initializes all <span> tags with the 'cuttag' class that are contained
// by the given parentTag
CutTagHandler.initLinks = function(parentTag) {
  var domObjects = parentTag.getElementsByTagName("span");
  var items = DOM.filterElementsByClassName(domObjects, "cuttag") || [];

  for (var i = 0; i < items.length; i++) {
    var spanid = items[i].id;
    var journal = spanid.replace( /^span-cuttag_(.*)_[0-9]+_[0-9]+/, "$1");
    var ditemid = spanid.replace( /^.*_([0-9]+)_[0-9]+/, "$1");
    var cutid = spanid.replace( /^.*_([0-9]+)/, "$1");
    CutTagHandler.writeExpandTag(items[i], journal, ditemid, cutid);
  }
}

// called at page load to initialize all <span> tags with the 'cuttag' class.
CutTagHandler.initAllLinks = function() {
  CutTagHandler.initLinks(document);
}

// calls CutTagHandler.initAllLinks on page load.
LiveJournal.register_hook("page_load", CutTagHandler.initAllLinks);
