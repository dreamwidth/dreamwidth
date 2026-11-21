#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Admin::Props;

use strict;
use Encode qw(decode_utf8);
use MIME::Base64 qw(decode_base64 encode_base64);
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use DW::Controller::Admin;
use DW::External::Account;
use LJ::Location;

=head1 NAME

DW::Controller::Admin::Props - Viewing and editing user and logprops

=cut

DW::Routing->register_string( "/admin/propedit", \&propedit_handler );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'propedit',
    ml_scope => '/admin/propedit.tt',
    privs    => [ 'canview:userprops', 'canview:*' ]
);

DW::Routing->register_string( "/admin/entryprops", \&entryprops_handler );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'entryprops',
    ml_scope => '/admin/entryprops.tt',
    privs    => [
        'canview:entryprops',
        'canview:*',
        sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
        }
    ]
);

my %EDITABLE_ENTRYPROPS =
    map { $_ => 1 } qw(adult_content current_coords current_location current_mood current_music);

sub _editable_entryprop {
    my ($name) = @_;
    return unless $EDITABLE_ENTRYPROPS{$name};
    my $meta = LJ::get_prop( 'log', $name ) or return;
    return $meta if $meta->{ownership} eq 'user' && $meta->{datatype} eq 'char';
    return;
}

sub _normalize_form_text {
    my ($value) = @_;
    $value =~ s/\r\n?/\n/g;
    return $value;
}

sub _is_entryprop_text {
    my ($value) = @_;
    return defined $value && $value !~ /\0/ && LJ::is_utf8($value);
}

sub _entryprop_validation_error {
    my ( $name, $value ) = @_;
    return if $value eq '';
    return 'Literal 0 is not supported. Leave the field blank to clear it.' if $value eq '0';
    return 'Enter no more than ' . LJ::BMAX_PROP . ' bytes.' if length($value) > LJ::BMAX_PROP;
    return 'Enter no more than ' . LJ::CMAX_PROP . ' characters.'
        if length( decode_utf8($value) ) > LJ::CMAX_PROP;
    return 'Enter none, concepts, or explicit.'
        if $name eq 'adult_content' && $value !~ /\A(?:none|concepts|explicit)\z/;
    return 'Enter valid coordinates, for example 45.2935N 123.3452W.'
        if $name eq 'current_coords' && !eval { LJ::Location->new( coords => $value ) };
    return;
}

sub _entryprop_changes {
    my ( $post, $errors ) = @_;
    my %changes;
    foreach my $field ( sort grep { /^prop_/ } keys %$post ) {
        my $name = substr( $field, length('prop_') );
        my $meta = _editable_entryprop($name);
        unless ($meta) {
            $errors->add_string( '', 'That entry property is read-only.' );
            next;
        }
        my @values    = $post->get_all($field);
        my @baselines = $post->get_all("baseline_$name");
        unless ( @values == 1 && _is_entryprop_text( $values[0] ) && @baselines == 1 ) {
            $errors->add_string( $field, 'Reload the form and enter one valid text value.' );
            next;
        }
        my $original = decode_base64( $baselines[0] );
        unless ( encode_base64( $original, '' ) eq $baselines[0] && _is_entryprop_text($original) )
        {
            $errors->add_string( $field, 'Reload the form and try again.' );
            next;
        }

        my $value = _normalize_form_text( $values[0] );
        next if $value eq _normalize_form_text($original);
        if ( my $error = _entryprop_validation_error( $name, $value ) ) {
            $errors->add_string( $field, $error );
            next;
        }
        $changes{$name} = { id => $meta->{id}, original => $original, value => $value };
    }
    return \%changes;
}

