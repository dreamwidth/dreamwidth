/*
xbStyle.js Revision: 0.202 2002-02-11

Contributor(s): Bob Clary, Original Work, Copyright 2000
                Bob Clary, Netscape Communications, Copyright 2001

Netscape grants you a royalty free license to use, modify and 
distribute this software provided that this copyright notice 
appears on all copies.  This software is provided "AS IS," 
without a warranty of any kind.

Change Log:

2001-07-19: bclary - fixed function cssStyleGetLeft() and cssStyleGetTop() to 
            correctly handle the case where the initial style.left/style.top
            are not initialized. This fixes positioning for relatively positioned
            DIVS and as a result fixes behavior for ILAYERs exposed as relatively
            positioned divs.
2001-10-02: bclary - added missing xbClipRect.getHeight/setHeight methods.

2001-11-20: bclary - removed use of practical browser sniffer, 
            added object sniffing, and limited support for opera
            note opera returns ints for HTMLElement.style.[left|top|height|width] etc.

2002-02-11: v 0.201 bclary - with the help of Rob Johnston <rob_johnston@hotmail.com>
            found that the "if (document.getElementsByName)" test excluded
            IE4. Added a test for document.all to enable IE4 to fully use 
            xbStyle.

2002-03-12: v 0.202 Daniel Resare contributed a patch to cssStyleSetPage[X|Y]() which
            handles the case where the element has no parentNode.
*/

function xbStyleNotSupported() {}

function xbStyleNotSupportStringValue(propname) { xbDEBUG.dump(propname + ' is not supported in this browser'); return '';};

/////////////////////////////////////////////////////////////
// xbClipRect

function xbClipRect(a1, a2, a3, a4)
{
  this.top  = 0;
  this.right  = 0;
  this.bottom  = 0;
  this.left  = 0;

  if (typeof(a1) == 'string')
  {
    var val;
    var ca;
    var i;
      
    if (a1.indexOf('rect(') == 0)
    {
      // I would have preferred [0-9]+[a-zA-Z]+ for a regexp
      // but NN4 returns null for that. 
      ca = a1.substring(5, a1.length-1).match(/-?[0-9a-zA-Z]+/g);
      for (i = 0; i < 4; ++i)
      {
        val = xbToInt(ca[i]);
        if (val != 0 && ca[i].indexOf('px') == -1)
        {
          xbDEBUG.dump('xbClipRect: A clipping region ' + a1 + ' was detected that did not use pixels as units.  Click Ok to continue, Cancel to Abort');
          return;
        }
        ca[i] = val;
      }
      this.top    = ca[0];
      this.right  = ca[1];
      this.bottom = ca[2];
      this.left   = ca[3];
    }
  }    
  else if (typeof(a1) == 'number' && typeof(a2) == 'number' && typeof(a3) == 'number' && typeof(a4) == 'number')
  {
    this.top    = a1;
    this.right  = a2;
    this.bottom = a3;
    this.left   = a4;
  }
}

xbClipRect.prototype.top = 0;
xbClipRect.prototype.right = 0;
xbClipRect.prototype.bottom = 0;
xbClipRect.prototype.left = 0;


function xbClipRectGetWidth()
{
    return this.right - this.left;
}
xbClipRect.prototype.getWidth = xbClipRectGetWidth; 

function xbClipRectSetWidth(width)
{
  this.right = this.left + width;
}
xbClipRect.prototype.setWidth = xbClipRectSetWidth;

function xbClipRectGetHeight()
{
    return this.bottom - this.top;
}
xbClipRect.prototype.getHeight = xbClipRectGetHeight; 

function xbClipRectSetHeight(height)
{
  this.bottom = this.top + height;
}
xbClipRect.prototype.setHeight = xbClipRectSetHeight;

function xbClipRectToString()
{
  return 'rect(' + this.top + 'px ' + this.right + 'px ' + this.bottom + 'px ' + this.left + 'px )' ;
}
xbClipRect.prototype.toString = xbClipRectToString;

/////////////////////////////////////////////////////////////
// xbStyle
//
// Note Opera violates the standard by cascading the effective values
// into the HTMLElement.style object. We can use IE's HTMLElement.currentStyle
// to get the effective values. In Gecko we will use the W3 DOM Style Standard getComputedStyle

function xbStyle(obj, position)
{
  if (typeof(obj) == 'object' && typeof(obj.style) != 'undefined') 
    this.styleObj = obj.style;
  else if (document.layers) // NN4
  {
    if (typeof(position) == 'undefined')
      position = '';
        
    this.styleObj = obj;
    this.styleObj.position = position;
  }
  this.object = obj;
}

xbStyle.prototype.styleObj = null;
xbStyle.prototype.object = null;

/////////////////////////////////////////////////////////////
// xbStyle.getEffectiveValue()
// note that xbStyle's constructor uses the currentStyle object 
// for IE5+ and that Opera's style object contains computed values
// already. Netscape Navigator's layer object also contains the 
// computed values as well. Note that IE4 will not return the 
// computed values.

