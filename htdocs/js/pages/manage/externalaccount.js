// Show/hide the custom-site fields and the per-protocol option sections on
// /manage/externalaccount, based on the selected site and service type.

// returns the currently selected protocol.  if we're editing an account, the
// form carries the account's protocol; otherwise it comes from the selected
// site's option (or the selected service type, for a custom site).
function getProtocol() {
    var form = document.getElementById("createacct");
    if (form && form.dataset.protocol) return form.dataset.protocol;

    var siteSelect = document.getElementById("site");
    if (!siteSelect) return null;

    if (siteSelect.value === "-1") {
        var serviceType = document.getElementById("servicetype");
        return serviceType ? serviceType.value : null;
    }

    var selected = siteSelect.options[siteSelect.selectedIndex];
    return selected ? selected.dataset.protocol : null;
}

// shows the custom-site fields only when 'Other Site' is selected, then
// updates the protocol option sections to match.
function updateSiteSelection() {
    var siteSelect = document.getElementById("site");
    var customSite = document.getElementById("customsite");
    if (siteSelect && customSite) {
        customSite.style.display = siteSelect.value === "-1" ? "" : "none";
    }
    updateProtocolSelection();
}

// shows only the option section for the currently selected protocol.
function updateProtocolSelection() {
    var protocol = getProtocol();
    var sections = document.getElementsByClassName("protocol_options");
    for (var i = 0; i < sections.length; i++) {
        sections[i].style.display = sections[i].id === protocol + "_options" ? "" : "none";
    }
}

document.addEventListener("DOMContentLoaded", function () {
    var siteSelect = document.getElementById("site");
    if (siteSelect) siteSelect.addEventListener("change", updateSiteSelection);

    var serviceType = document.getElementById("servicetype");
    if (serviceType) serviceType.addEventListener("change", updateProtocolSelection);

    updateSiteSelection();
});
