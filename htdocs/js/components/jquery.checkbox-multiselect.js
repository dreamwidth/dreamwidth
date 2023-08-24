$('input, .checkbox-multiselect-item, .toggle-row').removeClass('no-js');

$(".checkbox-multiselect-wrapper").on('input', ".multiselect-search", (evt) => {
	let input_str = evt.target.value;
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {
		let el_str = $(el).find("input")[0].value;
		if (el_str.match(input_str)) {
			$(el).removeClass("filtered");
		} else {
			$(el).addClass("filtered");
		}
	});	

});

$(".checkbox-multiselect-wrapper").on('click', "#select-all", () => {
	let state = $("#select-all").attr('checked') ? true : false;
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {$(el).find('input:visible').attr('checked', state)});
})

$(".checkbox-multiselect-wrapper").on('click', "#show-selected", () => {
	let toggle = $('#show-selected').attr('aria-pressed');
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {
		if (toggle == 'true') {
			if ($(el).find(":checked").length == 0 && toggle) {
				$(el).hide();
			} 
		} else {
			$(el).show();
		}
	});
});

$(".checkbox-multiselect-wrapper").on('click', "#clear-filters", () => {
	$(".multiselect-search").val("");
	let checkboxlist = $('.checkbox-multiselect-item.input-row ');
	checkboxlist.each((i, el) => {
		$(el).removeClass("filtered");
	});
});
