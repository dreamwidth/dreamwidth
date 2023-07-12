$("#current_group").on("change", (evt) => {
	let group_id = $("#current_group").val();
	let success = function(data) {
		let state = {memberlist: $("#members-wrapper").html()};
		$("#members-wrapper").html(data.members);

		// let url =  new URL(window.location);
		// url.searchParams.set('group_id', group_id);
		// console.log(url.toString());
		// history.pushState(state, "", url);
	};
	handle_post({current_group: group_id, mode: 'getmembers'}, success, evt);

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