// xGetElementById, Copyright 2001-2005 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

var nxIE = navigator.userAgent && navigator.userAgent.indexOf('MSIE ') > -1 ?
	1 : 0;

function xGetElementById(e)
{
  if(typeof(e)!='string') return e;
  if(document.getElementById) e=document.getElementById(e);
  else if(document.all) e=document.all[e];
  else e=null;
  return e;
}

// xWinOpen, Copyright 2003-2005 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

// A simple alternative to xWindow.

var xChildWindow = null;
function xWinOpen(sUrl)
{
  var features = "left=0,top=0,width=600,height=500,location=0,menubar=0," +
    "resizable=1,scrollbars=1,status=0,toolbar=0";
  if (xChildWindow && !xChildWindow.closed) {xChildWindow.location.href  = sUrl;}
  else {xChildWindow = window.open(sUrl, "myWinName", features);}
  xChildWindow.focus();
  return false;
}

// xGetCookie, Copyright 2001-2005 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

function xGetCookie(name)
{
  var value=null, search=name+"=";
  if (document.cookie.length > 0) {
    var offset = document.cookie.indexOf(search);
    if (offset != -1) {
      offset += search.length;
      var end = document.cookie.indexOf(";", offset);
      if (end == -1) end = document.cookie.length;
      value = unescape(document.cookie.substring(offset, end));
    }
  }
  return value;
}

// xGetCookie, Copyright 2001-2005 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

function xGetCookie(name)
{
  var value=null, search=name+"=";
  if (document.cookie.length > 0) {
    var offset = document.cookie.indexOf(search);
    if (offset != -1) {
      offset += search.length;
      var end = document.cookie.indexOf(";", offset);
      if (end == -1) end = document.cookie.length;
      value = unescape(document.cookie.substring(offset, end));
    }
  }
  return value;
}

// xSetCookie, Copyright 2001-2005 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

function xSetCookie(name, value, expire, path)
{
  document.cookie = name + "=" + escape(value) +
                    ((!expire) ? "" : ("; expires=" + expire.toGMTString())) +
                    "; path=" + ((!path) ? "/" : path);
}

// ---------------------------------------------------------------------------
//   Original code follows
// ---------------------------------------------------------------------------

// This does NOT scroll the object to the position! See nxscrollObject()
// below for that.
function nxpositionCursor(obj, pos)
{
	if (nxIE) {
		var range = obj.createTextRange();
		range.move('character', from);
		range.select();		// TODO: test this
	} else {
		obj.selectionStart = obj.selectionEnd = pos;
		obj.focus();
	}
}

// Scrolls the object to the given line out of the given total number of lines.
// The total number of lines must be supplied for the calculation to be
// correct.
function nxscrollObject(obj, line, total)
{
	if (total == 0)
		obj.scrollTop = 0;
	else
		obj.scrollTop = ((line - 1) / total) * obj.scrollHeight; 
}

// Retrieves the last character typed.
function nxgetLastChar(obj)
{
	if (window.event && window.event.keyCode)
		return window.event.keyCode;

	if (nxIE) {
		var range = document.selection.createRange();
		range.moveStart('character', -1);
		return range.text.charCodeAt(0);
	} else {
		var range = document.createRange();
		range.setStart(obj, obj.selectionEnd - 1);
		range.setEnd(obj, obj.selectionEnd);
		return range.toString().charCodeAt(0);
	}
}

// Retrieves the last n characters typed.
function nxgetLastChars(obj, n)
{
	if (nxIE) {
		var range = document.selection.createRange();
		range.moveStart('character', -n);
		return range.text;
	} else {
		return obj.value.substring(obj.selectionStart - n, obj.selectionStart);
	}
}

// Retrieves the line *before* the insertion point (or "" if on the first line).
function nxgetPrevLine(obj)
{
	var prefix;
	if (nxIE) {
		var range = document.selection.createRange();
		range.moveStart('textarea', 0);
		prefix = range.text;
	} else if (obj.selectionStart != null) {
		prefix = obj.value.substring(0, obj.selectionStart);
	}

	/*var end = prefix.lastIndexOf("\n");
	if (end > 0) {
		var start = prefix.substring(0, end).lastIndexOf("\n");
		if (end > 0)
			return prefix.substring(start + 1, end);
		else
			return "";
	} else
		return ""; */
		
	var m = prefix.match(/([^\n]*)\n[^\n]*$/);
	if (m)
		return m[1];
	else
		return "";
}

// Inserts the given text at the insertion point.
function nxinsertText(obj, text)
{
	if (nxIE) {
		obj.focus();
		document.selection.createRange().text += text;
	} else if (obj.selectionEnd != null) {
		var oend = obj.selectionEnd;
		var otop = obj.scrollTop;
		
		var val = obj.value;
		obj.value = val.substring(0, obj.selectionEnd) + text +
			val.substring(obj.selectionEnd);
			
		obj.selectionEnd = oend + text.length;
		obj.scrollTop = otop;
	}
}

// Replaces the last n characters typed with the given text.
function nxreplaceLastChars(obj, n, text)
{
	if (nxIE) {
		obj.focus();
		var range = document.selection.createRange();
		range.moveStart('character', -n);
		range.text = text;
	} else if (obj.selectionEnd != null) {
		var val = obj.value;
		obj.value = val.substring(0, obj.selectionEnd - n) + text +
			val.substring(obj.selectionEnd + 1);
	}
}
