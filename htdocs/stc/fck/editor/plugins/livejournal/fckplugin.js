//////////  LJ User Button //////////////
var LJUserCommand=function(){
};
LJUserCommand.prototype.Execute=function(){
}
LJUserCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

// Check for allowed lj user characters
LJUserCommand.validUsername = function(str) {
    var pattern = /^\w{1,15}$/i;
    return pattern.test(str);
}

LJUserCommand.Execute=function() {
    var username;
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
        username = selection;
    } else {
        username = prompt(window.parent.FCKLang.UserPrompt, '');
    }

    var postData = {
        "username" : username
    };
    if (username == null) return;

    var url = window.parent.Site.siteroot + "/tools/endpoints/ljuser.bml";

    var gotError = function(err) {
        alert(err);
        return;
    }

    var gotInfo = function (data) {
        if (data.error) {
            alert(data.error);
            return;
        }
        if (!data.success) return;
        data.ljuser = data.ljuser.replace(/<span.+?class=['"]?ljuser['"]?.+?>/,'<div class="ljuser">');
        data.ljuser = data.ljuser.replace(/<\/span>/,'</div>');
        FCK.InsertHtml(data.ljuser);
        FCKSelection.Collapse();
        FCK.Focus();
    }

    var opts = {
        "data": window.parent.HTTPReq.formEncoded(postData),
        "method": "POST",
        "url": url,
        "onError": gotError,
        "onData": gotInfo
    };

    window.parent.HTTPReq.getJSON(opts);
    return false;
}

FCKCommands.RegisterCommand('LJUserLink', LJUserCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJUserLink = new FCKToolbarButton('LJUserLink', window.parent.FCKLang.LJUser);
oLJUserLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljuser.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJUserLink', oLJUserLink) ;


//////////  LJ Video Button //////////////
var LJVideoCommand=function(){
};
LJVideoCommand.prototype.Execute=function(){
}
LJVideoCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJVideoCommand.Execute=function() {
    var url;
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
        url = selection;
    } else {
        url = prompt(window.parent.FCKLang.VideoPrompt,'');
    }

    if (url != null && url != '') {
        // Make the tag like the editor would
        var html = "<div url=\""+url+"\" class=\"ljvideo\"><img src=\""+FCKConfig.PluginsPath + "livejournal/ljvideo.gif\" /></div>";

        FCK.InsertHtml(html);
        FCKSelection.Collapse();
        FCK.Focus();
    }
    return;
}

FCKCommands.RegisterCommand('LJVideoLink', LJVideoCommand); //otherwise our command will not be found

// Create the toolbar button.
var oLJVideoLink = new FCKToolbarButton('LJVideoLink', window.parent.FCKLang.LJVideo);
oLJVideoLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljvideo.gif';

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJVideoLink', oLJVideoLink);
//////////  LJ Embed Media Button //////////////
var LJEmbedCommand=function(){};
LJEmbedCommand.prototype.Execute=function(){};
LJEmbedCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJEmbedCommand.Execute=function() {
    var html;
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

    function do_embed (content) {
        if (content != null && content != '') {
            // Make the tag like the editor would
            var html_final = "<div class='ljembed'>" + content + "</div><br/>";

            FCK.InsertHtml(html_final);
            FCKSelection.Collapse();
            FCK.Focus();
        }
    }

    if (selection != '') {
        html = selection;
        do_embed(html);
    } else {
        var prompt = "Add media from other websites by copying and pasting their embed code here. ";
        top.LJ_IPPU.textPrompt("Insert Embedded Content", prompt, do_embed);
    }

    return;
}

FCKCommands.RegisterCommand('LJEmbedLink', LJEmbedCommand ); //otherwise our command will not be found

// Create embed media button
var oLJEmbedLink = new FCKToolbarButton('LJEmbedLink', "Embed Media");
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

        FCK.InsertHtml(html);
        FCKSelection.Collapse();
        FCK.Focus();
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
    var node = FCK.Selection.GetAncestorNode( 'DIV' );
    if (evt && node && node.id.match(/poll\d+/)) {
        var ele = top.document.getElementById("draft___Frame");
        var href = "href='javascript:Poll.callRichTextEditor()'";
        var notice = parent.LJ_IPPU.showNote("Polls must be edited inside the Poll Wizard<br /><a "+href+">Go to poll wizard</a>", ele);
        notice.centerOnWidget(ele);
        parent.Event.stop(evt);
    }
}

LJPollCommand.openEditor=function() {
    var eSelected = FCK.Selection.MoveToAncestorNode( 'DIV' );
    if ( eSelected.id.match(/poll\d+/) ) {
        var oEditor = window.FCK ;
        oEditor.Commands.GetCommand('LJPollLink').Execute();
    }
    return false;
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
var oLJPollLink = new FCKToolbarButton('LJPollLink', 'LiveJournal Poll');
oLJPollLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljpoll.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJPollLink', oLJPollLink) ;

FCK.EditorWindow.document.body.onload = LJPollCommand.setKeyPressHandler;

