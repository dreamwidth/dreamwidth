/*
xbDOM.js v 0.005 2002-04-11

Contributor(s): Bob Clary, Netscape Communications, Copyright 2001, 2002

Netscape grants you a royalty free license to use, modify and 
distribute this software provided that this copyright notice 
appears on all copies.  This software is provided "AS IS," 
without a warranty of any kind.

Change Log: 

2002-04-11: v 0.005
  bclary -
    fix bug in IE version of xbGetElementsByName where windowRef was not correctly
    used. Thanks to Jens Ellegiers for the fix.

2002-03-15: v 0.004
  bclary -
    fix bug in bugfix for 0.003 in xbGetElementsByName 
    to not confuse elements with length properties with arrays

2002-03-09: v 0.003
  bclary -
    fix bug in xbGetElementsByName in Internet Explorer when there is
    only one instance of an element with name value.

2002-01-19: v 0.002
  bclary - 
    nav4FindElementsByName
      removed erroneous obj and return
      added search of form elements
    xbFindElementsByNameAndType
      renamed from FindElementsByNameAndType
      removed erroneouse obj and return
    xbSetInnerHTML
      ported over from xbStyle since it is more
      appropriate here.

2001-11-27: v 0.01
  bclary - 
    removed from xbStyle
*/

function xbToInt(s)
{
  var i = parseInt(s, 10);
  if (isNaN(i))
    i = 0;

  return i;
}

function xbGetWindowWidth(windowRef)
{
  var width = 0;

  if (!windowRef)
    windowRef = window;
  
  if (typeof(windowRef.innerWidth) == 'number')
    width = windowRef.innerWidth;
  else if (windowRef.document.body && typeof(windowRef.document.body.clientWidth) == 'number')
    width = windowRef.document.body.clientWidth;  
    
  return width;
}

function xbGetWindowHeight(windowRef)
{
  var height = 0;
  
  if (!windowRef)
    windowRef = window;

  if (typeof(windowRef.innerWidth) == 'number')
    height = windowRef.innerHeight;
  else if (windowRef.document.body && typeof(windowRef.document.body.clientWidth) == 'number')
    height = windowRef.document.body.clientHeight;    

  return height;
}

function nav4FindLayer(doc, id)
{
  var i;
  var subdoc;
  var obj;
  
  for (i = 0; i < doc.layers.length; ++i)
  {
    if (doc.layers[i].id && id == doc.layers[i].id)
      return doc.layers[i];
      
    subdoc = doc.layers[i].document;
    obj    = nav4FindLayer(subdoc, id);
    if (obj != null)
      return obj;
  }
  return null;
}

function nav4FindElementsByName(doc, name, elmlist)
{
  var i;
  var j;
  var subdoc;
  
  for (i = 0; i < doc.images.length; ++i)
  {
    if (doc.images[i].name && name == doc.images[i].name)
      elmlist[elmlist.length] = doc.images[i];
  }

  for (i = 0; i < doc.forms.length; ++i)
  {
    for (j = 0; j < doc.forms[i].elements.length; j++)
      if (doc.forms[i].elements[j].name && name == doc.forms[i].elements[j].name)
        elmlist[elmlist.length] = doc.forms[i].elements[j];

    if (doc.forms[i].name && name == doc.forms[i].name)
      elmlist[elmlist.length] = doc.forms[i];
  }

  for (i = 0; i < doc.anchors.length; ++i)
  {
    if (doc.anchors[i].name && name == doc.anchors[i].name)
      elmlist[elmlist.length] = doc.anchors[i];
  }

  for (i = 0; i < doc.links.length; ++i)
  {
    if (doc.links[i].name && name == doc.links[i].name)
      elmlist[elmlist.length] = doc.links[i];
  }

  for (i = 0; i < doc.applets.length; ++i)
  {
    if (doc.applets[i].name && name == doc.applets[i].name)
      elmlist[elmlist.length] = doc.applets[i];
  }

  for (i = 0; i < doc.embeds.length; ++i)
  {
    if (doc.embeds[i].name && name == doc.embeds[i].name)
      elmlist[elmlist.length] = doc.embeds[i];
  }

  for (i = 0; i < doc.layers.length; ++i)
  {
    if (doc.layers[i].name && name == doc.layers[i].name)
      elmlist[elmlist.length] = doc.layers[i];
      
    subdoc = doc.layers[i].document;
    nav4FindElementsByName(subdoc, name, elmlist);
  }
}

