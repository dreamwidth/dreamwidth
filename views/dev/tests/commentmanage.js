/* INCLUDE:

old: js/commentmanage.js
jquery: js/jquery/jquery.ui.widget.js
jquery: js/jquery.ajaxtip.js
jquery: js/jquery.commentmanage.js
jquery: js/tooltip.js
jquery: js/jquery/jquery.ui.position.js
*/

var lifecycle = {
    setup: function() {
        var p = {
            "freeze": {
                "mode": "freeze",
                "text": "Freeze",
                "img": "http://localhost/img/silk/comments/freeze.png",
                "url": "http://localhost/talkscreen?mode=freeze&journal=test&talkid=123",
                "msg": "thread was frozen"
            },

            "unfreeze": {
                "mode": "unfreeze",
                "text": "Unfreeze",
                "img": "http://localhost/img/silk/comments/unfreeze.png",
                "url": "http://localhost/talkscreen?mode=unfreeze&journal=test&talkid=123",
                "msg": "thread was unfrozen"
            },

            "screen": {
                "mode": "screen",
                "text": "Screen",
                "img": "http://localhost/img/silk/comments/screen.png",
                "url": "http://localhost/talkscreen?mode=screen&journal=test&talkid=123",
                "msg": "comment was screened"
            },

            "unscreen": {
                "mode": "unscreen",
                "text": "Unscreen",
                "img": "http://localhost/img/silk/comments/unscreen.png",
                "url": "http://localhost/talkscreen?mode=unscreen&journal=test&talkid=123",
                "msg": "comment was unscreened"
            },

            "delete": {
                "mode": "delete",
                "text": "Delete",
                "img": "http://localhost/img/silk/comments/delete.png",
                "url": "http://localhost/delcomment?journal=test&id=123",
                "msg": "comment deleted"
            }
        };
        this.linkprops = p;

        this.del_args = {
                cmtinfo: {
                "form_auth": "authauthauth",
                "remote": "test",
                "journal": "test",

                "canSpam": 1,
                "canAdmin": 1,

                "123": { "parent": "",
                    "u": "test",
                    "rc": [ "456" ],
                    "full": 1
                },
                "456": {
                    "parent": "123",
                    "u": "test",
                    "rc": [],
                    "full": 1
                }
            },
            journal: "test",
            form_auth: "authauthauth"
        };

        this.mod_args = {
            journal: "test",
            form_auth: "authauthauth"
        };

        this.server = sinon.sandbox.useFakeServer();
        this.server.respondWith( /mode=freeze/, [
            200,
            {},
            '{\
                "mode": "freeze",\
                "id": 123,\
                "newalt": "'+p.unfreeze.text+'",\
                "oldimage": "'+p.freeze.img+'",\
                "newimage": "'+p.unfreeze.img+'",\
                "newurl": "'+p.unfreeze.url+'",\
                "msg": "'+p.unfreeze.msg+'"\
            }'
        ] );

        this.server.respondWith( /mode=unfreeze/, [
            200,
            {},
            '{\
                "mode": "unfreeze",\
                "id": 123,\
                "newalt": "'+p.freeze.text+'",\
                "oldimage": "'+p.unfreeze.img+'",\
                "newimage": "'+p.freeze.img+'",\
                "newurl": "'+p.freeze.url+'",\
                "msg": "'+p.freeze.msg+'"\
            }'
        ] );

        this.server.respondWith( /mode=screen/, [
            200,
            {},
            '{\
                "mode": "screen",\
                "id": 123,\
                "newalt": "'+p.unscreen.text+'",\
                "oldimage": "'+p.screen.img+'",\
                "newimage": "'+p.unscreen.img+'",\
                "newurl": "'+p.unscreen.url+'",\
                "msg": "'+p.unscreen.msg+'"\
            }'
        ] );

        this.server.respondWith( /mode=unscreen/, [
            200,
            {},
            '{\
                "mode": "unscreen",\
                "id": 123,\
                "newalt": "'+p.screen.text+'",\
                "oldimage": "'+p.unscreen.img+'",\
                "newimage": "'+p.screen.img+'",\
                "newurl": "'+p.screen.url+'",\
                "msg": "'+p.screen.msg+'"\
            }'
        ] );

        this.server.respondWith( /delforcefail/ [
            200,
            {},
            '{ "error": "fail!" }'
        ] );

        this.server.respondWith( /delcomment/, [
            200,
            {},
            '{ "msg": "'+p["delete"].msg+'" }'
        ] );

        this.server.respondWith( [
            200,
            {},
            '{ "error": "error!" }'
        ] );
    },

    teardown: function() {
        this.server.restore();
    }
};


