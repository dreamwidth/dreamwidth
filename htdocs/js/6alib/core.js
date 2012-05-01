/*
Core JavaScript Library
$Id: core.js 232 2007-10-01 20:32:42Z whitaker $

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

/* stubs */

log = function() {};
log.error = log.warn = log.debug = log;


/* utility functions */

defined = function( x ) {
    return x === undefined ? false : true;
}


/**
 * Utility method.
 * @param x <code>any</code> Any JavaScript value, including <code>undefined</code>.
 * @return boolean <code>true</code> if the value is not <code>null</code> and is not <code>undefined</code>.
 */
exists = function( x ) {
   return (x === undefined || x === null) ? false : true;
}


finite = function( x ) {
    return isFinite( x ) ? x : 0;
}


finiteInt = function( x, base ) {
    return finite( parseInt( x, base ) );
}


finiteFloat = function( x ) {
    return finite( parseFloat( x ) );
}


max = function() {
    var a = arguments;
    var n = a[ 0 ];
    for( var i = 1; i < a.length; i++ )
        if( a[ i ] > n )
            n = a[ i ];
    return n;
}


min = function() {
    var a = arguments;
    var n = a[ 0 ];
    for( var i = 1; i < a.length; i++ )
        if( a[ i ] < n )
            n = a[ i ];
    return n;
}


/* try block */  
 
Try = {
    these: function() {
        for( var i = 0; i < arguments.length; i++ ) {
            try {
                return arguments[ i ]();
            } catch( e ) {}
        }
        return undefined;
    }
}


/* unique id generator */

Unique = {
    length: 0,
    
    id: function() {
        return ++this.length;
    }
}


/* event methods */

if( !defined( window.Event ) )
    Event = {};


Event.stop = function( event ) {
    event = event || this;
    if( event === Event )
        event = window.event;

    // w3c
    if( event.preventDefault )
        event.preventDefault();
    if( event.stopPropagation )
        event.stopPropagation();

    // ie
    try {
        event.cancelBubble = true;
        event.returnValue = false;
    } catch( e ) {}

    return false;
}


Event.prep = function( event ) {
    event = event || window.event;
    if( !defined( event.stop ) )
        event.stop = this.stop;
    if( !defined( event.target ) )
        event.target = event.srcElement;
    if( !defined( event.relatedTarget ) ) 
        event.relatedTarget = event.toElement;
    return event;
}


try { Event.prototype.stop = Event.stop; }
catch( e ) {}


/* object extensions */

Function.stub = function() {};


if( !Object.prototype.hasOwnProperty ) {
    Object.prototype.hasOwnProperty = function( p ) {
        if( !(p in this) )
            return false;
        try {
            var pr = this.constructor.prototype;
            while( pr ) {
                if( pr[ p ] === this[ p ] )
                    return false;
                if( pr === pr.constructor.prototype )
                    break;
                pr = pr.constructor.prototype;
            }
        } catch( e ) {}
        return true;
    }
}


if ( ! defined ( window.OBJ ) ) 
    OBJ = {};

OBJ.extend = function(obj_this) {
    var a = arguments;
    for( var i = 0; i < a.length; i++ ) {
        var o = a[ i ];
        for( var p in o ) {
            try {
                if( !obj_this[ p ] &&
                    (!o.hasOwnProperty || o.hasOwnProperty( p )) )
                    obj_this[ p ] = o[ p ];
            } catch( e ) {}
        }
    }
    return obj_this;
}


OBJ.override = function(obj_this) {
    var a = arguments;
    for( var i = 0; i < a.length; i++ ) {
        var o = a[ i ];
        for( var p in o ) {
            try {
                if( !o.hasOwnProperty || o.hasOwnProperty( p ) )
                    obj_this[ p ] = o[ p ];
            } catch( e ) {}
        }
    }
    return obj_this;
}


/* function extensions */

OBJ.extend( Function.prototype, {
    bind: function( object ) {
        var method = this;
        return function() {
            return method.apply( object, arguments );
        };
    },
    
    
    bindEventListener: function( object ) {
        var method = this; // Use double closure to work around IE 6 memory leak.
        return function( event ) {
            try {
                event = Event.prep( event );
            } catch( e ) {}
            return method.call( object, event );
        };
    }
} );


/* class helpers */

indirectObjects = [];


