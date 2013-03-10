/*

  contentfilters.js

  Provides the various functions that we use on the content filters management
  page to enable easy filter management.

  Authors:
       Mark Smith <mark@dreamwidth.org>

  Copyright (c) 2009 by Dreamwidth Studios, LLC.

  This program is free software; you may redistribute it and/or modify it under
  the same terms as Perl itself.  For a copy of the license, please reference
  'perldoc perlartistic' or 'perldoc perlgpl'.

*/


/*
 
   data structures...  I was going nuts not having this referencable, so I
   have broken down all of the globals and what's in them.


    cfSubs = {
        userid => {
            showbydefault => 0/1,
            fgcolor => '#000000',
            bgcolor => '#ffffff',
            groupmask => 2394829347,
            journaltype => 'P',
            username => 'test3',
        },
        userid => ...,
        userid => ...,
    };


    cfFilters = {
        filterid => {
            id => 1,
            name => 'filter',
            public => 1/0,
            sortorder => 234,

            // populated only when a filter is clicked on, initially null
            members => {
                userid => {
                    user => 'username',

                    // all of these are optional and may not be present
                    adult_content => enum('any', 'nonexplicit', 'sfw'),
                    poster_type => enum('any', 'maintainer', 'moderator'),
                    tags_mode => enum('any_of', 'all_of', 'none_of'),
                    tags => [ 1, 3, 59, 23, ... ],
                },
                userid => ...,
                userid => ...,
            },
        },
        filterid => ...,
        filterid => ...,
    };


    cfTags = {
        userid => {
            tagid => {
                name => 'tagname',
                uses => 13,
            },
            tagid => ...,
            tagid => ...,
        },
        userid => ...,
        userid => ...,
    };

*/

var cfSelectedFilterId = null, cfCurrentUserid = null;
var cfSubs = {}, cfTags = {}, cfFilters = {};

var cfTypeFilter = '';
var cfSubsSorted = [];

// [ total count, selected ]
var cfTagCount = [ 0, 0 ];

// current save timer
var cfTimerId = null, cfSaveTicksLeft = 0;


function cfShowTypes( newtype ) {
    if ( cfTypeFilter == newtype )
        return;
    cfTypeFilter = newtype;
    cfPopulateLists();
}


function cfPopulateLists(selectValue) {
    // whenever we repopulate the lists, we lose what is selected
    cfHideOptions();

    // short circuit, if we have no filter, just empty both
    if ( ! cfSelectedFilterId ) {
        $('#cf-in-list, #cf-notin-list').empty();
        $('#cf-rename, #cf-delete, #cf-view, #cf-edit').hide();
        $('#cf-intro').show();
        return;
    }

    // show our rename button
    $('#cf-rename, #cf-delete, #cf-view, #cf-edit').show();
    $('#cf-intro').hide();

    var filt = cfFilters[cfSelectedFilterId];

    // creates a sorted list of userids
    cfSubsSorted = [];
    for ( i in cfSubs )
        if ( cfTypeFilter == '' || cfSubs[i].journaltype == cfTypeFilter )
            cfSubsSorted.push( i );
    cfSubsSorted.sort( function( a, b ) {
        return ( cfSubs[a].username < cfSubs[b].username ) ? -1 : ( cfSubs[a].username > cfSubs[b].username ) ? 1 : 0;
    } );

    var inOpts = '', outOpts = '';
    for ( idx in cfSubsSorted ) {
        var i = cfSubsSorted[idx];
        var isIn = false;

        for ( j in filt.members ) {
            if ( filt.members[j].user == cfSubs[i].username )
                isIn = true;
        }

        if ( isIn )
            inOpts += '<option value="' + i + '">' + cfSubs[i].username + '</option>';
        else
            outOpts += '<option value="' + i + '">' + cfSubs[i].username + '</option>';
    }

    $('#cf-in-list').html( inOpts );
    $('#cf-notin-list').html( outOpts ).val( selectValue );

    if ($.browser.msie && parseInt($.browser.version, 10) <= 8) $('#cf-in-list, #cf-notin-list').css('width', 'auto').css('width', '100%'); // set #cf-in-list and #cf-notin-list width (IE n..7 bug)
}

