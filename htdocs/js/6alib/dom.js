/*
DOM Library - Copyright 2005 Six Apart
$Id: dom.js 261 2008-02-26 23:40:50Z janine $

Copyright (c) 2005, Six Apart, Ltd.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.

    * Neither the name of "Six Apart" nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/


/* Node class */

if( !defined( window.Node ) )
    Node = {};

try {
    OBJ.extend( Node, {
        ELEMENT_NODE: 1,
        ATTRIBUTE_NODE: 2,
        TEXT_NODE: 3,
        CDATA_SECTION_NODE: 4,  
        COMMENT_NODE: 8,    
        DOCUMENT_NODE: 9,
        DOCUMENT_FRAGMENT_NODE: 11
    } );
} catch( e ) {}


/* DOM class */

if( !defined( window.DOM ) )
    DOM = {};


OBJ.extend( DOM, {
    getElement: function( e ) {
        return (typeof e == "string" || typeof e == "number") ? document.getElementById( e ) : e;
    },


    addEventListener: function( e, eventName, func, useCapture ) {
        try {
            if( e.addEventListener )
                e.addEventListener( eventName, func, useCapture );
            else if( e.attachEvent )
                e.attachEvent( "on" + eventName, func );
            else
                e[ "on" + eventName ] = func;
        } catch( e ) {}
    },


    removeEventListener: function( e, eventName, func, useCapture ) {
        try {
            if( e.removeEventListener )
                e.removeEventListener( eventName, func, useCapture );
            else if( e.detachEvent )
                e.detachEvent( "on" + eventName, func );
            else
                e[ "on" + eventName ] = undefined;
        } catch( e ) {}
    },
    
    
    focus: function( e ) {
        try {
            e = DOM.getElement( e );
            e.focus();
        } catch( e ) {}
    },


    blur: function( e ) {
        try {
            e = DOM.getElement( e );
            e.blur();
        } catch( e ) {}
    },
    

    /* style */
    
    getComputedStyle: function( e ) {
        if( e.currentStyle )
            return e.currentStyle;
        var style = {};
        var owner = DOM.getOwnerDocument( e );
        if( owner && owner.defaultView && owner.defaultView.getComputedStyle ) {            
            try {
                style = owner.defaultView.getComputedStyle( e, null );
            } catch( e ) {}
        }
        return style;
    },


    getStyle: function( e, p ) {
        var s = DOM.getComputedStyle( e );
        return s[ p ];
    },


    // given a window (or defaulting to current window), returns
    // object with .x and .y of client's usable area
    getClientDimensions: function( w ) {
        if( !w )
            w = window;

        var d = {};

        // most browsers
        if( w.innerHeight ) {
            d.x = w.innerWidth;
            d.y = w.innerHeight;
            return d;
        }

        // IE6, strict
        var de = w.document.documentElement;
        if( de && de.clientHeight ) {
            d.x = de.clientWidth;
            d.y = de.clientHeight;
            return d;
        }

        // IE, misc
        if( document.body ) {
            d.x = document.body.clientWidth;
            d.y = document.body.clientHeight;
            return d;
        }
        
        return undefined;
    },


    getDimensions: function( e ) {
        if( !e )
            return undefined;

        var style = DOM.getComputedStyle( e );

        return {
            offsetLeft: e.offsetLeft,
            offsetTop: e.offsetTop,
            offsetWidth: e.offsetWidth,
            offsetHeight: e.offsetHeight,
            clientWidth: e.clientWidth,
            clientHeight: e.clientHeight,
            
            offsetRight: e.offsetLeft + e.offsetWidth,
            offsetBottom: e.offsetTop + e.offsetHeight,
            clientLeft: finiteInt( style.borderLeftWidth ) + finiteInt( style.paddingLeft ),
            clientTop: finiteInt( style.borderTopWidth ) + finiteInt( style.paddingTop ),
            clientRight: e.clientLeft + e.clientWidth,
            clientBottom: e.clientTop + e.clientHeight
        };
    },


    getAbsoluteDimensions: function( e ) {
        var d = DOM.getDimensions( e );
        if( !d )
            return d;
        d.absoluteLeft = d.offsetLeft;
        d.absoluteTop = d.offsetTop;
        d.absoluteRight = d.offsetRight;
        d.absoluteBottom = d.offsetBottom;
        var bork = 0;
        while( e ) {
            try { // IE 6 sometimes gives an unwarranted error ("htmlfile: Unspecified error").
                e = e.offsetParent;
            } catch ( err ) {
                log( "In DOM.getAbsoluteDimensions: " + err.message ); 
                if ( ++bork > 25 )
                    return null;
            }
            if( !e )
                return d;
            d.absoluteLeft += e.offsetLeft;
            d.absoluteTop += e.offsetTop;
            d.absoluteRight += e.offsetLeft;
            d.absoluteBottom += e.offsetTop;
        }
        return d;
    },
    
    
    getIframeAbsoluteDimensions: function( e ) {
        var d = DOM.getAbsoluteDimensions( e );
        if( !d )
            return d;
        var iframe = DOM.getOwnerIframe( e );
        if( !defined( iframe ) )
            return d;
        
        var d2 = DOM.getIframeAbsoluteDimensions( iframe );
        var scroll = DOM.getWindowScroll( iframe.contentWindow );
        var left = d2.absoluteLeft - scroll.left;
        var top = d2.absoluteTop - scroll.top;
        
        d.absoluteLeft += left;
        d.absoluteTop += top;
        d.absoluteRight += left;
        d.absoluteBottom += top;
        
        return d;
    },
    
    
    setLeft: function( e, v ) { e.style.left = finiteInt( v ) + "px"; },
    setTop: function( e, v ) { e.style.top = finiteInt( v ) + "px"; },
    setRight: function( e, v ) { e.style.right = finiteInt( v ) + "px"; },
    setBottom: function( e, v ) { e.style.bottom = finiteInt( v ) + "px"; },
    setWidth: function( e, v ) { e.style.width = max( 0, finiteInt( v ) ) + "px"; },
    setHeight: function( e, v ) { e.style.height = max( 0, finiteInt( v ) ) + "px"; },
    setZIndex: function( e, v ) { e.style.zIndex = finiteInt( v ); },


    getWindowScroll: function( w ) {
        var s = {
            left: 0,
            top: 0
        };

        if (!w) w = window;
        var d = w.document;
        var de = d.documentElement;

        // most browsers
        if ( defined( w.pageXOffset ) ) {
            s.left = w.pageXOffset;
            s.top = w.pageYOffset;
        }

        // ie
        else if( de && defined( de.scrollLeft ) ) {
            s.left = de.scrollLeft;
            s.top = de.scrollTop;
        }

        // safari
        else if( defined( w.scrollX ) ) {
            s.left = w.scrollX;
            s.top = w.scrollY;
        }

        // opera
        else if( d.body && defined( d.body.scrollLeft ) ) {
            s.left = d.body.scrollLeft;
            s.top = d.body.scrollTop;
        }


        return s;
    },


    getAbsoluteCursorPosition: function( event ) {
        event = event || window.event;
        var s = DOM.getWindowScroll( window );
        return {
            x: s.left + event.clientX,
            y: s.top + event.clientY
        };
    },
    
    
    invisibleStyle: {
        display: "block",
        position: "absolute",
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        margin: 0,
        border: 0,
        padding: 0,
        fontSize: "0.1px",
        lineHeight: 0,
        opacity: 0,
        MozOpacity: 0,
        filter: "alpha(opacity=0)"
    },
    
    
    makeInvisible: function( e ) {
        for( var p in this.invisibleStyle ) {
            if( this.invisibleStyle.hasOwnProperty( p ) )
                e.style[ p ] = this.invisibleStyle[ p ];
        }
    },


    /* text and selection related methods */

    mergeTextNodes: function( n ) {
        var c = 0;
        while( n ) {
            if( n.nodeType == Node.TEXT_NODE && n.nextSibling && n.nextSibling.nodeType == Node.TEXT_NODE ) {
                n.nodeValue += n.nextSibling.nodeValue;
                n.parentNode.removeChild( n.nextSibling );
                c++;
            } else {
                if( n.firstChild )
                    c += DOM.mergeTextNodes( n.firstChild );
                n = n.nextSibling;
            }
        }
        return c;
    },
    
    
    selectElement: function( e ) {  
        var d = e.ownerDocument;  
        
        // internet explorer  
        if( d.body.createControlRange ) {  
            var r = d.body.createControlRange();  
            r.addElement( e );  
            r.select();  
        }  
    }, 
    
    
    /* dom methods */
    
    isImmutable: function( n ) {
        try {
            if( n.getAttribute( "contenteditable" ) == "false" )
                return true;
        } catch( e ) {}
        return false;
    },
    
    
    getImmutable: function( n ) {
        var immutable = null;
        while( n ) {
            if( DOM.isImmutable( n ) )
                immutable = n;
            n = n.parentNode;
        }
        return immutable;
    },


    getOwnerDocument: function( n ) {
        if( !n )
            return document;
        if( n.ownerDocument )
            return n.ownerDocument;
        if( n.getElementById )
            return n;
        return document;
    },


    getOwnerWindow: function( n ) {
        if( !n )
            return window;
        if( n.parentWindow )
            return n.parentWindow;
        var doc = DOM.getOwnerDocument( n );
        if( doc && doc.defaultView )
            return doc.defaultView;
        return window;
    },
    
    
    getOwnerIframe: function( n ) {
        if( !n )
            return undefined;
        var nw = DOM.getOwnerWindow( n );
        var nd = DOM.getOwnerDocument( n );
        var pw = nw.parent || nw.parentWindow;
        if( !pw )
            return undefined;
        var parentDocument = pw.document;
        var es = parentDocument.getElementsByTagName( "iframe" );
        for( var i = 0; i < es.length; i++ ) {
            var e = es[ i ];
            try {
                var d = e.contentDocument || e.contentWindow.document;
                if( d === nd )
                    return e;
            }catch(err) {};
        }
        return undefined;
    },


    filterElementsByClassName: function( es, className ) {
        var filtered = [];
        for( var i = 0; i < es.length; i++ ) {
            var e = es[ i ];
            if( DOM.hasClassName( e, className ) )
                filtered[ filtered.length ] = e;
        }
        return filtered;
    },
    
    
    filterElementsByAttribute: function( es, attr ) {
        if( !es )
            return [];
        if( !defined( attr ) || attr == null || attr == "" )
            return es;
        var filtered = [];
        for( var i = 0; i < es.length; i++ ) {
            var element = es[ i ];
            if( !element )
                continue;
            if( element.getAttribute && ( element.getAttribute( attr ) ) )
                filtered[ filtered.length ] = element;
        }
        return filtered;
    },


    filterElementsByTagName: function( es, tagName ) {
        if( tagName == "*" )
            return es;
        var filtered = [];
        tagName = tagName.toLowerCase();
        for( var i = 0; i < es.length; i++ ) {
            var e = es[ i ];
            if( e.tagName && e.tagName.toLowerCase() == tagName )
                filtered[ filtered.length ] = e;
        }
        return filtered;
    },


    getElementsByTagAndAttribute: function( root, tagName, attr ) {
        if( !root )
            root = document;
        var es = root.getElementsByTagName( tagName );
        return DOM.filterElementsByAttribute( es, attr );
    },
    
    
    getElementsByAttribute: function( root, attr ) {
        return DOM.getElementsByTagAndAttribute( root, "*", attr );
    },


    getElementsByAttributeAndValue: function( root, attr, value ) {
        var es = DOM.getElementsByTagAndAttribute( root, "*", attr );
        var filtered = [];
        for ( var i = 0; i < es.length; i++ )
            if ( es[ i ].getAttribute( attr ) == value )
                filtered.push( es[ i ] );
        return filtered;
    },
    

    getElementsByTagAndClassName: function( root, tagName, className ) {
        if( !root )
            root = document;
        var elements = root.getElementsByTagName( tagName );
        return DOM.filterElementsByClassName( elements, className );
    },


    getElementsByClassName: function( root, className ) {
        return DOM.getElementsByTagAndClassName( root, "*", className );
    },


    getAncestors: function( n, includeSelf ) {
        if( !n )
            return [];
        var as = includeSelf ? [ n ] : [];
        n = n.parentNode;
        while( n ) {
            as.push( n );
            n = n.parentNode;
        }
        return as;
    },
    
    
    getAncestorsByTagName: function( n, tagName, includeSelf ) {
        var es = DOM.getAncestors( n, includeSelf );
        return DOM.filterElementsByTagName( es, tagName );
    },
    
    
    getFirstAncestorByTagName: function( n, tagName, includeSelf ) {
        return DOM.getAncestorsByTagName( n, tagName, includeSelf )[ 0 ];
    },


    getAncestorsByClassName: function( n, className, includeSelf ) {
        var es = DOM.getAncestors( n, includeSelf );
        return DOM.filterElementsByClassName( es, className );
    },


    getFirstAncestorByClassName: function( n, className, includeSelf ) {
        return DOM.getAncestorsByClassName( n, className, includeSelf )[ 0 ];
    },


    getAncestorsByTagAndClassName: function( n, tagName, className, includeSelf ) {
        var es = DOM.getAncestorsByTagName( n, tagName, includeSelf );
        return DOM.filterElementsByClassName( es, className );
    },


    getFirstAncestorByTagAndClassName: function( n, tagName, className, includeSelf ) {
        return DOM.getAncestorsByTagAndClassName( n, tagName, className, includeSelf )[ 0 ];
    },


    getPreviousElement: function( n ) {
        n = n.previousSibling;
        while( n ) {
            if( n.nodeType == Node.ELEMENT_NODE )
                return n;
            n = n.previousSibling;
        }
        return null;
    },


    getNextElement: function( n ) {
        n = n.nextSibling;
        while( n ) {
            if( n.nodeType == Node.ELEMENT_NODE )
                return n;
            n = n.nextSibling;
        }
        return null;
    },


    isInlineNode: function( n ) {
        // text nodes are inline
        if( n.nodeType == Node.TEXT_NODE )
            return n;

        // document nodes are non-inline
        if( n.nodeType == Node.DOCUMENT_NODE )
            return false;

        // all nonelement nodes are inline
        if( n.nodeType != Node.ELEMENT_NODE )
            return n;

        // br elements are not inline
        if( n.tagName && n.tagName.toLowerCase() == "br" )
            return false;

        // examine the style property of the inline n
        var display = DOM.getStyle( n, "display" ); 
        if( display && display.indexOf( "inline" ) >= 0 ) 
            return n;
    },
    
    
    isTextNode: function( n ) {
        if( n.nodeType == Node.TEXT_NODE )
            return n;
    },
    
    
    isInlineTextNode: function( n ) {
        if( n.nodeType == Node.TEXT_NODE )
            return n;
        if( !DOM.isInlineNode( n ) )
            return null;
    },


    /* this and the following classname functions honor w3c case-sensitive classnames */

    getClassNames: function( e ) {
        if( !e || !e.className )
            return [];
        return e.className.split( /\s+/g );
    },


    hasClassName: function( e, className ) {
        if( !e || !e.className )
            return false;
        var cs = DOM.getClassNames( e );
        for( var i = 0; i < cs.length; i++ ) {
            if( cs[ i ] == className )
                return true;
        }
        return false;
    },


    addClassName: function( e, className ) {
        if( !e || !className )
            return false;
        var cs = DOM.getClassNames( e );
        for( var i = 0; i < cs.length; i++ ) {
            if( cs[ i ] == className )
                return true;
        }
        cs.push( className );
        e.className = cs.join( " " );
        return false;
    },


    removeClassName: function( e, className ) {
        var r = false;
        if( !e || !e.className || !className )
            return r;
        var cs = (e.className && e.className.length)
            ? e.className.split( /\s+/g )
            : [];
        var ncs = [];
        for( var i = 0; i < cs.length; i++ ) {
            if( cs[ i ] == className ) {
                r = true;
                continue;
            }
            ncs.push( cs[ i ] );
        }
        if( r )
            e.className = ncs.join( " " );
        return r;
    },
    
    
    /* tree manipulation methods */
    
    replaceWithChildNodes: function( n ) {
        var firstChild = n.firstChild;
        var parentNode = n.parentNode;
        while( n.firstChild )
            parentNode.insertBefore( n.removeChild( n.firstChild ), n );
        parentNode.removeChild( n );
        return firstChild;
    },
    
    
    /* factory methods */
    
    createInvisibleInput: function( d ) {
        if( !d )
            d = window.document;
        var e = document.createElement( "input" );
        e.setAttribute( "autocomplete", "off" );
        e.autocomplete = "off";
        DOM.makeInvisible( e );
        return e;
    },


    getMouseEventAttribute: function( event, a ) {
        if( !a )
            return;
        var es = DOM.getAncestors( event.target, true );
        for( var i = 0; i < es.length; i++ ) {
            try {
                var e = es[ i ]
                var v = e.getAttribute ? e.getAttribute( a ) : null;
                if( v ) {
                    event.attributeElement = e;
                    event.attribute = v;
                    return v;
                }
            } catch( e ) {}
        }
    },
    

    setElementAttribute: function( e, a, v ) {
        /* safari workaround
         * safari's setAttribute assumes you want to use a namespace
         * when you have a colon in your attribute
         */
        if ( navigator.userAgent.toLowerCase().match(/webkit/) ) {
            var at = e.attributes;
            for ( var i = 0; i < at.length; i++ )
                if ( at[ i ].name == a )
                    return at[ i ].nodeValue = v;
        } else
            e.setAttribute( a, v );
    },


    swapAttributes: function( e, tg, at ) {
        var ar = e.getAttribute( tg );
        if( !ar )
            return false;
        
        /* clone the node with all children */
        if ( e.tagName.toLowerCase() == 'script' ) {
            /* only clone and replace script tags */
            var cl = e.cloneNode( true );
            if ( !cl )
                return false;

            DOM.setElementAttribute( cl, at, ar );
            cl.removeAttribute( tg );
        
            /* replace new, old */
            return e.parentNode.replaceChild( cl, e );
        } else {
            DOM.setElementAttribute( e, at, ar );
            e.removeAttribute( tg );
        }
    },


    findPosX: function( e ) {
        var curleft = 0;

        if (e.offsetParent) {
            while (1) {
                curleft += e.offsetLeft;
                if (!e.offsetParent) {
                    break;
                }
                e = e.offsetParent;
            }
        } else if (e.x) {
            curleft += e.x;
        }

        return curleft;
    },


    findPosY: function( e ) {
        var curtop = 0;

        if (e.offsetParent) {
            while (1) {
                curtop += e.offsetTop;
                if (!e.offsetParent) {
                    break;
                }
                e = e.offsetParent;
            }
        } else if (e.y) {
            curtop += e.y;
        }

        return curtop;
    }
    
    
} );

if (!(typeof $== 'function')) {
    $ = DOM.getElement;
};

