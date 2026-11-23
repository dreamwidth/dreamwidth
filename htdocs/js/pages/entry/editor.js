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
                onInput: window.LJDraft ? LJDraft.richInput : null
            });
        }

        if (lastFormat == 'rte1') {
            mount(lastFormat);
        }

        // Casual HTML's line breaks, auto-links and @mentions are worked out by
        // the server's cleaner, so the server does the conversion (one
        // implementation, the cleaner's own rules). The rest of the change
        // handling waits for it: otherwise autosave would store the unconverted
        // text as rich text.
        var CASUAL_SOURCE = { html_casual1: 1, html_casual0: 1 };

        function convertThenMount(from) {
            var textarea = document.getElementById(BODY_ID);
            select.disabled = true;
            textarea.readOnly = true;

            function done() {
                select.disabled = false;
                textarea.readOnly = false;
                var again = new Event('change', { bubbles: true });
                again.dwConverted = true;
                select.dispatchEvent(again);
            }

            fetch('/__rpc_entry_convert', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({ text: textarea.value, from: from })
            }).then(function (res) {
                return res.ok ? res.json() : {};
            }).then(function (data) {
                if (typeof data.text == 'string') {
                    textarea.value = data.text;
                    mount('rte1');
                } else {
                    mount(from);   // the editor's own, simpler conversion
                }
            }).catch(function () {
                mount(from);
            }).then(done);
        }

        // Capture phase, so this runs before the other change handlers on the
        // select and can veto the change.
        select.addEventListener('change', function (event) {
            if (event.dwConverted) return;   // our own re-dispatch, see above

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

            if (format == 'rte1' && CASUAL_SOURCE[prev] && !DWEditor.isActive(BODY_ID)) {
                event.stopImmediatePropagation();
                convertThenMount(prev);
            } else if (format == 'rte1' && !DWEditor.isActive(BODY_ID)) {
                mount(prev);
            } else if (format != 'rte1' && DWEditor.isActive(BODY_ID)) {
                DWEditor.unmount(BODY_ID, { toFormat: format });
            }
        }, true);
    });
})();
