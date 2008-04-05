/*
xbDebug.js revision: 0.003 2002-02-26

Contributor(s): Bob Clary, Netscape Communications, Copyright 2001

Netscape grants you a royalty free license to use, modify and 
distribute this software provided that this copyright notice 
appears on all copies.  This software is provided "AS IS," 
without a warranty of any kind.

ChangeLog:

2002-02-25: bclary - modified xbDebugTraceOject to make sure 
            that original versions of wrapped functions were not
            rewrapped. This had caused an infinite loop in IE.

2002-02-07: bclary - modified xbDebug.prototype.close to not null
            the debug window reference. This can cause problems with
	    Internet Explorer if the page is refreshed. These issues will
	    be addressed at a later date.
*/

function xbDebug()
{
  this.on = false;
  this.stack = new Array();
  this.debugwindow = null;
  this.execprofile = new Object();
}

xbDebug.prototype.push = function ()
{
  this.stack[this.stack.length] = this.on;
  this.on = true;
}

xbDebug.prototype.pop = function ()
{
  this.on = this.stack[this.stack.length - 1];
  --this.stack.length;
}

xbDebug.prototype.open =  function ()
{
  if (this.debugwindow && !this.debugwindow.closed)
    this.close();
    
  this.debugwindow = window.open('about:blank', 'DEBUGWINDOW', 'height=400,width=600,resizable=yes,scrollbars=yes');

  this.debugwindow.title = 'xbDebug Window';
  this.debugwindow.document.write('<html><head><title>xbDebug Window</title></head><body><h3>Javascript Debug Window</h3></body></html>');
  this.debugwindow.focus();
}

xbDebug.prototype.close = function ()
{
  if (!this.debugwindow)
    return;
    
  if (!this.debugwindow.closed)
    this.debugwindow.close();

  // bc 2002-02-07, other windows may still hold a reference to this: this.debugwindow = null;
}

xbDebug.prototype.dump = function (msg)
{
  if (!this.on)
    return;
    
  if (!this.debugwindow || this.debugwindow.closed)
    this.open();
    
  this.debugwindow.document.write(msg + '<br>');
  
  return;
}

var xbDEBUG = new xbDebug();

window.onunload = function () { xbDEBUG.close(); }

function xbDebugGetFunctionName(funcref)
{

  if (funcref.name)
    return funcref.name;

  var name = funcref + '';
  name = name.substring(name.indexOf(' ') + 1, name.indexOf('('));
  funcref.name = name;

  return name;
}

function xbDebugCreateFunctionWrapper(scopename, funcname, precall, postcall)
{
  var wrappedfunc;
  var scopeobject = eval(scopename);
  var funcref = scopeobject[funcname];

  scopeobject['xbDebug_orig_' + funcname] = funcref;

  wrappedfunc = function () 
  {
    precall(scopename, funcname, arguments);
    var rv = funcref.apply(this, arguments);
    postcall(scopename, funcname, arguments, rv);
    return rv;
  };

  if (typeof(funcref.constructor) != 'undefined')
    wrappedfunc.constructor = funcref.constuctor;

  if (typeof(funcref.prototype) != 'undefined')
    wrappedfunc.prototype = funcref.prototype;

  scopeobject[funcname] = wrappedfunc;
}

function xbDebugPersistToString(obj)
{
  var s = '';
  var p;

  if (obj == null)
     return 'null';

  switch(typeof(obj))
  {
    case 'number':
       return obj;
    case 'string':
       return '"' + obj + '"';
    case 'undefined':
       return 'undefined';
    case 'boolean':
       return obj + '';
  }

  return '[' + xbDebugGetFunctionName(obj.constructor) + ']';
}

function xbDebugTraceBefore(scopename, funcname, funcarguments) 
{
  var i;
  var s = '';
  var execprofile = xbDEBUG.execprofile[scopename + '.' + funcname];
  if (!execprofile)
    execprofile = xbDEBUG.execprofile[scopename + '.' + funcname] = { started: 0, time: 0, count: 0 };

  for (i = 0; i < funcarguments.length; i++)
  {
    s += xbDebugPersistToString(funcarguments[i]);
    if (i < funcarguments.length - 1)
      s += ', ';
  }

  xbDEBUG.dump('enter ' + scopename + '.' + funcname + '(' + s + ')');
  execprofile.started = (new Date()).getTime();
}

function xbDebugTraceAfter(scopename, funcname, funcarguments, rv) 
{
  var i;
  var s = '';
  var execprofile = xbDEBUG.execprofile[scopename + '.' + funcname];
  if (!execprofile)
    xbDEBUG.dump('xbDebugTraceAfter: execprofile not created for ' + scopename + '.' + funcname);
  else if (execprofile.started == 0)
    xbDEBUG.dump('xbDebugTraceAfter: execprofile.started == 0 for ' + scopename + '.' + funcname);
  else 
  {
    execprofile.time += (new Date()).getTime() - execprofile.started;
    execprofile.count++;
    execprofile.started = 0;
  }

  for (i = 0; i < funcarguments.length; i++)
  {
    s += xbDebugPersistToString(funcarguments[i]);
    if (i < funcarguments.length - 1)
      s += ', ';
  }

  xbDEBUG.dump('exit  ' + scopename + '.' + funcname + '(' + s + ')==' + xbDebugPersistToString(rv));
}

function xbDebugTraceFunction(scopename, funcname)
{
  xbDebugCreateFunctionWrapper(scopename, funcname, xbDebugTraceBefore, xbDebugTraceAfter);
}

function xbDebugTraceObject(scopename, objname)
{
  var objref = eval(scopename + '.' + objname);
  var p;

  if (!objref || !objref.prototype)
     return;

  for (p in objref.prototype)
  {
    if (typeof(objref.prototype[p]) == 'function' && (p+'').indexOf('xbDebug_orig') == -1)
    {
      xbDebugCreateFunctionWrapper(scopename + '.' + objname + '.prototype', p + '', xbDebugTraceBefore, xbDebugTraceAfter);
    }
  }
}

function xbDebugDumpProfile()
{
  var p;
  var execprofile;
  var avg;

  for (p in xbDEBUG.execprofile)
  {
    execprofile = xbDEBUG.execprofile[p];
    avg = Math.round ( 100 * execprofile.time/execprofile.count) /100;
    xbDEBUG.dump('Execution profile ' + p + ' called ' + execprofile.count + ' times. Total time=' + execprofile.time + 'ms. Avg Time=' + avg + 'ms.');
  }
}
