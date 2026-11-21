jQuery(document).ready(function($) {
    var reveal = '[data-reveal]';
    var active = '[data-reveal].open:not(.toback), [data-reveal][aria-modal="true"]:not(.toback)';

    function tabOrder(element) {
        return element.tabIndex > 0 ? element.tabIndex : Infinity;
    }

    function tabStops(modal) {
        var controls = $(modal).find('a[href], area[href], input, select, textarea, button, summary, [tabindex]')
            .filter(function() {
                return this.tabIndex >= 0 && !this.matches(':disabled, input[type="hidden"]') &&
                    !this.closest('[inert]') && this.getClientRects().length &&
                    window.getComputedStyle(this).visibility === 'visible';
            }).get().sort(function(first, second) {
                return tabOrder(first) - tabOrder(second);
            });

        return controls.filter(function(control) {
            if (control.type !== 'radio' || !control.name) return true;

            var group = controls.filter(function(candidate) {
                return candidate.type === 'radio' && candidate.name === control.name &&
                    candidate.form === control.form;
            });
            var checked = group.find(function(radio) { return radio.checked; });
            return control === (checked || group[0]);
        });
    }

    $(document)
        .on('open.fndtn.reveal', reveal, function(event, opener) {
            if (event.namespace !== 'fndtn.reveal') return;

            $(this).data('revealFocus', {
                opener: opener || document.activeElement,
                role: this.getAttribute('role'),
                hidden: this.getAttribute('aria-hidden'),
                tabIndex: this.getAttribute('tabindex')
            });
        })
        .on('opened.fndtn.reveal', reveal, function(event) {
            if (event.namespace !== 'fndtn.reveal') return;

            $(this).attr({ role: 'dialog', 'aria-modal': 'true', 'aria-hidden': 'false', tabindex: '-1' });
            if (!this.contains(document.activeElement)) {
                var stops = tabStops(this);
                var preferred = stops.find(function(control) { return control.hasAttribute('autofocus'); }) ||
                    stops.find(function(control) { return control.tagName === 'INPUT'; });
                (preferred || stops[0] || this).focus();
            }
        })
        .on('closed.fndtn.reveal', reveal, function(event) {
            if (event.namespace !== 'fndtn.reveal') return;

            var $modal = $(this);
            var state = $modal.data('revealFocus');
            if (!state) return;

            $modal.removeAttr('aria-modal').attr({
                role: state.role,
                'aria-hidden': state.hidden,
                tabindex: state.tabIndex
            }).removeData('revealFocus');
            if (state.opener && !$(active).not(this).length) state.opener.focus();
        })
        .on('keydown.dwRevealFocus', function(event) {
            if (event.key !== 'Tab' || event.altKey || event.ctrlKey || event.metaKey || event.isDefaultPrevented()) return;

            var modal = $(active).last()[0];
            if (!modal) return;

            event.preventDefault();
            if (!modal.hasAttribute('aria-modal')) return;

            var stops = tabStops(modal);
            if (!stops.length) {
                modal.focus();
                return;
            }
            var current = stops.indexOf(document.activeElement);
            var next = event.shiftKey
                ? (current <= 0 ? stops.length - 1 : current - 1)
                : (current + 1) % stops.length;
            stops[next].focus();
        });
});
