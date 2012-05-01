/*
Template - Copyright 2005 Six Apart
$Id: template.js 35 2006-02-18 00:46:55Z mischa $

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


/* core template object */

Template = new Class( Object, {
    beginToken: "[#",
    endToken: "#]",
    
    
    init: function( source ) {
        if( source )
            this.compile( source );
    },
    
    
    compile: function( source ) {
        var statements = [
            "context.open();",
            "with( context.vars ) {"
        ];
        
        var start = 0, end = -this.endToken.length;
        while( start < source.length ) {
            end += this.endToken.length;
            
            // plaintext
            start = source.indexOf( this.beginToken, end );
            if( start < 0 )
                start = source.length;
            if( start > end )
                statements.push( "context.write( ", source.substring( end, start ).toJSON(), " );" );
            start += this.beginToken.length;
            
            // code
            if( start >= source.length )
                break;
            end = source.indexOf( this.endToken, start );
            if( end < 0 )
                throw "Template parsing error: Unable to find matching end token (" + this.endToken + ").";
            var length = (end - start);
            
            // empty tag
            if( length <= 0 )
                continue;
            
            // comment
            else if( length >= 4 &&
                source.charAt( start ) == "-" && source.charAt( start + 1 ) == "-" &&
                source.charAt( end - 1 ) == "-" && source.charAt( end - 2 ) == "-" )
                continue;
            
            // write
            else if( source.charAt( start ) == "=" )
                statements.push( "context.write( ", source.substring( start + 1, end ), " );" );
            
            // filters
            else if( source.charAt( start ) == "|" ) {
                start += 1;

                // find the first whitespace
                var afterfilters = source.substring(start,end).search(/\s/);
                
                var filters;
                if (afterfilters > 0) {
                    // allow pipes or commas to seperate filters
                    // split the string, reverse and rejoin to reverse it
                    filters = source.substring(start,start + afterfilters).replace(/,|\|/g,"").split('');
                    afterfilters += 1; // data starts after whitespace and filter list
                } else {
                    // default to escapeHTML
                    filters = ["h"];
                }
                // we have to do them in reverse order
                filters = filters.reverse();
               
                // start with our original filter number
                var numfilters = filters.length;
                
                // add the text between [#|  #]
                filters.push(source.substring( start + afterfilters, end ));
                
                // adjust each filter into a function call
                // eg. u ( h ( H ( blah ) ) )
                for (i=0; i<numfilters; i++) {
                    filters[i] = "context.f."+filters[i]+"( ";
                    filters.push(" )");
                }
                
                statements.push( "context.write( " + filters.join('') + " );");
            }
            
            // evaluate
            else
                statements.push( source.substring( start, end ) );
        }
        
        statements.push( "} return context.close();" );

        this.exec = new Function( "context", statements.join( "\n" ) );
    },
    
    
    exec: function( context ) {
        return "";
    }
} );


/* static members */

Template.templates = {};


/* context object */

Template.Context = new Class( Object, {
    init: function( vars, templates ) {
        this.vars = vars || {};
        this.templates = templates || Template.templates;
        this.stack = [];
        this.out = [];
        this.f = Template.Filter;
    },
    
    
    include: function( name ) {
        return this.templates[ name ].exec( this );
    },


    write: function() {
        this.out.push.apply( this.out, arguments );
    },


    writeln: function() {
        this.write.apply( this, arguments );
        this.write( "\n" );
    },

    
    clear: function() {
        this.out.length = 0;
    },


    getOutput: function() {
        return this.out.join( "" );
    },
    
    
    open: function() {
        this.stack.push( this.out );
        this.out = [];
    },
    
    
    close: function() {
        var result = this.getOutput();
        this.out = this.stack.pop() || [];
        return result;
    }
   
} );

/* filters */

Template.Filter = {

    // escapeHTML
    h: function(obj) {
        var div = document.createElement('div');
        var textNode = document.createTextNode(obj);
        div.appendChild(textNode);
        return (div.innerHTML);
    },

    // unescapeHTML
    H: function(obj) {
        return (unescape(obj));
    },

    // encodeURL
    u: function(obj) {
        return (escape(obj).replace(/\//g,"%2F"));
    }

};