sub _save_entryprop_changes {
    my ( $entry, $remote, $changes, $entry_props, $errors ) = @_;
    my @names = sort keys %$changes;
    return unless @names;

    my $journal   = $entry->journal;
    my @entry_key = ( $journal->id, $entry->jitemid );
    my $dbh       = LJ::get_cluster_master($journal);
    unless ($dbh) {
        $errors->add_string( '', 'Could not save entry properties. Try again later.' );
        return;
    }

    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;
    my $transaction;
    my $saved = eval {
        my $table = $dbh->selectrow_hashref("SHOW TABLE STATUS WHERE Name = 'logprop2'");
        die 'Entry property saves require transactional storage'
            unless $table && $table->{Engine} eq 'InnoDB';

        $dbh->begin_work;
        $transaction = 1;
        my $placeholders = join ', ', ('?') x @names;
        my $current      = $dbh->selectall_hashref(
            'SELECT propid, value FROM logprop2 WHERE journalid = ? AND jitemid = ? '
                . "AND propid IN ($placeholders) ORDER BY propid FOR UPDATE",
            'propid', undef, @entry_key, map { $changes->{$_}{id} } @names
        );
        foreach my $name (@names) {
            my $change = $changes->{$name};
            my $row    = $current->{ $change->{id} };
            if ( $row && defined $row->{value} ) {
                $entry_props->{$name} = $row->{value};
                next if $row->{value} eq $change->{original};
            }
            else {
                delete $entry_props->{$name};
            }
            $errors->add_string( "prop_$name",
"$name changed since you opened this form. Review the current properties and try again."
            );
        }
        unless ( $errors->exist ) {
            foreach my $name (@names) {
                my $change = $changes->{$name};
                if ( length $change->{value} ) {
                    $dbh->do(
'UPDATE logprop2 SET value = ? WHERE journalid = ? AND jitemid = ? AND propid = ?',
                        undef, $change->{value}, @entry_key, $change->{id}
                    );
                }
                else {
                    $dbh->do(
                        'DELETE FROM logprop2 WHERE journalid = ? AND jitemid = ? AND propid = ?',
                        undef, @entry_key, $change->{id} );
                }
            }
            $dbh->commit;
            $transaction = 0;
        }
        !$errors->exist;
    };
    eval { $dbh->rollback } if $transaction;
    unless ($saved) {
        $errors->add_string( '', 'Could not save entry properties. Try again later.' )
            unless $errors->exist;
        return;
    }

    my $audit_note = 'Entry ' . $entry->ditemid . ': ' . join( ', ', @names );
    my $recorded   = eval { LJ::statushistory_add( $journal, $remote, 'entryprops', $audit_note ) };
    unless ($recorded) {
        warn sprintf "Could not write entryprops audit record for journal %d, admin %d: %s\n",
            $journal->id, $remote->id, $audit_note;
        $errors->add_string( '', 'Changes were saved, but the audit record could not be written.' );
    }

    LJ::MemCache::delete( [ $journal->id, 'logprop:' . join( ':', @entry_key ) ] );
    foreach my $name (@names) {
        my $value = $changes->{$name}{value};
        if ( length $value ) {
            $entry_props->{$name} = $value;
        }
        else {
            delete $entry_props->{$name};
        }
    }
    return 1;
}

sub entryprops_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller(
        privcheck => [
            'canview:entryprops',
            'canview:*',
            sub {
                return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
            }
        ],
        form_auth => 0
    );
    return $rv unless $ok;

    my $r        = $rv->{r};
    my $remote   = $rv->{remote};
    my $can_save = $remote->has_priv( 'canview', 'entryprops' )
        && $remote->has_priv( 'siteadmin', 'entryprops' );
    my %entry_info;
    my @props;
    my $saved;

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        my $post = $r->post_args;
        if ( $post->{_save} ) {
            return error_ml( 'admin.noprivserror',
                { numprivs => 1, needprivs => 'siteadmin:entryprops' } )
                unless $can_save;
            return error_ml('error.invalidform')
                unless LJ::check_form_auth( $post->{lj_form_auth} )
                && LJ::check_referer('/admin/entryprops');
        }
        my $entry = LJ::Entry->new_from_url( LJ::trim( $post->{url} ) );

        my $url = LJ::ehtml( $post->{url} );
        $errors->add_string( 'url', "$url is not a valid entry URL." )
            unless $entry && $entry->correct_anum;

        unless ( $errors->exist ) {

            # WE HAEV ENTRY!!

            my $subject;
            if ( $entry->visible_to($remote) ) {
                $subject = $entry->subject_html ? $entry->subject_html : "<em>no subject</em>";
            }
            else {
                $subject = "<em>hidden</em>";
            }

            my $security = $entry->security;
            if ( $security eq "usemask" ) {
                if ( $entry->allowmask == 1 ) {
                    $security = "friends";
                }
                else {
                    $security = "custom";
                }
            }

            my $pu      = $entry->poster;
            my $journal = $entry->journal;
            %entry_info = (
                subject       => $subject,
                security      => $security,
                url           => $entry->url,
                poster        => $pu->ljuser_display,
                journal       => $journal->ljuser_display,
                minsecurity   => $journal->prop("newpost_minsecurity") || "public",
                user_time     => $entry->eventtime_mysql,
                server_time   => $entry->logtime_mysql,
                adult_content => $journal->adult_content || "none",
            );
            $entry_info{edit_url} =
                "$LJ::SITEROOT/users/" . $journal->user . '/' . $entry->ditemid . '.html';

            my %entry_props = %{ $entry->props || {} };
            if ( $post->{_save} ) {
                my $changes = _entryprop_changes( $post, $errors );
                $saved =
                    _save_entryprop_changes( $entry, $remote, $changes, \%entry_props, $errors )
                    unless $errors->exist;
            }
            foreach my $prop_name ( sort keys %entry_props ) {
                my %prop = (
                    name        => $prop_name,
                    value       => $entry_props{$prop_name},
                    description => "",
                );
                my $raw_value = $prop{value};
                if (   $can_save
                    && _editable_entryprop($prop_name)
                    && _is_entryprop_text($raw_value) )
                {
                    $prop{field}          = "prop_$prop_name";
                    $prop{baseline_field} = "baseline_$prop_name";
                    $prop{baseline}       = encode_base64( $raw_value, '' );
                    $prop{raw_value}      = $raw_value;
                    $prop{textarea_value} = "\n$raw_value" if $raw_value =~ /[\r\n]/;
                }
                if ( my $prop_meta = LJ::get_prop( 'log', $prop_name ) ) {
                    $prop{description} = $prop_meta->{des};

                    # an ugly hack, i know
                    $prop{value} = LJ::mysql_time( $prop{value} ) if $prop_meta->{des} =~ /unix/i;

                    # render xpost prop into human readable form
                    if ( $prop_name eq "xpost" || $prop_name eq "xpostdetail" ) {
                        my %external_accounts_map = map {
                            $_->acctid => $_->servername . ( $_->active ? "" : " (deleted)" )
                        } DW::External::Account->get_external_accounts( $pu,
                            show_inactive => 1 );

                        # FIXME: temporary; trying to figure out when this is undef
                        my $xpost_prop = $prop{value};
                        my $xpost_hash =
                            DW::External::Account->xpost_string_to_hash( $prop{value} );
                        my %xpost_map = %{ $xpost_hash || {} };

                        if ( $prop_name eq "xpost" ) {
                            $prop{value} = join ", ", map {
                                ( $external_accounts_map{$_} || "unknown" ) . " => $xpost_map{$_}"
                            } keys %xpost_map;
                            $prop{description} .= " (site name => itemid)";
                        }
                        else {
                            $prop{value} = join ", ", map {
                                ( $external_accounts_map{$_} || "unknown" )
                                    . " => { $xpost_map{$_}->{itemid}, $xpost_map{$_}->{url} }"
                            } keys %xpost_map;
                            $prop{description} .= " (site name => { itemid, url })";
                        }

                    }
                    elsif ( $prop_name eq 'picture_mapid' && $pu->userpic_have_mapid ) {
                        my $result = "$prop{value} -> ";
                        my $kw     = $pu->get_keyword_from_mapid(
                            $prop{value},
                            redir_callback => sub {
                                $result .= "$_[2] -> ";
                            }
                        );
                        $result .= $kw;
                        my $picid = $pu->get_picid_from_keyword( $kw, -1 );
                        if ( $picid == -1 ) {
                            $result .= " ( not assigned to an icon )";
                        }
                        else {
                            $result .= " ( assigned to an icon )";
                        }
                        $prop{value} = $result;
                    }
                }
                push @props, \%prop;
            }
        }
    }

    my $vars = {
        entry          => %entry_info ? \%entry_info : undef,
        props          => \@props,
        errors         => $errors,
        can_save       => scalar grep( $_->{field}, @props ),
        saved          => $saved,
        max_prop_chars => LJ::CMAX_PROP,
    };
    return DW::Template->render_template( "admin/entryprops.tt", $vars );
}