function xbGetElementsByNameAndType(name, type, windowRef)
{
  if (!windowRef)
    windowRef = window;

  var elmlist = new Array();

  xbFindElementsByNameAndType(windowRef.document, name, type, elmlist);

  return elmlist;
}

function xbFindElementsByNameAndType(doc, name, type, elmlist)
{
  var i;
  var subdoc;
  
  for (i = 0; i < doc[type].length; ++i)
  {
    if (doc[type][i].name && name == doc[type][i].name)
      elmlist[elmlist.length] = doc[type][i];
  }

  if (doc.layers)
  {
    for (i = 0; i < doc.layers.length; ++i)
    {
      subdoc = doc.layers[i].document;
      xbFindElementsByNameAndType(subdoc, name, type, elmlist);
    }
  }
}

if (document.layers)
{
  xbGetElementById = function (id, windowRef)
  {
    if (!windowRef)
      windowRef = window;

    return nav4FindLayer(windowRef.document, id);
  };

  xbGetElementsByName = function (name, windowRef)
  {
    if (!windowRef)
      windowRef = window;

    var elmlist = new Array();

    nav4FindElementsByName(windowRef.document, name, elmlist);

    return elmlist;
  };

}
else if (document.all)
{
  xbGetElementById = function (id, windowRef) { if (!windowRef) windowRef = window; var elm = windowRef.document.all[id]; if (!elm) elm = null; return elm; };
  xbGetElementsByName = function (name, windowRef)
  {
    if (!windowRef)
      windowRef = window;

    var i;
    var idnamelist = windowRef.document.all[name];
    var elmlist = new Array();

    if (!idnamelist.length || idnamelist.name == name)
    {
      if (idnamelist)
        elmlist[elmlist.length] = idnamelist;
    }
    else
    {
      for (i = 0; i < idnamelist.length; i++)
      {
        if (idnamelist[i].name == name)
          elmlist[elmlist.length] = idnamelist[i];
      }
    }

    return elmlist;
  }

}
else if (document.getElementById)
{
  xbGetElementById = function (id, windowRef) { if (!windowRef) windowRef = window; return windowRef.document.getElementById(id); };
  xbGetElementsByName = function (name, windowRef) { if (!windowRef) windowRef = window; return windowRef.document.getElementsByName(name); };
}
else 
{
  xbGetElementById = function (id, windowRef) { return null; }
  xbGetElementsByName = function (name, windowRef) { return new Array(); }
}

if (typeof(window.pageXOffset) == 'number')
{
  xbGetPageScrollX = function (windowRef) { if (!windowRef) windowRef = window; return windowRef.pageXOffset; };
  xbGetPageScrollY = function (windowRef) { if (!windowRef) windowRef = window; return windowRef.pageYOffset; };
}
else if (document.all)
{
  xbGetPageScrollX = function (windowRef) { if (!windowRef) windowRef = window; return windowRef.document.body.scrollLeft; };
  xbGetPageScrollY = function (windowRef) { if (!windowRef) windowRef = window; return windowRef.document.body.scrollTop; };
}
else
{
  xbGetPageScrollX = function (windowRef) { return 0; };
  xbGetPageScrollY = function (windowRef) { return 0; };
}

if (document.layers)
{
  xbSetInnerHTML = function (element, str) { element.document.write(str); element.document.close(); };
}
else if (document.all || document.getElementById)
{
  xbSetInnerHTML = function (element, str) { if (typeof(element.innerHTML) != 'undefined') element.innerHTML = str; };
}
else
{
  xbSetInnerHTML = function (element, str) {};
}


// eof: xbDOM.js
