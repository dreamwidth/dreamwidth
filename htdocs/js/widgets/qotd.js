var QotD = new Object();

QotD.init = function () {
    QotD.skip = 0;
    QotD.domain = "homepage";

    if (! $('prev_questions')) return;
    if (! $('next_questions')) return;
    if (! $('prev_questions_disabled')) return;
    if (! $('next_questions_disabled')) return;

    if ($('vertical_name')) {
        QotD.domain = $('vertical_name').value;
    }

    DOM.addEventListener($('prev_questions'), "click", QotD.prevQuestions);
    DOM.addEventListener($('next_questions'), "click", QotD.nextQuestions);

    QotD.checkDirections();
}

QotD.checkDirections = function () {
    QotD.tryForQuestions("prev");
    QotD.tryForQuestions("next");
}

QotD.prevQuestions = function () {
    QotD.skip = QotD.skip + 1;
    QotD.getQuestions();
}

QotD.nextQuestions = function () {
    if (QotD.skip > 0) {
        QotD.skip = QotD.skip - 1;
    }
    QotD.getQuestions();
}

QotD.tryForQuestions = function (direction) {
    if (QotD.skip == 0 && direction == "next") {
        $('next_questions').style.display = "none";
        $('next_questions_disabled').style.display = "inline";
        return;
    }

    var skip;
    if (direction == "prev") {
        skip = QotD.skip + 1;
    } else {
        skip = QotD.skip - 1;
    }

    HTTPReq.getJSON({
        url: LiveJournal.getAjaxUrl("qotd"),
        method: "GET",
        data: HTTPReq.formEncoded({ skip: skip, domain: QotD.domain }),
        onData: function (data) {
            if (data.text) {
                if (direction == "prev") {
                    $('prev_questions_disabled').style.display = "none";
                    $('prev_questions').style.display = "inline";
                } else {
                    $('next_questions_disabled').style.display = "none";
                    $('next_questions').style.display = "inline";
                }
            } else {
                if (direction == "prev") {
                    $('prev_questions').style.display = "none";
                    $('prev_questions_disabled').style.display = "inline";
                } else {
                    $('next_questions').style.display = "none";
                    $('next_questions_disabled').style.display = "inline";
                }
            }
        },
        onError: function (msg) { }
    });
}

QotD.getQuestions = function () {
    HTTPReq.getJSON({
        url: LiveJournal.getAjaxUrl("qotd"),
        method: "GET",
        data: HTTPReq.formEncoded({skip: QotD.skip, domain: QotD.domain }),
        onData: QotD.printQuestions,
        onError: function (msg) { }
    });
}

QotD.printQuestions = function (data) {
    if (data.text || QotD.skip == 0) {
        $('all_questions').innerHTML = data.text;
    } else {
        if (QotD.skip > 0) {
            QotD.skip = QotD.skip - 1;
        }
    }

    QotD.checkDirections();
}

LiveJournal.register_hook("page_load", QotD.init);
