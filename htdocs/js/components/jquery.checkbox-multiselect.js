$('input').removeClass('no-js');

// var lastTarget;
// var shiftKey = false;
// window.onkeyup = function(e) { if (e.key == 'Shift') {shiftKey = false;} }
// window.onkeydown = function(e) { if (e.key == 'Shift') {shiftKey = true; } }

$(".checkbox-multiselect-wrapper").on('input', ".multiselect-search", (evt) => {
	let input_str = evt.target.value;
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {
		let el_str = $(el).find("input")[0].value;
		console.log(el_str);
		if (el_str.match(input_str)) {
			$(el).show();
		} else {
			$(el).hide();
		}
	});	

});

$(".checkbox-multiselect-wrapper").on('click', "#select-all", () => {
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {$(el).find('input:visible').attr('checked', true)});
})

$(".checkbox-multiselect-wrapper").on('click', "#selected-only", () => {
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {
		if ($(el).find(":checked").length == 0) {
			$(el).hide();
		}
	});
});

$(".checkbox-multiselect-wrapper").on('click', "#clear-filters", () => {
	$(".multiselect-search").val("");
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {
		$(el).show();
	});
});

// $(".checkbox-multiselect-wrapper").on('click', ".checkbox-multiselect-item.input-row", (evt) => {
// 	console.log(lastTarget);
// 	console.log(shiftKey);
// 	if (lastTarget && shiftKey) {
// 		let currentTarget = $(evt.target).parent();
// 		let markItem = false;
// 		console.log(currentTarget);
// 		let checkboxlist = $('.checkbox-multiselect-item.input-row');
// 		checkboxlist.each((i, el) => {
// 			if ($(el) == lastTarget || $(el) == currentTarget) {
// 				console.log("matched");
// 				markItem = !markItem;
// 			}
// 			if (markItem) {
// 				$(el).find('input:visible').attr('checked', true);
// 			}
// 		});

// 	} else {
// 		lastTarget = $(evt.target).parent();
// 	}

// })