function xbStyleGetEffectiveValue(propname)
{
  var value = null;

  // W3/Gecko
  if (document.defaultView && document.defaultView.getComputedStyle)
  {
    if (navigator.family == 'gecko')
    {
      // xxxHack: work around Gecko getComputedStyle bugs...
      switch(propname)
      {
      case 'clip':
         return this.styleObj[propname];
      case 'top':
        if (navigator.family == 'gecko' && navigator.version < 0.96 && this.styleObj.position == 'relative')
           return this.object.offsetTop;
      case 'left':
        if (navigator.family == 'gecko' && navigator.version < 0.96 && this.styleObj.position == 'relative')
           return this.object.offsetLeft;
      }
    }
    // Note that propname is the name of the property in the CSS Style
    // Object. However the W3 method getPropertyValue takes the actual
    // property name from the CSS Style rule, i.e., propname is 
    // 'backgroundColor' but getPropertyValue expects 'background-color'.

     var capIndex;
     var cappropname = propname;
     while ( (capIndex = cappropname.search(/[A-Z]/)) != -1)
     {
       if (capIndex != -1)
         cappropname = cappropname.substring(0, capIndex) + '-' + cappropname.substring(capIndex, capIndex).toLowerCase() + cappropname.substr(capIndex+1);
     }

     value =  document.defaultView.getComputedStyle(this.object, '').getPropertyValue(cappropname);

     // xxxHack for Gecko:
     if (!value && this.styleObj[propname])
       value = this.styleObj[propname];
  }
  else if (typeof(this.styleObj[propname]) == 'undefined') 
    value = xbStyleNotSupportStringValue(propname);
  else 
  {
    if (navigator.family != 'ie4' || navigator.version < 5)
    {
      // IE4+, Opera, NN4
      value = this.styleObj[propname];
    }
    else
    {
     // IE5+
     value = this.object.currentStyle[propname];
     if (!value)
       value = this.styleObj[propname];
    }
  }

  return value;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClip()

function cssStyleGetClip()
{
  var clip = this.getEffectiveValue('clip');

  // hack opera
  if (clip == 'rect()')
    clip = '';

  if (clip == '')
    clip = 'rect(0px ' + this.getWidth() + 'px ' + this.getHeight() + 'px 0px)';

  return clip;
}

function nsxbStyleGetClip()
{
  var clip = this.styleObj.clip;
  var rect = new xbClipRect(clip.top, clip.right, clip.bottom, clip.left);
  return rect.toString();
}

/////////////////////////////////////////////////////////////
// xbStyle.setClip()

function cssStyleSetClip(sClipString)
{
  this.styleObj.clip = sClipString;
}

function nsxbStyleSetClip(sClipString)
{
  var rect          = new xbClipRect(sClipString);
  this.styleObj.clip.top    = rect.top;
  this.styleObj.clip.right  = rect.right;
  this.styleObj.clip.bottom  = rect.bottom;
  this.styleObj.clip.left    = rect.left;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClipTop()

function cssStyleGetClipTop()
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  return rect.top;
}

function nsxbStyleGetClipTop()
{
  return this.styleObj.clip.top;
}

/////////////////////////////////////////////////////////////
// xbStyle.setClipTop()

function cssStyleSetClipTop(top)
{
  var clip = this.getClip();
  var rect         = new xbClipRect(clip);
  rect.top         = top;
  this.styleObj.clip = rect.toString();
}

function nsxbStyleSetClipTop(top)
{
  return this.styleObj.clip.top = top;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClipRight()

function cssStyleGetClipRight()
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  return rect.right;
}

function nsxbStyleGetClipRight()
{
  return this.styleObj.clip.right;
}

/////////////////////////////////////////////////////////////
// xbStyle.setClipRight()

function cssStyleSetClipRight(right)
{
  var clip = this.getClip();
  var rect          = new xbClipRect(clip);
  rect.right        = right;
  this.styleObj.clip  = rect.toString();
}

function nsxbStyleSetClipRight(right)
{
  return this.styleObj.clip.right = right;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClipBottom()

function cssStyleGetClipBottom()
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  return rect.bottom;
}

function nsxbStyleGetClipBottom()
{
  return this.styleObj.clip.bottom;
}

/////////////////////////////////////////////////////////////
// xbStyle.setClipBottom()

function cssStyleSetClipBottom(bottom)
{
  var clip = this.getClip();
  var rect           = new xbClipRect(clip);
  rect.bottom        = bottom;
  this.styleObj.clip   = rect.toString();
}

function nsxbStyleSetClipBottom(bottom)
{
  return this.styleObj.clip.bottom = bottom;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClipLeft()

function cssStyleGetClipLeft()
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  return rect.left;
}

function nsxbStyleGetClipLeft()
{
  return this.styleObj.clip.left;
}

/////////////////////////////////////////////////////////////
// xbStyle.setClipLeft()

function cssStyleSetClipLeft(left)
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  rect.left = left;
  this.styleObj.clip = rect.toString();
}