sub propedit_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) =
        controller( privcheck => [ 'canview:userprops', 'canview:*' ], form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $u;
    my @props;

    my $can_save = $remote && $remote->has_priv( "siteadmin", "propedit" );

    my $errors = DW::FormErrors->new;
    if ( $r->did_post && LJ::check_referer('/admin/propedit') ) {
        my $post = $r->post_args;

        $u = LJ::load_user( $post->{username} );
        my $username = LJ::ehtml( $post->{username} );
        $errors->add_string( 'username', "$username is not a valid username" ) unless $u;

        unless ( $errors->exist ) {

            if ( $can_save && $post->{_save} ) {
                foreach my $key ( $post->keys ) {
                    next if $key eq 'username';
                    next if $key eq '_save';
                    next if $key eq 'value';
                    next if $key eq 'lj_form_auth';

                    next unless LJ::get_prop( "user", $key );
                    $u->set_prop( $key, $post->{$key} );
                }
            }

            my $dbr = LJ::get_db_reader();
            my $sth = $dbr->prepare("SELECT * from userproplist ORDER BY name;");
            $sth->execute;

            while ( my $p = $sth->fetchrow_hashref ) {
                push @props,
                    {
                    name        => $p->{name},
                    value       => $u->raw_prop( $p->{name} ),
                    description => $p->{des},
                    is_text     => $p->{des} !~ /Storable hashref/,
                    };
            }
        }
    }

    # statusvis => english
    my %statusvis_map = (
        'V' => 'Visible',
        'D' => 'Deleted',
        'E' => 'Expunged',
        'S' => 'Suspended',
        'L' => 'Locked',
        'M' => 'Memorial',
        'O' => 'Read-Only',
        'R' => 'Renamed',
    );

    my $vars = {
        can_save => $can_save,
        u        => $u
        ? {
            username          => $u->username,
            userid            => $u->userid,
            clusterid         => $u->clusterid,
            dversion          => $u->dversion,
            statusvis         => $u->statusvis,
            statusvis_display => $statusvis_map{ $u->statusvis } || "???",
            }
        : undef,
        props  => \@props,
        errors => $errors,
    };
    return DW::Template->render_template( "admin/propedit.tt", $vars );
}

1;
