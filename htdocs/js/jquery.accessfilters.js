let unsaved_changes = false;

let rowcount = $("#content tr").length - 3; // We have two header rows and one footer row to remove from the count.
if ( rowcount >= 60) {
	$("#add-more-row").hide();
}



$("#current_group").on("change", (evt) => {
	let confirm = true;
	if (unsaved_changes) {
		confirm = window.confirm(unsaved);
	}
	if (confirm) {
	let group_id = $("#current_group").val();
	let success = function(data) {
		let state = {memberlist: $("#members-wrapper").html()};
		$("#members-wrapper").html(data.members);
		// we just loaded more data, so reset our 'unsaved changes' flag.
		$('#unsaved-warn').hide();
		unsaved_changes = false;
		$(".only-js").removeClass('only-js');

		// let url =  new URL(window.location);
		// url.searchParams.set('group_id', group_id);
		// console.log(url.toString());
		// history.pushState(state, "", url);
	};
	handle_post({current_group: group_id, mode: 'getmembers'}, success, evt);
 } else {
    evt.preventDefault();
    evt.stopPropagation(); 
 }
});

// addEventListener("popstate", (event) => {
// 	$("#members-wrapper").html(event.state.memberlist);
// });

$("#save_members").on("click", (evt) => {
	let group_id = $("#current_group").val();
	let selected =  $( ".checkbox-multiselect-item :checked" ).map( (i, el) => el.value).get();
	let success = (data) => {
		$(evt.target).ajaxtip().ajaxtip("success", data.msg);
	};
	handle_post({current_group: group_id, members: selected, mode: 'savemembers'}, success, evt);

});

$("#members-wrapper").on("click", ".input-row", (evt) => {
	unsaved_changes = true;
	$('#unsaved-warn').show();

});

$('#add-more').click( function(evt) {
    evt.preventDefault();
    evt.stopPropagation(); 
	first_new = first_new + 1;

	let clone_row = $("#add-more-row").prev('.clone').clone();

	let textbox = clone_row.find('.name');
	textbox.attr('name', `new_name_${first_new}`);
	textbox.attr('id', `new_name_${first_new}`);

	let numbox = clone_row.find('.sortorder');
	numbox.attr('name', `new_sortorder_${first_new}`);
	numbox.attr('id', `new_sortorder_${first_new}`);

	clone_row.insertBefore("#add-more-row");

	rowcount = rowcount + 1;
	if ( rowcount >= 60) {
		$("#add-more-row").hide();
	}

})

$('.delete_group').click(function(evt) {
    var allow = window.confirm(del);
    if (allow) {
    	let id = evt.target.value;
        let success = (data) => {
        	$(evt.target).ajaxtip().ajaxtip("success", data.msg);
        	$(evt.target).parents('tr').remove();
        };
		handle_post({group_id: id, mode: 'deletegroup'}, success, evt);
    } else {
        evt.preventDefault();
        evt.stopPropagation(); 
    }
});

function handle_post(data, success, evt) {
    $.ajax({
	    type: "POST",
	    url: "/__rpc_accessfilters",
	    contentType: 'application/json',
	    data: JSON.stringify(data),
	    success: function(data) {
	        if (data.success) {
	            success(data.success);
	        } else {
	            $(evt.target).ajaxtip()
	                .ajaxtip("error", data.alert);
	        }
	    },
	    dataType: "json"
	});
  
    evt.preventDefault();
    evt.stopPropagation();
}