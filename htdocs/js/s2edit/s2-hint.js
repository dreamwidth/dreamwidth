// CodeMirror, copyright (c) by Marijn Haverbeke and others
// Distributed under an MIT license: https://codemirror.net/LICENSE

(function(mod) {
  if (typeof exports == "object" && typeof module == "object") // CommonJS
    mod(require("../../lib/codemirror"));
  else if (typeof define == "function" && define.amd) // AMD
    define(["../../lib/codemirror"], mod);
  else // Plain browser env
    mod(CodeMirror);
})(function(CodeMirror) {
  var Pos = CodeMirror.Pos;

// Helper functions borrowed from the javascript-hint addon.
  function forEach(arr, f) {
    for (var i = 0, e = arr.length; i < e; ++i) f(arr[i]);
  }

  function arrayContains(arr, item) {
    if (!Array.prototype.indexOf) {
      var i = arr.length;
      while (i--) {
        if (arr[i] === item) {
          return true;
        }
      }
      return false;
    }
    return arr.indexOf(item) != -1;
  }

  function scriptHint(editor, keywords, getToken, options) {
    // Find the token at the cursor
    var cur = editor.getCursor(), token = getToken(editor, cur);
    var found = [], start = token.string;

    // some helpers that need access to the same editor/cursor instance to function
    function maybeAdd(str) {
      if (str.lastIndexOf(start, 0) == 0 && !arrayContains(found, str)) found.push(str);
    }

    function prevToken(start) { return editor.getTokenAt({line:cur.line, ch: start-1});}

    function classOperator(token) {
        // for operators that act on classes, we want to know the class of the
        // object it's acting on, so we can fetch the right autocomplete list
        var prev_token = prevToken(token.start);

        // autocomplete list returned depends on the operator type
        if (token.string == "->") {
          // Class function operator
          return methodsByClass[s2vars[prev_token.string]];
        } else if(token.string == ".") {
          // Class property operator
          return propsByClass[s2vars[prev_token.string]];
        } else if(token.string == "::") {
          // Class method operator
          return methodsByClass[prev_token.string];
        }
    }

    // The brains: show different autocomplete lists depending on the current token.
    if (token.type == "def") {
        // Find out if this is a class-specific def
        var prev_token = prevToken();
        if (prev_token.type == "operator" && (token.string == "->" || token.string == "." || token.string == "::")){
          // if so, return the autocomplete based on class
          var list = classOperator(prev_token);
          forEach(list, maybeAdd);
        } else {
          // otherwise it may be a class or standard method?
          var classlist = Object.keys(methodsByClass);
          forEach(s2Methods.concat(classlist), maybeAdd);
        }

      } else if(/variable/.test(token.type)) {
        // If we're adding a variable, use the variable autocomplete list.
        var s2varlist = Object.keys(s2vars);
        forEach(s2varlist, maybeAdd);

      } else if (token.type == "operator"){
        if (token.string == "->" || token.string == "." || token.string == "::") {
          var list = classOperator(token);
          // for all of these, we need to empty to token, so we don't try to match
          // the operator, and move it's start, so when the new text is inserted
          // it doesn't overwrite the operator.
          token.start = token.end;
          token.string = "";
          found = list || [];
        }
    
      } else if (token.type == null) {
        // Slightly messy, because null tokens aren't grouped,
        // they're just the character before the cursor. So we
        // need to examine the whole line up to that token for context.
        var linetext = editor.getLine(cur.line).slice(0, token.end + 1);
        
        //split on whitespace, and then the last block is the one closest to the cursor
        var blocks = linetext.split(" ") || [linetext];
        token.string = blocks[blocks.length - 1];
        token.start = token.end - blocks[blocks.length - 1].length;

        start = token.string;
        forEach(keywords.concat(s2Methods), maybeAdd);
    } else {
      // we got nothin'
      found = [];
    }

    return {list: found,
            from: Pos(cur.line, token.start),
            to: Pos(cur.line, token.end)};
  }

  function s2Hint(editor, options) {
    return scriptHint(editor, s2Keywords,
                      function (e, cur) {return e.getTokenAt(cur);},
                      options);
  };
  CodeMirror.registerHelper("hint", "s2", s2Hint);

// Helper methods for computing lists from s2library.js and assigning them to variables.

  function getMethodsByClass() {
    var hints = {};
    for (i=0; i<s2classlib.length; i++) {

        let el = s2classlib[i];
        hints[el.name] = [];

        for(k=0; k<el.methods.length; k++) {
            let meth = el.methods[k];
            hints[el.name].push(meth.name);
        }
    }
    return hints;
  }

  function getPropsByClass() {
    var hints = {};
    for (i=0; i<s2classlib.length; i++) {

        let el = s2classlib[i];
        hints[el.name] = [];
        for(j=0;j<el.members.length; j++) {
            let mem = el.members[j];
            hints[el.name].push(mem.name);
        }
      }
      return hints;
  }

  function getProps() {
    var hints = [];
    for (i=0; i<s2proplib.length; i++) {
        let el = s2proplib[i];
        hints.push(el.name); 
      }
      return hints;
  }

  function getMethods() {
    var hints = [];
    for (i=0; i<s2funclib.length; i++) {
        let el = s2funclib[i];
        hints.push(el.name); 
      }
      return hints;
  }

  var propsByClass = getPropsByClass();
  var methodsByClass = getMethodsByClass();
  var s2Props = getProps();
  var s2Methods = getMethods();

  // Keyword are from  dw-free/src/s2/S2/TokenKeyword.pm
  var s2Keywords = ("class else elseif function if builtin property propgroup set static var while foreach while for print println not and or xor " + 
                    "layerinfo extends return delete defined new true false reverse size isnull null readonly instanceof as isa break continue push pop").split(" ");

});
