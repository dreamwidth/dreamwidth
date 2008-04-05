var EditFriendsMany = {};

EditFriendsMany.init = function () {
    if ($("friend"))
        DOM.addEventListener($("friend"), "change", EditFriendsMany.friendChanged.bindEventListener());
}

EditFriendsMany.friendChanged = function (evt) {
    // if friends checkbox is not enabled, disable all the group selection checkboxes
    var fgroupboxes = $("friendgroups").getElementsByTagName("input");
    for (var i = 0; i < fgroupboxes.length; i++) {
        var box = fgroupboxes[i];
        box.disabled = $("friend").checked ? false : true;
    }
}

LiveJournal.register_hook("page_load", EditFriendsMany.init);
