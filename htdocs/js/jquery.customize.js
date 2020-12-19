jQuery(function($){

var authas = $('#authas').val();
var queryArgs = new URLSearchParams(window.location.search);

// Set up journaltitles functions
function editTitle(event) {
            event.preventDefault();
            var title = $(event.target).closest(".title_form");

            title.find(".title_modify").css("display", "inline");
            title.find(".title_view").css( "display",  "none");
            title.find(".title_input").focus();

            $(".title_form").each(function() {
                if (!$( this ).is(title)) {
                    $( this ).find(".title_cancel").click();
                }
            });
        }

function cancelTitle(event) {
    event.preventDefault();
    var title = $(event.target).closest(".title_form");

    title.find(".title_modify").css("display", "none");
    title.find(".title_view").css( "display",  "inline");

    // reset appropriate field to default
    title.find(".title_input").value = title.find(".title").value;

    return false;
}

function saveTitle(event) {
    event.preventDefault();
    var title = $(event.target).closest(".title_form");

    title.find(".title_save").attr("disabled", true);
    var value = title.find("input[name=title_value]").val();
    var which = title.find(".which_title").val();
    var postData = {
            which_title: which,
            title_value: value
             };
    if (authas)  postData.authas = authas;

    $.ajax({
      type: "POST",
      url: "/__rpc_journaltitles",
      data: postData,
      success: function( data ) {
          title.find(".title_modify").css("display", "none");
          title.find(".title_view").css( "display",  "inline");
          title.find(".title").text(value);
          title.find(".title_save").attr("disabled", false);
        },

      dataType: "html"
    });

    return false
}
// show view mode & set up handlers for journaltitles
$(".title_view").css("display", "inline");
$(".title_cancel").css("display", "inline");
$(".title_modify").css("display", "none");

$(".title_edit").click(function(event) { editTitle(event); });
$(".title_cancel").click(function(event) { cancelTitle(event); });
$(".title_form").submit(function(event){ saveTitle(event) });

// set up layoutchooser functions
function applyLayout(form, event) {
        var given_layout_choice = $(form).children("[name=layout_choice]").val();
        var given_layout_prop = $(form).children("[name=layout_prop]").val();
        var given_show_sidebar_prop = $(form).children("[name=show_sidebar_prop]").val();

        $("#layout_btn_" + given_layout_choice).attr("disabled", true);
        $("#layout_btn_" + given_layout_choice).addClass("layout-button-disabled disabled");

        var postData = {
                 'layout_choice': given_layout_choice,
                 'layout_prop': given_layout_prop,
                 'show_sidebar_prop': given_show_sidebar_prop
              }
        if (authas)  postData.authas = authas;


        $.ajax({
          type: "POST",
          url: "/__rpc_layoutchooser",
          data: postData,
          success: function( data ) { renderLayoutchooser(data) },
          dataType: "json"
        });
        event.preventDefault();
}



// Functions to re-render areas from JSON.
function renderLayoutchooser(data)   {
    var new_html = "";
    data.layouts.forEach(layout => {
        let temp_html = `<div class="layout-item ${layout.current ? ' selected' : ''}">
        <img src="/img/customize/layouts/${layout.layout}.png" class="layout-preview">
        <p class="layout-desc">${layout.name}</p>`;

        if(!layout.current) {
            temp_html = temp_html + `<form class="layout-form" method="POST">
            <input type="hidden" name="layout_choice" value="${layout.layout}">
            <input type="hidden" name="layout_prop" value="${data.layout_prop}">
            <input type="hidden" name="show_sidebar_prop" value="${data.show_sidebar_prop}">
            <input type="submit" name="apply_layout" value="Apply Layout" id="layout_btn_${layout.layout}" class="layout_button button">
            </form>
        `;
        }
        temp_html = temp_html + "</div>";
    new_html = new_html + temp_html;
        
    });  
    $( "div.layout-content" ).html(new_html);
}

function updateCurrentTheme(data){
    $('.theme-current-desc').html(`by <a href="${data.current.designer_link}" class="theme-designer" data-designer="${data.current.designer}">${data.current.designer}</a>
                    for <a href="${data.current.layout_link}" class="theme-layout" data-layout="${data.current.layout}"><em>${data.current.layout}</em></a>`);
    $('.theme-current-image').attr('src', data.current.imgurl);
    $('.theme-current-name').html(data.current.name);
    $('theme-current-options').html (
        data.current_options.forEach(opt => { return `<li><a href="${opt.url}">${opt.title}</a></li>`; })
    );
}


// init event listeners for layoutchooser
$(".layout-selector-wrapper").on("submit", ".layout-form", function(event){
    event.preventDefault();
    applyLayout(this, event);
});

// init event listeners for currenttheme
$(".theme-current").on("click", ".theme-current-designer", function(event){
            event.preventDefault();
            $(".theme-selector-wrapper").trigger("theme:filter", {"designer": $(this).data('designer')});
    });


    $(".theme-current").on("click", ".theme-current-layout", function(event){
            event.preventDefault();
            $(".theme-selector-wrapper").trigger("theme:filter", {"layoutid" : newLayout});
    });

// init event listeners for themechooser
    //Handle cat links
    $(".theme-selector-wrapper").on( "click", ".theme-nav-cat", function(event){
        event.preventDefault();
        filterThemes(event, "cat", $(this).data('cat'));

        //move CSS classes around for rendering
        $('li.on').removeClass('on');
        $(this).parent('li').addClass('on');


    return false;
})

$(".theme-selector-wrapper").on("theme:filter", function(evt, data) {
    for (var dkey in Object.keys(data)) {
            var dvalue = data[key];
          filterThemes(evt, dkey, dvalue);
        }

});

// add event listener to the search form
$(".theme-selector-wrapper").on("submit", "#search_form", function (evt) { filterThemes(evt, "search", $('#search_box').val()) });

//Handle preview links
$(".theme-selector-wrapper").on("click", ".theme-preview-link", function(){
            window.open($(this).attr("href"), 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
    return false;
})

//Handle the 'apply theme' buttons
$(".theme-selector-wrapper").on("submit", ".theme-form", function(event){
    var btn = $(this).children('.theme_button');
    var auth_token = $(this).children("[name=lj_form_auth]").val();
    btn.attr("disabled", true).addClass("theme-button-disabled disabled");

    var postData = Object.assign({}, queryArgs);
    postData.append('apply_themeid', btn.data('themeid'));
    postData.append('apply_layoutid', btn.data('layoutid'));
    postData.append('lj_form_auth', auth_token);

    $.ajax({
      type: "POST",
      url: "/__rpc_themechooser",
      data: postData.toString(),
      success: function( data ) {      
            $( "div.theme-selector-content" ).html(data.theme_html);
            renderLayoutchooser(data.layout_data);
            updateCurrentTheme(data.current_data);
            alert(confirmation);
        },
      dataType: "json"
    });
    event.preventDefault();

})

function filterThemes(evt, key, value) {
    queryArgs.set(key, value);

    // For some keys, we need to reset the page to 1
    if (key != 'page') {queryArgs.set('page', 1)};

    // Remove mutually-exclusive keys
    if (key != 'page' && key != 'show') {
        if (key != 'cat'){ queryArgs.delete('cat');};
        if (key != 'layoutid'){ queryArgs.delete('layoutid');};
        if (key != 'designer'){ queryArgs.delete('designer');};
        if (key != 'search'){ queryArgs.delete('search');};
    }

    $.ajax({
      type: "GET",
      url: "/__rpc_themefilter",
      data: queryArgs.toString(),
      success: function( data ) { 
          $( "div.theme-selector-content" ).html(data.theme_html);
            updateCurrentTheme(data.current_data);
         },
      dataType: "json"
    });

    evt.preventDefault();

    if (key == "search") {
        $("search_btn").disabled = true;
    } else if (key == "page" || key == "show") {
        $("paging_msg_area_top").innerHTML = "<em>Please wait...</em>";
        $("paging_msg_area_bottom").innerHTML = "<em>Please wait...</em>";
    } else {
        //cursorHourglass(evt);
    }
}

//Handle show select
$(".theme-selector-wrapper").on("change", ".show_dropdown",
    function (event) { filterThemes(event, "show", $(this).val()) }
)

$(".theme-selector-wrapper").on("click", ".theme-paging li", function(event){
        event.preventDefault();
        var pageLink = $(this).children('a').attr('href');
        var newPage = pageLink.replace(/.*page=([^&?]*)&?.*/, "$1");

        //reload the theme chooser area
        filterThemes(event, "page", newPage);
})

//Handle designer and layoutid links
$(".theme-selector-wrapper").on("click", ".theme-layout", function(event){
        event.preventDefault();
        filterThemes(event, "layoutid", $(this).data('layout'));
})

$(".theme-selector-wrapper").on("click", ".theme-designer", function(event){
        event.preventDefault();
        filterThemes(event, "designer", $(this).data('designer'));
});

// Load autocomplete keywords
if ($('#search_box').length) {
    let source = autocomplete_list ? autocomplete_list : [];
    $('#search_box').autocomplete(
        {'source': source,
         'appendTo': '#search_container'
        }
    );
}

});
