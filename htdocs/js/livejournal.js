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
    LiveJournal.initPlaceholders();
    LiveJournal.initLabels();
    LiveJournal.initInboxUpdate();
    LiveJournal.initAds();
    LiveJournal.initPolls();

    // run other hooks
    LiveJournal.run_hook("page_load");
};

// Set up two different ways to test if the page is loaded yet.
// The proper way is using DOMContentLoaded, but only Mozilla supports it.
{
    // Others
    DOM.addEventListener(window, "load", LiveJournal.initPage);

    // Mozilla
    DOM.addEventListener(window, "DOMContentLoaded", LiveJournal.initPage);
}

// Set up a timer to keep the inbox count updated
LiveJournal.initInboxUpdate = function () {
    // Don't run if not logged in or this is disabled
    if (! Site || ! Site.has_remote || ! Site.inbox_update_poll) return;

    // Don't run if no inbox count
    var unread = $("LJ_Inbox_Unread_Count");
    if (! unread) return;

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

    var unread = $("LJ_Inbox_Unread_Count");
    if (! unread) return;

    unread.innerHTML = resp.unread_count ? "  (" + resp.unread_count + ")" : "";
};

// Search for placeholders and initialize them
LiveJournal.initPlaceholders = function () {
    var placeholders = DOM.getElementsByTagAndClassName(document, "img", "LJ_Placeholder") || [];

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

// change drsc to src for ads
LiveJournal.initAds = function () {
    AdEngine.init();
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

LiveJournal.initPolls = function () {
    var pollLinks = DOM.getElementsByTagAndClassName(document, 'a', "LJ_PollAnswerLink") || [];  

    // attach click handlers to each answer link
    Array.prototype.forEach.call(pollLinks, function (pollLink) {
        DOM.addEventListener(pollLink, "click", LiveJournal.pollAnswerLinkClicked.bindEventListener(pollLink));
    });
};

// invocant is the pollLink from above
LiveJournal.pollAnswerLinkClicked = function (e) {
    Event.stop(e);

    if (! this || ! this.tagName || this.tagName.toLowerCase() != "a")
    return true;

    var pollid = this.getAttribute("lj_pollid");
    if (! pollid) return true;

    var pollqid = this.getAttribute("lj_qid");
    if (! pollqid) return true;

    var action = "get_answers";

    // Do ajax request to replace the link with the answers
    var params = {
        "pollid" : pollid,
        "pollqid": pollqid,
        "action" : action
    };

    var opts = {
        "url"    : LiveJournal.getAjaxUrl("poll"),
        "method" : "POST",
        "data"   : HTTPReq.formEncoded(params),
        "onData" : LiveJournal.pollAnswersReceived,
        "onError": LiveJournal.ajaxError
    };

    HTTPReq.getJSON(opts);
    this.innerHTML = "<div class='lj_pollanswer_loading'>Loading...</div>";

    return false;
};

LiveJournal.pollAnswersReceived = function (answers) {
    if (! answers) return false;
    if (answers.error) return LiveJournal.ajaxError(answers.error);

    var pollid = answers.pollid;
    var pollqid = answers.pollqid;
    if (! pollid || ! pollqid) return false;

    var linkEle = $("LJ_PollAnswerLink_" + pollid + "_" + pollqid);
    if (! linkEle) return false;

    var answerEle = document.createElement("div");
    DOM.addClassName(answerEle, "lj_pollanswer");
    answerEle.innerHTML = answers.answer_html ? answers.answer_html : "(No answers)";

    linkEle.parentNode.insertBefore(answerEle, linkEle);
    linkEle.parentNode.removeChild(linkEle);
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

LiveJournal.insertAdsMulti = function (params) {
  var i = 0;
  var containers = [];

  for (i = 0; i < params.length; i++) {
    if (! params[i].html || params[i].html == "<ul>\n</ul>") continue;
    AdEngine.insertAdResponse( params[i] );
    containers.push(document.getElementById(params[i].id));
  }

    // add the ad box style to the containers
    containers.forEach(function (container) {
      if (! container) return;

      DOM.addClassName(container.parentNode, "lj_content_ad");
      DOM.removeClassName(container.parentNode, "lj_inactive_ad");
    });
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
