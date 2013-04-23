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

      // update the expandAll/collapseAll links
      CutTagHandler.writeExpandAllControls();
    },

    // opens the cut tag inline
    // openNested if we want to open nested cuttags, too
    open: function( openNested ) {
      var opts = {
        "async": true,
        "method": "GET",
        "url": this.ajaxUrl,
        "onData": openNested ? this.replaceCutTagAndOpen.bindEventListener( this ) : this.replaceCutTag.bindEventListener( this ),
        "onError": this.handleError.bindEventListener( this )
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

    // wrapper for openNested=true
    replaceCutTagAndOpen: function( resObj ) {
      this.doReplaceCutTag( resObj, true );
    },
    // wrapper for openNested=false
    replaceCutTag: function( resObj ) {
      this.doReplaceCutTag( resObj, false );
    },
    // the actual callback
    doReplaceCutTag: function( resObj, openNested ) {
      if (resObj.error) {
        this.handleError(resObj.error);
      } else {
        var replaceDiv = $('div-' + this.identifier);
        replaceDiv.innerHTML=resObj.text;
        replaceDiv.style.display="block";

        var closeEnd = document.createElement("span");

        closeEnd.innerHTML = ' <a href="#span-'+this.identifier+'" onclick=" CutTagHandler.toggleCutTag(\''+this.data.journal+'\', \''+this.data.ditemid+'\', \''+this.data.cutid+'\');"><img style="border: 0; max-width: 100%; width: 0.7em; padding: 0.2em;" src="' + Site.imgprefix + '/collapse-end.gif" aria-controls="div-cuttag_' + this.identifier + '" alt="' + expanded + '" title="' + expanded + '"/></a>';
        replaceDiv.appendChild(closeEnd);

        DOM.addClassName(replaceDiv, "cuttag-open");
        $('img-' + this.identifier).alt=expanded;
        $('img-' + this.identifier).title=expanded;
        $("img-" + this.identifier).src= Site.imgprefix + "/expand.gif";
        CutTagHandler.initLinks(replaceDiv);
        LiveJournal.initPlaceholders(replaceDiv);
        LiveJournal.initPolls(replaceDiv);

        // update the expandAll/collapseAll links
        CutTagHandler.writeExpandAllControls();

        if ( openNested ) {
          CutTagHandler.openAll( replaceDiv );
        }
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
  tag.innerHTML = '<a href="#" onclick="return CutTagHandler.toggleCutTag(\'' + journal + '\', \'' + ditemid + '\', \'' + cutid + '\');" id="cuttag_' + identifier +'" ><img style="border: 0; max-width: 100%; width: 0.7em; padding: 0.2em;" id="img-cuttag_' + identifier + '" src="' + Site.imgprefix + '/collapse.gif" aria-controls="div-cuttag_' + identifier + '" alt="' + collapsed + '" title="' + collapsed + '"/></a>';
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
  CutTagHandler.writeExpandAllControls();
}

// calls CutTagHandler.initAllLinks on page load.
LiveJournal.register_hook("page_load", CutTagHandler.initAllLinks);

// creates a CutTagHandler for the provided span.cuttag tag
CutTagHandler.getCutTagHandler = function( spanCutTag ) {
  var spanid = spanCutTag.id;
  var journal = spanid.replace( /^span-cuttag_(.*)_[0-9]+_[0-9]+/, "$1" );
  var ditemid = spanid.replace( /^.*_([0-9]+)_[0-9]+/, "$1" );
  var cutid = spanid.replace( /^.*_([0-9]+)/, "$1" );
  return new CutTagHandler( journal, ditemid, cutid );
}

// returns a CutTagHandler for each cuttag span in the parent tag/document
CutTagHandler.getAllHandlers = function( parentTag ) {
  var returnValue = [];

  var domObjects = parentTag.getElementsByTagName( "span" );
  var items = DOM.filterElementsByClassName( domObjects, "cuttag" ) || [];

  for ( var i = 0; i < items.length; i++ ) {
    returnValue[i] = CutTagHandler.getCutTagHandler( items[i] );
  }
  return returnValue;
}

// Opens all cuttags in the given tag (call with document for the entire page)
CutTagHandler.openAll = function( parentTag ) {
  var cutTags = CutTagHandler.getAllHandlers( parentTag );

  for ( var i = 0; i < cutTags.length; i++ ) {
    if ( ! cutTags[i].isOpen() ) {
      cutTags[i].open( true );
    }
  }
}

// Closes all cuttags in the given tag (call with document for the entire page)
CutTagHandler.closeAll = function( parentTag ) {
  var cutTags = CutTagHandler.getAllHandlers( parentTag );

  for ( var i = 0; i < cutTags.length; i++ ) {
    if ( cutTags[i].isOpen() ) {
      cutTags[i].close();
    }
  }
}

// writes the expand all/close all controls
CutTagHandler.writeExpandAllControls = function() {
  // writes to each span.cutTagControls
  var domObjects = document.getElementsByTagName( "span" );
  var items = DOM.filterElementsByClassName( domObjects, "cutTagControls" ) || [];
  if ( items != null && items.length > 0 ) {
    var cutTags = CutTagHandler.getAllHandlers( document );
    if ( cutTags.length > 0 ) {
      var writeOpen = false;
      var writeClosed = false;
      var ariaOpen = "";
      var ariaClose = "";
      // see which links we should write
      for ( var i = 0; i < cutTags.length; i++ ) {
        if ( cutTags[i].isOpen() ) {
          writeClosed = true;
          ariaClose += " div-cuttag_" + cutTags[i].data.journal + "_" + cutTags[i].data.ditemid + "_" + cutTags[i].data.cutid;
        } else {
          writeOpen = true;
          ariaOpen += " div-cuttag_" + cutTags[i].data.journal + "_" + cutTags[i].data.ditemid + "_" + cutTags[i].data.cutid;
        }
      }

      var htmlString = "";
      if ( writeOpen ) {
        htmlString = '<a href = "javascript:CutTagHandler.openAll(document)"><img style="border: 0;" src="' + Site.imgprefix + '/collapseAll.gif" aria-controls="' + ariaOpen + '" alt="' + expandAll + '" title="' + expandAll + '"/></a> ';
      } else {
        htmlString = '<img style="border: 0; opacity: 0.4; filter: alpha(opacity=40); zoom: 1;" src="' + Site.imgprefix + '/collapseAll.gif" alt="' + expandAll + '" title="' + expandAll + '"/> ';
      }
      if ( writeClosed ) {
        htmlString = htmlString + '<a href = "javascript:CutTagHandler.closeAll(document)"><img style="border: 0;" src="' + Site.imgprefix + '/expandAll.gif" aria-controls="' + ariaClose + '" alt="' + collapseAll + '" title="' + collapseAll + '"/></a>';
      } else {
        htmlString = htmlString + '<img style="border: 0; opacity: 0.4; filter: alpha(opacity=40); zoom: 1;" src="' + Site.imgprefix + '/expandAll.gif" alt="' + collapseAll + '" title="' + collapseAll + '"/>';
      }
      for ( itemCount = 0; itemCount < items.length; itemCount++ ) {
        var controlsTag = items[itemCount];
        if ( controlsTag != null ) {
          controlsTag.innerHTML=htmlString;
        }
      }
    }
  }
}