function cfPopulateOptions( ) {
    $('#cf-public').val( cfFilters[cfSelectedFilterId]['public'] );
    $('#cf-sortorder').val( String( cfFilters[cfSelectedFilterId]['sortorder'] ) );
    $('#cf-foname').text( cfFilters[cfSelectedFilterId]['name'] );
    $('#cf-filtopts').show();
}

function cfSelectedFilter() {
    // filter options are not implemented yet, so don't show that box :)

    cfPopulateLists();
    cfPopulateOptions();
}


function cfSelectFilter( filtid ) {
    // do nothing case
    if ( filtid < 1 ) filtid = null;
    if ( cfSelectedFilterId != null && cfSelectedFilterId == filtid )
        return;

    // store this for usefulness
    cfSelectedFilterId = filtid;

    // have to hide the options now, as we're not sure what the user is doing
    cfHideOptions();

    // if they've chosen nothing...
    if ( filtid == null )
        return cfPopulateLists();

    // if this filter already has loaded members, just return
    if ( cfFilters[filtid].members != null )
        return cfSelectedFilter();

    // get the members of this filter
    $.getJSON( '/__rpc_contentfilters?mode=list_members&user=' + DW.currentUser + '&filterid=' + filtid,
        function( data ) {
            cfFilters[filtid].members = data.members;
            cfSelectedFilter();
        }
    );
}


function cfUpdateTags( data ) {
//    cfTags[cfCurrentUser] = data.tags

    var member = cfFilters[cfSelectedFilterId].members[cfCurrentUserid];
    if ( ! member )
        return;

    // initialize our tag structure
    if ( ! member.tags )
        member.tags = {};

    // reset the global tag counts
    cfTagCount = [ 0, 0 ];

    var html = '', htmlin = '';

    //sort tags alphabetically
    function sorttags( tag_a, tag_b ) {
        var name_a = data.tags[tag_a].name;
        var name_b = data.tags[tag_b].name;
        if ( name_a < name_b ) {
            return -1;
        } else if ( name_a > name_b ) {
            return 1;
        } else {
            return 0;
        }
    }

    var sorted_tags = [];
    for ( id in data.tags ) {
        sorted_tags.push( id );
    }

    sorted_tags = sorted_tags.sort( sorttags );

    // go through tag list alphabetically
    for(var i=0; i<sorted_tags.length; i++){
        var id = sorted_tags[i];
        // count every tag
        cfTagCount[0]++;

        // see if this tag is in the list ...
        var isin = member.tags[id] ? true : false;

        if ( isin ) {
            // count every selected tag and build our HTML
            cfTagCount[1]++
            htmlin += '<span id="' +  id + '" class="cf-tag-on cf-tag"><a href="javascript:void(0);">' + data.tags[id].name + '</a>[' + data.tags[id].uses + ']</span> ';
        } else {
            html += '<span id="' +  id + '" class="cf-tag"><a href="javascript:void(0);">' + data.tags[id].name + '</a>[' + data.tags[id].uses + ']</span> ';
        }
    }

    // do some default stuff if nothing is selected
    $('#cf-notagsavail').toggle( html == '' );
    $('#cf-notagssel').toggle( htmlin == '' );

    // and now show/hide the other boxes
    $('#cf-t-box2').toggle( html != '' );
    $('#cf-t-box3').toggle( htmlin != '' );

    // now pass this into the page for the user to view
    $('#cf-t-box2').html( html );
    $('#cf-t-box3').html( htmlin );

    // now, all of these tags need an onclick handler
    $('span.cf-tag').bind( 'click', function( e ) { cfClickTag( $(this).attr( 'id' ) ); } );
}