module( "jquery", lifecycle );
function _check_link(linkid, oldstate, newstate) {
    var $link = $("#"+linkid);

    equal($link.attr("href"), oldstate.url, linkid + " - original url" );
    equal($link.text(), oldstate.text, linkid + " - original text" );

    $link
        .moderate(this.mod_args)
        .one( "moderatecomplete", function( event, data ) {
            equal($link.attr("href"), newstate.url, linkid + " - new url" );
            equal($link.text(), newstate.text, linkid + " - new text" );

            equals($link.ajaxtip("widget").html(), newstate.msg, linkid + " - did action");
        })
        .trigger("click");
    this.server.respond();

    $link
        .one("moderatecomplete", function( event, data ) {
            equal($link.attr("href"), oldstate.url, linkid + " - changed back to old url");
            equal($link.text(), oldstate.text, linkid + " - changed back to old text");

            equals($link.ajaxtip("widget").html(), oldstate.msg, linkid + " - did action");
        })
        .trigger("click");
    this.server.respond();
}

function _check_link_with_image(linkid, oldstate, newstate) {
    var $link = $("#"+linkid);
    var $img = $link.find("img");

    equal($link.attr("href"), oldstate.url, linkid + " - original url" );
    equal($img.attr("alt"), oldstate.text, linkid + " - original alt" );
    equal($img.attr("title"), oldstate.text, linkid + " - original title" );

    $link
        .moderate(this.mod_args)
        .one( "moderatecomplete", function(event, data) {
            equal($link.attr("href"), newstate.url, linkid + " - new url" );
            equal($img.attr("alt"), newstate.text, linkid + " - new alt" );
            equal($img.attr("title"), newstate.text, linkid + " - new title" );

            equals($link.ajaxtip("widget").html(), newstate.msg, linkid + " - did action");
        })
        .trigger("click");
    this.server.respond();

    $link
        .one("moderatecomplete", function(event, data) {
            equal($link.attr("href"), oldstate.url, linkid + " - changed back to old url");
            equal($img.attr("alt"), oldstate.text, linkid + " - changed back to old alt");
            equal($img.attr("title"), oldstate.text, linkid + " - changed back to old title" );

            equals($link.ajaxtip("widget").html(), oldstate.msg, linkid + " - did action");
        })
        .trigger("click");
        this.server.respond();
}

test( "freeze / unfreeze", 38, function() {
    _check_link.call(this, "freeze_link", this.linkprops.freeze, this.linkprops.unfreeze);
    _check_link.call(this, "unfreeze_link", this.linkprops.unfreeze, this.linkprops.freeze);

    _check_link_with_image.call(this, "freeze_img", this.linkprops.freeze, this.linkprops.unfreeze);
    _check_link_with_image.call(this, "unfreeze_img", this.linkprops.unfreeze, this.linkprops.freeze);
} );

test( "screen / unscreen", 38, function() {
    _check_link.call(this, "screen_link", this.linkprops.screen, this.linkprops.unscreen);
    _check_link.call(this, "unscreen_link", this.linkprops.unscreen, this.linkprops.screen);

    _check_link_with_image.call(this, "screen_img", this.linkprops.screen, this.linkprops.unscreen);
    _check_link_with_image.call(this, "unscreen_img", this.linkprops.unscreen, this.linkprops.screen);
} );

test( "delete with shift", 4, function() {
    var parent = $("#cmt123");
    var child = $("#cmt456");
    ok( parent.is(":visible"), "Parent comment started out visible" );
    ok( child.is(":visible"), "Child comment started out visible" );

    $("#delete_link")
        .delcomment(this.del_args)
        .one( "delcommentcomplete", function(event, data) {
            // finish animation early
            parent.stop(true, true);
            child.stop(true, true);

            ok( ! parent.is(":visible"), "Parent comment successfully hidden after delete" );
            ok(   child.is(":visible"), "Child comment not deleted, still visible" );

        })
        .trigger({type: "click", shiftKey: true});
    this.server.respond();
} );

