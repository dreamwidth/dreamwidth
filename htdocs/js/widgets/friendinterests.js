var FriendInterests = new Object();

FriendInterests.init = function () {
    FriendInterests.user = $('from_user').value;
    HTTPReq.getJSON({
        url: "/tools/endpoints/getinterests?user=" + FriendInterests.user,
        onData: FriendInterests.gotInterests,
        onError: function (msg) { }
    });
    $('friend_interests').style.display = "inline";
}

FriendInterests.gotInterests = function (data) {
    FriendInterests.ints = data.interests;
    for (var interest in FriendInterests.ints) {
        if (!FriendInterests.ints.hasOwnProperty(interest)) continue;
        DOM.addEventListener($('int_' + FriendInterests.ints[interest]), "change", FriendInterests.checkboxChanged.bindEventListener(interest));
    }
    DOM.addEventListener($('interests_box'), "keyup", FriendInterests.textChanged);
}

FriendInterests.textChanged = function () {
    var val = $('interests_box').value;
    var ints = val.split(',');

    for (var interest in FriendInterests.ints) {
        if (!FriendInterests.ints.hasOwnProperty(interest)) continue;
        $('int_' + FriendInterests.ints[interest]).checked = false;
    }

    ints.forEach(function (interest) {
        interest = interest.trim();
        var intid = FriendInterests.ints[interest];
        if (!intid) return;
        $('int_' + intid).checked = true;
    });

    return false;
}

FriendInterests.checkboxChanged = function (evt) {
    var interest = this;
    interest = interest.trim();
    var checkboxChecked = $('int_' + FriendInterests.ints[interest]).checked;

    var val = $('interests_box').value;
    var ints = val.split(',');

    for (var i = 0; i < ints.length; i++) {
        ints[i] = ints[i].trim();
    };

    if (checkboxChecked) {
        if (ints.indexOf(interest) == -1) {
            ints.push(interest);
        }
    } else {
        ints.remove(interest);
    }

    ints.sort();

    ints = ints.filter(function (theInt) {
        if (theInt.length) return 1;
        return 0;
    });

    $('interests_box').value = ints.join(", ");
}

LiveJournal.register_hook("page_load", FriendInterests.init);
