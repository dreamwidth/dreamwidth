// This file contains general-purpose LJ code

var LiveJournal = new Object;

// The hook mappings
LiveJournal.hooks = {};

LiveJournal.register_hook = function (hook, func) {
    if (! LiveJournal.hooks[hook])
        LiveJournal.hooks[hook] = [];

    LiveJournal.hooks[hook].push(func);
};

// args: hook, params to pass to hook
LiveJournal.run_hook = function () {
    var a = arguments;

    var hookfuncs = LiveJournal.hooks[a[0]];
    if (!hookfuncs || !hookfuncs.length) return;

    var hookargs = [];

    for (var i = 1; i < a.length; i++) {
        hookargs.push(a[i]);
    }

    var rv = null;

    hookfuncs.forEach(function (hookfunc) {
        rv = hookfunc.apply(null, hookargs);
    });

    return rv;
};

LiveJournal.pageLoaded = false;

LiveJournal.initPage = function () {
    // only run once
    if (LiveJournal.pageLoaded)
        return;
    LiveJournal.pageLoaded = 1;

    // set up various handlers for every page
    LiveJournal.initPagePlaceholders();
    LiveJournal.initLabels();
    LiveJournal.initInboxUpdate();
    LiveJournal.initPolls();

    // run other hooks
    LiveJournal.run_hook("page_load");
};

// Do setup once the page is ready
DOM.addEventListener(window, "DOMContentLoaded", LiveJournal.initPage);

// Set up a timer to keep the inbox count updated
LiveJournal.initInboxUpdate = function () {
    // Don't run if not logged in or this is disabled
    if (! Site || ! Site.has_remote || ! Site.inbox_update_poll) return;

    // Don't run if no inbox count
    var unread = $("Inbox_Unread_Count");
    var unread_menu = $("Inbox_Unread_Count_Menu");
    if (! unread && ! unread_menu) return;

    // Update every five minutes
    window.setInterval(LiveJournal.updateInbox, 1000 * 60 * 5);
};

// Do AJAX request to find the number of unread items in the inbox
LiveJournal.updateInbox = function () {
    var postData = {
        "action": "get_unread_items"
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "onData": LiveJournal.gotInboxUpdate
    };

    opts.url = Site.currentJournal ? "/" + Site.currentJournal + "/__rpc_esn_inbox" : "/__rpc_esn_inbox";

    HTTPReq.getJSON(opts);
};

// We received the number of unread inbox items from the server
LiveJournal.gotInboxUpdate = function (resp) {
    if (! resp || resp.error) return;

    var unread = $("Inbox_Unread_Count");
    var unread_menu = $("Inbox_Unread_Count_Menu");
    if (! unread && ! unread_menu) return;

    var unread_count = resp.unread_count? " (" + resp.unread_count + ")" : "";
    if ( unread )
        unread.innerHTML = unread_count;
    if ( unread_menu )
        unread_menu.innerHTML = unread_count;
};

// Search for placeholders and initialize them
LiveJournal.initPagePlaceholders = function () {
    LiveJournal.initPlaceholders(document);
}

LiveJournal.initPlaceholders = function (srcElement) {
    var placeholders = DOM.getElementsByTagAndClassName(srcElement, "img", "LJ_Placeholder") || [];

    Array.prototype.forEach.call(placeholders, function (placeholder) {
        var parent = DOM.getFirstAncestorByClassName(placeholder, "LJ_Placeholder_Container", false);
        if (!parent) return;

        var container = DOM.filterElementsByClassName(parent.getElementsByTagName("div"), "LJ_Container")[0];
        if (!container) return;

        var html = DOM.filterElementsByClassName(parent.getElementsByTagName("div"), "LJ_Placeholder_HTML")[0];
        if (!html) return;

        var placeholder_html = unescape(html.innerHTML);

        var placeholderClickHandler = function (e) {
            Event.stop(e);
            // have to wrap placeholder_html in another block, IE is weird
            container.innerHTML = "<span>" + placeholder_html + "</span>";
            DOM.makeInvisible(placeholder);
        };

        DOM.addEventListener(placeholder, "click", placeholderClickHandler);

        return false;
    });
};

