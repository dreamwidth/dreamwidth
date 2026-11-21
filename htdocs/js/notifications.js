document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('#notification-settings fieldset').forEach(function (category) {
        const selectAllLabel = category.querySelector('[data-email-select-all]');
        const selectAll = selectAllLabel && selectAllLabel.querySelector('input');
        const eligibleEmail = function () {
            return Array.from(category.querySelectorAll('[data-notification-email]:not([hidden]) input.notification-email:not(:disabled)'));
        };
        const updateSelectAll = function () {
            if (!selectAll) return;
            const options = eligibleEmail();
            const checked = options.filter(function (option) { return option.checked; }).length;
            selectAllLabel.hidden = !options.length;
            selectAll.checked = checked > 0 && checked === options.length;
            selectAll.indeterminate = checked > 0 && checked < options.length;
        };

        category.querySelectorAll('[data-notification-row]').forEach(function (row) {
            const inbox = row.querySelector('input.notification-inbox');
            const email = row.querySelector('[data-notification-email]');
            if (!email) return;
            const updateEmail = function () {
                email.hidden = !inbox.checked;
            };
            inbox.addEventListener('change', function () {
                updateEmail();
                updateSelectAll();
            });
            email.addEventListener('change', updateSelectAll);
            updateEmail();
        });

        if (selectAll) {
            updateSelectAll();
            selectAll.addEventListener('change', function () {
                eligibleEmail().forEach(function (option) { option.checked = selectAll.checked; });
                updateSelectAll();
            });
        }
    });

    document.querySelectorAll('#settings_form [data-confirm]').forEach(function (button) {
        button.addEventListener('click', function (event) {
            if (!window.confirm(button.dataset.confirm)) event.preventDefault();
        });
    });
});
