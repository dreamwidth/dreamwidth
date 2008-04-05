function LJUser(textArea) {
    var editor_frame = $(textArea + '___Frame');
    if (!editor_frame) return;
    if (! FCKeditorAPI) return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;

    var html = oEditor.GetXHTML(false);
    html = html.replace(/<\/lj>/, '');
    var regexp = /<lj user=['"](\w+?)['"] ?\/?>\s?(?:<\/lj>)?\s?/g;
    var userstr;
    var ljusers = [];
    var username;
    while ((ljusers = regexp.exec(html))) {
        username = ljusers[1];
        var postData = {
            "username" : username
        };
        var url = window.parent.Site.siteroot + "/tools/endpoints/ljuser.bml";

        var gotError = function(err) {
            alert(err+' '+username);
            return;
        }

        var gotInfo = function (data) {
            if (data.error) {
                alert(data.error+' '+username);
                return;
            }
            if (!data.success) return;
            data.ljuser = data.ljuser.replace(/<span.+?class=['"]?ljuser['"]?.+?>/,'<div class="ljuser">');
            data.ljuser = data.ljuser.replace(/<\/span>/,'</div>');
            html = html.replace(data.userstr,data.ljuser+'&nbsp;');
            editor_frame.focus();
            oEditor.SetHTML(html,false);
            oEditor.Focus();
        }

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


function useRichText(textArea, statPrefix) {
    if ( $("switched_rte_on").value == 1 ) return;

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

    entry_html = entry_html.replace(/<lj-cut text=['"]?(.+?)['"]?>(.+?)<\/lj-cut>/g, '<div text="$1" class="ljcut">$2</div>');
    entry_html = entry_html.replace(/<lj-cut>(.+?)<\/lj-cut>/g, '<div class="ljcut">$1</div>');
    entry_html = entry_html.replace(/<lj-raw>([\w\s]+?)<\/lj-raw>/g, '<div class="ljraw">$1</div>');
    entry_html = entry_html.replace(/<lj-template name=['"]video['"]>(\S+?)<\/lj-template>/g, "<div url=\"$1\" class=\"ljvideo\"><img src='" + statPrefix + "/fck/editor/plugins/livejournal/ljvideo.gif' /></div>");
    // Match across multiple lines and extract ID if it exists
    entry_html = entry_html.replace(/<lj-embed\s*(id="(\d*)")?\s*>\s*(.*)\s*<\/lj-embed>/gim, '<div class="ljembed" embedid="$2">$3</div>');

    $(textArea).value = entry_html;

    var editor_frame = $(textArea + '___Frame');
    // Check for RTE already existing.  IE will show multiple iframes otherwise.
    if (!editor_frame) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + "/fck/";
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = "Update";
        $(textArea).value = convert_poll_to_HTML($(textArea).value);
        $(textArea).value = convert_qotd_to_HTML($(textArea).value);
        if ($("event_format") && !$("event_format").checked) {
            $(textArea).value = $(textArea).value.replace(/\n/g, '<br />');
        }
        oFCKeditor.ReplaceTextarea();

        // outer iframe for text area, toolbars, buttons
        editor_frame = $(textArea + '___Frame');
    } else {
        if (! FCKeditorAPI) return;
        var oEditor = FCKeditorAPI.GetInstance(textArea);
        editor_frame.style.display = "block";
        $(textArea).style.display = "none";
        var editor_source = editor_frame.contentWindow.document.getElementById('eEditorArea');
        $(textArea).value = convert_poll_to_HTML($(textArea).value);
        $(textArea).value = convert_qotd_to_HTML($(textArea).value);
        if ($("event_format") && !$("event_format").checked) {
            $(textArea).value = $(textArea).value.replace(/\n/g, '<br />');
        }
        oEditor.EditorDocument.body.innerHTML = $(textArea).value;

        // Allow RTE to use it's handler again so it's happy.
        var oForm = oEditor.LinkedField.form;
        DOM.addEventListener( oForm, 'submit', oEditor.UpdateLinkedField, true ) ;
        oForm.originalSubmit = oForm.submit;
        oForm.submit = oForm.SubmitReplacer;
        oEditor.Focus();
    }

    // Need to pause here as it takes some time for the editor
    // to actually load within the browser before we can
    // access it.
    setTimeout("LJUser('" + textArea + "')", 2000);


    // iframe window for editable textarea

    window.setTimeout(function () {
        var editor_frame_doc = editor_frame.contentDocument ? editor_frame.contentDocument : editor_frame.contentWindow.document;

        if (! editor_frame_doc) alert("no doc");

        var text_iframe = editor_frame_doc.getElementById('eEditorArea');

        window.setTimeout(function () {
            var text_iframe_doc = text_iframe.contentDocument ? text_iframe.contentDocument : text_iframe.contentWindow.document;

            var text_iframe_body = text_iframe_doc.body;

            var text = text_iframe_doc.createTextNode( " " );
            text_iframe_body.appendChild( text );

            // make a selection on the window
            var win = DOM.getOwnerWindow( text );

            var selection;
            
            if (win.getSelection) {
                selection = win.getSelection();
            } else {
                selection = text_iframe_doc.selection;
            }

            if (! selection) return;

            if( selection.getRangeAt ) {
                range = selection.getRangeAt( 0 );
                range.selectNode( text );
                range.collapse( true );
            } else if( selection.createRange ) {
                var range = text_iframe_body.createTextRange();
                range.collapse( false );
                range.pasteHTML( " " );
                range.select();

                var oEditor = FCKeditorAPI.GetInstance(textArea);
                oEditor.Focus();
            }

        }, 2000);

    }, 2000);

    if ($("qotd_html_preview")) {
       $("qotd_html_preview").style.display='none';
    }

    $("switched_rte_on").value = '1';
    if (focus()) { editor_frame.focus() };

    return false; // do not follow link
}

function usePlainText(textArea) {
    if ( $("switched_rte_on").value == 0 ) return;

    if (! FCKeditorAPI) return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;
    var editor_frame = $(textArea + '___Frame');
    var editor_source = editor_frame.contentWindow.document.getElementById('eEditorArea');

    if ($("qotd_html_preview")) {
       $("qotd_html_preview").style.display='block';
    }

    var html = oEditor.GetXHTML(false);
    html = html.replace(/<div class=['"]ljcut['"] text=['"](.+?)['"]>(.+?)<\/div>/g, '<lj-cut text="$1">$2</lj-cut>');
    html = html.replace(/<div text=['"](.+?)['"] class=['"]ljcut['"]>(.+?)<\/div>/g, '<lj-cut text="$1">$2</lj-cut>');
    html = html.replace(/<div class=['"]ljcut['"]>(.+?)<\/div>/g, '<lj-cut>$1</lj-cut>');
    html = html.replace(/<div class=['"]ljuser['"]>.+?<b>(\w+?)<\/b><\/a><\/div>/g, '<lj user=\"$1\">');
    html = html.replace(/<div class=['"]ljvideo['"] url=['"](\S+)['"]><img.+?\/><\/div>/g, '<lj-template name=\"video\">$1</lj-template>');
    html = html.replace(/<div class=['"]ljvideo['"] url=['"](\S+)['"]><br \/><\/div>/g, '');
    html = html.replace(/<div class=['"]ljraw['"]>(.+?)<\/div>/g, '<lj-raw>$1</lj-raw>');
    html = html.replace(/<div class=['"]ljembed['"](\s*embedid="(\d*)")?\s*>(.*)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>');
    html = html.replace(/<div\s*(embedid="(\d*)")?\s*class=['"]ljembed['"]\s*>(.*)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>');

    if ($("event_format") && !$("event_format").checked) {
        html = html.replace(/\<br \/\>/g, '\n');
        html = html.replace(/\<p\>(.*?)\<\/p\>/g, '$1\n');
        html = html.replace(/&nbsp;/g, ' ');
    }
    html = convert_poll_to_ljtags(html);
    html = convert_qotd_to_ljtags(html);
    if (focus()) { editor_frame.focus() };
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

    // Remove onsubmit handler while in Plain text
    var oForm = oEditor.LinkedField.form;
    DOM.removeEventListener( oForm, 'submit', oEditor.UpdateLinkedField, true ) ;
    oForm.SubmitReplacer = oForm.submit;
    oForm.submit = oForm.originalSubmit;
    return false;
}

function convert_post(textArea) {
    if ( $("switched_rte_on").value == 0 ) return;

    var oEditor = FCKeditorAPI.GetInstance(textArea);
    var html = oEditor.GetXHTML(false);

    var tags = convert_poll_to_ljtags(html, true);
    tags = convert_qotd_to_ljtags(tags, true);

    oEditor.SetHTML(tags, false);
}

function convert_to_draft(html) {
    if ( $("switched_rte_on").value == 0 ) return html;

    var out = convert_poll_to_ljtags(html, true);
    out = convert_qotd_to_ljtags(out, true);

    return out;
}

function convert_poll_to_ljtags (html, post) {
    var tags = html.replace(/<div id=['"]poll(.+?)['"]>[^\b]*?<\/div>/gm,
                            function (div, id){ return generate_ljpoll(id, post) } );
    return tags;
}

function generate_ljpoll(pollID, post) {
    var poll = LJPoll[pollID];
    var tags = poll.outputLJtags(pollID, post);
    return tags;
}

function convert_poll_to_HTML(plaintext) {
    var html = plaintext.replace(/<lj-poll name=['"].*['"] id=['"]poll(\d+?)['"].*>[^\b]*?<\/lj-poll>/gm,
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

function convert_qotd_to_ljtags (html, post) {
    var tags = html.replace(/<div .*qotdid=['"]?(\d+)['"]? .*class=['"]?ljqotd['"]?.*>[^\b]*<\/div>(<br \/>)*/g, "<lj-template name=\"qotd\" id=\"$1\"></lj-template>");
    tags = tags.replace(/<div .*class=['"]?ljqotd['"]? .*qotdid=['"]?(\d+)['"]?.*>[^\b]*<\/div>(<br \/>)*/g, "<lj-template name=\"qotd\" id=\"$1\"></lj-template>");
    return tags;
}

function convert_qotd_to_HTML(plaintext) {
    var qotdText = LiveJournal.qotdText;

    var styleattr = " style='cursor: default; -moz-user-select: all; -moz-user-input: none; -moz-user-focus: none; -khtml-user-select: all;'";

    var html = plaintext;
    html = html.replace(/<lj-template name=['"]?qotd['"]? id=['"]?(\d+)['"]?>.*?<\/lj-template>(<br \/>)*/g, "<div class=\"ljqotd\" qotdid=\"$1\" contenteditable=\"false\"" + styleattr + ">" + qotdText + "</div>\n\n");
    html = html.replace(/<lj-template id=['"]?(\d+)['"]? name=['"]?qotd['"]?>.*?<\/lj-template>(<br \/>)*/g, "<div class=\"ljqotd\" qotdid=\"$1\" contenteditable=\"false\"" + styleattr + ">" + qotdText + "</div>\n\n");
    html = html.replace(/<lj-template name=['"]?qotd['"]? id=['"]?(\d+)['"]? \/>(<br \/>)*/g, "<div class=\"ljqotd\" qotdid=\"$1\" contenteditable=\"false\"" + styleattr + ">" + qotdText + "</div>\n\n");
    html = html.replace(/<lj-template id=['"]?(\d+)['"]? name=['"]?qotd['"]? \/>(<br \/>)*/g, "<div class=\"ljqotd\" qotdid=\"$1\" contenteditable=\"false\"" + styleattr + ">" + qotdText + "</div>\n\n");

    return html;
}
