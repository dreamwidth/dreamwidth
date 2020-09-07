// Helper for shrinking images in entry/comment content. The actual Squish is
// pure CSS; this just handles adding and removing classes to support:
// - Zooming (on click)
// - Exempting decorative markup from Squish (should be pure CSS, but can't yet)
// - Hiding zoom cursors for images that won't zoom
// - Marking tall images so they get modified squish behavior
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

    // Dummied out observeImages function, to simplify browser support in (Fifth).
    var observeImages = function(container) {return;};

    if (typeof ResizeObserver === 'function') {
        var imageShrinkResizeObserver = new ResizeObserver(function(resizeList, observer) {
            resizeList.forEach(function(entry) {
                var img = entry.target;
                if (img.tagName !== 'IMG') { return; }

                // Third: Skip zoom cursors for images that won't zoom (.imageshrink-actualsize on/off)
                // "Won't zoom" means it's in its "shrunk" state and is already
                // either "natural" full size or "requested" full size (as per
                // the height/width attributes).
                // "Natural" is easy:
                var isNaturalSize = img.width === img.naturalWidth && img.height === img.naturalHeight;
                // "Requested" is hard. `object-fit: contain` w/ max-height means
                // layout width might be wider than visible width. There's no way
                // to directly measure visible width, and of course that's the one
                // we care about. Plus maybe they only set one attribute. So we
                // measure indirectly: if the layout aspect ratio doesn't match the
                // natural aspect ratio (+/- some slop bc floats), it CAN'T be the
                // requested size. (And at least one dimension has to match.)
                // And yes, this ignores the use case of deliberately mutilating the
                // aspect ratio for comedy; use something other than the height/width
                // attrs for that.
                var attrWidth = parseInt(img.getAttribute('width'));
                var attrHeight = parseInt(img.getAttribute('height'));
                var isRequestedSize =
                    (    ( !isNaN(attrWidth) && attrWidth === img.width )
                      || ( !isNaN(attrHeight) && attrHeight === img.height )
                    )
                    && Math.abs( (img.height / img.width) - (img.naturalHeight / img.naturalWidth) ) < 0.004;
                    // Might want to tune that slop later. Or hey, maybe I nailed it. -NF

                var isActualSize = isNaturalSize || isRequestedSize;

                if ( isActualSize && ! img.classList.contains('imageshrink-expanded') ) {
                    img.classList.add('imageshrink-actualsize');
                } else {
                    img.classList.remove('imageshrink-actualsize');
                }

                // Fourth: Mark tall images so we can let them scroll. Doing
                // this in the ResizeObserver because images have unknown natural
                // aspect ratios until load & decode; they'll fire a resize once
                // the browser sorts it out.
                if ( (img.naturalHeight / img.naturalWidth) >= 2 ) {
                    img.classList.add('imageshrink-tall');
                } else {
                    img.classList.remove('imageshrink-tall');
                }
            });
        });

        // And now the real version:
        observeImages = function(container) {
            let images = container.querySelectorAll('.entry-content img, .comment-content img');
            // Anything with ResizeObserver definitely has NodeList.forEach.
            images.forEach(function(img) {
                imageShrinkResizeObserver.observe(img);
            });
        }

        // Check the whole document to start with.
        observeImages(document);
    }

    // Fifth: Repeat (Second), (Third), (Fourth) when adding images to the page.
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
