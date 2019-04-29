// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2edit.js - main editor declarations
// ---------------------------------------------------------------------------

var s2vars = {};
var s2nav = [];
var codeMirror;

function moveCursor(line, col) {
    codeMirror.focus();
    codeMirror.setCursor({line:line, char:col});
}

$(document).ready( function() {
  s2initDrag();
  s2buildReference();

  CodeMirror.commands.save = function() {
    $("#compilelink").click();
  }

  codeMirror = CodeMirror.fromTextArea(document.querySelector("#main"), {
  mode:  "s2",
  lineWrapping: true,
  lineNumbers: true,
  lineWiseCopyCut: false,
  inputStyle: "contenteditable",
  cursorScrollMargin: 4,
  extraKeys: {"Tab": function(cm) {
    // If we're in text, show the autocomplete, otherwise just insert spaces.
    var cur = cm.getCursor(), token = cm.getTokenAt(cur);
    var m = token.string.match(/([\s]+)/);
    if (!m) { cm.showHint(); }
    else {
        var spaces = Array(cm.getOption("indentUnit") + 1).join(" ");
        cm.replaceSelection(spaces);
    }
}}});

function lineparser(line) {
    // Make a list of variables defined in doc so autocomplete can suggest them 
    var var_re = /var\s+(?:readonly\s+)?([\w_]+)[\[\](){}]*\s+([\w_]+)/g;
    var m;
    while ((m = var_re.exec(line.text)) !== null) {
        s2vars[m[2]] = m[1];
    }

    // Make a list of all propgroups for the nav sidebar
    var propgroup = /propgroup\s+([\w_]+)/i.exec(line.text);
    if (propgroup) {
        s2nav.push({name: propgroup[1], type: "navpropgroup", line: line.lineNo()});
    }

    // Make a list of all module calls for the nav sidebar
    var module = /([A-Za-z0-9_]+::[A-Za-z0-9_]+)/i.exec(line.text);
    if (module) {
        s2nav.push({name: module[1], type: "navmethod", line: line.lineNo()});
    }

    // Make a list of all non-module functions for the navbar
    var func = /function\s+([A-Za-z0-9_]+)/i.exec(line.text);
    if (func) {
        s2nav.push({name: func[1], type: "navfunction", line: line.lineNo()});
    }
}

function buildnav() {
    var i = 0;
    var html = '';
    s2nav.sort(function(a, b){
        if (a.line < b.line) {
            return -1;
        } else if (a.line > b.line) {
            return 1;
        } else {
            return 0;
        }
    });
    
       for (var j = 0; j < s2nav.length; j++) {
            var sym = s2nav[j];
            html += '<div class="';
            html += sym.type;
            html += '"><a href="javascript:moveCursor(' + sym.line;
            html += ',0)">' + sym.name + "</a></div>\n";
        }
   $("#nav").html(html);
   s2nav =[];
}

// Intial build of the variable cache and nav sidebar
codeMirror.eachLine(lineparser);
buildnav();

// Event listeners
$("#compilelink").click(function () {
  codeMirror.save();
	$.post(window.location.href, $( "#s2build" ).serialize(), function(data){
		$("#out").html(data);});
    });

window.setInterval(function() {
    codeMirror.eachLine(lineparser);
    buildnav();
}, 20000)
});