// set up labels for Safari
LiveJournal.initLabels = function () {
    // disabled because new webkit has labels that work
    return;

    // safari doesn't know what <label> tags are, lets fix them
    if (navigator.userAgent.indexOf('Safari') == -1) return;

    // get all labels
    var labels = document.getElementsByTagName("label");

    for (var i = 0; i < labels.length; i++) {
        DOM.addEventListener(labels[i], "click", LiveJournal.labelClickHandler);
    }
};

LiveJournal.labelClickHandler = function (evt) {
    Event.prep(evt);

    var label = DOM.getAncestorsByTagName(evt.target, "label", true)[0];
    if (! label) return;

    var targetId = label.getAttribute("for");
    if (! targetId) return;

    var target = $(targetId);
    if (! target) return;

    target.click();

    return false;
};

// handy utilities to create elements with just text in them
function _textSpan () { return _textElements("span", arguments); }
function _textDiv  () { return _textElements("div", arguments);  }

function _textElements (eleType, txts) {
    var ele = [];
    for (var i = 0; i < txts.length; i++) {
        var node = document.createElement(eleType);
        node.innerHTML = txts[i];
        ele.push(node);
    }

    return ele.length == 1 ? ele[0] : ele;
};

var PollPages = {
    "hourglass": null
};

LiveJournal.initPolls = function (element) {
    var ele = element || document;
    var pollLinks = DOM.getElementsByTagAndClassName(ele, 'a', "LJ_PollAnswerLink") || [];

    // attach click handlers to each answer link
    Array.prototype.forEach.call(pollLinks, function (pollLink) {
        DOM.addEventListener(pollLink, "click", LiveJournal.pollAnswerLinkClicked.bindEventListener(pollLink));
    });

    var pollClears = DOM.getElementsByTagAndClassName(ele, 'a', "LJ_PollClearLink") || [];

    // attach click handlers to each clear link
    Array.prototype.forEach.call(pollClears, function (pollClear) {
        DOM.addEventListener(pollClear, "click", LiveJournal.pollClearLinkClicked.bindEventListener(pollClear));
    });

    var pollButtons = DOM.getElementsByTagAndClassName(ele, 'input', "LJ_PollSubmit") || []; 
    
    // attaches a click handler to all poll submit buttons
    Array.prototype.forEach.call(pollButtons, function (pollButton) {
        DOM.addEventListener(pollButton, "click", LiveJournal.pollButtonClicked.bindEventListener(pollButton));
    });

    var pollChange = DOM.getElementsByTagAndClassName(ele, 'a', "LJ_PollChangeLink") || [];

    // attaches a click handler to all poll change answers buttons
    Array.prototype.forEach.call(pollChange, function (pollChange) {
        DOM.addEventListener(pollChange, "click", LiveJournal.pollChangeClicked.bindEventListener(pollChange));
    });

    var pollDisplay = DOM.getElementsByTagAndClassName(ele, 'a', "LJ_PollDisplayLink") || [];

    // attaches a click handler to all poll display answers buttons
    Array.prototype.forEach.call(pollDisplay, function (pollDisplay) {
        DOM.addEventListener(pollDisplay, "click", LiveJournal.pollDisplayClicked.bindEventListener(pollDisplay));
    });

    var pollForms = DOM.getElementsByTagAndClassName(ele, 'form', "LJ_PollForm") || []; 

    // attach submit handlers to each poll form
    Array.prototype.forEach.call(pollForms, function (pollForm) {
        DOM.addEventListener(pollForm, "submit", LiveJournal.pollFormSubmitted.bindEventListener(pollForm));
    });

    var pollRespondentsLinks = DOM.getElementsByTagAndClassName(document, 'a', "LJ_PollRespondentsLink") || [];

    // attach click handlers to each link to show respondents to a poll
    Array.prototype.forEach.call(pollRespondentsLinks, function (pollRes) {
        DOM.addEventListener(pollRes, "click", LiveJournal.pollRespondentsLinkClicked.bindEventListener(pollRes));
    });

    var pollUserLinks = DOM.getElementsByTagAndClassName(document, 'a', "LJ_PollUserAnswerLink") || [];

    // attach click handlers to each answer link
    Array.prototype.forEach.call(pollUserLinks, function (pollLink) {
        DOM.addEventListener(pollLink, "click", LiveJournal.pollUserAnswerLinkClicked.bindEventListener(pollLink));
    });
};

