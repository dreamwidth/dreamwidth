jQuery(function($) {
// Icon form, lifted wholesale from jquery.replyforms.js
var iconSelect = $("#prop_picture_keyword");

function randomIcon() {
    if ( iconSelect.length === 0 ) return;

    // take a random number, ignoring the "(default)" and "(random)" options
    var randomnumber = Math.floor(
        Math.random() * (iconSelect.prop("length") - 2)
    ) + 2;
    iconSelect.prop("selectedIndex", randomnumber);
    iconSelect.change();
}

// Add random icon option to menu if there's more than one icon
if ( $('option#random').length === 0 && iconSelect.children('option').length > 2 ) {
    iconSelect.children('option').first()
        .after('<option value=",random" id="random">(random) 🔀</option>');
        // Commas are illegal in keywords, so this won't conflict with
        // anyone's real icons. Since the value immediately changes to
        // something else if you select it, this should never be
        // submitted... but if it is, it just reverts to the default icon.
}

// Random icon re-roll button (hidden until random is selected once)
$("#randomicon").on("click", randomIcon);


// New-new icon browser, if available
if ( $.fn.iconBrowser ) {
    $('#js-icon-browser').removeClass('hide-icon-browser');
    iconSelect.iconBrowser({
        triggerSelector: "#lj_userpicselect, #js-icon-browse",
        modalId: "js-icon-browser",
        focusAfterBrowse: $('#lj_userpicselect').data('iconbrowserFocusAfterBrowse'),
        preferences: {
            "keywordorder": $('#lj_userpicselect').data('iconbrowserKeywordorder'),
            "metatext": $('#lj_userpicselect').data('iconbrowserMetatext'),
            "smallicons": $('#lj_userpicselect').data('iconbrowserSmallicons')
        }
    });
}
var iconPreview = $(".block-icon");
iconPreview.removeClass("no-label"); // hides browse button in talkform when no JS.


iconSelect.on("change", function(e) {
    var selection = $(this).find("option:selected");
    if (selection.attr('id') === 'random') {
        randomIcon();
        // For easy re-rolls:
        $("#randomicon").show();
    } else {
        // Update icon preview
             iconPreview.find("img")
            .attr("src", selection.data("url"))
            .removeAttr("width").removeAttr("height").removeAttr("alt");
        if (selection.attr('value') === '') {
            iconPreview.addClass("default");
        } else {
            iconPreview.removeClass("default");
        }
    }
});
});