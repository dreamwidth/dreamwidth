// Helpers specific to quickreply aka quicker-reply and lessquick-reply aka The Critters
// See also jquery.talkform.js, jquery.replyforms.js
(function($) {
var _ok;
var customsubject;
var previous;
var firstCommentWidgetParent;

function can_continue() {
    if ( _ok == undefined )
        _ok =
            ($("#parenttalkid,#replyto,#dtid,#qrdiv,#qrformdiv,#qrform,#subject").length == 7);
    return _ok;
}

function update(data,widget) {
    // There's three target patterns:
    // - "entry-dw_dev-215060-reply" (lastn page, reply to entry)
    // - "topcomment", "bottomcomment" (entry page, reply to entry)
    // - "1236487" (entry page, reply to comment)
    var targetParts = data.target.split("-");
    if ( targetParts.length === 1 ) {
        data.dtid = data.target;
    } else {
        data.dtid = 0;
        $("#journal").val(targetParts[1]);
        $("#itemid").val(targetParts[2]);
        $("#basepath").val(document.location.protocol + "//" +
                            targetParts[1].replace("_", "-") + "." + Site.user_domain +
                            "/" + targetParts[2] + ".html?");
        data.stayOnPage = true;
    }
    $("#qrform").data("stayOnPage", data.stayOnPage);

    $("#parenttalkid, #replyto").val(data.pid);
    $("#dtid").val(data.dtid);

    var old_subject;
    if ( previous ) {
        old_subject = previous.subject;
        previous.widget.hide();
    }

    var subject = $("#subject");
    var cur_subject = subject.val();

    if ( old_subject != undefined && cur_subject != old_subject )
        customsubject = true;
    if ( ! customsubject || cur_subject == "" )
        subject.val(data.subject);

    $("#prop_picture_keyword").change();

    // If we previously munged the layout of #qrformdiv, reset it.
    $('#qrformdiv').removeAttr('style').removeClass('width-adjusted');

    // If replying to a comment, sort out the width. If the reply form would be
    // super-small but there's plenty of whitespace to the left due to comment
    // indentation, extend the form out to the left.
    if ( data.target.match(/^\d+$/) ) {
        if ( ! firstCommentWidgetParent ) {
            // Parent element of the ljqrtNNNNN divs is different from style to
            // style, so we can't hardcode it.
            firstCommentWidgetParent = $('.comment').first().find('[data-quickreply-container]').parent();
        }
        // .width() always gives content width, which is what we want here.
        var maxAvailableCommentWidth = firstCommentWidgetParent.width();
        var plannedWidth = widget.parent().width();
        // 640 = 40em @ 16px, reasonable size on desktop. If we're mobile or
        // otherwise too small for that, just max out what we've got.
        var minWidth = Math.min( 640, maxAvailableCommentWidth );
        if ( plannedWidth < minWidth ) {
            // Ascend and grab the first non-transparent background color we
            // see, so the form fields aren't just dangling out in space
            var backgroundColor;
            // not guessing every browser's exact stringification of computed transparent
            var rootBackgroundColor = $(':root').css('background-color');
            widget.parentsUntil('.comment-thread').each(function(i, element) {
                var bg = $(element).css('background-color');
                if ( bg !== rootBackgroundColor ) {
                    backgroundColor = bg;
                    return false; // exit .each() early
                }
            });
            // #qrdiv is the sacrificial inline-display wrapper. #qrformdiv is
            // the block-display workhorse behind it.
            $('#qrformdiv').css({
                'min-width': minWidth,
                'position': 'relative',
                'right': minWidth - plannedWidth + 'px',
                'background-color': backgroundColor
            }).addClass('width-adjusted');
        }
    }

    // display: inline is to keep the whole container from getting kicked sideways by a float.
    $("#qrdiv").show().css("display", "inline").appendTo(widget);
    widget.show();
    $("#body").focus();

    previous = {
        subject: data.subject,
        widget: widget
    };
};

$.widget("dw.quickreply", {
    options: {
        target: undefined,
        stayOnPage: false,
        dtid: undefined,
        pid: undefined,
        subject: undefined
    },
    _create: function() {
        var self = this;
        self.element.click(function(e){
            if ( ! can_continue() ) return;
            e.stopPropagation();
            e.preventDefault();
            update(self.options, self.widget())
        }).click();

        $(".qr-icon").find("img")
            .attr("src", $(this).find("option:selected").data("url"))
            .removeAttr("width").removeAttr("height");
    },
    widget: function() {
        return this.options.target ? $("#ljqrt"+this.options.target) : [];
    }
});

$.extend( $.dw.quickreply, {
    can_continue: function() { return _ok; }
} );

})(jQuery);

