/* Glue between the entry form and the rich text editor (DWEditor, the
 * ProseMirror bundle in js/vendor/dw-editor.js). Mounts the editor over the
 * #entry-body textarea whenever the format select is on 'rte1', and unmounts
 * it (writing the HTML back into the textarea) for any other format.
 *
 * Changing the format converts the text explicitly, so nothing is lost or
 * silently reinterpreted: see the notes on casual HTML and Markdown in
 * src/editor/src/serialize.js. Copyright (c) 2026 by Dreamwidth Studios, LLC.
 * Same terms as Perl itself.
 */

(function () {
    var BODY_ID = 'entry-body';

    var conf = (window.postFormInitData && postFormInitData.dwEditor) || {};
    var strings = conf.strings || {};

    window.addEventListener('DOMContentLoaded', function () {
        var select = document.getElementById('editor');
        if (!select || !window.DWEditor) return;

        // An entry or draft written in the retired editor (rte0) is loaded as
        // rte1; its text is still rte0 source until the editor has converted
        // it. The page marks that with data-source on the warning.
        var warning = document.getElementById('js-rte0-warning');
        var pendingSource = warning && warning.getAttribute('data-source') == '1' ? 'rte0' : '';

        // Read the format here, not at script load: a restored draft may
        // have changed the selection without firing a change event.
        var lastFormat = select.value;

        function mount(fromFormat) {
            DWEditor.mount(BODY_ID, {
                circleUrl: conf.circleUrl,
                strings: strings,
                icons: conf.icons,
                pollUrl: conf.pollUrl,
                canEmbed: conf.canEmbed,
                fromFormat: fromFormat,

                // The page's image modal (which also serves the plain editor).
                onImage: window.DWImageInsert ? DWImageInsert.open : null,

                // Every edit, so autosave's own debouncing sees continuous typing.
                onInput: window.LJDraft ? LJDraft.handleInput : null
            });
        }

        if (lastFormat == 'rte1') {
            mount(pendingSource || lastFormat);
            pendingSource = '';
        }

        // Capture phase, so this runs before the other change handlers on the
        // select and can veto the change.
        select.addEventListener('change', function (event) {
            var format = select.value;
            var prev = lastFormat;
            if (format == prev) return;

            if (format == 'rte1' && prev == 'markdown0' && !window.confirm(strings.markdownConfirm)) {
                // Declined: put the select back and keep anything else from
                // reacting to the change.
                select.value = prev;
                event.stopImmediatePropagation();
                return;
            }

            lastFormat = format;

            if (format == 'rte1' && !DWEditor.isActive(BODY_ID)) {
                mount(pendingSource || prev);
                pendingSource = '';
            } else if (format != 'rte1' && DWEditor.isActive(BODY_ID)) {
                DWEditor.unmount(BODY_ID, { toFormat: format });
                pendingSource = '';
            }
        }, true);
    });
})();
