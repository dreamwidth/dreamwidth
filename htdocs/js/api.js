$(function() {
	$("body").collapse();
	var api_key = $('#api_key').text();
	function api_request(event) {
		event.preventDefault();
form = $(event.target);

path = form.children('input[name=path]').val();
method = form.children('input[name=method]').val();

var pathvars = form.children('input[data-location=path]').serializeArray();
var queryvars = form.children('input[data-location=query]').serialize();
var requestbody = {};
form.children('input[data-location=body]').each(function(index, item){
	if (item.value !== '') {
	console.log(item.getAttribute('data-type'));
        if (item.getAttribute("data-type") == "integer") {
            console.log(item.value);
            var num = new Number(item.value)
            console.log(num);
            requestbody[item.name] = num.valueOf();
        }
        if (item.getAttribute("data-type") == "boolean") {
            console.log(item.value);
            requestbody[item.name] = (item.value == "true");
        }
        else {
            requestbody[item.name] = item.value;
        }
	}
});

$.each(pathvars, function(index, item) {
	var re = new RegExp('{' + item.name + '}');
	path = path.replace(re, item.value);
	});

if (queryvars.length > 0) {
	path = path + "?" + queryvars;
}

var resp = form.children('.response');
var ajax_settings = {
	url: "/api/v1" + path,
	contentType: 'application/json',
	headers: {"Authorization": "Bearer " + api_key},
	type: method,
	success: function(data) {
		resp.html('<pre>' + JSON.stringify(data, null, '\t') + '</pre>');
		resp.removeClass('hide').addClass('alert-box success');
	},
    error: function(XHR, status, error) {
		resp.html('<pre>' + status + '\n' + error + '</pre>');
		resp.removeClass('hide').addClass('alert-box alert');
	}
}

console.log(requestbody);
if (! $.isEmptyObject(requestbody)) {
	ajax_settings.data = JSON.stringify(requestbody)
}
$.ajax(ajax_settings);
return false;
};

$('form').submit(api_request);

	});