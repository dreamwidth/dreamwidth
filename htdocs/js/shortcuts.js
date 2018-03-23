/*
 * This checks the dw_shortcuts object and connects the provided keybindings/
 * touch gestures (if any) with the supplied function.
 */
var dw_gesture_registered = false;
var dw_gesture = {};

// this should be called by any keyboard/touch shortcut
function dw_register_shortcut(scName, scFunction) {
    // check to see if the text shortcut is enabled
    if ( typeof dw_shortcuts.keyboard != 'undefined' && typeof dw_shortcuts.keyboard[scName] != 'undefined' ) {
        Mousetrap.bind(dw_shortcuts.keyboard[scName], scFunction);
    }
    if ( typeof dw_shortcuts.touch != 'undefined' && typeof dw_shortcuts.touch[scName] != 'undefined' ) {
        var gestureSplit = dw_shortcuts.touch[scName].split(",");

        if ( gestureSplit[0] != 'disabled' ) {
            if ( ! dw_gesture_registered ) {
                // only register the swipe event once
                $(document).swipe( {
                    swipe: function(event, direction, distance, duration, fingerCount, fingerData) {
                        // since we only register the swipe once, we have to
                        // save the action in a map and see if it matches
                        // at event-time
                        directionConfig = dw_gesture[direction];
                        if (directionConfig != null) {
                            fingerAction = directionConfig[fingerCount];
                            if (fingerAction != null) {
                                fingerAction(event);
                            }
                        }
                    },
                    threshold:5,
                    fingers:'all',
                    fallbackToMouseEvents: false,
                    preventDefaultEvents: false,
                    preventDefaultMethod: function(event, direction, fingerCount) {
                        directionConfig = dw_gesture[direction];
                        if (directionConfig != null) {
                            fingerConfig = directionConfig[fingerCount];
                            if (fingerConfig != null) {
                                return true;
                            }
                        }
                        return false;
                    }
                });
                dw_gesture_registered = true;
            }

            var gesture = gestureSplit[0];
            var fingerCount = gestureSplit[1];
            var direction = gestureSplit[2];

            var directionConfig = dw_gesture[direction];
            if (directionConfig == null) {
                directionConfig = {};
                dw_gesture[direction] = directionConfig;
            }
            directionConfig[fingerCount] = scFunction;
        }
    }
}
