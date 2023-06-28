/* ******************** DRAFT SUPPORT ******************** */

  /* RULES:
    -- don't save if they have typed in last 3 seconds, unless it's been
       15 seconds.
  */

var LJDraft = {};

LJDraft.saveInProg = false;
LJDraft.maxTimeout = 15000; // Maximum length of time to go between saves, even if user is still typing
LJDraft.inputDelay = 3000; // Input debounce delay, so we're not saving on each individual keypress
LJDraft.savedMsg = "Autosaved at [[time]]";
LJDraft.savedUnload = false; // Flag so we don't double-post when trying various methods of page unload saves.

LJDraft.handleInput = function (evt) {
    const date = Date.now();
    if (LJDraft.saveTimeout == null) {
        LJDraft.saveTimeout = date;
    } else if (date - LJDraft.saveTimeout > LJDraft.maxTimeout) {
        // Clear any existing delayed fuction call and save now
        if (LJDraft.timer) {
            clearTimeout(LJDraft.timer);
        }
        LJDraft.saveBody();
        return;
    }

    clearTimeout(LJDraft.timer);
    LJDraft.timer = setTimeout(function () {
            LJDraft.saveBody();
        }, LJDraft.inputDelay);

}

LJDraft.handleChange = function (evt) {
    if (evt.target.id == "entry-body") {
        LJDraft.saveBody();
    } else {
        LJDraft.saveProperties();
    }
}

LJDraft.saveProperties = function () {
    let newProps = {
        saveEditor: $("#editor").val(),
        saveSubject: $("#id-subject-0").val(),
        saveTaglist: $("#js-taglist").val(),
        saveMoodID: $("#js-current-mood").val(),
        saveMood: $("#js-current-mood-other").val(),
        saveLocation: $("#current-location").val(),
        saveMusic: $("#current-music").val(),
        saveAdultReason: $("#age_restriction_reason").val(),
        saveCommentSet: $("#comment_settings").val(),
        saveCommentScr: $("#opt_screening").val(),
        saveAdultCnt: $("#age_restriction").val(),
    };

    if ( $("#prop_picture_keyword") ) { //In case the user has no userpics
        newProps.saveUserpic = $("#prop_picture_keyword").val();
    };

    $.post("/__rpc_draft", newProps);

};

LJDraft.saveBody = function () {
    // Clear our global save timeout
    LJDraft.saveTimeout = null;
    LJDraft.saveInProg = true;
    let curBody;

    if ($("#entry-body").css('display') == 'none') { // Need to check this to deal with hitting the back button
        // Since they may start using the RTE in the middle of writing their
        // entry, we should just get the editor each time.
        if (! FCKeditorAPI) return;
        var oEditor = FCKeditorAPI.GetInstance('entry-body');
        if (oEditor.GetXHTML) {
            curBody = oEditor.GetXHTML(true);
            curBody = curBody.replace(/\n/g, '');
        }
    } else {
        curBody = $("#entry-body").val();
    }

    $.post("/__rpc_draft", {"saveDraft": curBody}, function () {
        let date = new Date();
        let msg = LJDraft.savedMsg.replace(/\[\[time\]\]/, date.toLocaleTimeString('en-US', {timeStyle: "medium"}));
        $("#draftstatus").text(msg + ' ');
        LJDraft.saveInProg  = false;
    });

};

function unloadSave() {
    LJDraft.savedUnload = true;
    LJDraft.saveBody();
    LJDraft.saveProperties();
}

function initDraft(askToRestore) {
    if (askToRestore && restoredDraft) {
        if (confirm(confirmMsg)) {
          // If the user wants to restore the draft, we place the
          // values of their saved draft into the form.
          $("#entry-body").val(restoredDraft);
          $("#editor").val(restoredEditor);
          $("#draftstatus").text(restoredMsg);
          $("#id-subject-0").val(restoredSubject);
          $("#js-taglist").val(restoredTaglist);
          $("#js-current-mood").val(restoredMoodID);
          $("#js-current-mood-other").val(restoredMood);
          $("#current-location").val(restoredLocation);
          $("#current-music").val(restoredMusic);
          $("#age_restriction_reason").val(restoredAdultReason);
          $("#comment_settings").val(restoredCommentSet);
          $("#opt_screening").val(restoredCommentScr);
          $("#age_restriction").val(restoredAdultCnt);
          if ( $("#prop_picture_keyword") ) {
              $("#prop_picture_keyword").val(restoredUserpic);
              $("#prop_picture_keyword").trigger("change");
          }
        } else {
            // Clear out their current draft
            $.post("/__rpc_draft", {clearProperties: 1, clearDraft: 1});
        }
   }

    // set up event handlers
    $("#content").on('change', 'input.draft-autosave, textarea.draft-autosave', null, LJDraft.handleChange);
    $("#content").on('input', '#entry-body', null, LJDraft.handleInput);

    // Try to save draft when page is closed/hidden
    document.onvisibilitychange = function(){
      if (document.visibilityState === "hidden" && !LJDraft.savedUnload) {
        unloadSave();
      }
    };

    window.onpagehide = function (event) {
      if (!LJDraft.savedUnload) {
        unloadSave();
      }
    };
}



//LJDraft.maxTimeout = autoSaveInterval;
LJDraft.savedMsg = savedMsg;

if (should_init != null) {
    initDraft(should_init);

    // Hook into the RTE iframe once it's loaded, if we have draft support.
    function FCKeditor_OnComplete( editor ){ 
        editor.EditorDocument.addEventListener('input', LJDraft.handleInput);
    };
}

