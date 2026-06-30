/* Glue between the entry form and the rich text editor (DWEditor, the
 * ProseMirror bundle in js/vendor/dw-editor.js). Mounts the editor over the
 * #entry-body textarea whenever the format select is on 'rte1', and unmounts
 * it (serializing back into the textarea) for any other format.
 *
 * This script's change listener must attach BEFORE rte.js's (it's listed
 * earlier in form.tt), so that when switching away from rte1 we flush the
 * textarea before the old FCK editor reads it. In the other direction —
 * old RTE to rte1 — the mount is deferred a tick so rte.js's usePlainText
 * has written FCK's content back to the textarea before we import it.
 */

(function () {
    var BODY_ID = 'entry-body';

    // Formats where plain newlines are meaningful (the server adds <br>);
    // switching from one of these materializes them into explicit <br />.
    var LINEBREAK_FORMATS = { html_casual1: 1, html_casual0: 1, markdown0: 1 };

    var conf = (window.postFormInitData && postFormInitData.dwEditor) || {};
    var lastFormat = null;

    function mount(prevFormat) {
        DWEditor.mount(BODY_ID, {
            circleUrl: conf.circleUrl,
            strings: conf.strings,
            onInput: window.LJDraft ? LJDraft.handleInput : null,
            materializeLinebreaks: !!LINEBREAK_FORMATS[prevFormat]
        });
    }

    window.addEventListener('DOMContentLoaded', function () {
        var select = document.getElementById('editor');
        if (!select || !window.DWEditor) return;

        // Read the format here, not at script load: a restored draft may
        // have changed the selection without firing a change event.
        lastFormat = select.value;
        if (lastFormat == 'rte1') mount(lastFormat);

        select.addEventListener('change', function () {
            var format = select.value;
            var prev = lastFormat;
            lastFormat = format;

            if (format == 'rte1' && !DWEditor.isActive(BODY_ID)) {
                // Deferred so rte.js's own change handler (which runs after
                // this one) can tear down FCK and restore the textarea first.
                setTimeout(function () {
                    if (select.value == 'rte1' && !DWEditor.isActive(BODY_ID))
                        mount(prev);
                }, 0);
            } else if (format != 'rte1' && DWEditor.isActive(BODY_ID)) {
                DWEditor.unmount(BODY_ID);
            }
        });
    });
})();