function cfClickTag( id ) {
    var obj = $('span.cf-tag#' + id);
    var filt = cfFilters[cfSelectedFilterId];
    var member = filt.members[cfCurrentUserid];
    if ( !obj || !filt || !member || !DW.userIsPaid )
        return;

    // first, let's toggle the class that boldens the tag
    obj.toggleClass( 'cf-tag-on' );

    // now make sure we have a tags array...
    if ( ! member.tags )
        member.tags = {};

    // now, if the class is ON, we need to move this tag to the bucket
    if ( obj.hasClass( 'cf-tag-on') ) {
        $('#cf-t-box3').append(' '); // thanks Janine!
        obj.appendTo('#cf-t-box3');
        member.tags[id] = true;
        cfTagCount[1]++;

    // and if it's off, remove it
    } else {
        $('#cf-t-box2').append(' '); // damn splits...
        obj.appendTo('#cf-t-box2');
        delete member.tags[id];
        cfTagCount[1]--;
    }

    // now show/hide our UI markers
    $('#cf-notagssel').toggle( cfTagCount[1] == 0 );
    $('#cf-notagsavail').toggle( cfTagCount[0] == 0 || ( cfTagCount[0] - cfTagCount[1] == 0 ) );

    // and now... tag contents
    $('#cf-t-box3').toggle( cfTagCount[1] > 0 );
    $('#cf-t-box2').toggle( cfTagCount[0] > 0 && ( cfTagCount[0] - cfTagCount[1] > 0 ) );

    // kick off a save
    cfSaveChanges();
}


function cfSaveChanges() {
    // if we have a save timer, nuke it
    if ( cfTimerId )
        clearTimeout( cfTimerId );

    // set a timer... then try to save, which actually sets a new timer
    // for us to use.
    cfSaveTicksLeft = 6;
    cfTrySave();
}


function cfTrySave() {
    // our timer has fired
    cfTimerId = null;

    // now, if we're out of ticks just save
    if ( --cfSaveTicksLeft <= 0 )
        return cfDoSave();

    // okay, wait another second
    cfTimerId = setTimeout( cfTrySave, 1000 );

    // now update the text
    $('#cf-unsaved').html( 'Saving in ' + cfSaveTicksLeft + ' seconds...' );
    $('#cf-unsaved, #cf-hourglass').show();
}


function cfDoSave() {
    // this actually posts the save
    $.post( '/__rpc_contentfilters?mode=save_filters&user=' + DW.currentUser,
        { 'json': JSON.stringify( cfFilters ) },
        function( data ) {
            // FIXME: error handling...
            if ( !data.ok )
                return;

            // we're saved
            cfTimerId = null;
            $('#cf-unsaved, #cf-hourglass').hide();
        },
        'json'
    );
}


function cfSelectMember( sel ) {
    // if we have selected more than one (or less than one) thing, then hide the
    // options box and call it good
    if ( sel.length < 1 || sel.length > 1 ) {
        cfCurrentUserid = null;
        return cfHideOptions();
    }

    // some variables we're going to use later, in particular cfCurrentUserid is
    // used in many places so we know who we're editing
    var userid = sel[0];
    user = cfSubs[userid];
    cfCurrentUserid = userid;
    
    // these have to be true, or we have serious issues
    var filt = cfFilters[cfSelectedFilterId];
    var member = filt.members[cfCurrentUserid];
    if ( !filt || !member )
        return;

    // FIXME: don't always reget the tags
    $.getJSON( '/__rpc_general?mode=list_tags&user=' + user.username, cfUpdateTags );

    // clear out both of the tag lists
    $('#cf-t-box2, #cf-t-box3').empty();

    // if this is a comm show the extra community options
    $('#cf-pt-box').toggle( user.journaltype == 'C' );

    // default the member to a few options...
    if ( ! member.adultcontent )
        member.adultcontent = 'any';
    if ( ! member.postertype )
        member.postertype = 'any';
    if ( ! member.tagmode )
        member.tagmode = 'any_of';

    // now fill the options in
    $('#cf-adultcontent').val( member.adultcontent );
    $('#cf-postertype').val( member.postertype );
    $('#cf-tagmode').val( member.tagmode );

    // and now show the actual options box
    cfShowOptions();
}


function cfHideOptions() {
    $('#cf-options').hide();
}


function cfShowOptions() {
    // if the user is not paid, make sure we disable things, etc
    if ( ! DW.userIsPaid ) {
        $('#cf-adultcontent, #cf-postertype, #cf-tagmode').attr( 'disabled', 'disabled' );
        $('#cf-free-warning').show();
    }

    $('#cf-options').show();
}