LiveJournal.pollButtonClicked = function (e) {  
    // shows the hourglass. The submit event wouldn't update the coordinates, so the click event
    // had to be used for this
    if (!PollPages.hourglass) {
        var coords = DOM.getAbsoluteCursorPosition(e);
        PollPages.hourglass = new Hourglass();
        PollPages.hourglass.init();
        PollPages.hourglass.hourglass_at(coords.x, coords.y+25);    // 25 is added to the y axis, otherwise the button would cover it
        PollPages.e = e;
    }
    
    return true;
};

LiveJournal.pollFormSubmitted = function (e) {
    Event.stop(e);
    
    var formObject = LiveJournal.getFormObject(this);  //gets the form ready for serialization

    var opts = {
        "url"    : LiveJournal.getAjaxUrl("pollvote"),
        "method" : "POST",
        "data"   : "action=vote&" + HTTPReq.formEncoded(formObject),
        "onData" : LiveJournal.pollUpdateContainer,
        "onError": LiveJournal.pollUpdateContainer
    };

    HTTPReq.getJSON(opts);
    
    return false;
};

LiveJournal.pollChangeClicked = function (e) {
    Event.stop(e);

    var opts = {
        "url"    : LiveJournal.getAjaxUrl("pollvote"),
        "method" : "POST",
        "data"   : "action=change&pollid=" + this.getAttribute("lj_pollid"),
        "onData" : LiveJournal.pollUpdateContainer,
        "onError": LiveJournal.pollUpdateContainer
    };

    HTTPReq.getJSON(opts);

    return false;
};

LiveJournal.pollDisplayClicked = function (e) {
    Event.stop(e);

    var opts = {
        "url"    : LiveJournal.getAjaxUrl("pollvote"),
        "method" : "POST",
        "data"   : "action=display&pollid=" + this.getAttribute("lj_pollid"),
        "onData" : LiveJournal.pollUpdateContainer,
        "onError": LiveJournal.pollUpdateContainer
    };

    HTTPReq.getJSON(opts);

    return false;
};

LiveJournal.pollUpdateContainer = function (results) {
    if (! results) return false;

    if (PollPages.hourglass) {
        PollPages.hourglass.hide();
        PollPages.hourglass = null;
    }

    if (results.error) return LiveJournal.ajaxError(results.error);

    resultsDiv = document.getElementById("poll-"+results.pollid+"-container");

    resultsDiv.innerHTML = results.results_html;

    LiveJournal.initPolls();
};



LiveJournal.getFormObject = function (form) {

    var inputs = form.getElementsByTagName("input");
    
    var formObject = new Object();
    
    for (var i = 0; i < inputs.length; i++) {
        var obj = inputs[i];
        
        if (obj.type == "checkbox") {
            if (!formObject[obj.name]) {
                formObject[obj.name] = new Array();
            }
            if (obj.checked)
                formObject[obj.name].push(obj.value);
        }
        else if (obj.type == "radio") {
           if (obj.checked) {
              formObject[obj.name] = obj.value;
           }
        }
        else 
        {
            formObject[obj.name] = obj.value;
        }
    }
    
    var selects = form.getElementsByTagName("select");

    for (var i = 0; i < selects.length; i++) {
        var sel = selects[i];
        formObject[sel.name] = sel.options[sel.selectedIndex].value;
    }
    
    return formObject;

};

LiveJournal.pollClearLinkClicked = function (e) {
    Event.stop(e);

    var pollid = this.getAttribute("lj_pollid");
    var inputelements = DOM.getElementsByTagAndClassName(document, 'input', "poll-"+pollid ) || [];
    var inputelement;

    // clear all options of this poll
    for (var i = 0; i < inputelements.length; i++) {
        inputelement = inputelements[i];
        // text fields
        if (inputelement.type == 'text') {
            inputelement.value = "";
        } else {
        // checboxes and radio buttons
            inputelements[i].checked = false;
        }
    }

    var selectelements = DOM.getElementsByTagAndClassName(document, 'select', "poll-"+pollid ) || [];
    // drop-down selects
    for (var i = 0; i < selectelements.length; i++) {
        selectelements[i].selectedIndex = 0;
    }
}

