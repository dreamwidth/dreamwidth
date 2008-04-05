// Cross-Browser Rich Text Editor  v2.0
// http://www.kevinroth.com/rte/demo.htm
// Written by Kevin Roth (kevin@NOSPAMkevinroth.com - remove NOSPAM)
// Modifications by Kevin Phillips and Mahlon E. Smith for LiveJournal.com

//init variables
var isRichText = false;
var rng;
var currentRTE;
var textsize = 3;

function writeRichText(rte, postvar, html, width, height, buttons) {
    if (isRichText) {
        writeRTE(rte, postvar, html, width, height, buttons);
        setTimeout('updateRTE("' + rte + '");', 1000);
    } else {
        writeDefault(postvar, html, width, height, buttons);
    }
}

function initRTE() {
    isRichText = browser.isRichText;
}

function writeRTE(rte, postvar, html, width, height, buttons) {
    if (buttons == true) {
        document.writeln('<style type="text/css">');
        document.writeln('.btnImage {cursor: pointer; cursor: hand;}');
        document.writeln('</style>');
        document.writeln('<table cellpadding="1" cellspacing="0" border="0">');
        document.writeln('      <tr>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_bold.gif" width="25" height="24" alt="Bold" title="Bold" onClick="FormatText(\'' + rte + '\', \'bold\', \'\')"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_italic.gif" width="25" height="24" alt="Italic" title="Italic" onClick="FormatText(\'' + rte + '\', \'italic\')"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_underline.gif" width="25" height="24" alt="Underline" title="Underline" onClick="FormatText(\'' + rte + '\', \'underline\', \'\')"></td>');
        document.writeln('              <td>&nbsp;</td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_text_smaller.gif" width="25" height="24" alt="Smaller Text" title="Smaller Text" onClick="FormatText(\'' + rte + '\', \'fontsize\', ChangeTSize(\'-\'));"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_text_normal.gif" width="25" height="24" alt="Normal Text" title="Normal Text" onClick="textsize = 3; FormatText(\'' + rte + '\', \'fontsize\', textsize);"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_text_larger.gif" width="25" height="24" alt="Larger Text" title="Larger Text" onClick="FormatText(\'' + rte + '\', \'fontsize\', ChangeTSize(\'+\'));"></td>');
        document.writeln('              <td>&nbsp;</td>');
        document.writeln('              <td><div id="forecolor"><img class="btnImage" src="/img/rte/post_button_textcolor.gif" width="25" height="24" alt="Text Color" title="Text Color" onClick="FormatText(\'' + rte + '\', \'forecolor\', \'\')"></div></td>');
        document.writeln('              <td>&nbsp;</td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_numbered_list.gif" width="25" height="24" alt="Ordered List" title="Ordered List" onClick="FormatText(\'' + rte + '\', \'insertorderedlist\', \'\')"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_list.gif" width="25" height="24" alt="Unordered List" title="Unordered List" onClick="FormatText(\'' + rte + '\', \'insertunorderedlist\', \'\')"></td>');
        document.writeln('              <td>&nbsp;</td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_hyperlink.gif" width="25" height="24" alt="Insert Link" title="Insert Link" onClick="FormatText(\'' + rte + '\', \'createlink\')"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_image.gif" width="25" height="24" alt="Add Image" title="Add Image" onClick="AddImage(\'' + rte + '\')"></td>');
        document.writeln('              <td>&nbsp;</td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_ljuser.gif" width="25" height="24" alt="Add LJ User" title="Add LJ User" onClick="AddLJTag(\'' + rte + '\', \'user\')"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_ljcut.gif" width="25" height="24" alt="Add LJ Cut" title="Add LJ Cut" onClick="AddLJTag(\'' + rte + '\', \'cut\')"></td>');
        document.writeln('              <td>&nbsp;</td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_undo.gif" width="25" height="24" alt="Undo" title="Undo" onClick="FormatText(\'' + rte + '\', \'undo\')"></td>');
        document.writeln('              <td><img class="btnImage" src="/img/rte/post_button_redo.gif" width="25" height="24" alt="Redo" title="Redo" onClick="FormatText(\'' + rte + '\', \'redo\')"></td>');
        document.writeln('      </tr>');
        document.writeln('</table>');
    }
    document.writeln('<iframe onblur="save_entry();" name="event" id="' + rte + '" width="' + width + 'px" height="' + height + 'px" src="/rte/blank.html"></iframe>');
    document.writeln('<iframe width="254" height="174" id="cp' + rte + '" src="/rte/palette.html" marginwidth="0" marginheight="0" scrolling="no" style="visibility:hidden; position: absolute;"></iframe>');
    document.writeln('<input type="hidden" id="hdn' + rte + '" name="' + postvar + '" value="">');
    if (browser.isIE55up) {
        enableDesignMode(rte, html);
    } else {
        setTimeout(function(){ enableDesignMode(rte, html); }, 1000);
    }
}