Class = function( superClass ) {

    // Set the constructor:
    var constructor = function() {
        if( arguments.length && this.init )
            this.init.apply( this, arguments );
    };    
    //   -- Accomplish static-inheritance:
    OBJ.override( constructor,Class );  // inherit static methods from Class
    superClass = superClass || Object; 
    OBJ.override(constructor, superClass ); // inherit static methods from the superClass 
    constructor.superClass = superClass.prototype;
    
    // Set the constructor's prototype (accomplish object-inheritance):
    constructor.prototype = new superClass();
    constructor.prototype.constructor = constructor; // rev. 0.7    
    //   -- extend prototype with Class instance methods
    OBJ.extend(constructor.prototype, Class.prototype );    
    //   -- override prototype with interface methods
    for( var i = 1; i < arguments.length; i++ )
        OBJ.override(constructor.prototype, arguments[ i ] );
    
    return constructor;
}


OBJ.extend( Class, {
    initSingleton: function() {
        if( this.singleton )
            return this.singleton;
        this.singleton = this.singletonConstructor
            ? new this.singletonConstructor()
            : new this();
        if ( this.singleton.init )
            this.singleton.init.apply( this.singleton, arguments );
        return this.singleton;
    }
} );


Class.prototype = {
    destroy: function() {
        try {
            if( this.indirectIndex )
                indirectObjects[ this.indirectIndex ] = undefined;
            delete this.indirectIndex;
        } catch( e ) {}
        
        for( var property in this ) {
            try {
                if( this.hasOwnProperty( property ) )
                    delete this[ property ];
            } catch( e ) {}
        }
    },
    
    
    getBoundMethod: function( methodName ) {
        return this[ name ].bind( this );
    },
    
    
    getEventListener: function( methodName ) {
        return this[ methodName ].bindEventListener( this );
    },
    
    
    getIndirectIndex: function() {
        if( !defined( this.indirectIndex ) ) {
            this.indirectIndex = indirectObjects.length;
            indirectObjects.push( this );
        }
        return this.indirectIndex;
    },
    
    
    getIndirectMethod: function( methodName ) {
        if( !this.indirectMethods )
            this.indirectMethods = {};
        var method = this[ methodName ];
        if( typeof method != "function" )
            return undefined;
        var indirectIndex = this.getIndirectIndex();
        if( !this.indirectMethods[ methodName ] ) {
            this.indirectMethods[ methodName ] = new Function(
                "var o = indirectObjects[" + indirectIndex + "];" +
                "return o." + methodName + ".apply( o, arguments );"
            );
        }
        return this.indirectMethods[ methodName ];
    },
    
    
    getIndirectEventListener: function( methodName ) {
        if( !this.indirectEventListeners )
            this.indirectEventListeners = {};
        var method = this[ methodName ];
        if( typeof method != "function" )
            return undefined;
        var indirectIndex = this.getIndirectIndex();
        if( !this.indirectEventListeners[ methodName ] ) {
            this.indirectEventListeners[ methodName ] = new Function( "event",
                "try { event = Event.prep( event ); } catch( e ) {}" +
                "var o = indirectObjects[" + indirectIndex + "];" +
                "return o." + methodName + ".call( o, event );"
            );
        }
        return this.indirectEventListeners[ methodName ];
    }
}


/* string extensions */

