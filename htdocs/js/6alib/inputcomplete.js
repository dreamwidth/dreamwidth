/* input completion library */

/* TODO:
    -- test on non-US keyboard layouts (too much use of KeyCode)
    -- lazy data model (xmlhttprequest, or generic callbacks)
    -- drop-down menu?
    -- option to disable comma-separated mode (or explicitly ask for it)
*/

/*
  Copyright (c) 2005, Six Apart, Ltd.
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met:

  * Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the following disclaimer
  in the documentation and/or other materials provided with the
  distribution.

  * Neither the name of "Six Apart" nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/


/* ***************************************************************************

  Class: InputCompleteData

  About: An InputComplete object needs a data source to auto-complete
          from.  This is that model.  You can create one from an
          array, or create a lazy version that gets its data over the
          network, on demand.  You will probably not use this class'
          methods directly, as they're called by the InputComplete
          object.

          The closer a word is to the beginning of the array, the more
          likely it will be recommended as the word the user is typing.

          If you pass the string "ignorecase" as the second argument in
          the constructor, then the case of both the user's input and
          the data in the array will be ignored when looking for a match.

  Constructor:

    var model = new InputCompleteData ([ "foo", "bar", "alpha" ]);

*************************************************************************** */

var InputCompleteData = new Class ( Object, {
    init: function () {
        if (arguments[0] instanceof Array) {
            this.source = [];

            // copy the user-provided array (which is sorted most
            // likely to least likely) into our internal form, which
            // is opposite, with most likely at the end.
            var arg = arguments[0];
            for (var i=arg.length-1; i>=0; i--) {
                this.source.length++;
                this.source[this.source.length-1] = arg[i];
            }
        }

        this.ignoreCase = 0;
        if (arguments[1] == "ignorecase") {
            this.ignoreCase = 1;
        }
    },

    // method: given prefix, returns best suffix, or null if no answer
    bestFinish: function (pre) {
        if (! pre || pre.length == 0)
            return null;

        if (! this.source)
            return null;

        var i;
        for (i=this.source.length-1; i>=0; i--) {
            var item = this.source[i];

            var itemToCompare = item;
            var preToCompare = pre;
            if (this.ignoreCase) {
                item += '';
                pre += '';
                itemToCompare = item.toLowerCase();
                preToCompare = pre.toLowerCase();
            }

            if (itemToCompare.substring(0, pre.length) == preToCompare) {
                var suff = item.substring(pre.length, item.length);
                return suff;
            }
        }

        return null;
    },

    // method: given a piece of data, learn it, and prioritize it for future completions
    learn: function (word) {
        if (!word) return false;
        if (!this.source) return false;
        this.source[this.source.length++] = word;

        if (this.onModelChange)
            this.onModelChange();
    },

    getItems: function () {
        if (!this.source) return [];

        // return only unique items to caller
        var uniq = [];
        var seen = {};
        for (i=this.source.length-1; i>=0; i--) {
            var item = this.source[i];
            if (! seen[item]) {
                seen[item] = 1;
                uniq.length++;
                uniq[uniq.length - 1] = item;
            }
        }

        return uniq;
    },

    dummy: 1
});

/* ***************************************************************************

  Class: InputComplete

  About:

  Constructor:

*************************************************************************** */

var InputComplete = new Class( Object, {
    init: function () {
        var opts = arguments[0];
        var ele;
        var model;
        var debug;

        if (arguments.length == 1) {
            ele = opts["target"];
            model = opts["model"];
            debug = opts["debug"];
        } else {
            ele = arguments[0];
            model = arguments[1];
            debug = arguments[2];
        }

        this.ele   = ele;
        this.model = model;
        this.debug = debug;

        // no model?  don't setup object.
        if (! ele) {
            this.disabled = true;
            return;
        }

        // return false if auto-complete won't work anyway
        if (! (("selectionStart" in ele) || (document.selection && document.selection.createRange)) ) {
            this.disabled = true;
            return false;
        }

        DOM.addEventListener(ele, "focus",   InputComplete.onFocus.bindEventListener(this));
        DOM.addEventListener(ele, "keydown", InputComplete.onKeyDown.bindEventListener(this));
        DOM.addEventListener(ele, "keyup",   InputComplete.onKeyUp.bindEventListener(this));
        DOM.addEventListener(ele, "blur",    InputComplete.onBlur.bindEventListener(this));
    },

    dbg: function (msg) {
        if (this.debug) {
            this.debug(msg);
        }
    },

    // returns the word currently being typed, or null
    wordInProgress: function () {
        var sel = this.getSelectedRange();
        if (!sel) return null;

        var cidx = sel.selectionStart; // current indx
        var sidx = cidx;  // start of word index
        while (sidx > 0 && this.ele.value.charAt(sidx) != ',') {
            sidx--;
        }
        var skipStartForward = function (chr) { return (chr == "," || chr == " "); }

        while (skipStartForward(this.ele.value.charAt(sidx))) {
            sidx++;
        }

        return this.ele.value.substring(sidx, this.ele.value.length);
    },

    // appends some selected text after the care
    addSelectedText: function (chars) {
        var sel = this.getSelectedRange();
        this.ele.value = this.ele.value + chars;
        this.setSelectedRange(sel.selectionStart, this.ele.value.length);
    },

    moveCaretToEnd: function () {
        var len = this.ele.value.length;
        this.setSelectedRange(len, len);
    },

    getSelectedRange: function () {
        var ret = {};
        var ele = this.ele;

        if ("selectionStart" in ele) {
            ret.selectionStart = ele.selectionStart;
            ret.selectionEnd   = ele.selectionEnd;
            return ret;
        }

        if (document.selection && document.selection.createRange) {
            var range = document.selection.createRange();
            ret.selectionStart = InputComplete.IEOffset(range, "StartToStart");
            ret.selectionEnd   = InputComplete.IEOffset(range, "EndToEnd");
            return ret;
        }

        return null;
    },

    setSelectedRange: function (sidx, eidx) {
        var ele = this.ele;

        // preferred to setting selectionStart and end
        if (ele.setSelectionRange) {
            ele.focus();
            ele.setSelectionRange(sidx, eidx);
            return true;
        }

        // IE
        if (document.selection && document.selection.createRange) {
            ele.focus();
            var sel = document.selection.createRange ();
            sel.moveStart('character', -ele.value.length);
            sel.moveStart('character', sidx);
            sel.moveEnd('character', eidx - sidx);
            sel.select();
            return true;
        }

        // mozilla
        if ("selectionStart" in ele) {
            ele.selectionStart = sidx;
            ele.selectionEnd   = eidx;
            return true;
        }

        return false;
    },

    // returns true if caret is at end of line, or everything to the right
    // of us is selected
    caretAtEndOfNotSelected: function (sel) {
        sel = sel || this.getSelectedRange();
        var len = this.ele.value.length;
        return sel.selectionEnd == len;
    },

    disable: function () {
        this.disabled = true;
    },

    dummy: 1
});

