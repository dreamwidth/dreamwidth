function photobucket_complete(inurl, width, height)
{
    // Special handling for RTE image chooser
    if (window.inRTE && window.inRTE == true) {
        GetE('txtUrl').value = inurl;
        GetE('txtWidth').value = width;
        GetE('txtHeight').value = height;
        parent.Ok();
        return;
    }

    // Handling for non-RTE editor
    if (window.parent.parent && window.parent.parent.InOb) {
        window.parent.parent.InOb.onInsURL(inurl, width, height);
        // Timeout used to prevent Firefox from spinning
        setTimeout(function () { window.parent.parent.InOb.onClosePopup(); }, 100);
    } else if (window.parent && window.parent.InOb) {
        window.parent.InOb.onInsURL(inurl, width, height);
        // Timeout used to prevent Firefox from spinning
        setTimeout(function () { window.parent.InOb.onClosePopup(); }, 100);
    }
}