OBJ.extend( String, {
    escapeJSChar: function( c ) {
        // try simple escaping
        switch( c ) {
            case "\\": return "\\\\";
            case "\"": return "\\\"";
            case "'":  return "\\'";
            case "\b": return "\\b";
            case "\f": return "\\f";
            case "\n": return "\\n";
            case "\r": return "\\r";
            case "\t": return "\\t";
        }
        
        // return raw bytes now ... should be UTF-8
        if( c >= " " )
            return c;
        
        // try \uXXXX escaping, but shouldn't make it for case 1, 2
        c = c.charCodeAt( 0 ).toString( 16 );
        switch( c.length ) {
            case 1: return "\\u000" + c;
            case 2: return "\\u00" + c;
            case 3: return "\\u0" + c;
            case 4: return "\\u" + c;
        }
        
        // should never make it here
        return "";
    },
    
    
    encodeEntity: function( c ) {
        switch( c ) {
            case "<": return "&lt;";
            case ">": return "&gt;";
            case "&": return "&amp;";
            case '"': return "&quot;";
            case "'": return "&apos;";
        }
        return c;
    },


    decodeEntity: function( c ) {
        switch( c ) {
            case "amp": return "&";
            case "quot": return '"';
            case "gt": return ">";
            case "lt": return "<";
        }
        var m = c.match( /^#(\d+)$/ );
        if( m && defined( m[ 1 ] ) )
            return String.fromCharCode( m[ 1 ] );
        m = c.match( /^#x([0-9a-f]+)$/i );
        if(  m && defined( m[ 1 ] ) )
            return String.fromCharCode( parseInt( hex, m[ 1 ] ) );
        return c;
    }
} );


OBJ.extend( String.prototype, {
    escapeJS: function() {
        return this.replace( /([^ -!#-\[\]-~])/g, function( m, c ) { return String.escapeJSChar( c ); } )
    },
    
    
    escapeJS2: function() {
        return this.replace( /([\u0000-\u0031'"\\])/g, function( m, c ) { return String.escapeJSChar( c ); } )
    },
    
    
    escapeJS3: function() {
        return this.replace( /[\u0000-\u0031'"\\]/g, function( m ) { return String.escapeJSChar( m ); } )
    },
    
    
    escapeJS4: function() {
        return this.replace( /./g, function( m ) { return String.escapeJSChar( m ); } )
    },
    
    
    encodeHTML: function() {
        return this.replace( /([<>&"])/g, function( m, c ) { return String.encodeEntity( c ) } );
    },


    decodeHTML: function() {
        return this.replace( /&(.*?);/g, function( m, c ) { return String.decodeEntity( c ) } );
    },
    
    
    cssToJS: function() {
        return this.replace( /-([a-z])/g, function( m, c ) { return c.toUpperCase() } );
    },
    
    
    jsToCSS: function() {
        return this.replace( /([A-Z])/g, function( m, c ) { return "-" + c.toLowerCase() } );
    },
    
    
    firstToLowerCase: function() {
        return this.replace( /^(.)/, function( m, c ) { return c.toLowerCase() } );
    },
    
        
    rgbToHex: function() {
        var c = this.match( /(\d+)\D+(\d+)\D+(\d+)/ );
        if( !c )
            return undefined;
        return "#" +
            finiteInt( c[ 1 ] ).toString( 16 ).pad( 2, "0" ) +
            finiteInt( c[ 2 ] ).toString( 16 ).pad( 2, "0" ) +
            finiteInt( c[ 3 ] ).toString( 16 ).pad( 2, "0" );
    },
    
    
    pad: function( length, padChar ) {
        var padding = length - this.length;
        if( padding <= 0 )
            return this;
        if( !defined( padChar ) )
            padChar = " ";
        var out = [];
        for( var i = 0; i < padding; i++ )
            out.push( padChar );
        out.push( this );
        return out.join( "" );
    },


    trim: function() {
        return this.replace( /^\s+|\s+$/g, "" );
    }

} );


/* extend array object */

OBJ.extend( Array, { 
    fromPseudo: function ( args ) {
        var out = [];
        for ( var i = 0; i < args.length; i++ )
            out.push( args[ i ] );
        return out;
    }
});


/* extend array object */

OBJ.extend(Array.prototype, {
    copy: function() {
        var out = [];
        for( var i = 0; i < this.length; i++ )
            out[ i ] = this[ i ];
        return out;
    },


    first: function( callback, object ) {
        var length = this.length;
        for( var i = 0; i < length; i++ ) {
            var result = object
                ? callback.call( object, this[ i ], i, this )
                : callback( this[ i ], i, this );
            if( result )
                return this[ i ];
        }
        return null;
    },


    fitIndex: function( fromIndex, defaultIndex ) {
        if( !defined( fromIndex ) || fromIndex == null )
            fromIndex = defaultIndex;
        else if( fromIndex < 0 ) {
            fromIndex = this.length + fromIndex;
            if( fromIndex < 0 )
                fromIndex = 0;
        } else if( fromIndex >= this.length )
            fromIndex = this.length - 1;
        return fromIndex;
    },


    scramble: function() {
        for( var i = 0; i < this.length; i++ ) {
            var j = Math.floor( Math.random() * this.length );
            var temp = this[ i ];
            this[ i ] = this[ j ];
            this[ j ] = temp;
        }
    },
    
    
    add: function() {
        var a = arguments;
        for( var i = 0; i < a.length; i++ ) {
            var index = this.indexOf( a[ i ] );
            if( index < 0 ) 
                this.push( arguments[ i ] );
        }
        return this.length;
    },
        
    
    remove: function() {
        var a = arguments;
        for( var i = 0; i < a.length; i++ ) {
            var j = this.indexOf( a[ i ] );
            if( j >= 0 )
                this.splice( j, 1 );
        }
        return this.length;
    },


    /* javascript 1.5 array methods */
    /* http://developer-test.mozilla.org/en/docs/Core_JavaScript_1.5_Reference:Objects:Array#Methods */

    every: function( callback, object ) {
        var length = this.length;
        for( var i = 0; i < length; i++ ) {
            var result = object
                ? callback.call( object, this[ i ], i, this )
                : callback( this[ i ], i, this );
            if( !result )
                return false;
        }
        return true;
    },


    filter: function( callback, object ) {
        var out = [];
        var length = this.length;
        for( var i = 0; i < length; i++ ) {
            var result = object
                ? callback.call( object, this[ i ], i, this )
                : callback( this[ i ], i, this );
            if( result )
                out.push( this[ i ] );
        }
        return out;
    },
    
    
    forEach: function( callback, object ) {
        var length = this.length;
        for( var i = 0; i < length; i++ ) {
            object
                ? callback.call( object, this[ i ], i, this )
                : callback( this[ i ], i, this );
        }
    },
    
    
    indexOf: function( value, fromIndex ) {
        fromIndex = this.fitIndex( fromIndex, 0 );
        for( var i = 0; i < this.length; i++ ) {
            if( this[ i ] === value )
                return i; 
        }
        return -1;
    },


    lastIndexOf: function( value, fromIndex ) {
        fromIndex = this.fitIndex( fromIndex, this.length - 1 );
        for( var i = fromIndex; i >= 0; i-- ) {
            if( this[ i ] == value )
                return i;
        }
        return -1;
    },


    some: function( callback, object ) {
        var length = this.length;
        for( var i = 0; i < length; i++ ) {
            var result = object
                ? callback.call( object, this[ i ], i, this )
                : callback( this[ i ], i, this );
            if( result )
                return true;
        }
        return false;
    },


    /* javascript 1.2 array methods */

    concat: function() {
        var a = arguments;
        var out = this.copy();
        for( i = 0; i < a.length; i++ ) {
            var b = a[ i ];
            for( j = 0; j < b.length; j++ )
                out.push( b[ j ] );
        }
        return out;
    },
    

    push: function() {
        var a = arguments;
        for( var i = 0; i < a.length; i++ )
            this[ this.length ] = a[ i ];
        return this.length;     
    },


    pop: function() {
        if( this.length == 0 )
            return undefined;
        var out = this[ this.length - 1 ];
        this.length--;
        return out;
    },
    
    
    unshift: function() {
        var a = arguments;
        for( var i = 0; i < a.length; i++ ) {
            this[ i + a.length ] = this[ i ];
            this[ i ] = a[ i ];
        }
        return this.length;     
    },
    
    
    shift: function() {
        if( this.length == 0 )
            return undefined;
        var out = this[ 0 ];
        for( var i = 1; i < this.length; i++ )
            this[ i - 1 ] = this[ i ];
        this.length--;
        return out;
    }
} );


/* date extensions */

OBJ.extend(Date, {
    /*  iso 8601 date format parser
        this was fun to write...
        thanks to: http://www.cl.cam.ac.uk/~mgk25/iso-time.html */

    matchISOString: new RegExp(
        "^([0-9]{4})" +                                                     // year
        "(?:-(?=0[1-9]|1[0-2])|$)(..)?" +                                   // month
        "(?:-(?=0[1-9]|[12][0-9]|3[01])|$)([0-9]{2})?" +                    // day of the month
        "(?:T(?=[01][0-9]|2[0-4])|$)T?([0-9]{2})?" +                        // hours
        "(?::(?=[0-5][0-9])|\\+|-|Z|$)([0-9]{2})?" +                        // minutes
        "(?::(?=[0-5][0-9]|60$|60[+|-|Z]|60.0+)|\\+|-|Z|$):?([0-9]{2})?" +  // seconds
        "(\.[0-9]+)?" +                                                     // fractional seconds
        "(Z|\\+[01][0-9]|\\+2[0-4]|-[01][0-9]|-2[0-4])?" +                  // timezone hours
        ":?([0-5][0-9]|60)?$"                                               // timezone minutes
    ),
    
    
    fromISOString: function( string ) {
        var t = this.matchISOString.exec( string );
        if( !t )
            return undefined;

        var year = finiteInt( t[ 1 ], 10 );
        var month = finiteInt( t[ 2 ], 10 ) - 1;
        var day = finiteInt( t[ 3 ], 10 );
        var hours = finiteInt( t[ 4 ], 10 );
        var minutes = finiteInt( t[ 5 ], 10 );
        var seconds = finiteInt( t[ 6 ], 10 );
        var milliseconds = finiteInt( Math.round( parseFloat( t[ 7 ] ) * 1000 ) );
        var tzHours = finiteInt( t[ 8 ], 10 );
        var tzMinutes = finiteInt( t[ 9 ], 10 );

        var date = new this( 0 );
        if( defined( t[ 8 ] ) ) {
            date.setUTCFullYear( year, month, day );
            date.setUTCHours( hours, minutes, seconds, milliseconds );
            var offset = (tzHours * 60 + tzMinutes) * 60000;
            if( offset )
                date = new this( date - offset );
        } else {
            date.setFullYear( year, month, day );
            date.setHours( hours, minutes, seconds, milliseconds );
        }

        return date;
    }
} );


OBJ.extend(Date.prototype, {
    getISOTimezoneOffset: function() {
        var offset = -this.getTimezoneOffset();
        var negative = false;
        if( offset < 0 ) {
            negative = true;
            offset *= -1;
        }
        var offsetHours = Math.floor( offset / 60 ).toString().pad( 2, "0" );
        var offsetMinutes = Math.floor( offset % 60 ).toString().pad( 2, "0" );
        return (negative ? "-" : "+") + offsetHours + ":" + offsetMinutes;
    },


    toISODateString: function() {
        var year = this.getFullYear();
        var month = (this.getMonth() + 1).toString().pad( 2, "0" );
        var day = this.getDate().toString().pad( 2, "0" );
        return year + "-" + month + "-" + day;
    },


    toUTCISODateString: function() {
        var year = this.getUTCFullYear();
        var month = (this.getUTCMonth() + 1).toString().pad( 2, "0" );
        var day = this.getUTCDate().toString().pad( 2, "0" );
        return year + "-" + month + "-" + day;
    },


    toISOTimeString: function() {
        var hours = this.getHours().toString().pad( 2, "0" );
        var minutes = this.getMinutes().toString().pad( 2, "0" );
        var seconds = this.getSeconds().toString().pad( 2, "0" );
        var milliseconds = this.getMilliseconds().toString().pad( 3, "0" );
        var timezone = this.getISOTimezoneOffset();
        return hours + ":" + minutes + ":" + seconds + "." + milliseconds + timezone;
    },


    toUTCISOTimeString: function() {
        var hours = this.getUTCHours().toString().pad( 2, "0" );
        var minutes = this.getUTCMinutes().toString().pad( 2, "0" );
        var seconds = this.getUTCSeconds().toString().pad( 2, "0" );
        var milliseconds = this.getUTCMilliseconds().toString().pad( 3, "0" );
        return hours + ":" + minutes + ":" + seconds + "." + milliseconds + "Z";
    },


    toISOString: function() {
        return this.toISODateString() + "T" + this.toISOTimeString();
    },


    toUTCISOString: function() {
        return this.toUTCISODateString() + "T" + this.toUTCISOTimeString();
    }
} );


/* ajax */

if( !defined( window.XMLHttpRequest ) ) {
    window.XMLHttpRequest = function() {
        var types = [
            "Microsoft.XMLHTTP",
            "MSXML2.XMLHTTP.5.0",
            "MSXML2.XMLHTTP.4.0",
            "MSXML2.XMLHTTP.3.0",
            "MSXML2.XMLHTTP"
        ];
        
        for( var i = 0; i < types.length; i++ ) {
            try {
                return new ActiveXObject( types[ i ] );
            } catch( e ) {}
        }
        
        return undefined;
    }
}
