var UserTagCache = {};

function LJUser(textArea) {
    var editor_frame = document.getElementById(textArea + '___Frame');
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


function useRichText(textArea, statPrefix, raw) {
    var rte = new FCKeditor();
    var t = rte._IsCompatibleBrowser();
    if (!t) return false;

    const body = document.getElementById(textArea);
    const plainTextBody = body.value;

    var entry_html = convertToHTMLTags(plainTextBody, statPrefix);
    if (!raw) {
        entry_html = entry_html.replace(/\n/g, '<br />');
    }

    var editor_frame = document.getElementById(textArea + '___Frame');
    // Check for RTE already existing.  IE will show multiple iframes otherwise.
    if (!editor_frame) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + "/fck/";
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = "Update";
        oFCKeditor.ReplaceTextarea();
        if (body.style.display !== 'none') return false;
        pendingRichTextBody = plainTextBody;
        body.value = entry_html;

    } else {
        if (!FCKeditor_LOADED || typeof FCKeditorAPI === 'undefined') return false;
        var oEditor = FCKeditorAPI.GetInstance(textArea);
        editor_frame.style.display = "block";
        body.style.display = "none";
        oEditor.SetData(entry_html);

        oEditor.Focus();
        // Hack for handling submitHandler
        oEditor.switched_rte_on = '1';
    }

   LJUser(textArea);
   return true;
}

function usePlainText(textArea, raw) {
    const body = document.getElementById(textArea);
    var editor_frame = document.getElementById(textArea + '___Frame');
    if (!FCKeditor_LOADED) {
        if (typeof FCKeditorAPI !== 'undefined') {
            const queue = FCKeditorAPI._FunctionQueue;
            const loadToolbar = editor_frame.contentWindow.LoadToolbar;
            if (queue.Functions.includes(loadToolbar)) queue.Remove(loadToolbar);
        }
        editor_frame.remove();
        document.getElementById(textArea + '___Config').remove();
        body.value = pendingRichTextBody;
        pendingRichTextBody = undefined;
        body.style.display = "block";
        return;
    }
    if (typeof FCKeditorAPI === 'undefined') return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;

    var html = oEditor.GetXHTML(false);
    html = convertToTags(html);
    if (!raw) {
        html = html.replace(/\<br \/\>/g, '\n');
        html = html.replace(/\<p\>(.*?)\<\/p\>/g, '$1\n');
        html = html.replace(/&nbsp;/g, ' ');
    }

    body.value = html;
    oEditor.Focus();

    editor_frame.style.display = "none";
    body.style.display = "block";

    // Hack for handling submitHandler
    oEditor.switched_rte_on = '0';

    return false;
}

function convert_post(textArea) {
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    var html = oEditor.GetXHTML(false);

    var tags = convert_poll_to_tags(html, true);

    document.getElementById(textArea).value = tags;
    oEditor.SetData(tags);
}

function convert_to_draft(html) {
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
let pendingRichTextBody;
let originalRichTextBody;
let initialRichTextHTML;

function FCKeditor_OnComplete( editorInstance ) {
    if (originalRichTextBody !== undefined) {
        initialRichTextHTML = editorInstance.GetXHTML(false);
    }
    editorInstance.Events.AttachEvent( 'OnAfterLinkedFieldUpdate', doLinkedFieldUpdate) ;
    pendingRichTextBody = undefined;
    FCKeditor_LOADED = true;
}

function doLinkedFieldUpdate(oEditor) {
    var html = oEditor.GetXHTML(false);
    document.getElementById('entry-body').value =
        html === initialRichTextHTML ? originalRichTextBody : convertToTags(html);
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

var use_rte = false;
var raw = document.querySelector('#editor').value == 'html_raw0';

window.addEventListener('DOMContentLoaded', () => {
    if (document.querySelector('#editor').value == 'rte0') {
        const body = document.getElementById('entry-body');
        use_rte = useRichText('entry-body', '/stc/', raw);
        if (use_rte && postFormInitData.edit) {
            originalRichTextBody = pendingRichTextBody;
            body.form.addEventListener('formdata', event => {
                if (pendingRichTextBody !== undefined) {
                    event.formData.set(body.name, pendingRichTextBody);
                }
            });
        }
      }
})


// Watch the format select for changes, and add or destroy the RTE as necessary
document.querySelector('#editor').addEventListener('change', e => {
    const format = e.target.value;
    if (format === 'rte0' && !use_rte) {
        if (document.getElementById('entry-body').value !== originalRichTextBody) {
            originalRichTextBody = initialRichTextHTML = undefined;
        }
        use_rte = useRichText('entry-body', '/stc/', raw);
    } else if (format !== 'rte0' && use_rte) {
        if (FCKeditor_LOADED) originalRichTextBody = initialRichTextHTML = undefined;
        usePlainText('entry-body', format === 'html_raw0');
        use_rte = false;
    }
});