// invocant is the pollLink from above
LiveJournal.pollAnswerLinkClicked = function (e) {
    Event.stop(e);

    if (! this || ! this.tagName || this.tagName.toLowerCase() != "a")
    return true;

    var pollid = this.getAttribute("lj_pollid");
    if (! pollid) return true;

    var pollqid = this.getAttribute("lj_qid");
    if (! pollqid) return true;

    var page     = this.getAttribute("lj_page");
    var pagesize = this.getAttribute("lj_pagesize");

    var action = "get_answers";

    // Do ajax request to replace the link with the answers
    var params = {
        "pollid"   : pollid,
        "pollqid"  : pollqid,
        "page"     : page,
        "pagesize" : pagesize,
        "action"   : action
    };

    var opts = {
        "url"    : LiveJournal.getAjaxUrl("poll"),
        "method" : "POST",
        "data"   : HTTPReq.formEncoded(params),
        "onData" : LiveJournal.pollAnswersReceived,
        "onError": LiveJournal.ajaxError
    };

    HTTPReq.getJSON(opts);

    if (!PollPages.hourglass) {
        var coords = DOM.getAbsoluteCursorPosition(e);
        PollPages.hourglass = new Hourglass();
        PollPages.hourglass.init();
        PollPages.hourglass.hourglass_at(coords.x, coords.y);
        PollPages.e = e;
    }

    return false;
};

LiveJournal.pollAnswersReceived = function (answers) {
    if (! answers) return false;

    if (PollPages.hourglass) {
        PollPages.hourglass.hide();
        PollPages.hourglass = null;
    }

    if (answers.error) return LiveJournal.ajaxError(answers.error);

    var pollid = answers.pollid;
    var pollqid = answers.pollqid;
    if (! pollid || ! pollqid) return false;
    var page     = answers.page;

    var answerPagEle;
    var answerEle;
    if (page) {
        answerPagEle = DOM.getElementsByTagAndClassName(document, 'div', "lj_pollanswer_paging")[0];
        answerEle    = DOM.getElementsByTagAndClassName(document, 'div', "lj_pollanswer")[0];
    } else {
        var linkEle = $("LJ_PollAnswerLink_" + pollid + "_" + pollqid);
        if (! linkEle) return false;

        answerPagEle = document.createElement("div");
        DOM.addClassName(answerPagEle, "lj_pollanswer_paging");

        answerEle = document.createElement("div");
        DOM.addClassName(answerEle, "lj_pollanswer");

        linkEle.parentNode.insertBefore(answerEle,    linkEle);
        linkEle.parentNode.insertBefore(answerPagEle, linkEle);

        linkEle.parentNode.removeChild(linkEle);
    }

    answerPagEle.innerHTML  = answers.paging_html ? answers.paging_html : "";
    answerEle.innerHTML     = answers.answer_html ? answers.answer_html : "(No answers)";

    if (typeof ContextualPopup != "undefined")
        ContextualPopup.setup();

    LiveJournal.initPolls();
};

LiveJournal.pollRespondentsLinkClicked = function (e) {
    Event.stop(e);

    if (! this || ! this.tagName || this.tagName.toLowerCase() != "a")
    return true;

    var pollid = this.getAttribute("lj_pollid");
    if (! pollid) return true;

    var action = "get_respondents";

    answerEle = $("LJ_PollRespondentsLink_" + pollid);
    if (! answerEle) return false;

    var params = {
        "pollid"   : pollid,
        "action"   : action
    };

    var opts = {
        "url"    : LiveJournal.getAjaxUrl("poll"),
        "method" : "POST",
        "data"   : HTTPReq.formEncoded(params),
        "onData" : LiveJournal.pollRespondentsReceived,
        "onError": LiveJournal.ajaxError
    };

    HTTPReq.getJSON(opts);

    if (!PollPages.hourglass) {
        var coords = DOM.getAbsoluteCursorPosition(e);
        PollPages.hourglass = new Hourglass();
        PollPages.hourglass.init();
        PollPages.hourglass.hourglass_at(coords.x, coords.y);
        PollPages.e = e;
    }

    return false;
}