function writeDefault(rte, html, width, height, buttons) {
    document.writeln('<textarea name="' + rte + '" id="' + rte + '" style="width: ' + width + '; height: ' + height + 'px;">' + html + '</textarea>');
}

function enableDesignMode(rte, html) {
    var content = document.getElementById('rte');
    var saved_entry = document.updateForm.saved_entry.value;
    if (saved_entry != "") html = saved_entry; // only for gecko browsers

    if (browser.isIE55up) {
        frames[rte].document.designMode = "On";
        setTimeout(function(){ content.contentWindow.document.body.innerHTML = html; }, 100);
    }
    else {
        document.getElementById(rte).contentDocument.designMode = "on"
        setTimeout(function(){ content.contentWindow.document.body.innerHTML = html; }, 100);
        setTimeout(function(){ content.contentDocument.designMode = 'on'; }, 200);
    }
}

//Change textsize within boundries allowed by midas. (1 .. 7)
function ChangeTSize(dir) {
    if (dir == "-") {
        if (textsize == 1) return textsize;
        textsize--;
    }
    if (dir == "+") {
        if (textsize == 7) return textsize;
        textsize++;
    }
    return textsize;
}

// Check for allowed lj user characters
function goodChars(str) {
    var pattern = /^\w{1,15}$/i;
    return pattern.test(str);
}

// lj-user text
function make_ljuser (res, type) {
    if (type != null) { // gecko
        // manually build lj user node
        var span = document.createElement("span");
        span.setAttribute("class", "ljuser");

        var img = document.createElement("img");
        img.setAttribute("src", siteroot + "/img/userinfo.gif");
        img.setAttribute("alt", "userinfo");
        img.setAttribute("width", "17");
        img.setAttribute("height", "17");
        img.setAttribute("style", "vertical-align: bottom; border: 0;");

        var uinfo_link = document.createElement("a");
        uinfo_link.setAttribute("href", siteroot + '/userinfo.bml?user=' + res);
        uinfo_link.appendChild(img);

        var userlink = document.createTextNode(res);
        var bold = document.createElement("b");
        var ujournal_link = document.createElement("a");
        ujournal_link.setAttribute("href", siteroot + '/users/' + res + '/');
        bold.appendChild(userlink);
        ujournal_link.appendChild(bold);

        span.appendChild(uinfo_link);
        span.appendChild(ujournal_link);

        rng.insertNode(span);
    } else { // ie
        return "<span class=\"ljuser\" style='white-space: nowrap;'><a href='" + siteroot + "/userinfo.bml?user=" + res + "'><img src='" + siteroot + "/img/userinfo.gif' alt='userinfo' width='17' height='17' style='vertical-align: bottom; border: 0;' /></a><a href='" + siteroot + "/users/" + res + "/'><b>" + res + "</b></a></span> ";
    }
}


//Add LJ specific tags - lj user and lj-cut.
function AddLJTag(rte, type) {
    var cw = document.getElementById(rte).contentWindow;
    var res;

    // Get current user selection
    if (cw.window.getSelection) { // gecko
        res = cw.window.getSelection();
        rng = cw.window.getSelection().getRangeAt(0);
    } else if (cw.document.selection) { // ie
        rng = cw.document.selection.createRange();
        res = rng.text;
    } 

    // lj-user
    if (type == 'user') {
        if (res == "" || res.length == 0) {
            // Nothing selected or totally unsupported
            res = prompt('Enter a username', '');
            if ((res != null) && (res != "")) {
                if (! goodChars(res)) {
                    alert("Invalid characters in username.");
                    return;
                }
                cw.focus();
                // tack onto the existing text
                cw.document.body.innerHTML += make_ljuser(res);
                return;
            } else {
                return;
            }
        }

        if (! goodChars(res)) {
            alert("Invalid characters in username.");
            return;
        }

        if (rng.pasteHTML) {    // ie
            rng.pasteHTML(make_ljuser(res));
        } else {                // gecko
            var username = rng.toString();
            rng.deleteContents();
            make_ljuser(username, "node");
        }
    }

    // lj-cut
    if (type == 'cut') {
        var cut = prompt('Optional cut caption', '');
        if (cut != null) {
            var cuttag;
            var cutend = "\n</lj-cut>\n";
            cw.focus();

            if (cut == "") {
                cuttag = '<lj-cut>' + "\n";
            } else {
                cuttag = '<lj-cut text="' + cut + '">' + "\n";
            }

            // give the user a chance to back out
            if ( (rng.text && res.length > 0) ||
                 ( rng.insertNode && rng.toString().length > 0) ) {
                var ok = confirm("Rich text formatting within your selection will be lost.  Ok to continue?");
                if ( ! ok ) return false;
            }

            if (rng.text && rng.text != "") { // ie
                rng.text = cuttag + rng.text;
                if (res.length > 0) rng.text += cutend;
            } else if (rng.insertNode && rng.toString() != "") { // gecko
                var content = document.createTextNode(rng.toString());
                var cut_s = document.createTextNode(cuttag);
                var cut_e = document.createTextNode(cutend);
                rng.deleteContents();
                rng.insertNode(cut_e);
                rng.insertNode(content);
                rng.insertNode(cut_s);
            } else { // nothing selected or totally unsupported
                if (cut == "") {
                    cuttag = '&lt;lj-cut&gt;' + "\n";
                } else {
                    cuttag = '&lt;lj-cut text="' + cut + '"&gt;' + "\n";
                }
                cw.document.body.innerHTML += cuttag;
            }
        }
    }

    cw.focus();
    return;
}


