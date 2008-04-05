// This library will provide handy functionality to a contextual prodding
// box on a page.

CProd = new Object;
CProd.hourglass = null;

// show the next tip
CProd.next = function (evt) {
  var prodClassElement = $("CProd_class");
  var prodStyleElement = $("CProd_style");
  var prodClass, prodStyle;

  if (prodClassElement)
    prodClass = prodClassElement.innerHTML;

  if (prodStyleElement)
    prodStyle = prodStyleElement.innerHTML;

  var data = HTTPReq.formEncoded({
      "class": prodClass,
          "content": "framed",
          "style": prodStyle
          });

  var req = HTTPReq.getJSON({
      "url": "/tools/endpoints/cprod.bml",
      "method": "GET",
        "data": data,
      "onData": CProd.gotData
  });

  Event.prep(evt);
  var pos = DOM.getAbsoluteCursorPosition(evt);
  if (!pos) return;

  if (!CProd.hourglass) {
    CProd.hourglass = new Hourglass();
    CProd.hourglass.init();
    CProd.hourglass.hourglass_at(pos.x, pos.y);
  } else {
    CProd.hourglass.hourglass_at(pos.x, pos.y);
  }
}

// got the next tip
CProd.gotData = function (res) {
  if (CProd.hourglass)
    CProd.hourglass.hide();

  if (!res || !res.content) return;

  var cprodbox = $("CProd_box");
  if (!cprodbox) return;

  cprodbox.innerHTML = res.content;

  CProd.attachNextClickListener();
}

// attach onclick listener to the "next" button
CProd.attachNextClickListener = function () {
  var nextBtn = $("CProd_nextbutton");

  DOM.addEventListener(nextBtn, "click", CProd.next.bindEventListener());
}

DOM.addEventListener(window, "load", function () {
  CProd.attachNextClickListener();
});
