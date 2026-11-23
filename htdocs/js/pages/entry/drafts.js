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

// Edits made inside the rich text editor don't fire input events on the
// textarea, so editor.js reports them here. They're handled exactly like plain
// edits: ignored where autosave isn't running (editing a published entry must
// never write the new-entry draft), and remembered while the initial draft
// clear is still in flight.
LJDraft.richInput = function () {
    if (LJDraft.bound) {
        LJDraft.handleInput();
    } else if (LJDraft.clearPending) {
        LJDraft.clearPending.body = true;
    }
};

LJDraft.currentProperties = function () {
    return {
        editor: $("#editor").val(),
        subject: $("#id-subject-0").val(),
        taglist: $("#js-taglist").val(),
        moodid: $("#js-current-mood").val(),
        mood: $("#js-current-mood-other").val(),
        location: $("#current-location").val(),
        music: $("#current-music").val(),
        adultreason: $("#age_restriction_reason").val(),
        commentset: $("#comment_settings").val(),
        commentscr: $("#opt_screening").val(),
        adultcnt: $("#age_restriction").val(),
        userpic: $("#prop_picture_keyword").val(),
    };
};

LJDraft.handleChange = function (evt) {
    if (evt.target.id == "entry-body") {
        LJDraft.saveBody();
        return;
    }

    // Switching format converts the body, so the converted body and its format
    // have to be stored together (a reload would otherwise restore the old
    // body under the new format).
    if (evt.target.id == "editor") {
        LJDraft.saveBody();
        return;
    }

    // Widget initialization can dispatch delayed changes after restoration.
    // Ignore only the current saved-property snapshot; user reversions differ
    // after a real save updates that snapshot.
    if (JSON.stringify(LJDraft.currentProperties()) == JSON.stringify(LJDraft.savedProperties)) return;
    LJDraft.saveProperties();
}

// The draft's properties as the server stores them. The server replaces the
// whole set whenever it gets any of them, so they are always sent together.
LJDraft.propertyPayload = function () {
    let props = {
        // Tells the server this page sends the format with its body; older
        // pages sent them separately (see draft_rpc_handler).
        draftv: 2,
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
        props.saveUserpic = $("#prop_picture_keyword").val();
    };

    return props;
};

LJDraft.saveProperties = function () {
    LJDraft.savedProperties = LJDraft.currentProperties();
    $.post("/__rpc_draft", LJDraft.propertyPayload());
};

LJDraft.saveBody = function () {
    // Clear our global save timeout
    LJDraft.saveTimeout = null;
    LJDraft.saveInProg = true;
    let curBody;

    if (window.DWEditor && DWEditor.isActive('entry-body')) { // New rich text editor (rte1)
        curBody = DWEditor.getHTML('entry-body');
    } else {
        curBody = $("#entry-body").val();
    }

    // The body goes with the current properties (notably the format it is
    // written in), so the two can never be stored out of step.
    LJDraft.savedProperties = LJDraft.currentProperties();
    $.post("/__rpc_draft", Object.assign({"saveDraft": curBody}, LJDraft.propertyPayload()), function () {
        let date = new Date();
        let msg = LJDraft.savedMsg.replace(/\[\[time\]\]/, date.toLocaleTimeString('en-US', {timeStyle: "medium"}));
        $("#draftstatus").text(msg + ' ');
        LJDraft.saveInProg  = false;
    });

};

function initDraft(askToRestore) {
    let persistConverted = false;
    if (askToRestore && restoredDraft) {
        if (confirm(confirmMsg)) {
          // If the user wants to restore the draft, we place the
          // values of their saved draft into the form.
          $("#entry-body").val(restoredDraft);
          // A legacy saved-properties hash can lack editor. Preserve the
          // form's preferred current mode instead of clearing its selection.
          if (restoredEditor) {
              // A draft saved in the retired rich text editor (rte0) was
              // converted to rte1 by the server; warn that it needs checking.
              if (restoredRte0) {
                  $("#js-rte0-warning").removeClass('display_none');
                  $("#js-rte0-converted").val(1);
                  persistConverted = true;
              }
              $("#editor").val(restoredEditor);
          }
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
            // Keep real edits made while the clear is in flight. Binding the
            // normal autosave handlers first would let their requests race the
            // clear, so only remember changes until the clear has succeeded.
            const changed = { body: false, properties: false };
            LJDraft.clearPending = changed;
            const initialBody = $("#entry-body").val();
            const initialProperties = LJDraft.currentProperties();
            $("#content").on("input.draft-clear", "#entry-body", function () {
                changed.body ||= $("#entry-body").val() !== initialBody;
            });
            const captureProperties = function () {
                changed.properties ||= JSON.stringify(LJDraft.currentProperties())
                    !== JSON.stringify(initialProperties);
            };
            $("#content").on("input.draft-clear change.draft-clear", ".draft-autosave", captureProperties);
            $.post("/__rpc_draft", {clearProperties: 1, clearDraft: 1}).done(function () {
                $("#content").off(".draft-clear");
                LJDraft.clearPending = null;
                bindDraftHandlersAfterInitialization();
                if (changed.properties) LJDraft.saveProperties();
                if (changed.body) LJDraft.saveBody();
            }).fail(function () {
                $("#content").off(".draft-clear");
                LJDraft.clearPending = null;
                bindDraftHandlersAfterInitialization();
            });
            return;
        }
   }

    bindDraftHandlersAfterInitialization();

    // The stored draft is still the old editor's text under the old format.
    // Store the converted text and its new format together, right away, so no
    // later save can pair one with the other.
    if (persistConverted) LJDraft.saveBody();
}

function bindDraftHandlersAfterInitialization() {
    // Capture the restored/cleared state before widget initialization can emit
    // delayed changes. Do not wait for window.load: real input must work now.
    LJDraft.savedProperties = LJDraft.currentProperties();
    bindDraftHandlers();
}

function bindDraftHandlers() {
    LJDraft.bound = true;
    $("#content").on('change', '.draft-autosave', null, LJDraft.handleChange);
    $("#content").on('input', '#entry-body', null, LJDraft.handleInput);
}



//LJDraft.maxTimeout = autoSaveInterval;
LJDraft.savedMsg = savedMsg;

if (should_init != null) {
    initDraft(should_init);
}

