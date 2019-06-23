
var usernameWasFocused = 0;

if (document.getElementById) {
    // If there's no getElementById, this whole script won't do anything

    var radio_remote = document.getElementById("talkpostfromremote");
    var radio_user = document.getElementById("talkpostfromlj");
    var radio_anon = document.getElementById("talkpostfromanon");
    var radio_oidlo = document.getElementById("talkpostfromoidlo");
    var radio_oidli = document.getElementById("talkpostfromoidli");

    var check_login = document.getElementById("logincheck");
    var sel_pickw = document.getElementById("prop_picture_keyword");
    var commenttext = document.getElementById("commenttext");

    var form = document.getElementById("postform");

    var username = form.userpost;
    if (username) {
        username.onfocus = function () { usernameWasFocused = 1; }
    }
    var password = form.password;

    var oidurl = document.getElementById("oidurl");
    var oid_more = document.getElementById("oid_more");
    var lj_more = document.getElementById("lj_more");
    var ljuser_row = document.getElementById("ljuser_row");
    var otherljuser_row = document.getElementById("otherljuser_row");
    var oidlo_row = document.getElementById("oidlo");
    var oidli_row = document.getElementById("oidli");

    var remotef = document.getElementById("cookieuser");
    var remote;
    if (remotef) {
        remote = remotef.value;
    }

    var subjectIconField = document.getElementById("subjectIconField");
    var subjectIconImage = document.getElementById("subjectIconImage");

    var subject_field = document.getElementById("subject");
    var subject_nohtml = document.getElementById("ljnohtmlsubj");
    hideMe(subject_nohtml);

    var edit_nohtml = document.getElementById("nohtmledit");
    hideMe(edit_nohtml);

    showRandomIcon();
}

var apicurl = "";
var picprevt;

if (! sel_pickw) {
    // make a fake sel_pickw to play with later
    sel_pickw = new Object();
}

function handleRadios(sel) {
    password.disabled = check_login.disabled = (sel != 2);
    if (password.disabled) password.value='';

    // Anonymous
    if (sel == 0) {
        if (radio_anon && radio_anon.checked != 1) {
            radio_anon.checked = 1;
        }
    }

    // Remote LJ User
    if (sel == 1) {
        if (radio_remote && radio_remote.checked != 1) {
            radio_remote.checked = 1;
        }
    }

    // LJ User
    if (sel == 2) {
        showMe(otherljuser_row);
        if (ljuser_row) {
            hideMe(ljuser_row);
        }
        if (lj_more) {
                showMe(lj_more);
        }
        username.focus();

        if (radio_user && radio_user.checked != 1) {
            radio_user.checked = 1;
        }

    } else {
        if (lj_more) {
            hideMe(lj_more);
        }
    }

    // OpenID
    if (oid_more) {
        if (sel == 3) {
            showMe(oid_more);
            oidurl.focus();
            if (oidli_row) {
               hideMe(oidli_row);
            }
            showMe(oidlo_row);

            if (radio_oidlo && radio_oidlo.checked != 1) {
                radio_oidlo.checked = 1;
            }

        } else if (sel == 4) {
            if (oidlo_row) {
               hideMe(oidlo_row);
            }
            showMe(oidli_row);
            hideMe(oid_more);

            if (radio_oidli && radio_oidli.checked != 1) {
                radio_oidli.checked = 1;
            }
        } else {
            hideMe(oid_more);
        }
    }

    if (sel_pickw.disabled = (sel != 1 && sel != 4 )) sel_pickw.value='';
}

function submitHandler() {
    if (remote && username.value == remote && ((! radio_anon || ! radio_anon.checked) && (! radio_oidlo || ! radio_oidlo.checked))) {
        //  Quietly arrange for cookieuser auth instead, to avoid
        // sending cleartext password.
        password.value = "";
        username.value = "";
        radio_remote.checked = true;
        return true;
    }
    if (usernameWasFocused && username.value && ! radio_user.checked) {
        alert(usermismatchtext);
        return false;
    }
    if (! radio_user.checked) {
        username.value = "";
    }
    return true;
}

