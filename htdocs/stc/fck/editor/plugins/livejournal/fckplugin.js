//////////  LJ User Button //////////////
var LJUserCommand=function(){
};
LJUserCommand.prototype.Execute=function(){
}
LJUserCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}


LJUserCommand.Execute=function() {
    var username;
    var selection = '';
    var UserTagCache = window.parent.UserTagCache;

    if (FCK.EditorWindow.getSelection) {
        selection = FCK.EditorWindow.getSelection();
        // Create a new div to clone the selection's content into
        var d = FCK.EditorDocument.createElement('DIV');
        for (var i = 0; i < selection.rangeCount; i++) {
            d.appendChild(selection.getRangeAt(i).cloneContents());
        }
        selection = d.innerHTML;
    } else if (FCK.EditorDocument.selection) {
        var range = FCK.EditorDocument.selection.createRange();
        var type = FCKSelection.GetType();
        if (type == 'Control') {
            selection = range.item(0).outerHTML;
        } else if (type == 'None') {
            selection = '';
        } else {
            selection = range.htmlText;
        }
    }

    function do_insert( username, site ) {
        var postData = {
            "username" : username || '',
            "site"     : site || ''
        };

        if (username == null) return;

        var url = window.parent.Site.siteroot + "/tools/endpoints/ljuser";

        var gotError = function(err) {
            alert(err);
        }

        var gotInfo = function (data) {
            if (data.error) {
                alert(data.error);
                return;
            }

            if (!data.success) return;

            if ( site )
                data.ljuser = data.ljuser.replace(/<span.+?class=['"]?ljuser['"]?.+?>/,'<div class="ljuser" site="' + site + '">');
            else
                data.ljuser = data.ljuser.replace(/<span.+?class=['"]?ljuser['"]?.+?>/,'<div class="ljuser">');

            data.ljuser = data.ljuser.replace(/<\/span>/,'</div>');
            UserTagCache[username + "_" + site] = data.ljuser;

            FCK.InsertHtml(data.ljuser + "&nbsp;");
            if (selection != '') FCKSelection.Collapse();
            FCK.Focus();
        }

        if ( UserTagCache[postData.username+"_"+postData.site] ) {
            FCK.InsertHtml(UserTagCache[postData.username+"_"+postData.site] + "&nbsp;");
            if (selection != '') FCKSelection.Collapse();
            FCK.Focus();
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

    if (selection != '') {
        username = selection;
        do_insert( username );
    } else {
        var DOM = window.parent.DOM;
        var _textDiv = window.parent._textDiv;
        var userPopup = new window.parent.LJ_IPPU( window.parent.FCKLang.UserPrompt );
        userPopup.hide =   function() {
            window.parent.LJ_IPPU.superClass.hide.apply(this);
            DOM.removeEventListener( window.parent.document, "keyup", LJUserCommand.KeyUpHandler );
        }


        var inner = document.createElement( "div" );
        DOM.addClassName( inner, "userprompt" );

        var label = document.createElement( "label" );
        label.appendChild( _textDiv( window.parent.FCKLang.UserPrompt_User ) );
        label.setAttribute( "for", "userprompt-username" );
        inner.appendChild( label );

        var username = document.createElement( "input" );
        username.name = "username";
        username.id = "userprompt-username";
        inner.appendChild( username );

        label = document.createElement( "label" );
        label.appendChild( _textDiv( window.parent.FCKLang.UserPrompt_Site ) );
        label.setAttribute( "for", "userprompt-site" );
        inner.appendChild( label );

        var siteList = document.createElement( "select" );
        siteList.name = "site";
        siteList.id = "userprompt-site";
        var option = new Option( "--", "" );
        option.selected = "selected";
        siteList.appendChild( option );
        inner.appendChild( siteList );

        for ( var i = 0; i < window.parent.FCKLang.UserPrompt_SiteList.length; i++ ) {
            var site = window.parent.FCKLang.UserPrompt_SiteList[i];
            var option = new Option( site.sitename, site.domain );
            siteList.appendChild( option );
        }

        var btncont = document.createElement( "div" );
        DOM.addClassName( btncont, "submitbtncontainer" );
        var btn = document.createElement( "input" );
        DOM.addClassName ( btn, "submitbtn" );
        btn.type = "button";
        btn.value = "Insert";
        btncont.appendChild( btn );
        inner.appendChild( btncont );

        userPopup.setContentElement( inner );

        userPopup.setAutoCenter( true, true );
        userPopup.setDimensions( "15em", "auto" );
        userPopup.show();
        username.focus();

        DOM.addEventListener( window.parent.document, "keyup", function(userPopup) {
            return  LJUserCommand.KeyUpHandler = function(e) {
                var code = e.keyCode || e.which;
                // enter
                if ( code == 13 ) {
                    userPopup.hide();
                    do_insert( username.value, siteList.value );
                    return;
                }
                // escape
                if ( code == 27 ) {
                    userPopup.hide();
                    return;
                }
            } }(userPopup)
        );

        DOM.addEventListener( btn, "click", function (e) {
            userPopup.hide();
            do_insert( username.value, siteList.value );
        } );
    }

    return false;
}

FCKCommands.RegisterCommand('LJUserLink', LJUserCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJUserLink = new FCKToolbarButton('LJUserLink', window.parent.FCKLang.LJUser);
oLJUserLink.IconPath = FCKConfig.PluginsPath + 'livejournal/dwuser.png' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJUserLink', oLJUserLink) ;

//////////  LJ Embed Media Button //////////////
var LJEmbedCommand=function(){};
LJEmbedCommand.prototype.Execute=function(){};
LJEmbedCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJEmbedCommand.Execute=function() {
    var html;
    var selection = '';

    FCKSelection.Save();

    function do_embed (content) {
        if (content != null && content != '') {
            // Make the tag like the editor would
            var html_final = "<div class='ljembed'>" + content + "</div><br/>";

            FCKSelection.Restore();
            FCK.InsertHtml(html_final);
            FCKSelection.Collapse();
            FCK.Focus();
        }
    }

    if (selection != '') {
        html = selection;
        do_embed(html);
    } else {
        var prompt = window.parent.FCKLang.EmbedContents;
        top.LJ_IPPU.textPrompt(window.parent.FCKLang.EmbedPrompt, prompt, do_embed);
    }

    return;
}

FCKCommands.RegisterCommand('LJEmbedLink', LJEmbedCommand ); //otherwise our command will not be found

// Create embed media button
var oLJEmbedLink = new FCKToolbarButton('LJEmbedLink', window.parent.FCKLang.LJVideo);
oLJEmbedLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljvideo.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJEmbedLink', oLJEmbedLink) ;

//////////  LJ Cut Button //////////////
var LJCutCommand=function(){
};
LJCutCommand.prototype.Execute=function(){
}
LJCutCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJCutCommand.Execute=function() {
    var text = prompt(window.parent.FCKLang.CutPrompt, window.parent.FCKLang.ReadMore);
    if (text == window.parent.FCKLang.ReadMore) {
        text = '';
    } else {
        text = text.replace('"', '\"');
        text = ' text="' + text + '"';
    }

    var selection = '';

    if (FCK.EditorWindow.getSelection) {
        selection = FCK.EditorWindow.getSelection();

        // Create a new div to clone the selection's content into
        var d = FCK.EditorDocument.createElement('DIV');
        for (var i = 0; i < selection.rangeCount; i++) {
            d.appendChild(selection.getRangeAt(i).cloneContents());
        }
        selection = d.innerHTML;

    } else if (FCK.EditorDocument.selection) {
        var range = FCK.EditorDocument.selection.createRange();

        var type = FCKSelection.GetType();
        if (type == 'Control') {
            selection = range.item(0).outerHTML;
        } else if (type == 'None') {
            selection = '';
        } else {
            selection = range.htmlText;
        }
    }

    if (selection != '') {
        selection += ''; // Cast it to a string
    } else {
        selection += window.parent.FCKLang.CutContents;
    }

    var html = "<div class='ljcut'" +  text + ">";
    html    += selection;
    html    += "</div>";

    FCK.InsertHtml(html);
    FCK.Focus();

    return;
}

FCKCommands.RegisterCommand('LJCutLink', LJCutCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJCutLink = new FCKToolbarButton('LJCutLink', window.parent.FCKLang.LJCut);
oLJCutLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljcut.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJCutLink', oLJCutLink) ;

//////////  LJ Poll Button //////////////
var LJPollCommand=function(){
};
LJPollCommand.prototype.Execute=function(){
}
LJPollCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJPollCommand.Add=function(pollsource, index) {
    var poll = pollsource;

    if (poll != null && poll != '') {
        // Make the tag like the editor would
        var html = "<div id=\"poll"+index+"\">"+poll+"</div>";

        // IE and Safari handle Selections differently and InsertHtml
        // will not overwrite the enclosing DIVs in those browsers,
        // so just replace the selected polls innerHTML
        if (FCK.Selection.Element) {
            FCK.Selection.Element.innerHTML = poll;
        } else {
            FCK.InsertHtml(html);
        }

    }

    return;
}

LJPollCommand.setKeyPressHandler=function() {
    var editor = FCK.EditorWindow.document;
    if (editor) {
        if (editor.addEventListener) {
            editor.addEventListener('keypress', LJPollCommand.ippu, false);
            editor.addEventListener('click', LJPollCommand.ippu, false);
        } else if (editor.attachEvent) {
            editor.attachEvent('onkeypress', function() { LJPollCommand.ippu(FCK.EditorWindow.event); } );
            editor.attachEvent('onclick', function() { LJPollCommand.ippu(FCK.EditorWindow.event); } );
        } else {
            editor.onkeypress = LJPollCommand.ippu;
        }
    }
}

LJPollCommand.ippu=function(evt) {
    evt = evt || window.event;
    var node = FCKSelection.GetAncestorNode( 'DIV' );
    if (evt && node && node.id.match(/poll\d+/)) {
        var ele = top.document.getElementById("draft___Frame");
        var href = "href='javascript:Poll.callRichTextEditor()'";
        var notice = parent.LJ_IPPU.showNote("Polls must be edited inside the Poll Wizard<br /><a "+href+">Go to poll wizard</a>", ele);
        notice.centerOnWidget(ele);
        if (parent.Event.stop) parent.Event.stop(evt);
    }
}

// For handling when polls are not available to a user
var LJNoPoll=function(){
};
LJNoPoll.prototype.Execute=function(){
}
LJNoPoll.GetState=function() {
        return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}
LJNoPoll.Execute=function() {
    var ele = top.document.getElementById("draft___Frame");
    var notice = top.LJ_IPPU.showNote("You may only create and post polls if you have a Plus or Paid Account or if you are posting the poll to a Plus or Paid community that you maintain.", ele);
    notice.centerOnWidget(ele);
    return;
}

if (top.canmakepoll == false) {
    FCKCommands.RegisterCommand('LJPollLink', LJNoPoll);
} else {
    FCKCommands.RegisterCommand('LJPollLink',
            new FCKDialogCommand( 'LJPollCommand', 'Poll Wizard',
            '/tools/fck_poll.bml', 420, 370 ));
}

// Create the toolbar button.
var oLJPollLink = new FCKToolbarButton('LJPollLink', 'Poll');
oLJPollLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljpoll.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJPollLink', oLJPollLink) ;

// Custom Converter for pasting from Word
// Original source taken from fck_paste.html
FCK.CustomCleanWord = function( oNode, bIgnoreFont, bRemoveStyles ) {
	var html = oNode.innerHTML ;
	html = html.replace(/<o:p>\s*<\/o:p>/g, '') ;
	html = html.replace(/<o:p>[\s\S]*?<\/o:p>/g, '&nbsp;') ;

	// Remove mso-xxx styles.
	html = html.replace( /\s*mso-[^:]+:[^;"]+;?/gi, '' ) ;

	// Remove margin styles.
	html = html.replace( /\s*MARGIN: 0cm 0cm 0pt\s*;/gi, '' ) ;
	html = html.replace( /\s*MARGIN: 0cm 0cm 0pt\s*"/gi, "\"" ) ;

	html = html.replace( /\s*TEXT-INDENT: 0cm\s*;/gi, '' ) ;
	html = html.replace( /\s*TEXT-INDENT: 0cm\s*"/gi, "\"" ) ;

	html = html.replace( /\s*TEXT-ALIGN: [^\s;]+;?"/gi, "\"" ) ;

	html = html.replace( /\s*PAGE-BREAK-BEFORE: [^\s;]+;?"/gi, "\"" ) ;

	html = html.replace( /\s*FONT-VARIANT: [^\s;]+;?"/gi, "\"" ) ;

	html = html.replace( /\s*tab-stops:[^;"]*;?/gi, '' ) ;
	html = html.replace( /\s*tab-stops:[^"]*/gi, '' ) ;

	// Remove FONT face attributes.
	if ( bIgnoreFont )
	{
		html = html.replace( /\s*face="[^"]*"/gi, '' ) ;
		html = html.replace( /\s*face=[^ >]*/gi, '' ) ;

		html = html.replace( /\s*FONT-FAMILY:[^;"]*;?/gi, '' ) ;
	}

	// Remove Class attributes
	html = html.replace(/<(\w[^>]*) class=([^ |>]*)([^>]*)/gi, "<$1$3") ;

	// Remove styles.
	if ( bRemoveStyles )
		html = html.replace( /<(\w[^>]*) style="([^\"]*)"([^>]*)/gi, "<$1$3" ) ;

	// Remove style, meta and link tags
	html = html.replace( /<STYLE[^>]*>[\s\S]*?<\/STYLE[^>]*>/gi, '' ) ;
	html = html.replace( /<(?:META|LINK)[^>]*>\s*/gi, '' ) ;

	// Remove empty styles.
	html =  html.replace( /\s*style="\s*"/gi, '' ) ;

	html = html.replace( /<SPAN\s*[^>]*>\s*&nbsp;\s*<\/SPAN>/gi, '&nbsp;' ) ;

	html = html.replace( /<SPAN\s*[^>]*><\/SPAN>/gi, '' ) ;

	// Remove Lang attributes
	html = html.replace(/<(\w[^>]*) lang=([^ |>]*)([^>]*)/gi, "<$1$3") ;

	html = html.replace( /<SPAN\s*>([\s\S]*?)<\/SPAN>/gi, '$1' ) ;

	html = html.replace( /<FONT\s*>([\s\S]*?)<\/FONT>/gi, '$1' ) ;

	// Remove XML elements and declarations
	html = html.replace(/<\\?\?xml[^>]*>/gi, '' ) ;

	// Remove w: tags with contents.
	html = html.replace( /<w:[^>]*>[\s\S]*?<\/w:[^>]*>/gi, '' ) ;

	// Remove Tags with XML namespace declarations: <o:p><\/o:p>
	html = html.replace(/<\/?\w+:[^>]*>/gi, '' ) ;

	// Remove comments [SF BUG-1481861].
	html = html.replace(/<\!--[\s\S]*?-->/g, '' ) ;

	html = html.replace( /<(U|I|STRIKE)>&nbsp;<\/\1>/g, '&nbsp;' ) ;

	html = html.replace( /<H\d>\s*<\/H\d>/gi, '' ) ;

	// Remove "display:none" tags.
	html = html.replace( /<(\w+)[^>]*\sstyle="[^"]*DISPLAY\s?:\s?none[\s\S]*?<\/\1>/ig, '' ) ;

	// Remove language tags
	html = html.replace( /<(\w[^>]*) language=([^ |>]*)([^>]*)/gi, "<$1$3") ;

	// Remove onmouseover and onmouseout events (from MS Word comments effect)
	html = html.replace( /<(\w[^>]*) onmouseover="([^\"]*)"([^>]*)/gi, "<$1$3") ;
	html = html.replace( /<(\w[^>]*) onmouseout="([^\"]*)"([^>]*)/gi, "<$1$3") ;

	if ( FCKConfig.CleanWordKeepsStructure )
	{
		// The original <Hn> tag send from Word is something like this: <Hn style="margin-top:0px;margin-bottom:0px">
		html = html.replace( /<H(\d)([^>]*)>/gi, '<h$1>' ) ;

		// Word likes to insert extra <font> tags, when using MSIE. (Wierd).
		html = html.replace( /<(H\d)><FONT[^>]*>([\s\S]*?)<\/FONT><\/\1>/gi, '<$1>$2<\/$1>' );
		html = html.replace( /<(H\d)><EM>([\s\S]*?)<\/EM><\/\1>/gi, '<$1>$2<\/$1>' );
	}
	else
	{
		html = html.replace( /<H1([^>]*)>/gi, '<div$1><b><font size="6">' ) ;
		html = html.replace( /<H2([^>]*)>/gi, '<div$1><b><font size="5">' ) ;
		html = html.replace( /<H3([^>]*)>/gi, '<div$1><b><font size="4">' ) ;
		html = html.replace( /<H4([^>]*)>/gi, '<div$1><b><font size="3">' ) ;
		html = html.replace( /<H5([^>]*)>/gi, '<div$1><b><font size="2">' ) ;
		html = html.replace( /<H6([^>]*)>/gi, '<div$1><b><font size="1">' ) ;

		html = html.replace( /<\/H\d>/gi, '<\/font><\/b><\/div>' ) ;

		// Transform <P> to <DIV>
		var re = new RegExp( '(<P)([^>]*>[\\s\\S]*?)(<\/P>)', 'gi' ) ;	// Different because of a IE 5.0 error
		html = html.replace( re, '<div$2<\/div>' ) ;

		// Remove empty tags (three times, just to be sure).
		// This also removes any empty anchor
		html = html.replace( /<([^\s>]+)(\s[^>]*)?>\s*<\/\1>/g, '' ) ;
		html = html.replace( /<([^\s>]+)(\s[^>]*)?>\s*<\/\1>/g, '' ) ;
		html = html.replace( /<([^\s>]+)(\s[^>]*)?>\s*<\/\1>/g, '' ) ;
	}

    // Convert LJ specific tags
    html = html.replace(/&lt;lj-cut text=.{1}(.+?).{1}&gt;([\S\s]+?)&lt;\/lj-cut&gt;/gm, '<div text="$1" class="ljcut">$2</div>');
    html = html.replace(/&lt;lj-cut&gt;([\S\s]+?)&lt;\/lj-cut&gt;/gm, '<div class="ljcut">$1</div>');


	return html ;

}
