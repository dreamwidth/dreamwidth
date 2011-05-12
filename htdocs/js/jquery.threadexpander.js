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

  // Returns the given talkid, plus the talkids of all comments that are
  // replies to this talkid.
  function getReplies(LJ, talkid) {
    var returnValue = [ talkid ];
    for (var i = 0; i < LJ[talkid].rc.length; i++) {
      returnValue = returnValue.concat(getReplies(LJ, LJ[talkid].rc[i]));
    }
    return returnValue;
  }

  // shows an error.  just uses alert() for now.
  function showExpanderError(error) {
    alert(error);
  }

  // ajax expands the comments for the given talkid
  $.fn.expandComments = function(LJ, expand_url, talkid, isS1) {
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
            doJqExpand(LJ, data, talkid, isS1);
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
  function doJqExpand(LJ, data, talkid, isS1) {
    var updateCount = 0;
    // check for matching expansions on the page
    var replies = getReplies(LJ, talkid);
    for (var cmtIdCnt = 0; cmtIdCnt < replies.length; cmtIdCnt++) {
      var cmtId = replies[cmtIdCnt];
      // if we're a valid comment, and either the comment is not expanded
      // or it's the original comment, then it's valid to expand it.
      if (/^\d*$/.test(cmtId) && (talkid == cmtId || (! LJ[cmtId].full))) {
        var cmtElement = $("#cmt" + cmtId);
        if (cmtElement) {
          var newComment = $("#cmt" + cmtId, data);
          if (newComment && newComment.attr('id') == 'cmt' + cmtId) {
            if (isS1) {
            var oldWidth = getS1SpacerObject(cmtElement).width();
            getS1SpacerObject(newComment).width(oldWidth);
          }
            cmtElement.html($(newComment).html())
                .trigger( "updatedcontent.comment" );
            LJ[cmtId].full = true;
            if (! isS1) {
              setFull(cmtElement, true);
            }
            updateCount++;
          }
        }
      }
    }

    // if we didn't update any comments, something must have gone wrong
    if (updateCount == 0) {
      showExpanderError($.threadexpander.config.text.error_nomatches);
    }
  }

  $.threadexpander = {
    config: {
      text: {
        error: "Error:  no response while expanding comments.",
        error_nomatches: "Error:  no comments found to expand."
      }
    }
  };
})(jQuery);

Expander = {
  make: function(element, url, dtid, isS1) {
    $(element).expandComments(LJ_cmtinfo, url, dtid, isS1);
  }
};
