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

