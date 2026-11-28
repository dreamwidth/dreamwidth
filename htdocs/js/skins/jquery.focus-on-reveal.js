jQuery(document).ready(function($) {
    var reveal = '[data-reveal]';
    var stack = [];
    var controlSelector = 'a[href], area[href], input, select, textarea, button, summary, [tabindex]';

    function foreground() {
        return stack[stack.length - 1];
    }

    function canFocus(element) {
        return element && element.isConnected && !element.matches(':disabled, input[type="hidden"]') &&
            !element.closest('[hidden], [inert]') && element.getClientRects().length &&
            window.getComputedStyle(element).visibility === 'visible';
    }

    function focusElement(element) {
        if (!canFocus(element)) return false;
        element.focus();
        return document.activeElement === element;
    }

    function tabOrder(element) {
        return element.tabIndex > 0 ? element.tabIndex : Infinity;
    }

    function tabStops(modal) {
        var controls = $(modal).find(controlSelector)
            .filter(function() {
                return this.tabIndex >= 0 && canFocus(this);
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

    function focusInitial(modal) {
        var stops = tabStops(modal);
        var preferred = stops.find(function(control) { return control.hasAttribute('autofocus'); }) ||
            stops.find(function(control) { return control.tagName === 'INPUT'; });
        focusElement(preferred || stops[0]) || focusElement(modal);
    }

    function focusPage() {
        var landmarks = document.querySelectorAll('#content, main');
        if (Array.prototype.some.call(landmarks, function(landmark) {
            if (!canFocus(landmark) || landmark.closest(reveal)) return false;
            if (!landmark.hasAttribute('tabindex')) landmark.setAttribute('tabindex', '-1');
            return focusElement(landmark);
        })) return;

        tabStops(document.body).some(function(control) {
            return !control.closest(reveal) && focusElement(control);
        });
    }

    $(document)
        .on('open.fndtn.reveal', reveal, function(event, opener) {
            if (event.namespace !== 'fndtn.reveal' || event.target !== this) return;

            var $modal = $(this);
            if ($modal.data('revealFocus')) return;
            var previous = foreground();
            var settings = $modal.data('reveal-init') || window.Foundation.libs.reveal.settings;
            opener = opener || document.activeElement;
            if (previous) {
                previous.removeAttribute('aria-modal');
                if (!settings.multiple_opened) {
                    for (var index = stack.length - 1; index >= 0; index--) {
                        if (stack[index].contains(opener)) opener = $(stack[index]).data('revealFocus').opener;
                    }
                    stack.length = 0;
                }
            }

            $modal.data('revealFocus', {
                opener: opener,
                role: this.getAttribute('role'),
                hidden: this.getAttribute('aria-hidden'),
                tabIndex: this.getAttribute('tabindex')
            }).attr({ role: 'dialog', 'aria-hidden': 'false', 'aria-modal': 'true', tabindex: '-1' });
            stack.push(this);
        })
        .on('opened.fndtn.reveal', reveal, function(event) {
            if (event.namespace !== 'fndtn.reveal' || event.target !== this || !$(this).data('revealFocus')) return;

            if (this !== foreground()) return;
            if (!this.contains(document.activeElement)) focusInitial(this);
        })
        .on('closed.fndtn.reveal', reveal, function(event) {
            if (event.namespace !== 'fndtn.reveal' || event.target !== this) return;

            var $modal = $(this);
            var state = $modal.data('revealFocus');
            if (!state) return;

            var returnFocus = $modal.data('revealReturnFocus');
            $modal.removeAttr('aria-modal').attr({
                role: state.role,
                'aria-hidden': state.hidden,
                tabindex: state.tabIndex
            }).removeData('revealFocus revealReturnFocus');

            var index = stack.indexOf(this);
            if (index === -1) return;
            stack.splice(index, 1);
            var resumed = foreground();
            if (index !== stack.length) return;

            queueMicrotask(function() {
                if (foreground() !== resumed) return;
                if (resumed) {
                    resumed.setAttribute('aria-modal', 'true');
                    if (!(resumed.contains(returnFocus) && focusElement(returnFocus)) &&
                        !(resumed.contains(state.opener) && focusElement(state.opener))) focusInitial(resumed);
                } else if (!focusElement(returnFocus) && !focusElement(state.opener)) {
                    focusPage();
                }
            });
        })
        .on('keydown.dwRevealFocus', function(event) {
            if (event.key !== 'Tab' || event.altKey || event.ctrlKey || event.metaKey || event.isDefaultPrevented()) return;

            var modal = foreground();
            if (!modal) return;

            event.preventDefault();
            if (!canFocus(modal)) return;

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
