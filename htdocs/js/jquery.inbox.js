$('.check_all').change(function() {
    var checked = $(this);
    $('.item_checkbox').prop("checked", checked.is(':checked'));
    $('.item_checkbox').trigger('change');
    // This is because we have two 'check-all' boxes, and we want them to be in sync
    $('.check_all').prop("checked", checked.is(':checked'));
});

$('.action_button').click(function(e) {
    var action = $(this).data('action');
    mark_items(e, action);
});

$("#inbox_messages").on("click", ".item_expand_action", function(e) {
    var qid = $(this).data('qid');
    var child = $(this).children();
    var item = $("#inbox_item_" + qid);

    if (item.hasClass('inbox_collapse')) {
        item.removeClass('inbox_collapse');
        item.addClass('inbox_expand');
        child.attr({
            'src': '/img/expand.gif',
            'alt': 'Collapse',
            'title': 'Collapse'
        });
    } else {
        item.removeClass('inbox_expand');
        item.addClass('inbox_collapse');
        child.attr({
            'src': '/img/collapse.gif',
            'alt': 'Expand',
            'title': 'Expand'
        });
    }
    e.preventDefault();
    e.stopPropagation();
});

$("#inbox_messages").on("click", ".item_bookmark_action", function(e) {
    var action = $(this).data('action');
    var qid = $(this).data('qid');
    mark_items(e, action, qid);
});

$("#inbox_messages").on("click", ".inbox_item_row", function(e) {
    let checkbox = $(e.currentTarget).find('.item_checkbox');

    // Don't fire if the item clicked on was the checkbox (otherwise the change will trigger twice)
    // Don't fire on link clicks
    if (!$(e.target).hasClass('item_checkbox') && e.target.tagName != "A") {
        checkbox.prop("checked", !checkbox.is(':checked'));
        checkbox.trigger('change');
    }
});


$("#inbox_messages").on("change", ".item_checkbox", function(e) {
    let checkbox = $(e.target);
    let row = checkbox.parents('.inbox_item_row');
    if (checkbox.prop('checked')) {
        row.addClass('selected-msg');
    } else {
        row.removeClass('selected-msg');
    }
    e.preventDefault();
    e.stopPropagation();
});



function mark_items(e, action, qid) {
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
    var view = $("[name=view]").val();
    var page = $("[name=page]").val();
    var itemid = $("[name=itemid]").val();

    var postData = {
        'lj_form_auth': auth_token,
        'ids': item_qids,
        'action': action,
        'view': view,
        'page': page,
        'itemid': itemid
    }

    $.ajax({
        type: "POST",
        url: "/__rpc_inbox_actions",
        contentType: 'application/json',
        data: JSON.stringify(postData),
        success: function(data) {
            if (data.success) {
                $("#inbox_message_list").html(data.success);
            } else {
                $(e.target).ajaxtip()
                    .ajaxtip("error", data.error);
            }
        },
        dataType: "json"
    });
    e.preventDefault();
    e.stopPropagation();

    // We've reloaded the view, so set the select-all checkbox to unchecked.
    $('.check_all').prop("checked", false);
}

// Only load this on the compose page
if ($('#msg_to').length) {
    let source = autocomplete_list ? autocomplete_list : [];
    $('#msg_to').autocompletewithunknown({
        populateSource: source,
    });
}
$('.folders').removeClass('no-js');
$("#folder_btn").removeClass('no-js');
$("#folder_btn").click(function() {
    var folders = $('#folder_list');
    var img = $(this).children();

    if (folders.hasClass('folder_collapsed')) {
        folders.removeClass('folder_collapsed');
        folders.addClass('folder_expanded');
        img.attr({
            'src': '/img/expand.gif',
            'alt': 'Collapse',
            'title': 'Collapse'
        });

    } else {
        folders.removeClass('folder_expanded');
        folders.addClass('folder_collapsed');
        img.attr({
            'src': '/img/collapse.gif',
            'alt': 'Expand',
            'title': 'Expand'
        });
    }
});