jQuery(function($) {
    $("#qrform").submit(function(e) {
        var $form = $(this);

        if ($form.data("stayOnPage")) {
            e.preventDefault();
            e.stopPropagation();

            $("#submitpost").ajaxtip() // init
            .ajaxtip( "load", {
                endpoint: "addcomment",

                ajax: {
                    type: "POST",

                    data: $form.serialize(),

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            if ( data.error === "Client error: Message looks like spam" ) {
                                // It just wants a captcha; disable ajax and take the long way around.
                                $form.data("stayOnPage", false).submit();
                            } else {
                                // Go bother grandma cuz mom don't care.
                                $("#submitpost").ajaxtip( "error", data.error );
                            }
                        } else {
                            var $container = $("#qrdiv").parent();
                            var $readLink = $("[data-quickreply-target='" + $container.data("quickreply-container") + "'] .entry-readlink a");
                            $container
                                .slideUp(function() {
                                    // reset form
                                    $("#subject").val("");
                                    $("#body").val("");
                                    var $iconSelect = $("#prop_picture_keyword");
                                    if ( $iconSelect.length > 0 ) {
                                        $iconSelect.get(0).selectedIndex = 0;
                                        $iconSelect.trigger("change");
                                    }

                                    // for the 0 -> 1 case, when the link starts out hidden
                                    $readLink.parent().show();

                                    $readLink
                                        .ajaxtip() // init
                                        .ajaxtip("success", data.message); // success message

                                    var commentText = '';
                                    if ( data.count == 1 ) {
                                        commentText = $readLink.data('sing');
                                    }
                                    else if ( data.count == 2 ) {
                                        commentText = $readLink.data('dual');
                                    }
                                    else {
                                        commentText = $readLink.data('plur').replace(/\d+/, data.count);
                                    }

                                    $readLink.text(commentText); // replace count
                                });

                        }
                    }
                }
            });
        } else {
            // prevent double-submits
            $form.find('input[type="submit"]').prop("disabled", true);

            var dtid = $("#dtid");
            if ( ! Number(dtid.val()) )
                dtid.val("0");

            // ...and then carry on.
        }
    });

    $("#submitpview").on("click", function(e){
        $("#qrform").data("stayOnPage", false);
        // Why use a hidden input for the real "submitpreview" instead of just
        // relying on the button? Because we disable the submit buttons to guard
        // against double-submits, and that causes the preview button's value to
        // appear as falsy when the form data arrives back in perl-land, which
        // in turn causes surprise posts.
        $("#qrform input[name='submitpreview']").val(1);
        $("#qrform").attr("action", Site.siteroot + "/talkpost_do" );
    });
    $("#submitpost").on("click", function(e){
        $("#qrform").attr("action", Site.siteroot + "/talkpost_do" );
    });
    $("#submitmoreopts").on("click", function(e) {
        e.preventDefault();
        e.stopPropagation();

        var qrform = $("#qrform");
        var replyto = Number($("#dtid").val());
        var pid = Number($("#parenttalkid").val());
        var basepath = $("#basepath").val();

        if(replyto > 0 && pid > 0) {
            qrform.attr("action", basepath + "replyto=" + replyto );
        } else {
            qrform.attr("action", basepath + "mode=reply" );
        }

        qrform.data("stayOnPage", false);
        qrform.submit();
    });

});


function quickreply(target, pid, newsubject, trigger) {
    trigger = trigger || document;

    $(trigger).quickreply({ target: target, pid: pid, subject: newsubject })
            .attr("onclick", null);
    return ! $.dw.quickreply.can_continue();
}
