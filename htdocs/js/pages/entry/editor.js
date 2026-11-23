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
        // implementation, the cleaner's own rules). While it runs, the page keeps
        // the OLD format selected and the OLD text in the box: they are what a
        // submit or an autosave sees, and they are still a matching pair. Only
        // when the converted text arrives do the text and the new format switch
        // together, and only then does the rest of the change handling (autosave,
        // the simple layout's tabs) hear about it. Any other format change in
        // the meantime, or a failure, abandons the pending conversion.
        var CASUAL_SOURCE = { html_casual1: 1, html_casual0: 1 };
        var conversion = 0;   // number of the conversion allowed to finish

        function convertThenMount(from) {
            var textarea = document.getElementById(BODY_ID);
            var mine = ++conversion;
            textarea.readOnly = true;   // keep the text still while it's converted

            function finish() {
                if (mine == conversion) textarea.readOnly = false;
            }

            fetch('/__rpc_entry_convert', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({ text: textarea.value, from: from })
            }).then(function (res) {
                return res.ok ? res.json() : {};
            }).then(function (data) {
                if (mine != conversion) return;   // superseded: ignore
                if (typeof data.text != 'string') throw new Error('no text');

                textarea.value = data.text;
                textarea.readOnly = false;
                select.value = 'rte1';
                lastFormat = 'rte1';
                mount('rte1');

                var again = new Event('change', { bubbles: true });
                again.dwConverted = true;
                select.dispatchEvent(again);
            }).catch(function () {
                if (mine != conversion) return;
                finish();
                window.alert(strings.convertFailed);   // the old format stays selected
            });
        }

        // Capture phase, so this runs before the other change handlers on the
        // select and can veto the change.
        select.addEventListener('change', function (event) {
            if (event.dwConverted) return;   // our own re-dispatch, see above

            var format = select.value;
            var prev = lastFormat;

            // Whatever was being converted is no longer what was asked for.
            if (format != prev || conversion) {
                conversion++;
                document.getElementById(BODY_ID).readOnly = false;
            }
            if (format == prev) return;

            if (format == 'rte1' && prev == 'markdown0' && !window.confirm(strings.markdownConfirm)) {
                // Declined: put the select back and keep anything else from
                // reacting to the change.
                select.value = prev;
                event.stopImmediatePropagation();
                return;
            }

            if (format == 'rte1' && CASUAL_SOURCE[prev] && !DWEditor.isActive(BODY_ID)) {
                // Not switched yet: put the old format back until it's converted.
                event.stopImmediatePropagation();
                select.value = prev;
                convertThenMount(prev);
                return;
            }

            lastFormat = format;

            if (format == 'rte1' && !DWEditor.isActive(BODY_ID)) {
                mount(prev);
            } else if (format != 'rte1' && DWEditor.isActive(BODY_ID)) {
                DWEditor.unmount(BODY_ID, { toFormat: format });
            }
        }, true);
    });
})();
