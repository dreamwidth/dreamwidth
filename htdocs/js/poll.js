// Poll Object Constructor
function Poll (doc, q_num) {
    var pollform = doc.poll;
    this.name = pollform.name.value || '';
    this.whovote = getRadioValue(pollform.whovote);
    this.whoview = getRadioValue(pollform.whoview);

    // Array of Questions and Answers
    // A single poll can have multiple questions
    // Each question can have one or several answers
    this.qa = new Array();
    for (var i=0; i<q_num; i++) {
        this.qa[i] = new Answer(doc, i);
    }
}

// Poll method to generate HTML for RTE
Poll.prototype.outputHTML = function () {
    var html;

    html = '<form action="#"><b>Poll #xxxx</b>';
    if (this.name) html += " <i>"+this.name+"</i>";
    html += "<br />Open to: ";
    html += "<b>"+this.whovote+"</b>, results viewable to: ";
    html += "<b>"+this.whoview+"</b>";
    for (var i=0; i<this.qa.length; i++) {
        html += "<br />\n<p>"+this.qa[i].question+"</p>\n";
        html += '<p style="margin: 0px 0pt 10px 40px;">';
        if (this.qa[i].atype == "radio" || this.qa[i].atype == "check") {
            var type = this.qa[i].atype;
            if (type == "check") type = "checkbox";
            for (var j=0; j<this.qa[i].answer.length; j++) {
                html += '<input type="'+type+'">';
                html += this.qa[i].answer[j] + '<br />\n';
            }
        } else if (this.qa[i].atype == "drop") {
            html += '<select name="select_'+i+'">\n';
            html += '<option value=""></option>\n';
            for (var j=0; j<this.qa[i].answer.length; j++) {
                html += '<option value="">' + this.qa[i].answer[j] + '</option>\n';
            }
            html += '</select>\n';
        } else if (this.qa[i].atype == "text") {
            html += '<input maxlength="' + this.qa[i].maxlength + '" ';
            html += 'size="' + this.qa[i].size + '" type="text">';
        } else if (this.qa[i].atype == "scale") {
            html += '<table><tbody><tr align="center" valign="top">'
            var from = Number(this.qa[i].from);
            var to = Number(this.qa[i].to);
            var by = Number(this.qa[i].by);
            for (var j=from; j<=to; j=j+by) {
                html += '<td><input type="radio"><br>' +j+ '</td>';
            }
            html += '</tr></tbody></table>';
        }
        html += '</p>';
    }

    html += '<input type="submit" disabled="disabled" value="Submit Poll" /> </form>';

    return html;
}

// Poll method to generate LJ Poll tags
Poll.prototype.outputLJtags = function (pollID, post) {
    var tags = '';

    if (post == true) tags += '<div class="LJpoll">';
    tags+= '<lj-poll name="'+this.name+'" id="poll'+pollID+'" ';
    tags+= 'whovote="'+this.whovote+'" whoview="'+this.whoview+'">\n';

    for (var i=0; i<this.qa.length; i++) {
        var extrargs = '' // for text and scale polls
        if (this.qa[i].atype == 'text') {
            extrargs = ' size="'+this.qa[i].size+'"';
            extrargs += ' maxlength="'+this.qa[i].maxlength+'"';
        } else if (this.atype == 'scale') {
            extrargs = ' from="'+this.qa[i].from+'"';
            extrargs += ' to="'+this.qa[i].to+'"';
            extrargs += ' by="'+this.qa[i].by+'"';
        }

        tags += ' <lj-pq type="'+this.qa[i].atype+'"'+extrargs+'>\n';
        tags += ' ' + this.qa[i].question + '\n';
        // answer choices for radio, checkbox and drop-down
        if (this.qa[i].atype == "radio" || this.qa[i].atype == "check" || this.qa[i].atype == "drop") {
            for (var j=0; j<this.qa[i].answer.length; j++) {
                tags += '  <lj-pi>' + this.qa[i].answer[j] + '</lj-pi>\n';
            }
        }
        tags += ' </lj-pq>\n';
    }

    tags += '</lj-poll>';
    if (post == true) tags += '</div>';

    return tags;
}

Poll.callRichTextEditor = function() {
    var oEditor = FCKeditorAPI.GetInstance('draft');
    oEditor.Commands.GetCommand('LJPollLink').Execute();
}

// Answer Object Constructor
function Answer (doc, q_idx) {
    var pollform = doc.poll;
    this.question = pollform["question_"+q_idx].value;
    var type = pollform["type_"+q_idx];
    this.atype = type.options[type.selectedIndex].value;

    this.answer = new Array();
    if (this.atype == "radio" || this.atype == "check" || this.atype == "drop") {
        for (var i=0; i<pollform.elements.length; i++) {
            if (pollform.elements[i].name.match(/pq_\d+_opt_\d+/) &&
                pollform.elements[i].value != '') {
                var qID = pollform.elements[i].name.replace(/pq_(\d+)_opt_\d+/, "$1");
                if (qID == q_idx) {
                    var ansID = pollform.elements[i].name.replace(/pq_\d+_opt_(\d+)/, "$1");
                    this.answer[ansID] = pollform.elements[i].value;
                }
            }
        }
    } else if (this.atype == "text") {
        this.size = pollform["pq_"+q_idx+"_size"].value;
        this.maxlength = pollform["pq_"+q_idx+"_maxlength"].value;
    } else if (this.atype == "scale") {
        this.from = pollform["pq_"+q_idx+"_from"].value;
        this.to = pollform["pq_"+q_idx+"_to"].value;
        this.by = pollform["pq_"+q_idx+"_by"].value;
    }

}

// Useful Functions //
function getRadioValue(radio) {
    var radio_length = radio.length;
    if(radio_length == undefined) {
        if(radio.checked) return radio.value;
    }

    for(var i = 0; i < radio_length; i++) {
        if(radio[i].checked) return radio[i].value;
    }
    return "";
}

function setRadioValue(radio, value) {
    var radio_length = radio.length;
    if(radio_length == undefined) {
        radio.checked = (radio.value == value);
        return;
    }

    for(var i = 0; i < radio_length; i++) {
        radio[i].checked = false;
        if(radio[i].value == value) radio[i].checked = true;
    }
}

function setSelectValue(select, value) {
    var select_length = select.options.length;

    for(var i = 0; i < select_length; i++) {
        select.options[i].selected = false;
        if(select.options[i].value == value) select.options[i].selected = true;
    }
}