InputComplete.onKeyDown = function (e) {
    if (this.disabled) return;

    var code = e.keyCode || e.which;

    this.dbg("onKeyDown, code="+code+", shift="+e.shiftKey);
    
    // if comma, but not with a shift which would be "<".  (FIXME: what about other keyboards layouts?)
    //FIXME: may be there is a stable cross-browser way to detect so-called other keyboard layouts - but i don't know anything easier than ... (see onKeyUp changes in tis revision)
    /*if ((code == 188 || code == 44) && ! e.shiftKey && this.caretAtEndOfNotSelected()) {
        this.moveCaretToEnd();
        return Event.stop(e);
    }*/

    return true;
};

InputComplete.onKeyUp = function (e) {
    if (this.disabled) return;

    var val = this.ele.value;

    var code = e.keyCode || e.which;
    this.dbg("keyUp = " + code);
    
    
    // ignore tab, backspace, left, right, delete, and enter
    if (code == 9 || code == 8 || code == 37 || code == 39 || code == 46 || code == 13)
       return false;

    var sel = this.getSelectedRange();

    var ss = sel.selectionStart;
    var se = sel.selectionEnd;

    this.dbg("keyUp, got ss="+ss +  ", se="+se+", val.length="+val.length);

    // only auto-complete if we're at the end of the line
    if (se != val.length) return false;

    var chr = String.fromCharCode(code);

    this.dbg("keyUp, got chr="+chr);
    //if (code == 188 || chr == ",") {
    if(/,$/.test(val)){	
        if (! this.caretAtEndOfNotSelected(sel)) {
            return false;
        }

        this.dbg("hit comma! .. value = " + this.ele.value);

        this.ele.value = this.ele.value.replace(/[\s,]+$/, "") + ", ";
        this.moveCaretToEnd();

        return Event.stop(e);
    }


    var inProg = this.wordInProgress();
    if (!inProg) return true;

    var rest = this.model.bestFinish(inProg);

    if (rest && rest.length > 0) {
        this.addSelectedText(rest);
    }
};

InputComplete.onBlur = function (e) {
    if (this.disabled) return;

    var tg = e.target;
    var list = tg.value;

    var noendjunk = list.replace(/[\s,]+$/, "");
    if (noendjunk != list) {
        tg.value = list = noendjunk;
    }

    var tags = list.split(",");
    for (var i =0; i<tags.length; i++) {
        var tag = tags[i].replace(/^\s+/,"").replace(/\s+$/,"");
        if (tag.length) {
            this.model.learn(tag);
        }
    }
};

InputComplete.onFocus = function (e) {
    if (this.disabled) return;
};


InputComplete.IEOffset = function ( range, compareType ) {
    if (this.disabled) return;

    var range2 = range.duplicate();
    range2.collapse( true );
    var parent = range2.parentElement();
    var length = range2.text.length;
    range2.move("character", -parent.value.length);

    var delta = max( 1, finiteInt( length * 0.5 ) );
    range2.collapse( true );
    var offset = 0;
    var steps = 0;

    // bail after 10k iterations in case of borkage
    while( (test = range2.compareEndPoints( compareType, range )) != 0 ) {
        if( test < 0 ) {
            range2.move( "character", delta );
            offset += delta;
        } else {
            range2.move( "character", -delta );
            offset -= delta;
        }
        delta = max( 1, finiteInt( delta * 0.5 ) );
        steps++;
        if( steps > 1000 )
            throw "unable to find textrange endpoint in " + steps + " steps";
    }

    return offset;
};
