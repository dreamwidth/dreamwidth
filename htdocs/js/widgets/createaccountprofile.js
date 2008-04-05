var CreateAccountProfile = new Object();

CreateAccountProfile.init = function () {
    if (!$('js_on')) return;
    if (!$('interests_music')) return;
    if (!$('interests_moviestv')) return;
    if (!$('interests_books')) return;
    if (!$('interests_hobbies')) return;
    if (!$('interests_other')) return;
    if (!$('interests_music_changed')) return;
    if (!$('interests_moviestv_changed')) return;
    if (!$('interests_books_changed')) return;
    if (!$('interests_hobbies_changed')) return;
    if (!$('interests_other_changed')) return;

    $('js_on').value = 1;

    CreateAccountProfile.doAddText("interests_music");
    CreateAccountProfile.doAddText("interests_moviestv");
    CreateAccountProfile.doAddText("interests_books");
    CreateAccountProfile.doAddText("interests_hobbies");
    CreateAccountProfile.doAddText("interests_other");

    DOM.addEventListener($('interests_music'), "focus", CreateAccountProfile.removeText.bindEventListener("interests_music"));
    DOM.addEventListener($('interests_moviestv'), "focus", CreateAccountProfile.removeText.bindEventListener("interests_moviestv"));
    DOM.addEventListener($('interests_books'), "focus", CreateAccountProfile.removeText.bindEventListener("interests_books"));
    DOM.addEventListener($('interests_hobbies'), "focus", CreateAccountProfile.removeText.bindEventListener("interests_hobbies"));
    DOM.addEventListener($('interests_other'), "focus", CreateAccountProfile.removeText.bindEventListener("interests_other"));

    DOM.addEventListener($('interests_music'), "change", CreateAccountProfile.markAsChanged.bindEventListener("interests_music"));
    DOM.addEventListener($('interests_moviestv'), "change", CreateAccountProfile.markAsChanged.bindEventListener("interests_moviestv"));
    DOM.addEventListener($('interests_books'), "change", CreateAccountProfile.markAsChanged.bindEventListener("interests_books"));
    DOM.addEventListener($('interests_hobbies'), "change", CreateAccountProfile.markAsChanged.bindEventListener("interests_hobbies"));
    DOM.addEventListener($('interests_other'), "change", CreateAccountProfile.markAsChanged.bindEventListener("interests_other"));
}

CreateAccountProfile.addText = function (evt) {
    var id = this + "";

    CreateAccountProfile.doAddText(id);
}

CreateAccountProfile.doAddText = function (id) {
    id = id + "";

    var color = "#999";
    var text;
    if (id == "interests_music") {
        text = "the beatles, kanye west, metal";
    } else if (id == "interests_moviestv") {
        text = "lost, brad pitt, real world";
    } else if (id == "interests_books") {
        text = "fiction, david sedaris, harry potter";
    } else if (id == "interests_hobbies") {
        text = "snowboarding, painting, making music";
    } else if (id == "interests_other") {
        text = "whiskers on kittens, motocross racing";
    }

    if (CreateAccountProfile.isChanged(id) == 0 && $(id).value == "") {
        $(id).style.color = color;
        $(id).value = text;
    } else {
        CreateAccountProfile.doMarkAsChanged(id);
    }
}

CreateAccountProfile.removeText = function (evt) {
    var id = this + "";

    if (CreateAccountProfile.isChanged(id) == 0) {
        $(id).style.color = "";
        $(id).value = "";
    }
}

CreateAccountProfile.markAsChanged = function (evt) {
    var id = this + "";

    CreateAccountProfile.doMarkAsChanged(id);
}

CreateAccountProfile.doMarkAsChanged = function (id) {
    $(id + "_changed").value = 1;
}

CreateAccountProfile.isChanged = function (id) {
    return $(id + "_changed").value;
}

LiveJournal.register_hook("page_load", CreateAccountProfile.init);
