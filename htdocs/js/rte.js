var UserTagCache = {};

function LJUser(textArea) {
    var editor_frame = $(textArea + '___Frame');
    if (!editor_frame) return;
    if (! FCKeditor_LOADED) return;
    if (! FCKeditorAPI) return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;

    var html = oEditor.GetXHTML(false);
    if (html) html = html.replace(/<\/(lj|user)>/, '');
    var regexp = /<(?:lj|user)( (?:user|name|site)=[^/>]+)\/?>\s?(?:<\/(?:lj|user)>)?\s?/g;
    var attrs_regexp = /(user|name|site)=['"]([.\w-]+?)['"]/g;
    var userstr;
    var users = [];
    var username;

    while ((users = regexp.exec(html))) {
        var attrs = [];
        var postData = { 'username': '', 'site': '' };

        while (( attrs=attrs_regexp.exec(users[1]) )) {
            if (attrs[1] == 'user' || attrs[1] == 'name')
                postData.username = attrs[2];
            else
                postData[attrs[1]] = attrs[2];
        }
        var url = window.parent.Site.siteroot + "/tools/endpoints/ljuser";

        var gotError = function(err) {
            alert(err+' '+username);
            return;
        }

        // trim any trailing spaces from the userstr
        // so that we don't get rid of them when we do the replace below
        var userStrToReplace = users[0].replace(/\s\s*$/, '');

        var gotInfo = (function (userstr, username, site) { return function(data) {
            if (data.error) {
                alert(data.error+' '+username);
                return;
            }
            if (!data.success) return;

            if ( site )
                data.ljuser = data.ljuser.replace(/<span.+?class=['"]?ljuser['"]?.+?>/,'<div class="ljuser" site="' + site + '">');
            else
                data.ljuser = data.ljuser.replace(/<span.+?class=['"]?ljuser['"]?.+?>/,'<div class="ljuser">');

            data.ljuser = data.ljuser.replace(/<\/span>\s?/,'</div>');
            UserTagCache[username + "_" + site] = data.ljuser;

            html = html.replace(userstr,data.ljuser);
            oEditor.SetData(html);
            oEditor.Focus();
        }})(userStrToReplace, postData.username, postData.site);

        if ( UserTagCache[postData.username+"_"+postData.site] ) {
            html = html.replace( userStrToReplace, UserTagCache[postData.username+"_"+postData.site] );
            oEditor.SetData(html);
            oEditor.Focus();
        } else {
            var opts = {
                "data": window.parent.HTTPReq.formEncoded(postData),
                "method": "POST",
                "url": url,
                "onError": gotError,
                "onData": gotInfo
            };

            window.parent.HTTPReq.getJSON(opts);
        }
    }
}


function useRichText(textArea, statPrefix) {
    if ( $("switched_rte_on").value == '1' ) return;

    var rte = new FCKeditor();
    var t = rte._IsCompatibleBrowser();
    if (!t) return;

    if ($("insobj")) {
        $("insobj").className = 'on';
    }
    if ($("jrich")) {
        $("jrich").className = 'on';
    }
    if ($("jplain")) {
        $("jplain").className = '';
    }
    if ($("htmltools")) {
        $("htmltools").style.display = 'none';
    }

    var entry_html = $(textArea).value;

    entry_html = convertToHTMLTags(entry_html, statPrefix);
    if ($("event_format") && !$("event_format").checked) {
        entry_html = entry_html.replace(/\n/g, '<br />');
    }

    var editor_frame = $(textArea + '___Frame');
    // Check for RTE already existing.  IE will show multiple iframes otherwise.
    if (!editor_frame) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + "/fck/";
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = "Update";
        $(textArea).value = entry_html;
        oFCKeditor.ReplaceTextarea();

    } else {
        if (! FCKeditorAPI) return;
        var oEditor = FCKeditorAPI.GetInstance(textArea);
        editor_frame.style.display = "block";
        $(textArea).style.display = "none";
        oEditor.SetData(entry_html);

        oEditor.Focus();
        // Hack for handling submitHandler
        oEditor.switched_rte_on = '1';
    }

    // Need to pause here as it takes some time for the editor
    // to actually load within the browser before we can
    // access it.
    setTimeout("LJUser('" + textArea + "')", 2000);


    $("switched_rte_on").value = '1';

    return false; // do not follow link
}

function usePlainText(textArea) {
    if ( $("switched_rte_on").value == '0' ) return;

    if (! FCKeditorAPI) return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;
    var editor_frame = $(textArea + '___Frame');

    var html = oEditor.GetXHTML(false);
    html = convertToTags(html);
    if ($("event_format") && !$("event_format").checked) {
        html = html.replace(/\<br \/\>/g, '\n');
        html = html.replace(/\<p\>(.*?)\<\/p\>/g, '$1\n');
        html = html.replace(/&nbsp;/g, ' ');
    }

    $(textArea).value = html;
    oEditor.Focus();

    if ($("insobj"))
        $("insobj").className = '';
    if ($("jrich"))
        $("jrich").className = '';
    if ($("jplain"))
        $("jplain").className = 'on';
    editor_frame.style.display = "none";
    $(textArea).style.display = "block";
    $('htmltools').style.display = "block";
    $("switched_rte_on").value = '0';

    // Hack for handling submitHandler
    oEditor.switched_rte_on = '0';

    return false;
}

function convert_post(textArea) {
    if ( $("switched_rte_on").value == '0' ) return;

    var oEditor = FCKeditorAPI.GetInstance(textArea);
    var html = oEditor.GetXHTML(false);

    var tags = convert_poll_to_tags(html, true);

    $(textArea).value = tags;
    oEditor.SetData(tags);
}

function convert_to_draft(html) {
    if ( $("switched_rte_on").value == '0' ) return html;

    var out = convert_poll_to_tags(html, true);
    out = out.replace(/\n/g, '');

    return out;
}

function convert_poll_to_tags (html, post) {
    var tags = html.replace(/<div id=['"]poll(.+?)['"]>[^\b]*?<\/div>/gm,
                            function (div, id){ return generate_poll(id, post) } );
    return tags;
}

function generate_poll(pollID, post) {
    var poll = LJPoll[pollID];
    var tags = poll.outputPolltags(pollID, post);
    return tags;
}

function convert_poll_to_HTML(plaintext) {
    var html = plaintext.replace(/<(?:lj-)?poll name=['"].*['"] id=['"]poll(\d+?)['"].*>[^\b]*?<\/(?:lj-)?poll>/gm,
                                 function (ljtags, id){ return generate_pollHTML(ljtags, id) } );
    return html;
}

function generate_pollHTML(ljtags, pollID) {
    try {
        var poll = LJPoll[pollID];
    } catch (e) {
        return ljtags;
    }

    var tags = "<div id=\"poll"+pollID+"\">";
    tags += poll.outputHTML();
    tags += "</div>";

    return tags;
}

// Constant used to check if FCKeditorAPI is loaded
var FCKeditor_LOADED = false;

function FCKeditor_OnComplete( editorInstance ) {
    editorInstance.Events.AttachEvent( 'OnAfterLinkedFieldUpdate', doLinkedFieldUpdate) ;
    FCKeditor_LOADED = true;
}

function doLinkedFieldUpdate(oEditor) {
    var html = oEditor.GetXHTML(false);
    var tags = convertToTags(html);

    $('draft').value = tags;
}

function convertToTags(html) {
    // no site
    html = html.replace(/<div class=['"]ljuser['"]>.+?<b>(\w+?)<\/b><\/a><\/div>/g, '<user name=\"$1\">');
    // with site
    html = html.replace(/<div(?: site=['"](.+?)['"]) class=['"]ljuser['"]>.+?<b>(\w+?)<\/b><\/a><\/div>/g, '<user name=\"$2\" site=\"$1\">');
    html = html.replace(/<div class=['"]ljraw['"]>(.+?)<\/div>/g, '<raw-code>$1</raw-code>');
    html = html.replace(/<div class=['"]ljembed['"](\s*embedid="(\d*)")?\s*>(.*?)<\/div>/gi, '<site-embed id="$2">$3</site-embed>');
    html = html.replace(/<div\s*(embedid="(\d*)")?\s*class=['"]ljembed['"]\s*>(.*?)<\/div>/gi, '<site-embed id="$2">$3</site-embed>');
    html = html.replace(/<div class=['"]ljcut['"] text=['"](.+?)['"]>(.+?)<\/div>/g, '<cut text="$1">$2</cut>');
    html = html.replace(/<div text=['"](.+?)['"] class=['"]ljcut['"]>(.+?)<\/div>/g, '<cut text="$1">$2</cut>');
    html = html.replace(/<div class=['"]ljcut['"]>(.+?)<\/div>/g, '<cut>$1</cut>');

    html = convert_poll_to_tags(html);
    return html;
}

function convertToHTMLTags(html, statPrefix) {
    html = html.replace(/<(lj-)?cut text=['"](.+?)['"]>([\S\s]+?)<\/\1cut>/gm, '<div text="$2" class="ljcut">$3</div>');
    html = html.replace(/<(lj-)?cut>([\S\s]+?)<\/\1cut>/gm, '<div class="ljcut">$2</div>');
    html = html.replace(/<(lj-raw|raw-code)>([\w\s]+?)<\/\1>/gm, '<div class="ljraw">$2</div>');
    // Match across multiple lines and extract ID if it exists
    html = html.replace(/<(lj|site)-embed\s*(id="(\d*)")?\s*>\s*(.*)\s*<\/\1-embed>/gim, '<div class="ljembed" embedid="$3">$4</div>');

    html = convert_poll_to_HTML(html);

    return html;
}