//Function to format text in the text box
function FormatText(rte, command, option) {
    if ((command == "forecolor") || (command == "hilitecolor")) {
        parent.command = command;
        buttonElement = document.getElementById(command);
        document.getElementById('cp' + rte).style.left = getOffsetLeft(buttonElement) + "px";
        document.getElementById('cp' + rte).style.top = (getOffsetTop(buttonElement) + buttonElement.offsetHeight) + "px";
        if (document.getElementById('cp' + rte).style.visibility == "hidden")
            document.getElementById('cp' + rte).style.visibility="visible";
        else {
            document.getElementById('cp' + rte).style.visibility="hidden";
        }

        //get current selected rte
        currentRTE = rte;

        //get current selected range
        var sel = document.getElementById(rte).contentWindow.document.selection; 
        if (sel!=null) {
            rng = sel.createRange();
        }
    }
    else if (command == "createlink") { // && browser.isIE55up == false
        var szURL = prompt("Enter a URL:", "http://");
        document.getElementById(rte).contentWindow.document.execCommand("Unlink",false,null);
        if ((szURL != "http://") && (szURL != "")) {
            document.getElementById(rte).contentWindow.document.execCommand("CreateLink",false,szURL);
        }
    }
    else {
        document.getElementById(rte).contentWindow.focus();
        document.getElementById(rte).contentWindow.document.execCommand(command, false, option);
        document.getElementById(rte).contentWindow.focus();
    }
}

//Function to set color
function setColor(color) {
    var parentCommand = parent.command;
    var rte = currentRTE;

    if (browser.isIE55up) {
        //retrieve selected range
        var sel = document.getElementById(rte).contentWindow.document.selection; 
        if (parentCommand == "hilitecolor") parentCommand = "backcolor";
        if (sel!=null) {
            var newRng = sel.createRange();
            newRng = rng;
            newRng.select();
        }
    }
    else {
        document.getElementById(rte).contentWindow.focus();
    }
    document.getElementById(rte).contentWindow.document.execCommand(parentCommand, false, color);
    document.getElementById(rte).contentWindow.focus();
    document.getElementById('cp' + rte).style.visibility="hidden";
}

//Function to add image
function AddImage(rte) {
    imagePath = prompt('Enter Image URL:', 'http://');                              
        if ((imagePath != null) && (imagePath != "") && (imagePath != "http://")) {
            document.getElementById(rte).contentWindow.focus()
                document.getElementById(rte).contentWindow.document.execCommand('InsertImage', false, imagePath);
        }
    document.getElementById(rte).contentWindow.focus()
}

//Function to clear form
function ResetForm(rte) {
    if (window.confirm('<%=strResetFormConfirm%>')) {
        document.getElementById(rte).contentWindow.focus()
            document.getElementById(rte).contentWindow.document.body.innerHTML = ''; 
        return true;
    } 
    return false;          
}

function getOffsetTop(elm) {
    var mOffsetTop = elm.offsetTop;
    var mOffsetParent = elm.offsetParent;

    while(mOffsetParent){
        mOffsetTop += mOffsetParent.offsetTop;
        mOffsetParent = mOffsetParent.offsetParent;
    }

    return mOffsetTop;
}

function getOffsetLeft(elm) {
    var mOffsetLeft = elm.offsetLeft;
    var mOffsetParent = elm.offsetParent;

    while(mOffsetParent) {
        mOffsetLeft += mOffsetParent.offsetLeft;
        mOffsetParent = mOffsetParent.offsetParent;
    }

    return mOffsetLeft;
}

function Select(rte, selectname)
{
    var cursel = document.getElementById(selectname).selectedIndex;
    // First one is always a label
    if (cursel != 0) {
        var selected = document.getElementById(selectname).options[cursel].value;
        document.getElementById(rte).contentWindow.document.execCommand(selectname, false, selected);
        document.getElementById(selectname).selectedIndex = 0;
    }
    document.getElementById(rte).contentWindow.focus();
}

function updateRTE(rte) {
    //set message value
    var oHdnMessage = document.getElementById('hdn' + rte);
    var oMessageFrame = document.getElementById(rte);

    if (isRichText) {
        if (oHdnMessage.value == null) oHdnMessage.value = "";
        oHdnMessage.value = oMessageFrame.contentWindow.document.body.innerHTML;

        //exception for Mozilla
        if (oHdnMessage.value.indexOf('<br>') > -1 && oHdnMessage.value.length == 8) oHdnMessage.value = "";
    }
}

initRTE();
