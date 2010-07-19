var StatusvisMessage = new Object();

StatusvisMessage.init = function () {
    var message = document.createElement("div");
    message.style.color = "#000";
    message.style.font = "12px Verdana, Arial, Sans-Serif";
    message.style.backgroundColor = "#ffd";
    message.style.backgroundRepeat = "repeat-x";
    message.style.border = "1px solid #fc3";
    message.style.padding = "8px";
    message.style.margin = "5px auto";
    message.style.width = "auto";
    message.style.textAlign = "center";
    message.className = "warning-background";
    message.innerHTML = Site.StatusvisMessage;

    if ($('lj_controlstrip')) {
        document.body.insertBefore(message, $('lj_controlstrip').nextSibling);
    } else {
        document.body.insertBefore(message, document.body.firstChild);
    }
}

LiveJournal.register_hook("page_load", StatusvisMessage.init);
