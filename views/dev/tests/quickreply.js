/* INCLUDE:
jquery: js/jquery/jquery.ui.widget.js
jquery: js/jquery.quickreply.js
*/

var lifecycle = {
    setup: function() {
        this.links = {
            replyto_entry_top: {
                pid     : 0,
                replyto : 0,
                dtid    : "topcomment",
                subject : ""
            },
            replyto_entry_bottom: {
                pid     : 0,
                replyto : 0,
                dtid    : "bottomcomment",
                subject : ""
            },
            existing_comment: {
                pid     : 1,
                replyto : 1,
                dtid    : 1,
                subject : ""                
            },
            child_of_existing_comment: {
                pid     : 2,
                replyto : 2,
                dtid    : 2,
                subject : ""                
            },
            hassubject : {
                pid     : 3,
                replyto : 3,
                dtid    : 3,
                subject : "Re: has subject"
            }
        }

        if ( QUnit.config.current.module == "old" ) {
            this.has_qr = function(selector) {
                var prev_sibling = $("qrdiv").previousElementSibling || $("qrdiv").previousSibling;
                if ( prev_sibling )
                    return prev_sibling.id == selector;

                return false;
            };
            this.check_values = function(values) {
                for( var element_id in values ) {
                    equals( $(element_id).value, values[element_id][0], values[element_id][1] );
                }
            }
        } else if ( QUnit.config.current.module == "jquery" ) {
            this.has_qr = function(selector) {
                return $("#ljqrt"+this.links[selector].dtid).find("#qrdiv").length > 0;
            };
            this.get_qr_container = function(selector) {
                return $("#ljqrt"+this.links[selector].dtid);
            };
            this.check_values = function(values) {
                for( var element_id in values ) {
                    equals( $("#"+element_id).val(), values[element_id][0], values[element_id][1] );
                }
            }
        }
    }
}

module( "jquery", lifecycle );
test( "quickreply to entry", 25, function() {
    ok( ! this.has_qr("replyto_entry_top"), "no qrdiv here yet" );
    ok( ! this.get_qr_container("replyto_entry_top").is(":visible"), "qr container starts out invisible");
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["", "Empty body"],
        parenttalkid: ["0", "No parent"],
        dtid    : ["", "No dtid"],
        replyto : ["0", "No replyto"]
    });

    $("#replyto_entry_top").click();
    ok(   this.has_qr("replyto_entry_top"), "qrdiv shows up when clicking link to reply to entry (top)" );
    ok(   this.get_qr_container("replyto_entry_top").is(":visible"), "qr container becomes visible when we add qr to it");
    $("#body").val("foo");
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["foo", "Contains body"],
        parenttalkid: ["0", "No parent"],
        dtid    : ["topcomment", "No dtid"],
        replyto : ["0", "No replyto"]
    });


    ok( ! this.has_qr("replyto_entry_bottom"), "no qrdiv here yet" );
    ok( ! this.get_qr_container("replyto_entry_bottom").is(":visible"), "qr container starts out invisible");

    $("#replyto_entry_bottom").click();
    ok(   this.has_qr("replyto_entry_bottom"), "qrdiv shows up after clicking link to reply to entry (bottom)" );
    ok(   this.get_qr_container("replyto_entry_bottom").is(":visible"), "qr container becomes visible when we add qr to it");
    ok( ! this.has_qr("replyto_entry_top"), "previous qr container no longer has contains the qr" );
    ok( ! this.get_qr_container("replyto_entry_top").is(":visible"), "previous qr container no longer visible");
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["foo", "Keep existing body"],
        parenttalkid: ["0", "No parent"],
        dtid    : ["bottomcomment", "No dtid"],
        replyto : ["0", "No replyto"]
    });
});

test( "quickreply to comments", 25, function() {
    ok( ! this.has_qr("existing_comment"), "no qrdiv here yet" );
    ok( ! this.get_qr_container("existing_comment").is(":visible"), "qr container starts out invisible");
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["", "Empty body"],
        parenttalkid: ["0", "No parent"],
        dtid    : ["", "No dtid"],
        replyto : ["0", "No replyto"]
    });

    $("#existing_comment").click();
    ok(   this.has_qr("existing_comment"), "qrdiv shows up when clicking link to reply to existing toplevel comment" );
    ok(   this.get_qr_container("existing_comment").is(":visible"), "qr container becomes visible when we add qr to it");
    $("#body").val("bar");
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["bar", "Contains body"],
        parenttalkid: ["1", "Parent is existing comment"],
        dtid    : ["1", "Dtid is existing comment"],
        replyto : ["1", "Replyto is existing comment"]
    });


    ok( ! this.has_qr("child_of_existing_comment"), "no qrdiv here yet" );
    ok( ! this.get_qr_container("child_of_existing_comment").is(":visible"), "qr container starts out invisible");

    $("#child_of_existing_comment").click();
    ok(   this.has_qr("child_of_existing_comment"), "qrdiv shows up after clicking link to reply to existing second-level comment" );
    ok(   this.get_qr_container("child_of_existing_comment").is(":visible"), "qr container becomes visible when we add qr to it");
    ok( ! this.has_qr("existing_comment"), "previous qr container no longer has contains the qr" );
    ok( ! this.get_qr_container("existing_comment").is(":visible"), "previous qr container no longer visible");
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["bar", "Keep existing body"],
        parenttalkid: ["2", "Parent is existing secondlevel comment"],
        dtid    : ["2", "Dtid is existing secondlevel comment"],
        replyto : ["2", "Replyto is existing secondlevel comment"]
    });
});

test( "reply to comment which has subject", 17, function() {
    $("#existing_comment").click();
    ok(   this.has_qr("existing_comment"), "reply to existing_comment" );
    this.check_values({
        subject : ["", "Empty subject"],
        body    : ["", "Empty body"],
    });

    $("#hassubject").click();
    ok(   this.has_qr("hassubject"), "reply to comment which has a subject" );
    $("#body").val("whee");
    this.check_values({
        subject : ["Re: has subject", "Use existing comment subject"],
        body    : ["whee", "Contains body"],
    });

    $("#existing_comment").click();
    ok(   this.has_qr("existing_comment"), "reply to existing_comment again" );
    this.check_values({
        subject : ["", "Clear comment subject if it matches previous / hasn't been customized"],
        body    : ["whee", "Keep old body"],
    });


    $("#subject").val("some custom subject");
    this.check_values({
        subject : ["some custom subject", "Using custom subject"],
        body    : ["whee", "Contains body"],
    });


    $("#hassubject").click();
    ok(   this.has_qr("hassubject"), "reply to something with a subject again, but this time with a custom subject" );
    this.check_values({
        subject : ["some custom subject", "Custom subject overrides original comment subject"],
        body    : ["whee", "Contains body"],
    });

    $("#existing_comment").click();
    ok(   this.has_qr("existing_comment"), "switch back to existing_comment" );
    this.check_values({
        subject : ["some custom subject", "Still using custom subject"],
        body    : ["whee", "Keep old body"],
    });

});

test( "class names", 1, function() {
    $("#hasclass").click();
    // not the same as in old style; this puts #qrformdiv within .container_class
    ok( $(".container_class").find("#qrformdiv").length == 1, "#qrdiv is contained within quick reply container which has a class");
});

test( "submit post", 0, function() {
    // FIXME: add test
});
test( "submit preview", 0, function() {
    // FIXME: add test
});
test( "submit more options", 0, function() {
    // FIXME: add test
});