function cfAddMembers() {
    var members = $('#cf-notin-list').val();
    var filt = cfFilters[cfSelectedFilterId];
    if ( !filt || members.length <= 0 )
        return;

    // simply create a new row in the filter members list for this person
    for ( i in members ) {
        var userid = members[i];

        filt.members[userid] = {
            'user': cfSubs[userid].username
        };
    }

    // kick off a save event
    cfSaveChanges();

    var $opt = $("#cf-notin-list option");
    var lastsel = $opt.filter(":selected:last").index();
    var at_end = $opt.length - 1 - lastsel == 0;
    var $newsel = $opt.filter((at_end?":lt(":":gt(") + lastsel+")").filter(":not(:selected)" + (at_end?":last":":first"))

    // and then redisplay our lists
    cfPopulateLists( $newsel.val() );
}


function cfRemoveMembers() {
    var members = $('#cf-in-list').val();
    var filt = cfFilters[cfSelectedFilterId];
    if ( ! filt || members.length <= 0 )
        return;

    // simply delete the row in the filter members list for this person
    for ( i in members ) {
        var userid = members[i];

        delete filt.members[userid];
    }

    // kick off a save event
    cfSaveChanges();

    // and then redisplay our lists
    cfPopulateLists();
}


function cfChangedTagMode() {
    var tagmode = $('#cf-tagmode').val();
    var filt = cfFilters[cfSelectedFilterId];
    var member = filt.members[cfCurrentUserid];
    if ( !tagmode || !filt || !member )
        return;

    member.tagmode = tagmode;
    cfSaveChanges();
}


function cfChangedAdultContent() {
    var adultcontent = $('#cf-adultcontent').val();
    var filt = cfFilters[cfSelectedFilterId];
    var member = filt.members[cfCurrentUserid];
    if ( !adultcontent || !filt || !member )
        return;

    member.adultcontent = adultcontent;
    cfSaveChanges();
}


function cfChangedPosterType() {
    var postertype = $('#cf-postertype').val();
    var filt = cfFilters[cfSelectedFilterId];
    var member = filt.members[cfCurrentUserid];
    if ( !postertype || !filt || !member )
        return;

    member.postertype = postertype;
    cfSaveChanges();
}


function cfNewFilter() {
    // prompt the user for a filter name...
    var name = prompt( 'New filter name:', '' );
    if ( ! name )
        return;

    // now that we have a name, kick off a request to make a new filter
    $.getJSON( '/__rpc_contentfilters?mode=create_filter&user=' + DW.currentUser + '&name=' + name,
        function( data ) {
            // no id means some sort of failure
            // FIXME: error handling so the user knows what's up
            if ( !data.id || !data.name )
                return;

            // save a roundtrip, we don't have to hit the server since it just gave us
            // the filter information
            cfFilters[data.id] = {
                'id': data.id,
                'name': data.name,
                'public': data["public"],
                'sortorder': data.sortorder
            };

            // we have to do this first, before the update of the filter select, due to the
            // way the code is structured
            cfSelectFilter( data.id );

            // happens last
            cfUpdateFilterSelect();
        }
    );
}


function cfRenameFilter() {
    var filt = cfFilters[cfSelectedFilterId];
    if ( !filt )
        return;

    // FIXME: don't think dialogs are accessible at all
    var renamed = prompt( 'Rename filter to:', filt.name );
    if ( renamed != null )
        filt.name = renamed;

    // and now update the select dialog
    cfUpdateFilterSelect();
    // and any labeling
    $('#cf-foname').text( cfFilters[cfSelectedFilterId]['name'] );

    // kick off a saaaaaaaave!
    cfSaveChanges();
}

function cfSortOrder() {
    cfFilters[cfSelectedFilterId]['sortorder'] = parseInt( $('#cf-sortorder').val(), 10 );

    cfSaveChanges();
    cfUpdateFilterSelect();
}

function cfPublic( sel ) {
    cfFilters[cfSelectedFilterId]['public'] = sel === "1" ? 1 : 0;

    cfSaveChanges();
}

function cfViewFilter() {
    var filt = cfFilters[cfSelectedFilterId];

    $.getJSON( '/__rpc_contentfilters?mode=view_filter&user=' + DW.currentUser + '&name=' + filt.name,
        function( data ) {
            if ( !data.url )
                return;

            window.open(data.url);
        }
    );
}

