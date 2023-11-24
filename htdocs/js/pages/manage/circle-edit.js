$(".sub-box").on("change", function () {
    let match = this.name.match(/\d+/);
    let id = match[0];
    if (this.checked && id) {
        let bg_color = $(`editfriend_add_${id}_bg`).val();
        let fg_color = $(`editfriend_add_${id}_fg`).val();
        let swatch = $(`#swatch-${id}`);
        swatch.removeClass("hidden").css({ 'background-color': bg_color, 'color': fg_color });
    } else if (id) {
        $(`#swatch-${id}`).addClass("hidden");
    }

});

$(".bg-color").on("change", function () {
    let match = this.name.match(/\d+/);
    let id = match[0];
    if (id) {
        let bg_color = this.value;
        $(`#swatch-${id}`).css('background-color', bg_color);
    }
});

$(".fg-color").on("change", function () {
    let match = this.name.match(/\d+/);
    let id = match[0];
    if (id) {
        let fg_color = this.value;
        $(`#swatch-${id}`).css('color', fg_color);
    }
});

Coloris({
    el: '.coloris',
    swatches: colors,
    theme: 'polaroid',
    swatchesOnly: true
  });