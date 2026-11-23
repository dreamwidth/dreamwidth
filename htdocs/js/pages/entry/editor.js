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
        // implementation, the cleaner's own rules). While it runs the body area is
        // in a plain "busy" state: a "Converting..." layer covers it, so nothing
        // can write to the body (typing, the Insert Image dialog), and the old
        // format stays selected with the old text in the box -- a matching pair,
        // which is all a submit or autosave can see. Picking another format or tab,
        // or pressing Cancel, abandons the conversion and leaves things exactly as
        // they were. Only when the converted text arrives do the text and the new
        // format switch together, and only then is the change announced (autosave,
        // the simple layout's tabs).
        var CASUAL_SOURCE = { html_casual1: 1, html_casual0: 1 };
        var CONVERT_TIMEOUT = 10000;
        var pending = null;   // { cancel: function } while a conversion is running

        // Other scripts ask before they write to the body (image-insert.js) and
        // cancel on a tab click (simple.js).
        window.DWConvert = {
            busy: function () { return !!pending; },
            cancel: function () { if (pending) pending.cancel(); }
        };

        function convertThenMount(from) {
            var textarea = document.getElementById(BODY_ID);
            var sent = textarea.value;
            var controller = new AbortController();
            var finished = false;

            // The busy layer.
            var host = textarea.parentNode;
            var layer = document.createElement('div');
            layer.className = 'dw-editor-busy';
            layer.setAttribute('role', 'status');
            var label = document.createElement('span');
            label.textContent = strings.converting;
            var cancel = document.createElement('button');
            cancel.type = 'button';
            cancel.className = 'button secondary';
            cancel.textContent = strings.cancel;
            layer.appendChild(label);
            layer.appendChild(cancel);
            host.classList.add('dw-editor-busy-host');
            host.appendChild(layer);
            textarea.readOnly = true;

            function end() {
                if (finished) return false;
                finished = true;
                clearTimeout(timer);
                layer.remove();
                host.classList.remove('dw-editor-busy-host');
                textarea.readOnly = false;
                pending = null;
                return true;
            }

            function fail() {
                if (end()) window.alert(strings.convertFailed);   // the old format stays
            }

            var timer = setTimeout(function () { controller.abort(); }, CONVERT_TIMEOUT);
            pending = {
                cancel: function () {
                    controller.abort();
                    end();
                }
            };
            cancel.addEventListener('click', pending.cancel);

            fetch('/__rpc_entry_convert', {
                method: 'POST',
                credentials: 'same-origin',
                signal: controller.signal,
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({ text: sent, from: from })
            }).then(function (res) {
                return res.ok ? res.json() : {};
            }).then(function (data) {
                if (finished) return;   // cancelled or already failed
                if (typeof data.text != 'string' || textarea.value != sent) throw new Error('stale');

                end();
                textarea.value = data.text;
                select.value = 'rte1';
                lastFormat = 'rte1';
                mount('rte1');

                var again = new Event('change', { bubbles: true });
                again.dwConverted = true;
                select.dispatchEvent(again);
            }).catch(function () {
                fail();
            });
        }

        // Capture phase, so this runs before the other change handlers on the
        // select and can veto the change.
        select.addEventListener('change', function (event) {
            if (event.dwConverted) return;   // our own re-dispatch, see above

            var format = select.value;
            var prev = lastFormat;

            // Whatever was being converted is no longer what was asked for.
            if (pending) pending.cancel();
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