LiveJournal.pollRespondentsReceived = function (answers) {
    if (! answers) return false;

    if (PollPages.hourglass) {
        PollPages.hourglass.hide();
        PollPages.hourglass = null;
    }

    if (answers.error) return LiveJournal.ajaxError(answers.error);

    var pollid = answers.pollid;
    if (! pollid) return false;

    answerEle = $("LJ_PollRespondentsLink_" + pollid);
    if (! answerEle) return false;

    var answer = answers.answer_html ? answers.answer_html : "(No answers)";
    var newAnswerEle = document.createElement("span");
    newAnswerEle.innerHTML = answer;
    answerEle.parentNode.replaceChild(newAnswerEle, answerEle);

    if (typeof ContextualPopup != "undefined")
        ContextualPopup.setup();

    LiveJournal.initPolls();
};


LiveJournal.pollUserAnswerLinkClicked = function (e) {
    Event.stop(e);

    if (! this || ! this.tagName || this.tagName.toLowerCase() != "a")
    return true;

    var pollid = this.getAttribute("lj_pollid");
    if (! pollid) return true;

    var userid = this.getAttribute("lj_userid");
    if (! userid) return true;

    var action = "get_user_answers";

    answerEle = $("LJ_PollUserAnswerLink_" + pollid + "_" + userid);
    if (! answerEle) return false;

    	// Do ajax request to replace the link with the answers
    var params = {
        "pollid"   : pollid,
        "userid"   : userid,
        "action"   : action
    };

    var opts = {
       	"url"    : LiveJournal.getAjaxUrl("poll"),
       	"method" : "POST",
       	"data"   : HTTPReq.formEncoded(params),
       	"onData" : LiveJournal.pollUserAnswersReceived,
       	"onError": LiveJournal.ajaxError
    };

    HTTPReq.getJSON(opts);

    if (!PollPages.hourglass) {
       	var coords = DOM.getAbsoluteCursorPosition(e);
       	PollPages.hourglass = new Hourglass();
       	PollPages.hourglass.init();
       	PollPages.hourglass.hourglass_at(coords.x, coords.y);
       	PollPages.e = e;
    }
    return false;
};

LiveJournal.pollUserAnswersReceived = function (answers) {
    if (! answers) return false;

    if (PollPages.hourglass) {
        PollPages.hourglass.hide();
        PollPages.hourglass = null;
    }

    if (answers.error) return LiveJournal.ajaxError(answers.error);

    var pollid = answers.pollid;
    var userid = answers.userid;
    if (! pollid || ! userid) return false;

    var linkEle = $("LJ_PollUserAnswerLink_" + pollid + "_" + userid);
    if (! linkEle) return false;

    answerEle = $("LJ_PollUserAnswerRes_" + pollid + "_" + userid);
    if (! answerEle) return false;

    answerEle.innerHTML = answers.answer_html ? answers.answer_html : "(No answers)";
	linkEle.innerHTML = "";
	answerEle.style.display = "block";
	
    if (typeof ContextualPopup != "undefined")
        ContextualPopup.setup();
};

// gets a url for doing ajax requests
LiveJournal.getAjaxUrl = function (action) {
    // if we are on a journal subdomain then our url will be
    // /journalname/__rpc_action instead of /__rpc_action
    return Site.currentJournal
        ? "/" + Site.currentJournal + "/__rpc_" + action
        : "/__rpc_" + action;
};

// generic handler for ajax errors
LiveJournal.ajaxError = function (err) {
    if (LJ_IPPU) {
        LJ_IPPU.showNote("Error: " + err);
    } else {
        alert("Error: " + err);
    }
};

// utility method to get all items on the page with a certain class name
LiveJournal.getDocumentElementsByClassName = function (className) {
  var domObjects = document.getElementsByTagName("*");
  var items = DOM.filterElementsByClassName(domObjects, className) || [];

  return items;
};

// utility method to add an onclick callback on all items with a classname
LiveJournal.addClickHandlerToElementsWithClassName = function (callback, className) {
  var items = LiveJournal.getDocumentElementsByClassName(className);

  items.forEach(function (item) {
    DOM.addEventListener(item, "click", callback);
  })
};

// given a URL, parse out the GET args and return them in a hash
LiveJournal.parseGetArgs = function (url) {
    var getArgsHash = {};

    var urlParts = url.split("?");
    if (!urlParts[1]) return getArgsHash;
    var getArgs = urlParts[1].split("&");
    for (var arg in getArgs) {
        if (!getArgs.hasOwnProperty(arg)) continue;
        var pair = getArgs[arg].split("=");
        getArgsHash[pair[0]] = pair[1];
    }

    return getArgsHash;
};