test( "delete all children (has children)", 4, function() {
    var parent = $("#cmt123");
    var child = $("#cmt456");
    ok( parent.is(":visible"), "Parent comment started out visible" );
    ok( child.is(":visible"), "Child comment started out visible" );

    $("#delete_link")
        .delcomment(this.del_args)
        .one( "delcommentcomplete", function(event, data) {
            // finish animation early
            parent.stop(true, true);
            child.stop(true, true);

            ok( ! parent.is(":visible"), "Parent comment successfully hidden after delete" );
            ok( ! child.is(":visible"), "Child comment successfully hidden after delete" );
        })
        .trigger("click")
        .ajaxtip("widget")
            .find("input[value='thread']")
                .attr("checked", "checked")
                .end()
            .find("input[value='Delete']")
                .click()

    this.server.respond();
} );

test( "delete all children (has no children)", 4, function() {
    var parent = $("#cmt123");
    var child = $("#cmt456");
    ok( parent.is(":visible"), "Parent comment started out visible" );
    ok( child.is(":visible"), "Child comment started out visible" );

    $("#child_delete_link")
        .delcomment(this.del_args)
        .one( "delcommentcomplete", function(event, data) {
            // finish animation early
            parent.stop(true, true);
            child.stop(true, true);

            ok(   parent.is(":visible"), "Parent comment not deleted" );
            ok( ! child.is(":visible"), "Child comment successfully hidden after delete" );
        })
        .trigger("click")
        .ajaxtip("widget")
            .find("input[value='thread']")
                .attr("checked", "checked")
                .end()
            .find("input[value='Delete']")
                .click();
    this.server.respond();
} );

test( "delete no children (has children)", 4, function() {
    var parent = $("#cmt123");
    var child = $("#cmt456");
    ok( parent.is(":visible"), "Parent comment started out visible" );
    ok( child.is(":visible"), "Child comment started out visible" );

    $("#delete_link")
        .delcomment(this.del_args)
        .one( "delcommentcomplete", function(event, data) {
            // finish animation early
            parent.stop(true, true);
            child.stop(true, true);

            ok( ! parent.is(":visible"), "Parent comment successfully hidden after delete" );
            ok(   child.is(":visible"), "Child comment not deleted, still visible" );
        })
        .trigger("click")
        .ajaxtip("widget")
            .find("input[value='Delete']")
                .click();

    this.server.respond();
} );

test( "delete no children (has no children)", 4, function() {
    var parent = $("#cmt123");
    var child = $("#cmt456");
    ok( parent.is(":visible"), "Parent comment started out visible" );
    ok( child.is(":visible"), "Child comment started out visible" );

    $("#child_delete_link")
        .delcomment(this.del_args)
        .one( "delcommentcomplete", function(event, data) {
            // finish animation early
            parent.stop(true, true);
            child.stop(true, true);

            ok(   parent.is(":visible"), "Parent comment not deleted, still visible" );
            ok( ! child.is(":visible"), "Child comment successfully hidden after delete" );
        })
        .trigger("click")
        .ajaxtip("widget")
            .find("input[value='Delete']")
                .click();

    this.server.respond();
} );

test( "failed delete: no hiding", 4, function() {
    var parent = $("#cmt123");
    var child = $("#cmt456");
    ok( parent.is(":visible"), "Parent comment started out visible" );
    ok( child.is(":visible"), "Child comment started out visible" );

    this.del_args["endpoint"] = "/delforcefail";

    $("#delete_link")
        .delcomment(this.del_args)
        .one( "delcommentcomplete", function(event, data) {
            // finish animation early
            parent.stop(true, true);
            child.stop(true, true);

            ok( parent.is(":visible"), "Parent comment not deleted, still visible" );
            ok( child.is(":visible"), "Child comment not deleted, still visible" );
        })
        .trigger("click")
        .ajaxtip("widget")
            .find("input[value='Delete']")
                .click();

    this.server.respond();

} );


test( "invalid moderate link", 1, function() {
    $("#invalid_moderate_link")
        .moderate(this.mod_args)
        .trigger("click")
    this.server.respond()

    equals($("#invalid_moderate_link").ajaxtip("widget").text(),
            "Error moderating comment #. Not enough context available.");
});

test( "invalid delete link", 1, function() {
    $("#invalid_delete_link")
        .delcomment(this.del_args)
        .trigger({ type: "click", shiftKey: true })
    this.server.respond();

    equals($("#invalid_delete_link").ajaxtip("widget").text(),
            "Error deleting comment #. Comment is not visible on this page.");
} );


test( "no such comment for moderation", 1, function() {
    $("#mismatched_moderate_link")
        .moderate(this.mod_args)
        .trigger("click")
    this.server.respond();

    equals($("#mismatched_moderate_link").ajaxtip("widget").text(),
            "Error moderating comment #999. Cannot moderate comment which is not visible on this page.")
} );