if (document.getElementById) {

    if (radio_anon && radio_anon.checked) handleRadios(0);
    if (radio_remote && radio_remote.checked) handleRadios(1);
    if (radio_user && radio_user.checked) handleRadios(2);
    if (radio_oidlo && radio_oidlo.checked) handleRadios(3);
    if (radio_oidli && radio_oidli.checked) handleRadios(4);

    if (radio_remote) {
        radio_remote.onclick = function () {
            handleRadios(1);
        };
        if (radio_remote.checked) handleRadios(1);
    }
    if (radio_user)
        radio_user.onclick = function () {
            handleRadios(2);
        };
    if (radio_anon)
        radio_anon.onclick = function () {
            handleRadios(0);
        };
    if (radio_oidlo)
        radio_oidlo.onclick = function () {
            handleRadios(3);
        };
    if (radio_oidli)
        radio_oidli.onclick = function () {
            handleRadios(4);
        };
    if (username) {
        username.onkeydown = username.onchange = function () {
            if (radio_remote) {
                password.disabled = check_login.disabled = 0;
                if (password.disabled) password.value='';
            } else {
                if (radio_user && username.value != "")
                    radio_user.checked = true;
                handleRadios(2);  // update the form
            }
        }
    }
    form.onsubmit = submitHandler;

    document.addEventListener("DOMContentLoaded", function () {
        hideMe(otherljuser_row);
        hideMe(lj_more);
        hideMe(oid_more);
        if (radio_anon && radio_anon.checked) handleRadios(0);
        if (radio_user && radio_user.checked) otherLJUser();
        if (radio_remote && radio_remote.checked) handleRadios(1);
        if (radio_oidlo && radio_oidlo.checked) handleRadios(3);
        if (radio_oidli && radio_oidli.checked) handleRadios(4);
    });

}

// toggle subject icon list

function subjectIconListToggle() {
    if (! document.getElementById) { return; }
    var subjectIconList = document.getElementById("subjectIconList");
    if(subjectIconList) {
     if (subjectIconList.style.display != 'block') {
         subjectIconList.style.display = 'block';
     } else {
         subjectIconList.style.display = 'none';
     }
    }
}

// change the subject icon and hide the list

function subjectIconChange(icon) {
    if (! document.getElementById) { return; }
    if (icon) {
        if(subjectIconField) subjectIconField.value=icon.id;
        if(subjectIconImage) {
            subjectIconImage.src=icon.src;
            subjectIconImage.width=icon.width;
            subjectIconImage.height=icon.height;
        }
        subjectIconListToggle();
    }
}

function showRandomIcon() {
    var ele = document.getElementById("randomicon");
    if (ele) {
        ele.setAttribute("class", "randomicon");
        ele.onclick = randomicon;
    }
}

function randomicon(e) {
    var icons_list = document.getElementById('prop_picture_keyword');
    // we need to ignore the "(default)" option for this code
    var numberoficons = icons_list.length-1;
    var randomnumber=Math.floor(Math.random()*numberoficons) +1;
    icons_list.selectedIndex = randomnumber;
    e.preventDefault();
}

function subjectNoHTML(e) {

   var key;

   key = getKey(e);

   if (key == 60) {
      showMe(subject_nohtml);
   }
}

function editNoHTML(e) {

    var key;

    key = getKey(e);

    if (key == 60) {
        showMe(edit_nohtml);
    }
}

function getKey(e) {
   if (window.event) {
      return window.event.keyCode;
   } else if(e) {
      return e.which;
   } else {
      return undefined;
   }
}

function otherLJUser() {
   handleRadios(2);

   showMe(otherljuser_row);
   radio_user.checked = 1;
}

function otherOIDUser() {
   handleRadios(3);

   radio_oidlo.checked = 1;
}

function hideMe(e) {
   if ( e )
      e.className = 'display_none';
}

function showMe(e) {
   if ( e )
      e.className = '';
}