function nsxbStyleSetClipLeft(left)
{
  return this.styleObj.clip.left = left;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClipWidth()

function cssStyleGetClipWidth()
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  return rect.getWidth();
}

function nsxbStyleGetClipWidth()
{
  return this.styleObj.clip.width;
}

/////////////////////////////////////////////////////////////
// xbStyle.setClipWidth()

function cssStyleSetClipWidth(width)
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  rect.setWidth(width);
  this.styleObj.clip = rect.toString();
}

function nsxbStyleSetClipWidth(width)
{
  return this.styleObj.clip.width = width;
}

/////////////////////////////////////////////////////////////
// xbStyle.getClipHeight()

function cssStyleGetClipHeight()
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  return rect.getHeight();
}

function nsxbStyleGetClipHeight()
{
  return this.styleObj.clip.height;
}

/////////////////////////////////////////////////////////////
// xbStyle.setClipHeight()

function cssStyleSetClipHeight(height)
{
  var clip = this.getClip();
  var rect = new xbClipRect(clip);
  rect.setHeight(height);
  this.styleObj.clip = rect.toString();
}

function nsxbStyleSetClipHeight(height)
{
  return this.styleObj.clip.height = height;
}

// the CSS attributes left,top are for absolutely positioned elements
// measured relative to the containing element.  for relatively positioned
// elements, left,top are measured from the element's normal inline position.
// getLeft(), setLeft() operate on this type of coordinate.
//
// to allow dynamic positioning the getOffsetXXX and setOffsetXXX methods are
// defined to return and set the position of either an absolutely or relatively
// positioned element relative to the containing element.
//
//

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getLeft()

function cssStyleGetLeft()
{
  var left = this.getEffectiveValue('left');
  if (typeof(left) == 'number')
     return left;

  if (left != '' && left.indexOf('px') == -1)
  {
    xbDEBUG.dump('xbStyle.getLeft: Element ID=' + this.object.id + ' does not use pixels as units. left=' + left + ' Click Ok to continue, Cancel to Abort');
    return 0;
  }

  if (left == '')
    left = this.styleObj.left = '0px';
      
  return xbToInt(left);
}

