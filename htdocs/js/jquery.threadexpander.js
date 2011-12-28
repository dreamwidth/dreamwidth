/*
 * This handles the thread expansion for comments.  It also handles
 * the show/hide functionality for comments.
 */

(function($) {
  // makes the given comment element displayed fully.
  function setFull(commentElement, full) {
    commentElement.parent()
      .toggleClass("full", full)
      .toggleClass("partial", !full);
  }

  // Returns the spacer object for S1 indents.
  function getS1SpacerObject(element){
    return $("td.spacer img", element);
  }

  // Returns the talkids of all comments that are replies to this talkid,
  // plus the given talkid if includeSelf is called.
  function getReplies(LJ, talkid, includeSelf) {
    var returnValue = [];
    if (includeSelf) {
      returnValue.push(talkid);
    }
    if (LJ[talkid] && LJ[talkid].rc) {
      for (var i = 0; i < LJ[talkid].rc.length; i++) {
        returnValue = returnValue.concat(getReplies(LJ, LJ[talkid].rc[i], true));
      }
    }
    return returnValue;
  }

  /**
   * Returns all of the unexpanded comments on this page.
   */
  function getUnexpandedComments(LJ) {
    var returnValue = [];
    for (var talkid in LJ) {
      if (LJ[talkid].hasOwnProperty("full") && ! LJ[talkid].full && ! LJ[talkid].deleted && ! LJ[talkid].screened) {
        returnValue.push(talkid);
      }
    }
    return returnValue;
  }

  // shows an error.  just uses alert() for now.
  function showExpanderError(error) {
    alert(error);
  }

  // ajax expands the comments for the given talkid
  $.fn.expandComments = function(LJ, expand_url, talkid, isS1, unhide) {
    element = this;
    // if we've already been clicked, just return.
    if (element.hasClass("disabled")) {
      return;
    }

    if (!LJ) {
      return false;
    }

    element.addClass("disabled");
    element.fadeTo("fast", 0.5);
    var img = $("<img>", { src: Site.imgprefix+"/ajax-loader.gif"});
    element.append(img);

    $.ajax( { url: expand_url,
          datatype: "html",
          timeout: 30000,
          success: function(data) {
            var updateCount = element.doJqExpand(LJ, data, talkid, isS1, unhide);
            // if we didn't update any comments, something must have gone wrong
            if (updateCount == 0) {
              showExpanderError($.threadexpander.config.text.error_nomatches);
            } else if (unhide) {
              element.unhideComments(LJ, talkid, isS1);
            }

            // remove the expand_all option if all comments are expanded
            var expand_all_span = $('.expand_all');
            if (expand_all_span.length > 0) {
              if (getUnexpandedComments(LJ).length == 0) {
                expand_all_span.fadeOut('fast');
              } else if (talkid < 0) {
                img.remove();
                element.removeClass("disabled").fadeTo("fast", 1.0);
              }
            }
          },
          error: function(jqXHR, textStatus, errorThrown) {
            img.remove();
            element.removeClass("disabled");
            element.fadeTo("fast", 1.0);
            showExpanderError($.threadexpander.config.text.error);
          }
      } );
  };

  // callback to handle comment expansion
  $.fn.doJqExpand = function(LJ, data, talkid, isS1, unhide) {
    var updateCount = 0;
    // check for matching expansions on the page
    var replies;
    if (talkid > 0) {
      replies = getReplies(LJ, talkid, true);
    } else {
      replies = getUnexpandedComments(LJ);
    }

    if (replies.length > 0) {
      for (var cmtIdCnt = 0; cmtIdCnt < replies.length; cmtIdCnt++) {
        var cmtId = replies[cmtIdCnt];
        // if we're a valid comment, and either the comment is not expanded
        // or it's the original comment, then it's valid to expand it.
        if (/^\d*$/.test(cmtId) && (talkid == cmtId || (! LJ[cmtId].full))) {
          var cmtElement = $('#cmt' + cmtId);
          if (cmtElement.length > 0) {
            var newComment = $("#cmt" + cmtId, data);
            if (newComment) {
              if (isS1) {
                var oldWidth = getS1SpacerObject(cmtElement).width();
                getS1SpacerObject(newComment).width(oldWidth);
              }
              cmtElement.html($(newComment).html())
                .trigger( "updatedcontent.comment" );
              $(".cmt_show_hide_default", cmtElement).show();

              // don't mark partial comments as full; make sure that the
              // loaded comments are full.
              if (isS1) {
                if ($('table.talk-comment', newComment).length > 0) {
                  LJ[cmtId].full = true;
                }
              } else {
                if (newComment.parent().hasClass("full")) {
                  LJ[cmtId].full = true;
                  setFull(cmtElement, true);
                }
              }
              updateCount++;
            }
          }
        }
      }
    }

    return updateCount;

  }

  // returns the comment elements for the given talkids.
  function getReplyElements(replies) {
    var returnValue = [];
    for (var cmtIdCnt = 0; cmtIdCnt < replies.length; cmtIdCnt++) {
      var cmtId = replies[cmtIdCnt];
      if (/^\d*$/.test(cmtId)) {
        var cmtElement = $("#cmt" + cmtId);
        returnValue.push(cmtElement);
      }
    }
    return returnValue;
  }

  // hides all the comments under this comment.
  $.fn.hideComments = function(LJ, talkid, isS1) {
    var replies = getReplies(LJ, talkid, false);
    var replyElements = getReplyElements(replies);
    for (var i = 0; i < replyElements.length; i++) {
      if (isS1) {
        replyElements[i].hide();
      } else {
        replyElements[i].slideUp("fast");
      }
    }

    $("#cmt" + talkid + "_hide").hide();
    $("#cmt" + talkid + "_unhide").show();
  }

  // shows all the comments under this comment.
  $.fn.unhideComments = function(LJ, talkid, isS1) {
    var replies = getReplies(LJ, talkid, false);
    var replyElements = getReplyElements(replies);
    for (var i = 0; i < replyElements.length; i++) {
      // we're revealing the entire tree, so the subcomments should
      // all show the hide option, not the unhide option.
      $(".cmt_hide", replyElements[i]).show();
      $(".cmt_unhide", replyElements[i]).hide();
      if (isS1) {
        replyElements[i].show();
      } else {
        replyElements[i].slideDown("fast");
      }
    }

    // and this comment itself should show hide.
    $("#cmt" + talkid + "_hide").show();
    $("#cmt" + talkid + "_unhide").hide();
  }

  // reveal all hide links on document ready, so we don't have them if
  // we don't have javascript enabled.
  $(document).ready(function() {
      $(".cmt_show_hide_default").show();
    });

  $.threadexpander = {
    config: {
      text: {
        error: "Error:  no response while expanding comments.",
        error_nomatches: "Error:  no comments found to expand."
      }
    }
  };

})(jQuery);

// globals for backwards compatibility
Expander = {
  make: function(element, url, dtid, isS1, unhide) {
    $(element).expandComments(LJ_cmtinfo, url, dtid, isS1, unhide);
  },

  hideComments: function(element, dtid, isS1) {
    $(element).hideComments(LJ_cmtinfo, dtid, isS1);
  },

  unhideComments: function(element, dtid, isS1) {
    $(element).unhideComments(LJ_cmtinfo, dtid, isS1);
  }
};