test( "mismatched journal for deletion", 1, function() {
    $("#mismatched_journal_delete_link")
        .delcomment(this.del_args)
        .trigger({ type: "click", shiftKey: true })
    this.server.respond();

    equals($("#mismatched_journal_delete_link").ajaxtip("widget").text(),
            "Error deleting comment #123. Journal in link does not match expected journal.")
} );

test( "no such comment for moderation", 1, function() {
    $("#mismatched_journal_moderate_link")
        .moderate(this.mod_args)
        .trigger("click")
    this.server.respond();

    equals($("#mismatched_journal_moderate_link").ajaxtip("widget").text(),
            "Error moderating comment #123. Journal in link does not match expected journal.")
} );

test( "no such comment for deletion", 1, function() {
    $("#mismatched_delete_link")
        .delcomment(this.del_args)
        .trigger({ type: "click", shiftKey: true })
    this.server.respond();

    equals($("#mismatched_delete_link").ajaxtip("widget").text(),
            "Error deleting comment #999. Comment is not visible on this page.")
} );

test( "lacking arguments for moderate: form_auth", 1, function() {
    delete this.mod_args["form_auth"]
    $("#freeze_link")
        .moderate(this.mod_args)
        .trigger("click");
    this.server.respond();

    equals($("#freeze_link").ajaxtip("widget").text(),
            "Error moderating comment #123. Not enough context available.")
} );

test( "lacking arguments for moderate: journal", 1, function() {
    delete this.mod_args["journal"]
    $("#freeze_link")
        .moderate(this.mod_args)
        .trigger("click");
    this.server.respond();

    equals($("#freeze_link").ajaxtip("widget").text(),
            "Error moderating comment #123. Not enough context available.")
} );

test( "lacking arguments for delete: cmtinfo", 1, function() {
    delete this.del_args["cmtinfo"]
    $("#delete_link")
        .delcomment(this.del_args)
        .trigger({ type: "click", shiftKey: true })
    this.server.respond();

    equals($("#delete_link").ajaxtip("widget").text(),
            "Error deleting comment #123. Not enough context available.")
} );

test( "lacking arguments for delete: journal", 1, function() {
    delete this.del_args["journal"];
    $("#delete_link")
        .delcomment(this.del_args)
        .trigger({ type: "click", shiftKey: true })
    this.server.respond();

    equals($("#delete_link").ajaxtip("widget").text(),
            "Error deleting comment #123. Not enough context available.")
} );

test( "lacking arguments for delete: form_auth", 1, function() {
    delete this.del_args["form_auth"]
    $("#delete_link")
        .delcomment(this.del_args)
        .trigger({ type: "click", shiftKey: true })
    this.server.respond();

    equals($("#delete_link").ajaxtip("widget").text(),
            "Error deleting comment #123. Not enough context available.")
} );


module( "jquery util" );
test( "extract params", 18, function() {
    var params;

    params = $.extractParams("http://blah.com/");
    deepEqual( params, {}, "no params" );

    params = $.extractParams("http://blah.com/?");
    deepEqual( params, {}, "has ?, but no params" );

    params = $.extractParams("http://blah.com/?noequals&novalue=&key=value&key2=value 2");
    equal( params["key"], "value", "extract url params: key" );
    equal( params["noequals"], undefined, "extract url params: noequals" );
    equal( params["novalue"], "", "extract url params: novalue" );
    equal( params["key2"], "value 2", "extract url params: key2" );

    params = $.extractParams("http://blah.com/?noequals&novalue=&key=value&key2=value%202");
    equal( params["key"], "value", "extract url params URI-escaped: key" );
    equal( params["noequals"], undefined, "extract url params URI-escaped: noequals" );
    equal( params["novalue"], "", "extract url params URI-escaped: novalue" );
    equal( params["key2"], "value 2", "extract url params: key2" );

    params = $.extractParams($("#url_with_params_noescape").attr("href"));
    equal( params["key"], "value", "url from dom: key" );
    equal( params["noequals"], undefined, "url from dom: noequals" );
    equal( params["novalue"], "", "url from dom: novalue" );
    equal( params["key2"], "value 2", "url from dom: key2" );

    params = $.extractParams($("#url_with_params_escaped").attr("href"));
    equal( params["key"], "value", "url from dom, escaped: key" );
    equal( params["noequals"], undefined, "url from dom, escaped: noequals" );
    equal( params["novalue"], "", "url from dom, escaped: novalue" );
    equal( params["key2"], "value 2", "url from dom, escaped: key2" );
});
