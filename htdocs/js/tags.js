
function initTagPage()
{
    // initial page load - setup page elements based on
    // what is selected in the option list.
    // (initial page load has nothing selected, of course,
    // but we need to check anyway for 'back' button stuff.)
    var list = document.getElementById("tags");
    if (list) tagselect(list);
}

function toggle_actions( selected_num )
{
    var form = document.getElementById("tagform");
    if (! form) return;

    // names of form elements to disable/enable
    // on item selections
    var toggle_elements_disabled = [], toggle_elements_enabled = [];
    switch ( selected_num ) {
        case 0:
            toggle_elements_disabled = ["rename", "rename_field", "merge", "merge_field", "delete", "show posts"];
            break;
        case 1:
            toggle_elements_enabled = ["rename", "rename_field", "delete", "show posts"];
            toggle_elements_disabled = ["merge", "merge_field"];
            break;
        default:
            toggle_elements_enabled = ["merge", "merge_field", "delete", "show posts"];
            toggle_elements_disabled = ["rename", "rename_field"];
            break;
    }

    for ( i = 0; i < toggle_elements_disabled.length; i++ ) {
        form.elements[toggle_elements_disabled[i]].disabled = true;
    }

    for ( i = 0; i < toggle_elements_enabled.length; i++ ) {
        form.elements[toggle_elements_enabled[i]].disabled = false;
    }

}

function tagselect(list)
{
    if (! list) return;

    var selected_num = 0;        // counter
    var selected = new Array();  // tagnames, for display

    var selected_id;             // tag id if only one selected
    var id_re = /^\d+/;

    for ( $i = 0; $i < list.options.length; $i++ ) {
        if (list.options[$i].selected) {
            var val = list.options[$i].value.replace( /&/g, "&amp;" );
            selected[selected_num] = val.substring( val.indexOf('_')+1 );
            selected_num++;
            selected_id = val.match(id_re);
        }
    }

    var form = document.getElementById("tagform");
    if (! form) return;

    var tagfield   = document.getElementById("selected_tags");
    var tagprops   = document.getElementById("tag_props");
    if (! tagfield || ! tagprops ) return;

    // reset any 'red' fields
    reset_field( form.elements[ "rename_field" ]);
    reset_field( form.elements[ "add_field" ]);

    toggle_actions(selected_num);

    // no selections
    if (! selected_num) {
        toggle_actions(0);
        show_props(tagprops);
    } else {
        tagfield.innerHTML = selected.join(", ");

        // exactly one selection
        if (selected_num == 1) {
            show_props(tagprops, selected_id);
        }

        // multiple items selected
        else {
            show_props(tagprops);
        }
    }

}

// just check for non-space characters or 'bad phrase',
// change css on problems.
function validate_input(btn, field_name, badtext)
{
    var form = document.getElementById("tagform");
    if (! form) return true;  // let submit happen
    var field = form.elements[ field_name ];
    if (! field) return true;

    var re = /\S/;
    if (! field.value.match(re) || field.value.indexOf(badtext) != -1) {
        field.className = 'error';
        return false;
    }

    return true;
}

function reset_field(field, resettext)
{
    if ( !field ) return;
    field.className = 'tagfield';
    if (resettext && field.value.indexOf(resettext) != -1) field.value = '';
}

// update tag properties - display with 
// security counts.  right now, we have a 
// JS array with everything in tags.bml.
// eventually, this needs to be some xml-rpc goodness,
// with JS caching on the results of rpc calls.
function show_props(div, id)
{
    var tag = tags[id];
    var out;

    if (! tag) tag = [ ml.na_label, ml.na_label, '-', '-', '-', '-', '-' ];

    var secimg = '&nbsp; <img align="middle" src="/img/';
    var seclabel;
    if (tag[1] == "public") {
        secimg = secimg + "silk/identity/user.png";
        seclabel = ml.public_label;
    }
    else if (tag[1] == "private") {
        secimg = secimg + "silk/entry/private.png";
        seclabel = ml.private_label;
    }
    else if (tag[1] == "protected") {
        secimg = secimg + "silk/entry/locked.png";
        seclabel = ml.trusted_label;
    } 
    else if (tag[1] == "group") {
        secimg = secimg + "silk/entry/filtered.png";
        seclabel = ml.filters_label;
    }
    secimg = secimg + '" />';
    if (tag[1] == "n/a") secimg = "";

    out = "<table class='proptbl column-table' cellspacing='0'><tbody>";
    out = out + "<tr><td class='h' colspan='2'>" + ml.counts_label + "</td></tr>";
    out = out + "<tr><th>" + ml.public_label + "</th><td class='c'>" + tag[2] + "</td></tr>";
    out = out + "<tr><th>" + ml.private_label + "</th><td class='c'>" + tag[3] + "</td></tr>";
    out = out + "<tr><th>" + ml.trusted_label + "</th><td class='c'>" + tag[4] + "</td></tr>";
    out = out + "<tr><th>" + ml.filters_label + "</th><td class='c'>" + tag[5] + "</td></tr>";
    out = out + "<tr class='summary'><th>" + ml.total_label + "</th><td class='highlight'>" + tag[6] + "</td></tr>";
    out = out + "<tr class='summary'><th style='height: 16px'>" + ml.security_label + "</th><td class='highlight' align='middle'>" + seclabel + secimg + "</td></tr>";
    out = out + "</tbody></table>";

    div.innerHTML = out;
    return;
}

// for edittags.bml
function edit_tagselect(list)
{
    if (! list) return;

    var selected = new Array();  // tagnames, for display
    selected_num = 0;

    for ( $i = 0; $i < list.options.length; $i++ ) {
        if (list.options[$i].selected) {
            selected[selected_num] = list.options[$i].value;
            selected_num++;
        }
    }

    var form = document.getElementById("edit_tagform");
    if (! form) return;

    var tagfield = form.elements[ "tagfield" ];
    if (! tagfield ) return;

    // merge selected and current tags into new array
    var cur_tags = new Array();
    cur_tags = cur_taglist.split(", ");

    var taglist = new Array();

    for ( $i = 0; $i < selected.length; $i++ ) {
        var sel_tag = selected[$i];
        var seen = 0;
        for ( $j = 0; $j < cur_tags.length; $j++ ) {
            if (sel_tag == cur_tags[$j]) seen = 1;
        }
        if (seen == 0) taglist.push(sel_tag);
    }

    if (taglist.length) {
        if (cur_taglist.length > 0) {
            tagfield.value = cur_taglist + ", " + taglist.join(", ");
        } else {
            tagfield.value = taglist.join(", ");
        }
    } else {
        tagfield.value = cur_taglist;
    }

    return;
}


