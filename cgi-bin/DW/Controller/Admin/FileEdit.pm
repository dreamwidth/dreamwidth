#!/usr/bin/perl
#
# DW::Controller::Admin::FileEdit
#
# Frontend for editing site content stored in local files. Note that
# any edits are saved in the includetext table, not in the actual file.
# (File contents are loaded using the LJ::load_include function.)
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::FileEdit;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/admin/fileedit/index", \&index_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'fileedit',
    ml_scope => '/admin/fileedit/index.tt',
    privs    => ['fileedit']
);

sub index_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['fileedit'] );
    return $rv unless $ok;

    my $scope = '/admin/fileedit/index.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = {};

    my $valid_filename = sub { return ( $_[0] =~ /^[a-zA-Z0-9-\_]{1,80}$/ ) };

    {    # construct sorted list of files visible to remote

        my $remote  = $rv->{remote};
        my %files   = $remote->priv_args("fileedit");
        my $INC_DIR = "$LJ::HTDOCS/inc";

        if ( $files{'*'} ) {

            # if user has access to edit all files, find what those files are!
            delete $files{'*'};
            opendir( DIR, $INC_DIR );
            while ( my $f = readdir(DIR) ) {
                $files{$f} = 1;
            }
            closedir(DIR);
        }

        # get rid of any listed files that don't match our safe pattern
        my @fn = keys %files;
        foreach my $f (@fn) {
            delete $files{$f} unless $valid_filename->($f);
        }

        $vars->{files}     = \%files;
        $vars->{file_menu} = [ map { $_, $_ } ( sort keys %files ) ];
    }

    my $DEF_ROW = 30;
    my $DEF_COL = 80;

    my $mode = $form_args->{mode};
    $mode ||= $form_args->{file} ? "edit" : "pick";

    if ( $mode eq "pick" ) {
        $vars->{formdata} = { r => $DEF_ROW, c => $DEF_COL };
        return DW::Template->render_template( 'admin/fileedit/index.tt', $vars );
    }

    # all other modes require a file argument that needs validation
    $vars->{file} = $form_args->{file};

    return error_ml("$scope.error.nofile")
        unless defined $vars->{file} && $vars->{files}->{ $vars->{file} };

    if ( $mode eq "edit" ) {
        my $load_file = sub {
            my ($filename) = @_;
            return undef unless $valid_filename->($filename);
            return LJ::load_include($filename);
        };

        my $contents = $load_file->( $vars->{file} );

        return error_ml( "$scope.error.noload", { filename => $vars->{file} } )
            unless defined $contents;

        # this is escaped by form.textarea in the template
        $vars->{contents} = $contents;

        $vars->{txt} = {
            r => ( $form_args->{r} || $DEF_ROW ) + 0,
            c => ( $form_args->{c} || $DEF_COL ) + 0,
            w => ( $form_args->{w} ? "SOFT" : "OFF" ),
        };

        return DW::Template->render_template( 'admin/fileedit/editform.tt', $vars );
    }

    if ( $mode eq "save" ) {
        return error_ml("bml.requirepost") unless $r->did_post;

        my $save_file = sub {
            my ( $filename, $content ) = @_;
            return 0 unless $valid_filename->($filename);

            my $dbh = LJ::get_db_writer();
            $dbh->do(
                "REPLACE INTO includetext (incname, inctext, updatetime) "
                    . "VALUES (?, ?, UNIX_TIMESTAMP())",
                undef, $filename, $content
            );
            return 0 if $dbh->err;

            LJ::MemCache::set( "includefile:$filename", $content );
            return 1;
        };

        if ( $save_file->( $vars->{file}, $form_args->{contents} ) ) {
            return DW::Controller->render_success( 'admin/fileedit/editform.tt',
                { file => $vars->{file} } );
        }
        else {
            return error_ml("$scope.error.nosave");
        }
    }

    # if we got here, we were passed a form mode other than "save"
    return error_ml("$scope.error.mode");
}

1;
