// the siteProtocol (if edit), or the map of sites to protocols (if new)
var siteProtocol = null;
var siteProtocolMap = {};

// callback for updating the site selection.  if selecting 'custom site',
// shows the customsitetable.  also calls to updateProtocolSelection().
function updateSiteSelection() {
  var siteSelect = document.getElementById("createacct");
  if (siteSelect != null && siteSelect.site != null) {
    var customsitetable = document.getElementById('customsite');
    if (siteSelect.site.value == -1) {
      customsitetable.style.display='block';
    } else {
      customsitetable.style.display='none';
    }
  }
  updateProtocolSelection();
}

// returns the currently selected protocol.  if we're editing an account,
// uses the preset siteProtocol.  otherwise checks the siteProtocolMap (if a
// configured site is selected) or the selected servicetype (if a custom site
// is selected)
function getProtocol() {
  if (siteProtocol != null)
    return siteProtocool;

  var siteSelect = document.getElementById("createacct");
  if (siteSelect != null && siteSelect.site != null) {
    var customsitetable = document.getElementById('customsite');
    if (siteSelect.site.value == -1) {
      return $('servicetype').value;
    } else {
      return siteProtocolMap[siteSelect.site.value];
    }
  }
}

// updates the protocol selection.  shows/hides the appropriate options rows.
function updateProtocolSelection() {
  var protocol = getProtocol();
  var optionBodies = DOM.getElementsByTagAndClassName(document, "tbody", "protocol_options") || [];
  for (var i = 0; i < optionBodies.length; i++) {
    var optionBody = optionBodies[i];
    if ( optionBody.id != protocol + '_options' ) {
      optionBody.style.display='none';
    } else {
      optionBody.style.display='';
    }
  }

}

LiveJournal.register_hook("page_load", updateProtocolSelection);