// function used for sorting filters -- compares based on sort order, then name
function compareFilters( a, b ) {
    if ( a.sortorder == b.sortorder ) {
        return a.name > b.name ? 1 : a.name < b.name ? -1 : 0;
    }

    return a.sortorder > b.sortorder ? 1 : -1;
}

function cfUpdateFilterSelect() {
    // regenerate HTML for the Filter: dropdown
    var options = '<option value="0">( select filter )</option><option value="0"></option>';

    // sort by sortorder, then name
    var sortedFilters = [];
    for ( i in cfFilters ) {
        sortedFilters.push(cfFilters[i]);
    }
    sortedFilters.sort(compareFilters);

    for ( var i = 0; i < sortedFilters.length; i++ ) {
        var id = sortedFilters[i]['id'];
        cfFilters[id]['members'] = null;
        options += '<option value="' + id + '">' + cfFilters[id].name + '</option>';
    }
    $('#cf-filters').html( options );

    // and if we have a current filter id, reselect
    if ( cfSelectedFilterId )
        $('#cf-filters').val( cfSelectedFilterId );
}


function cfRefreshFilterList() {
    // in a function because we call from multiple places
    $.getJSON( '/__rpc_contentfilters?mode=list_filters&user=' + DW.currentUser, function( data ) {
        cfFilters = data.filters;
        cfUpdateFilterSelect();
    } );
}


function cfDeleteFilter() {
    var filt = cfFilters[cfSelectedFilterId];
    if ( !filt )
        return;

    // confirm!
    if ( ! confirm( 'Really delete this content filter?  There is no turning back if you say yes.' ) )
        return;

    $.getJSON( '/__rpc_contentfilters?mode=delete_filter&user=' + DW.currentUser + '&id=' + filt.id,
        function( data ) {
            // FIXME: error handling ...
            if ( !data.ok )
                return;

            // the filter is gone, so nuke from some of our stuff
            delete cfFilters[filt.id];

            // and update the UI, again, the order of these two calls matters
            cfSelectFilter( null );
            cfUpdateFilterSelect();
        }
    );
}


jQuery( function($) {

    // load the current filters into the box
    cfRefreshFilterList();

    // and get who this person is subscribed to, we're going to need this later
    $.getJSON( '/__rpc_general?mode=list_subscriptions&user=' + DW.currentUser, function( data ) {
        cfSubs = {};
        for ( i in data.subs ) {
            cfSubs[i] = data.subs[i];
        }
        cfPopulateLists();
    } );

    // setup our click handlers
    $('#cf-filters').bind( 'change', function(e) { cfSelectFilter( $(e.target).val() ); } );
    $('#cf-in-list').bind( 'change', function(e) { cfSelectMember( $(e.target).val() ); } );
    $('#cf-add-btn').bind( 'click', function(e) { cfAddMembers(); } );
    $('#cf-del-btn').bind( 'click', function(e) { cfRemoveMembers(); } );
    $('#cf-new').bind( 'click', function(e) { cfNewFilter(); } );
    $('#cf-rename').bind( 'click', function(e) { cfRenameFilter(); } );
    $('#cf-view').bind( 'click', function(e) { cfViewFilter(); } );
    $('#cf-delete').bind( 'click', function(e) { cfDeleteFilter(); } );
    $('#cf-showtypes').bind( 'change', function(e) { cfShowTypes( $(e.target).val() ); } );
    $('#cf-public').bind( 'change', function(e) { cfPublic( $(e.target).val() ); } );
    // not working on the input element? put the function in directly as onChange
    //$('#cf-sortorder').bind( 'change', function(e) { cfSortOrder( $(e.target).val() ); } );

    // if the user is paid, we bind these.  note that even if someone goes through the
    // trouble of hacking up the form and submitting data, the server won't actually give
    // you an advanced filter.  so don't waste your time!
    if ( DW.userIsPaid ) {
        $('#cf-adultcontent').bind( 'change', function(e) { cfChangedAdultContent(); } );
        $('#cf-postertype').bind( 'change', function(e) { cfChangedPosterType(); } );
        $('#cf-tagmode').bind( 'change', function(e) { cfChangedTagMode(); } );
    }

} );
