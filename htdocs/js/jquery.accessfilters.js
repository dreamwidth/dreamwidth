$("#current_group").on("change", (evt) => {
	let group_id = $("#current_group").val();
	let success = function(data) { $("#members_wrapper").html(data.members); };
	handle_post({current_group: group_id, mode: 'getmembers'}, success, evt);
});

$("#save_members").on("click", (evt) => {
	let group_id = $("#current_group").val();
	let selected =  $( ".checkbox-multiselect-item :checked" ).map( (i, el) => el.value).get();
	let success = (data) => {$(evt.target).ajaxtip().ajaxtip("success", data.msg);};
	handle_post({current_group: group_id, members: selected, mode: 'savemembers'}, success, evt);

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