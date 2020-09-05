$('#check_all').change(function() {
    var checked = $( this );
    $('.item_checkbox').prop("checked", checked.is(':checked'));
});

$('.action_button').click(function () {
    var action = $(this).data('action');
    mark_items(action);
    return false;
});

$("#inbox_messages").on("click", ".item_expand_action", function(){
    var qid = $(this).data('qid');
    var child = $(this).children();
    var item = $("#inbox_item_" + qid);

    if (item.hasClass('inbox_collapse')) {
        item.removeClass('inbox_collapse');
        item.addClass('inbox_expand');
        child.attr({'src': '/img/expand.gif',
                'alt': 'Collapse',
                'title': 'Collapse'
                });
    } else {
        item.removeClass('inbox_expand');
        item.addClass('inbox_collapse');
        child.attr({'src': '/img/collapse.gif',
                'alt': 'Expand',
                'title': 'Expand'
                });
        }
    return false;
});

$("#inbox_messages").on("click", ".item_bookmark_action", function(){
    var action = $(this).data('action');
    var qid = $(this).data('qid');
    mark_items(action, qid);
    return false;
});


function mark_items(action, qid) {
    // Build array of checked items to send
    if (qid == null) {
        var item_qids = [];
        $('.item_checkbox').each(function() {
            var box = $(this);
            if (box.is(':checked')) {
                item_qids.push(box.val());
            }
        });
    } else {
        var item_qids = qid;
    }

    // Grab param data from the hidden fields
    var auth_token = $("[name=lj_form_auth]").val();
    var view  = $("[name=view]").val();
    var page  = $("[name=page]").val();
    var itemid  = $("[name=itemid]").val();

    var postData = {
            'lj_form_auth': auth_token,
            'ids': item_qids,
            'action': action,
            'view': view,
            'page': page,
            'itemid': itemid }

    $.ajax({
      type: "POST",
      url: "/__rpc_inbox_actions",
      contentType: 'application/json',
      data: JSON.stringify(postData),
      success: function( data ) { $( "#inbox_message_list" ).html(data);
                                        alert(confirmation);
                                        },
      dataType: "html"
    });
    event.preventDefault();

    // We've reloaded the view, so set the select-all checkbox to unchecked.
    $('#check_all').prop("checked", false);
}

// Only load this on the compose page
if ($('#msg_to').length) {
    let source = autocomplete_list ? autocomplete_list : [];
    $('#msg_to').autocompletewithunknown(
        {populateSource: source,
        }
    );
}
$('.folders').removeClass('no-js');
$("#folder_btn").removeClass('no-js');
$("#folder_btn").click(function() {
    var folders = $('#folder_list');
    var img = $(this).children();

    if (folders.hasClass('folder_collapsed')) {
        folders.removeClass('folder_collapsed');
        folders.addClass('folder_expanded');
        img.attr({'src': '/img/expand.gif',
        'alt': 'Collapse',
        'title': 'Collapse'
        });

    } else {
        folders.removeClass('folder_expanded');
        folders.addClass('folder_collapsed');
        img.attr({'src': '/img/collapse.gif',
        'alt': 'Expand',
        'title': 'Expand'
        });
        }
    }
);

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
    iconSelect.iconBrowser({
        triggerSelector: "#lj_userpicselect",
        modalId: "js-icon-browser",
        preferences: {
            "metatext": $('#lj_userpicselect').data('iconbrowserMetatext'),
            "smallicons": $('#lj_userpicselect').data('iconbrowserSmallicons')
        }
    });
}

iconSelect.on("change", function(e) {
    var selection = $(this).find("option:selected");
    if (selection.attr('id') === 'random') {
        randomIcon();
        // For easy re-rolls:
        $("#randomicon").show();
    } else {
        // Update icon preview
        var iconPreview = $(".qr-icon");
        iconPreview.removeClass("no-label"); // hides browse button in talkform when no JS.
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
