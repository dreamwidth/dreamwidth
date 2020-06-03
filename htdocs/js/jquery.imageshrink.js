// Helper for shrinking images in entry/comment content. The actual Squish is
// pure CSS; this just handles adding and removing classes to support:
// - Zooming (on click)
// - Exempting decorative markup from Squish (should be pure CSS, but can't yet)
// - Hiding zoom cursors for images that won't zoom
jQuery(function($) {

    // First: Basic click-to-zoom. (.imageshrink-expanded on/off)
    $(document).on('click', '.entry-content img, .comment-content img', function(e) {
        var $that = $(e.target);
        if ( ! $that.is('a img, .poll-response img, .imageshrink-actualsize') ) {
            $that.toggleClass('imageshrink-expanded');
        }
    });

    // Second: Exempt codes from the squish. (.imageshrink-exempt on/off)
    // Only shrink casual pics; leave artisanal HTML alone. Can't predict
    // everything, but 99% of the time that's a <div style="..."> or a table.
    function protectTheCodes(container) {
        // Expanded cut tags have style='display: block', but aren't decorations.
        // Feeds (.journal-type-Y) always make a mess, so no mercy.
        var exemptImages = container.querySelectorAll(
            '.journal-type-P .entry-content div[style]:not(.cuttag-open) img, ' +
            '.journal-type-P .entry-content table img, ' +
            '.journal-type-C .entry-content div[style]:not(.cuttag-open) img, ' +
            '.journal-type-C .entry-content table img, ' +
            '.comment-content div[style] img, ' +
            '.comment-content table img'
        );
        for (var i = 0; i < exemptImages.length; i++) {
            exemptImages[i].classList.add('imageshrink-exempt');
        }
    }

    // Check the whole document to start with.
    protectTheCodes(document);

    // Third: Don't show zoom cursors for non-zooming images (.imageshrink-actualsize on/off)

    // Dummied out observeImages function, to simplify browser support in (Fourth).
    var observeImages = function(container) {return;};

    if (typeof ResizeObserver === 'function') {
        var zoomCursorCleaner = new ResizeObserver(function(resizeList, observer) {
            resizeList.forEach(function(entry) {
                var img = entry.target;
                if (img.tagName !== 'IMG') { return; }

                // Zoomed images don't count.
                if ( ! img.classList.contains('imageshrink-expanded')
                    && img.width === img.naturalWidth
                    && img.height === img.naturalHeight
                ) {
                    img.classList.add('imageshrink-actualsize');
                } else {
                    img.classList.remove('imageshrink-actualsize');
                }
            });
        });

        // And now the real version:
        observeImages = function(container) {
            let images = container.querySelectorAll('.entry-content img, .comment-content img');
            // Anything with ResizeObserver definitely has NodeList.forEach.
            images.forEach(function(img) {
                zoomCursorCleaner.observe(img);
            });
        }

        // Check the whole document to start with.
        observeImages(document);
    }

    // Fourth: Repeat (Second) and (Third) when adding images to the page.
    // (Via cut tags, comment expansion, or image placeholders.)
    if (typeof MutationObserver === 'function') {
        var imageUpdater = new MutationObserver(function(mutationList, observer) {
            mutationList.forEach(function(mutation) {
                if (mutation.addedNodes.length > 0) {
                    protectTheCodes(mutation.target);
                    observeImages(mutation.target);
                }
            });
        });

        var opts = {childList: true, subtree: true};
        var entries = document.getElementById('entries');
        var comments = document.getElementById('comments');
        if (entries) {
            imageUpdater.observe(entries, opts);
        }
        if (comments) {
            imageUpdater.observe(comments, opts);
        }
    }

});
