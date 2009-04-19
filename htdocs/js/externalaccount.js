
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
}