function nsxbStyleGetLeft()
{
  return this.styleObj.left;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setLeft()

function cssStyleSetLeft(left)
{
  if (typeof(this.styleObj.left) == 'number')
    this.styleObj.left = left;
  else
    this.styleObj.left = left + 'px';
}

function nsxbStyleSetLeft(left)
{
  this.styleObj.left = left;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getTop()

function cssStyleGetTop()
{
  var top = this.getEffectiveValue('top');
  if (typeof(top) == 'number')
     return top;

  if (top != '' && top.indexOf('px') == -1)
  {
    xbDEBUG.dump('xbStyle.getTop: Element ID=' + this.object.id + ' does not use pixels as units. top=' + top + ' Click Ok to continue, Cancel to Abort');
    return 0;
  }

  if (top == '')
    top = this.styleObj.top = '0px';
      
  return xbToInt(top);
}

function nsxbStyleGetTop()
{
  return this.styleObj.top;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setTop()

function cssStyleSetTop(top)
{
  if (typeof(this.styleObj.top) == 'number')
    this.styleObj.top = top;
  else
    this.styleObj.top = top + 'px';
}

function nsxbStyleSetTop(top)
{
  this.styleObj.top = top;
}


/////////////////////////////////////////////////////////////////////////////
// xbStyle.getPageX()

function cssStyleGetPageX()
{
  var x = 0;
  var elm = this.object;
  var elmstyle;
  var position;
  
  //xxxHack: Due to limitations in Gecko's (0.9.6) ability to determine the 
  // effective position attribute , attempt to use offsetXXX

  if (typeof(elm.offsetLeft) == 'number')
  {
    while (elm)
    {
      x += elm.offsetLeft;
      elm = elm.offsetParent;
    }
  }
  else
  {
    while (elm)
    {
      if (elm.style)
      {
        elmstyle = new xbStyle(elm);
        position = elmstyle.getEffectiveValue('position');
        if (position != '' && position != 'static')
          x += elmstyle.getLeft();
      }
      elm = elm.parentNode;
    }
  }
  
  return x;
}

function nsxbStyleGetPageX()
{
  return this.styleObj.pageX;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setPageX()

function cssStyleSetPageX(x)
{
  var xParent = 0;
  var elm = this.object.parentNode;
  var elmstyle;
  var position;
  
  //xxxHack: Due to limitations in Gecko's (0.9.6) ability to determine the 
  // effective position attribute , attempt to use offsetXXX

  if (elm && typeof(elm.offsetLeft) == 'number')
  {
    while (elm)
    {
      xParent += elm.offsetLeft;
      elm = elm.offsetParent;
    }
  }
  else
  {
    while (elm)
    {
      if (elm.style)
      {
        elmstyle = new xbStyle(elm);
        position = elmstyle.getEffectiveValue('position');
        if (position != '' && position != 'static')
          xParent += elmstyle.getLeft();
      }
      elm = elm.parentNode;
    }
  }
  
  x -= xParent;

  this.setLeft(x);
}
    
function nsxbStyleSetPageX(x)
{
  this.styleObj.x = this.styleObj.x  + x - this.styleObj.pageX;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getPageY()

function cssStyleGetPageY()
{
  var y = 0;
  var elm = this.object;
  var elmstyle;
  var position;
  
  //xxxHack: Due to limitations in Gecko's (0.9.6) ability to determine the 
  // effective position attribute , attempt to use offsetXXX

  if (typeof(elm.offsetTop) == 'number')
  {
    while (elm)
    {
      y += elm.offsetTop;
      elm = elm.offsetParent;
    }
  }
  else
  {
    while (elm)
    {
      if (elm.style)
      {
        elmstyle = new xbStyle(elm);
        position = elmstyle.getEffectiveValue('position');
        if (position != '' && position != 'static')
          y += elmstyle.getTop();
      }
      elm = elm.parentNode;
    }
  }
  
  return y;
}

function nsxbStyleGetPageY()
{
  return this.styleObj.pageY;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setPageY()

function cssStyleSetPageY(y)
{
  var yParent = 0;
  var elm = this.object.parentNode;
  var elmstyle;
  var position;
  
  //xxxHack: Due to limitations in Gecko's (0.9.6) ability to determine the 
  // effective position attribute , attempt to use offsetXXX

  if (elm && typeof(elm.offsetTop) == 'number')
  {
    while (elm)
    {
      yParent += elm.offsetTop;
      elm = elm.offsetParent;
    }
  }
  else
  {
    while (elm)
    {
      if (elm.style)
      {
        elmstyle = new xbStyle(elm);
        position = elmstyle.getEffectiveValue('position');
        if (position != '' && position != 'static')
          yParent += elmstyle.getTop();
      }
      elm = elm.parentNode;
    }
  }
  
  y -= yParent;

  this.setTop(y);
}
    
function nsxbStyleSetPageY(y)
{
  this.styleObj.y = this.styleObj.y  + y - this.styleObj.pageY;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getHeight()

function cssStyleGetHeight()
{
  var height = this.getEffectiveValue('height');
  if (typeof(height) == 'number')
     return height;

  if ((height == 'auto' || height.indexOf('%') != -1) && typeof(this.object.offsetHeight) == 'number')
    height = this.object.offsetHeight + 'px';

  if (height != '' && height != 'auto' && height.indexOf('px') == -1)
  {
    xbDEBUG.dump('xbStyle.getHeight: Element ID=' + this.object.id + ' does not use pixels as units. height=' + height + ' Click Ok to continue, Cancel to Abort');
    return 0;
  }

  height = xbToInt(height);

  return height;
}

function nsxbStyleGetHeight()
{
  //if (this.styleObj.document && this.styleObj.document.height)
  //  return this.styleObj.document.height;
    
  return this.styleObj.clip.height;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setHeight()

function cssStyleSetHeight(height)
{
  if (typeof(this.styleObj.height) == 'number')
    this.styleObj.height = height;
  else
    this.styleObj.height = height + 'px';
}

function nsxbStyleSetHeight(height)
{
  this.styleObj.clip.height = height;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getWidth()

function cssStyleGetWidth()
{
  var width = this.getEffectiveValue('width');
  if (typeof(width) == 'number')
     return width;

  if ((width == 'auto' || width.indexOf('%') != -1) && typeof(this.object.offsetWidth) == 'number')
    width = this.object.offsetWidth + 'px';

  if (width != '' && width != 'auto' && width.indexOf('px') == -1)
  {
    xbDEBUG.dump('xbStyle.getWidth: Element ID=' + this.object.id + ' does not use pixels as units. width=' + width + ' Click Ok to continue, Cancel to Abort');
    return 0;
  }

  width = xbToInt(width);

  return width;
}

function nsxbStyleGetWidth()
{
  //if (this.styleObj.document && this.styleObj.document.width)
  //  return this.styleObj.document.width;
    
  return this.styleObj.clip.width;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setWidth()

function cssStyleSetWidth(width)
{
  if (typeof(this.styleObj.width) == 'number')
    this.styleObj.width = width;
  else
    this.styleObj.width = width + 'px';
}

// netscape will not dynamically change the width of a 
// layer. It will only happen upon a refresh.
function nsxbStyleSetWidth(width)
{
  this.styleObj.clip.width = width;
}

/////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getVisibility()

function cssStyleGetVisibility()
{
  return this.getEffectiveValue('visibility');
}

function nsxbStyleGetVisibility()
{
  switch(this.styleObj.visibility)
  {
  case 'hide':
    return 'hidden';
  case 'show':
    return 'visible';
  }
  return '';
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setVisibility()

function cssStyleSetVisibility(visibility)
{
  this.styleObj.visibility = visibility;
}

function nsxbStyleSetVisibility(visibility)
{
  switch(visibility)
  {
  case 'hidden':
    visibility = 'hide';
    break;
  case 'visible':
    visibility = 'show';
    break;
  case 'inherit':
    break;
  default:
    visibility = 'show';
    break;
  }
  this.styleObj.visibility = visibility;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getzIndex()

function cssStyleGetzIndex()
{
  return xbToInt(this.getEffectiveValue('zIndex'));
}

function nsxbStyleGetzIndex()
{
  return this.styleObj.zIndex;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setzIndex()

function cssStyleSetzIndex(zIndex)
{
  this.styleObj.zIndex = zIndex;
}

function nsxbStyleSetzIndex(zIndex)
{
  this.styleObj.zIndex = zIndex;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getBackgroundColor()

function cssStyleGetBackgroundColor()
{
  return this.getEffectiveValue('backgroundColor');
}

function nsxbStyleGetBackgroundColor()
{
  return this.styleObj.bgColor;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setBackgroundColor()

function cssStyleSetBackgroundColor(color)
{
  this.styleObj.backgroundColor = color;
}

function nsxbStyleSetBackgroundColor(color)
{
  if (color)
  {
    this.styleObj.bgColor = color;
    this.object.document.bgColor = color;
    this.resizeTo(this.getWidth(), this.getHeight());
  }
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getColor()

function cssStyleGetColor()
{
  return this.getEffectiveValue('color');
}

function nsxbStyleGetColor()
{
  return '#ffffff';
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setColor()

function cssStyleSetColor(color)
{
  this.styleObj.color = color;
}

function nsxbStyleSetColor(color)
{
  this.object.document.fgColor = color;
}


/////////////////////////////////////////////////////////////////////////////
// xbStyle.moveAbove()

function xbStyleMoveAbove(cont)
{
  this.setzIndex(cont.getzIndex()+1);
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.moveBelow()

function xbStyleMoveBelow(cont)
{
  var zindex = cont.getzIndex() - 1;
            
  this.setzIndex(zindex);
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.moveBy()

function xbStyleMoveBy(deltaX, deltaY)
{
  this.moveTo(this.getLeft() + deltaX, this.getTop() + deltaY);
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.moveTo()

function xbStyleMoveTo(x, y)
{
  this.setLeft(x);
  this.setTop(y);
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.moveToAbsolute()

function xbStyleMoveToAbsolute(x, y)
{
  this.setPageX(x);
  this.setPageY(y);
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.resizeBy()

function xbStyleResizeBy(deltaX, deltaY)
{
  this.setWidth( this.getWidth() + deltaX );
  this.setHeight( this.getHeight() + deltaY );
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.resizeTo()

function xbStyleResizeTo(x, y)
{
  this.setWidth(x);
  this.setHeight(y);
}

////////////////////////////////////////////////////////////////////////
// Navigator 4.x resizing...

function nsxbStyleOnresize()
{
    if (saveInnerWidth != xbGetWindowWidth() || saveInnerHeight != xbGetWindowHeight())
    location.reload();

  return false;
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.setInnerHTML()

function xbSetInnerHTML(str)
{
  if (typeof(this.object.innerHTML) != 'undefined')
    this.object.innerHTML = str;
}

function nsxbSetInnerHTML(str)
{
  this.object.document.open('text/html');
  this.object.document.write(str);
  this.object.document.close();
}

////////////////////////////////////////////////////////////////////////
// Extensions to xbStyle that are not supported by Netscape Navigator 4
// but that provide cross browser implementations of properties for 
// Mozilla, Gecko, Netscape 6.x and Opera

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getBorderTopWidth()

function cssStyleGetBorderTopWidth()
{
  return xbToInt(this.getEffectiveValue('borderTopWidth'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getBorderRightWidth()

function cssStyleGetBorderRightWidth()
{
  return xbToInt(this.getEffectiveValue('borderRightWidth'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getBorderBottomWidth()

function cssStyleGetBorderBottomWidth()
{
  return xbToInt(this.getEffectiveValue('borderLeftWidth'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getBorderLeftWidth()

function cssStyleGetBorderLeftWidth()
{
  return xbToInt(this.getEffectiveValue('borderLeftWidth'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getMarginTop()

function cssStyleGetMarginTop()
{
  return xbToInt(this.getEffectiveValue('marginTop'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getMarginRight()

function cssStyleGetMarginRight()
{
  return xbToInt(this.getEffectiveValue('marginRight'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getMarginBottom()

function cssStyleGetMarginBottom()
{
  return xbToInt(this.getEffectiveValue('marginBottom'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getMarginLeft()

function cssStyleGetMarginLeft()
{
  return xbToInt(this.getEffectiveValue('marginLeft'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getPaddingTop()

function cssStyleGetPaddingTop()
{
  return xbToInt(this.getEffectiveValue('paddingTop'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getPaddingRight()

function cssStyleGetPaddingRight()
{
  return xbToInt(this.getEffectiveValue('paddingRight'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getPaddingBottom()

function cssStyleGetPaddingBottom()
{
  return xbToInt(this.getEffectiveValue('paddingBottom'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getPaddingLeft()

function cssStyleGetPaddingLeft()
{
  return xbToInt(this.getEffectiveValue('paddingLeft'));
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getClientTop()

function cssStyleGetClientTop()
{
  return this.getTop() - this.getMarginTop() - this.getBorderTopWidth() - this.getPaddingTop();
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getClientLeft()

function cssStyleGetClientLeft()
{
  return this.getLeft() - this.getMarginLeft() - this.getBorderLeftWidth() - this.getPaddingLeft();
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getClientWidth()

function cssStyleGetClientWidth()
{
  return this.getMarginLeft() + this.getBorderLeftWidth() + this.getPaddingLeft() + this.getWidth() + this.getPaddingRight() + this.getBorderRightWidth() + this.getMarginRight();
}

/////////////////////////////////////////////////////////////////////////////
// xbStyle.getClientHeight()

function cssStyleGetClientHeight()
{
  return this.getMarginTop() + this.getBorderTopWidth() + this.getPaddingTop() + this.getHeight() + this.getPaddingBottom() + this.getBorderBottomWidth() + this.getMarginBottom();
}

////////////////////////////////////////////////////////////////////////

xbStyle.prototype.getEffectiveValue     = xbStyleGetEffectiveValue;
xbStyle.prototype.moveAbove             = xbStyleMoveAbove;
xbStyle.prototype.moveBelow             = xbStyleMoveBelow;
xbStyle.prototype.moveBy                = xbStyleMoveBy;
xbStyle.prototype.moveTo                = xbStyleMoveTo;
xbStyle.prototype.moveToAbsolute        = xbStyleMoveToAbsolute;
xbStyle.prototype.resizeBy              = xbStyleResizeBy;
xbStyle.prototype.resizeTo              = xbStyleResizeTo;

if (document.all || document.getElementsByName)
{
  xbStyle.prototype.getClip            = cssStyleGetClip;
  xbStyle.prototype.setClip            = cssStyleSetClip;  
  xbStyle.prototype.getClipTop         = cssStyleGetClipTop;
  xbStyle.prototype.setClipTop         = cssStyleSetClipTop;  
  xbStyle.prototype.getClipRight       = cssStyleGetClipRight;
  xbStyle.prototype.setClipRight       = cssStyleSetClipRight;  
  xbStyle.prototype.getClipBottom      = cssStyleGetClipBottom;
  xbStyle.prototype.setClipBottom      = cssStyleSetClipBottom;  
  xbStyle.prototype.getClipLeft        = cssStyleGetClipLeft;
  xbStyle.prototype.setClipLeft        = cssStyleSetClipLeft;  
  xbStyle.prototype.getClipWidth       = cssStyleGetClipWidth;
  xbStyle.prototype.setClipWidth       = cssStyleSetClipWidth;  
  xbStyle.prototype.getClipHeight      = cssStyleGetClipHeight;
  xbStyle.prototype.setClipHeight      = cssStyleSetClipHeight;  
  xbStyle.prototype.getLeft            = cssStyleGetLeft;
  xbStyle.prototype.setLeft            = cssStyleSetLeft;
  xbStyle.prototype.getTop             = cssStyleGetTop;
  xbStyle.prototype.setTop             = cssStyleSetTop;
  xbStyle.prototype.getPageX           = cssStyleGetPageX;
  xbStyle.prototype.setPageX           = cssStyleSetPageX;
  xbStyle.prototype.getPageY           = cssStyleGetPageY;
  xbStyle.prototype.setPageY           = cssStyleSetPageY;
  xbStyle.prototype.getVisibility      = cssStyleGetVisibility;
  xbStyle.prototype.setVisibility      = cssStyleSetVisibility;
  xbStyle.prototype.getzIndex          = cssStyleGetzIndex;
  xbStyle.prototype.setzIndex          = cssStyleSetzIndex;            
  xbStyle.prototype.getHeight          = cssStyleGetHeight;
  xbStyle.prototype.setHeight          = cssStyleSetHeight;
  xbStyle.prototype.getWidth           = cssStyleGetWidth;
  xbStyle.prototype.setWidth           = cssStyleSetWidth;
  xbStyle.prototype.getBackgroundColor = cssStyleGetBackgroundColor;
  xbStyle.prototype.setBackgroundColor = cssStyleSetBackgroundColor;
  xbStyle.prototype.getColor           = cssStyleGetColor;
  xbStyle.prototype.setColor           = cssStyleSetColor;
  xbStyle.prototype.setInnerHTML       = xbSetInnerHTML;
  xbStyle.prototype.getBorderTopWidth    = cssStyleGetBorderTopWidth;
  xbStyle.prototype.getBorderRightWidth  = cssStyleGetBorderRightWidth;
  xbStyle.prototype.getBorderBottomWidth = cssStyleGetBorderBottomWidth;
  xbStyle.prototype.getBorderLeftWidth   = cssStyleGetBorderLeftWidth;
  xbStyle.prototype.getMarginLeft        = cssStyleGetMarginLeft;
  xbStyle.prototype.getMarginTop         = cssStyleGetMarginTop;
  xbStyle.prototype.getMarginRight       = cssStyleGetMarginRight;
  xbStyle.prototype.getMarginBottom      = cssStyleGetMarginBottom;
  xbStyle.prototype.getMarginLeft        = cssStyleGetMarginLeft;
  xbStyle.prototype.getPaddingTop        = cssStyleGetPaddingTop;
  xbStyle.prototype.getPaddingRight      = cssStyleGetPaddingRight;
  xbStyle.prototype.getPaddingBottom     = cssStyleGetPaddingBottom;
  xbStyle.prototype.getPaddingLeft       = cssStyleGetPaddingLeft;
  xbStyle.prototype.getClientTop         = cssStyleGetClientTop;
  xbStyle.prototype.getClientLeft        = cssStyleGetClientLeft;
  xbStyle.prototype.getClientWidth       = cssStyleGetClientWidth;
  xbStyle.prototype.getClientHeight      = cssStyleGetClientHeight;
}
else if (document.layers)
{
  xbStyle.prototype.getClip            = nsxbStyleGetClip;
  xbStyle.prototype.setClip            = nsxbStyleSetClip;  
  xbStyle.prototype.getClipTop         = nsxbStyleGetClipTop;
  xbStyle.prototype.setClipTop         = nsxbStyleSetClipTop;  
  xbStyle.prototype.getClipRight       = nsxbStyleGetClipRight;
  xbStyle.prototype.setClipRight       = nsxbStyleSetClipRight;  
  xbStyle.prototype.getClipBottom      = nsxbStyleGetClipBottom;
  xbStyle.prototype.setClipBottom      = nsxbStyleSetClipBottom;  
  xbStyle.prototype.getClipLeft        = nsxbStyleGetClipLeft;
  xbStyle.prototype.setClipLeft        = nsxbStyleSetClipLeft;  
  xbStyle.prototype.getClipWidth       = nsxbStyleGetClipWidth;
  xbStyle.prototype.setClipWidth       = nsxbStyleSetClipWidth;  
  xbStyle.prototype.getClipHeight      = nsxbStyleGetClipHeight;
  xbStyle.prototype.setClipHeight      = nsxbStyleSetClipHeight;  
  xbStyle.prototype.getLeft            = nsxbStyleGetLeft;
  xbStyle.prototype.setLeft            = nsxbStyleSetLeft;
  xbStyle.prototype.getTop             = nsxbStyleGetTop;
  xbStyle.prototype.setTop             = nsxbStyleSetTop;
  xbStyle.prototype.getPageX           = nsxbStyleGetPageX;
  xbStyle.prototype.setPageX           = nsxbStyleSetPageX;
  xbStyle.prototype.getPageY           = nsxbStyleGetPageY;
  xbStyle.prototype.setPageY           = nsxbStyleSetPageY;
  xbStyle.prototype.getVisibility      = nsxbStyleGetVisibility;
  xbStyle.prototype.setVisibility      = nsxbStyleSetVisibility;
  xbStyle.prototype.getzIndex          = nsxbStyleGetzIndex;
  xbStyle.prototype.setzIndex          = nsxbStyleSetzIndex;            
  xbStyle.prototype.getHeight          = nsxbStyleGetHeight;
  xbStyle.prototype.setHeight          = nsxbStyleSetHeight;
  xbStyle.prototype.getWidth           = nsxbStyleGetWidth;
  xbStyle.prototype.setWidth           = nsxbStyleSetWidth;
  xbStyle.prototype.getBackgroundColor = nsxbStyleGetBackgroundColor;
  xbStyle.prototype.setBackgroundColor = nsxbStyleSetBackgroundColor;
  xbStyle.prototype.getColor           = nsxbStyleGetColor;
  xbStyle.prototype.setColor           = nsxbStyleSetColor;
  xbStyle.prototype.setInnerHTML       = nsxbSetInnerHTML;
  xbStyle.prototype.getBorderTopWidth    = xbStyleNotSupported;
  xbStyle.prototype.getBorderRightWidth  = xbStyleNotSupported;
  xbStyle.prototype.getBorderBottomWidth = xbStyleNotSupported;
  xbStyle.prototype.getBorderLeftWidth   = xbStyleNotSupported;
  xbStyle.prototype.getMarginLeft        = xbStyleNotSupported;
  xbStyle.prototype.getMarginTop         = xbStyleNotSupported;
  xbStyle.prototype.getMarginRight       = xbStyleNotSupported;
  xbStyle.prototype.getMarginBottom      = xbStyleNotSupported;
  xbStyle.prototype.getMarginLeft        = xbStyleNotSupported;
  xbStyle.prototype.getPaddingTop        = xbStyleNotSupported;
  xbStyle.prototype.getPaddingRight      = xbStyleNotSupported;
  xbStyle.prototype.getPaddingBottom     = xbStyleNotSupported;
  xbStyle.prototype.getPaddingLeft       = xbStyleNotSupported;
  xbStyle.prototype.getClientTop         = xbStyleNotSupported;
  xbStyle.prototype.getClientLeft        = xbStyleNotSupported;
  xbStyle.prototype.getClientWidth       = xbStyleNotSupported;
  xbStyle.prototype.getClientHeight      = xbStyleNotSupported;

  window.saveInnerWidth = window.innerWidth;
  window.saveInnerHeight = window.innerHeight;

  window.onresize = nsxbStyleOnresize;

}
else 
{
  xbStyle.prototype.toString           = xbStyleNotSupported;
  xbStyle.prototype.getClip            = xbStyleNotSupported;
  xbStyle.prototype.setClip            = xbStyleNotSupported;
  xbStyle.prototype.getClipTop         = xbStyleNotSupported;
  xbStyle.prototype.setClipTop         = xbStyleNotSupported;
  xbStyle.prototype.getClipRight       = xbStyleNotSupported;
  xbStyle.prototype.setClipRight       = xbStyleNotSupported;
  xbStyle.prototype.getClipBottom      = xbStyleNotSupported;
  xbStyle.prototype.setClipBottom      = xbStyleNotSupported;
  xbStyle.prototype.getClipLeft        = xbStyleNotSupported;
  xbStyle.prototype.setClipLeft        = xbStyleNotSupported;
  xbStyle.prototype.getClipWidth       = xbStyleNotSupported;
  xbStyle.prototype.setClipWidth       = xbStyleNotSupported;
  xbStyle.prototype.getClipHeight      = xbStyleNotSupported;
  xbStyle.prototype.setClipHeight      = xbStyleNotSupported;
  xbStyle.prototype.getLeft            = xbStyleNotSupported;
  xbStyle.prototype.setLeft            = xbStyleNotSupported;
  xbStyle.prototype.getTop             = xbStyleNotSupported;
  xbStyle.prototype.setTop             = xbStyleNotSupported;
  xbStyle.prototype.getVisibility      = xbStyleNotSupported;
  xbStyle.prototype.setVisibility      = xbStyleNotSupported;
  xbStyle.prototype.getzIndex          = xbStyleNotSupported;
  xbStyle.prototype.setzIndex          = xbStyleNotSupported;
  xbStyle.prototype.getHeight          = xbStyleNotSupported;
  xbStyle.prototype.setHeight          = xbStyleNotSupported;
  xbStyle.prototype.getWidth           = xbStyleNotSupported;
  xbStyle.prototype.setWidth           = xbStyleNotSupported;
  xbStyle.prototype.getBackgroundColor = xbStyleNotSupported;
  xbStyle.prototype.setBackgroundColor = xbStyleNotSupported;
  xbStyle.prototype.getColor           = xbStyleNotSupported;
  xbStyle.prototype.setColor           = xbStyleNotSupported;
  xbStyle.prototype.setInnerHTML       = xbStyleNotSupported;
  xbStyle.prototype.getBorderTopWidth    = xbStyleNotSupported;
  xbStyle.prototype.getBorderRightWidth  = xbStyleNotSupported;
  xbStyle.prototype.getBorderBottomWidth = xbStyleNotSupported;
  xbStyle.prototype.getBorderLeftWidth   = xbStyleNotSupported;
  xbStyle.prototype.getMarginLeft        = xbStyleNotSupported;
  xbStyle.prototype.getMarginTop         = xbStyleNotSupported;
  xbStyle.prototype.getMarginRight       = xbStyleNotSupported;
  xbStyle.prototype.getMarginBottom      = xbStyleNotSupported;
  xbStyle.prototype.getMarginLeft        = xbStyleNotSupported;
  xbStyle.prototype.getPaddingTop        = xbStyleNotSupported;
  xbStyle.prototype.getPaddingRight      = xbStyleNotSupported;
  xbStyle.prototype.getPaddingBottom     = xbStyleNotSupported;
  xbStyle.prototype.getPaddingLeft       = xbStyleNotSupported;
  xbStyle.prototype.getClientTop         = xbStyleNotSupported;
  xbStyle.prototype.getClientLeft        = xbStyleNotSupported;
  xbStyle.prototype.getClientWidth       = xbStyleNotSupported;
  xbStyle.prototype.getClientHeight      = xbStyleNotSupported;
}


