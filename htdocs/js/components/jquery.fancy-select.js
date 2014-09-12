(function($) {

function userTag(matchFull, p1) {
    var username;
    var journaltype;
    var userinfo = p1.split(":");
    if (userinfo.length == 2) {
        journaltype = userinfo[0] == "c" ? "community" : "personal";
        username = userinfo[1];
    } else {
        journaltype = "personal";
        username = userinfo[0];
    }

    return "<img src='" + Site.imgprefix +"/silk/identity/" +
            (journaltype == "community" ? "community" : "user")+ ".png'" +
        " width='16' height='16'" +
        " style='padding-right: 1px;' alt='[" + journaltype + " profile]' />" +
        username;
}

function imageTag(data) {
    var img = data.split(":");
    var w = img[1] ? " width='" + img[1] + "'" : ""
    var h = img[2] ? " height='" + img[2] + "'" : ""
    return "<img src='" + Site.imgprefix + img[0]+ "' alt=''" + w + h + " /> ";
}

function updateSelected(e) {
    var $selected = $(e.target).find("option:selected");
    var text = $selected.data("fancyselect-format");
    var image = $selected.data("fancyselect-img");

    var displayHTML = text.replace(/(?:@([^\s]+))/, userTag);
    if (image) {
        displayHTML = imageTag(image) + displayHTML;
    }

    $(e.target).next().find("output").html(displayHTML);
}

function setMinWidth($ele, newMin, padding) {
    newMin = parseInt(newMin) || 0;
    padding = parseInt(padding) || 0;
    var mw = parseInt( $ele.css("min-width") ) || 0;

    $ele.css("min-width", Math.max(mw, newMin) + padding + "px")
}

$.fn.extend({
    fancySelect: function() {
        $(this).find(".fancy-select select").each(function() {
            var $select = $(this);
            $select
                .wrap("<div class='fancy-select-select'/>")
                .after("<span class='fancy-select-output split button secondary' aria-hidden='true'><output></output><span class='fancy-select-arrow'></span></span>")
                .focus(function() {
                    $(this).next(".fancy-select-output").addClass("focus");
                })
                .blur(function() {
                    $(this).next(".fancy-select-output").removeClass("focus");
                })
                .change(updateSelected)
                .change(function() {
                    setMinWidth(
                        $(this).next(".fancy-select-output"),
                        $(this).parent(".fancy-select-select").width()
                    );
                })
                .trigger("change");

            setMinWidth(
                $select.next(".fancy-select-output"),
                $select.width(),
                30
            );
        });

    }
});

})(jQuery);
