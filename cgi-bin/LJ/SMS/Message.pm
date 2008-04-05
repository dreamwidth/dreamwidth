package LJ::SMS::Message;

use strict;
use Carp qw(croak);

use Class::Autouse qw(
                      IO::Socket::INET
                      LJ::Typemap
                      DSMS::Message
                      DateTime
                      LJ::SMS::MessageAck
                      );

# LJ::SMS::Message object
#
# internal fields:
#
# FIXME: optional msgid arg if in db?
#
#    owner_uid:  userid of the 'owner' of this SMS
#                -- the user object who is sending
#                   or receiving this message
#    from_uid:   userid of the sender
#    from_num:   phone number of sender
#    to_uid:     userid of the recipient
#    to_num:     phone number of recipient
#    msgid:      optional message id if saved to DB
#    timecreate: timestamp when message was created
#    class_key:  key identifier for the type of this message
#    type:       'incoming' or 'outgoing' from LJ's perspective
#    status:     'success', 'error', or 'unknown' depending on msg status
#    error:      error string associated with this message, if any
#    body_text:  decoded text body of message
#    body_raw:   raw text body of message
#    meta:       hashref of metadata key/value pairs
#    acks:       array of SMS::MessageAck objects loaded from DB
#                -- note that these are read-only
#
# synopsis:
#
#    my $sms = LJ::SMS->new(owner     => $owneru,
#                           class_key => 'msg-type-123',
#                           type      => 'outgoing',
#                           status    => 'unknown',
#                           from      => $num_or_u,
#                           to        => $num_or_u,
#                           body_text => $utf8_text,
#                           meta      => { k => $v },
#                           );
#
#    my $sms = LJ::SMS->new_from_dsms($dsms_msg);
#
# accessors:
#
#    $msg->owner_u;
#    $msg->to_num;
#    $msg->from_num;
#    $msg->to_u;
#    $msg->from_u;
#    $msg->class_key;
#    $msg->type;
#    $msg->status;
#    $msg->error;
#    $msg->msgid;
#    $msg->body_text;
#    $msg->raw_text;
#    $msg->timecreate;
#    $msg->meta;
#    $msg->meta($k);
#    $msg->gateway_obj;
#    $msg->acks;
#
# FIXME: singletons + lazy loading for queries
#

sub new {
    my ($class, %opts) = @_;
    croak "new is a class method"
        unless $class eq __PACKAGE__;

    my $self = bless {}, $class;

    # from/to can each be passed as either number or $u object
    # in any case $self will end up with the _num and _uid fields
    # specified for each valid from/to arg
    foreach my $k (qw(from to)) {
        my $val = delete $opts{$k};
        next unless $val;

        # extract fields from $u object
        if (LJ::isu($val)) {
            my $u = $val;
            $self->{"${k}_uid"} = $u->{userid};
            $self->{"${k}_num"} = $u->sms_mapped_number
                or croak "'$k' user has no mapped number";
            next;
        }

        # normalize the number before validating...
        $val = $self->normalize_num($val);

        if ($val =~ /^\+?\d+$/) {
            # right now, we're trying to verify what a user has sent to us,
            # and if they haven't been verified yet then we need to send
            # verified_only = 0 until we mark them as verified.
            $self->{"${k}_uid"} = LJ::SMS->num_to_uid($val, verified_only => 0);
            $self->{"${k}_num"} = $val;
            next;
        }

        croak "invalid numeric argument '$k': $val";
    }

    # type: incoming/outgoing.  attempt to infer if none is specified
    $self->{type} = lc(delete $opts{type});
    unless ($self->{type}) {
        if ($self->{from_uid} && $self->{to_uid}) {
            croak "cannot send user-to-user messages";
        } elsif ($self->{from_uid}) {
            $self->{type} = 'incoming';
        } elsif ($self->{to_uid}) {
            $self->{type} = 'outgoing';
        }
    }

    # allow class_key to be set
    $self->{class_key} = delete $opts{class_key} || 'unknown';

    # now validate an explict or inferred type
    croak "type must be one of 'incoming' or 'outgoing', from the server's perspective"
        unless $self->{type} =~ /^(?:incoming|outgoing)$/;

    # from there, fill in the from/to num defaulted to $LJ::SMS_SHORTCODE
    if ($self->{type} eq 'outgoing') {
        croak "need valid 'to' argument to construct outgoing message"
            unless $self->{"to_num"};
        $self->{from_num} ||= $LJ::SMS_SHORTCODE;
    } else {
        croak "need valid 'from' argument to construct incoming message"
            unless $self->{"from_num"};
        $self->{to_num} ||= $LJ::SMS_SHORTCODE;
    }

    { # owner argument
        my $owner_arg = delete $opts{owner};
        croak "owner argument must be a valid user object"
            unless LJ::isu($owner_arg);

        $self->{owner_uid} = $owner_arg->{userid};
    }

    # omg we need text eh?
    $self->{body_text} = delete $opts{body_text};
    $self->{body_raw}  = exists $opts{body_raw} ? delete $opts{body_raw} : $self->{body_text};

    { # any metadata the user would like to pass through
        $self->{meta} = delete $opts{meta};
        croak "invalid 'meta' argument"
            if $self->{meta} && ref $self->{meta} ne 'HASH';

        $self->{meta} ||= {};
    }

    { # any message acks received for this message
        $self->{acks} = delete $opts{acks} || [];
        unless (ref $self->{acks} eq 'ARRAY' &&
                ! grep { ! ref $_ && ! $_->isa("LJ::SMS::MessageAck") } @{$self->{acks}})
        {
            croak "invalid 'acks' argument";
        }
    }

    # set timecreate stamp for this object
    $self->{timecreate} = delete $opts{timecreate} || time();
    croak "invalid 'timecreate' parameter: $self->{timecreate}"
        unless int($self->{timecreate}) > 0;

    # by default set status to 'unknown'
    $self->{status} = lc(delete $opts{status}) || 'unknown';
    croak "invalid msg status: $self->{status}"
        unless $self->{status} =~ /^(?:success|ack_wait|error|unknown)$/;

    # set msgid if a non-zero one was specified
    $self->{msgid} = delete $opts{msgid};
    croak "invalid msgid: $self->{msgid}"
        if $self->{msgid} && int($self->{msgid}) <= 0;

    # probably no error string specified here
    $self->{error} = delete $opts{error} || undef;

    # able to pass in a gateway object, but default works too
    $self->{gateway} = delete $opts{gateway} || LJ::sms_gateway();
    croak "invalid gateway object: $self->{gateway}"
        unless $self->{gateway} && $self->{gateway}->isa("DSMS::Gateway");

    die "invalid arguments: " . join(", ", keys %opts)
        if %opts;

    return $self;
}

sub new_from_dsms {
    my ($class, $dsms_msg) = @_;
    croak "new_from_dsms is a class method"
        unless $class eq __PACKAGE__;

    croak "invalid dsms_msg argument: $dsms_msg"
        unless ref $dsms_msg eq 'DSMS::Message';

    my $owneru = undef;
    {
        my $owner_num = $dsms_msg->is_incoming ?
            $dsms_msg->from : $dsms_msg->to;

        $owner_num = $class->normalize_num($owner_num);

        my $uid = LJ::SMS->num_to_uid($owner_num, verified_only => 0)
            or croak "invalid owner id from number: $owner_num";

        $owneru = LJ::load_userid($uid);
        croak "invalid owner u from number: $owner_num"
            unless LJ::isu($owneru);
    }

    # LJ needs utf8 flag off for all fields, we'll do that
    # here now that we're officially in LJ land.
    $dsms_msg->encode_utf8;

    # construct a new LJ::SMS::Message object
    my $msg = $class->new
        ( owner     => $owneru,
          from      => $class->normalize_num($dsms_msg->from),
          to        => $class->normalize_num($dsms_msg->to),
          type      => $dsms_msg->type,
          body_text => $dsms_msg->body_text,
          body_raw  => $dsms_msg->body_raw,
          meta      => $dsms_msg->meta,
          );

    # class_key is still unknown here, to be set later

    return $msg;
}

sub load {
    my $class = shift;
    croak "load is a class method"
        unless $class eq __PACKAGE__;

    my $owner_u = shift;
    croak "invalid owner_u: $owner_u"
        unless LJ::isu($owner_u);

    my $uid      = $owner_u->{userid};
    my @msgids   = ();
    my $msg_rows = {};
    my $bind     = "";

    # remaining args can be key/value pairs of options, or a list of msgids
    if ($_[0] =~ /\D/) {
        my %opts = @_;

        # loading msgids by month and year
        if (exists $opts{month} || exists $opts{year}) {
            my $month = delete $opts{month};
            croak "invalid month: $month"
                unless $month =~ /^\d\d?$/ && $month > 0 && $month <= 12;

            my $year  = delete $opts{year};
            croak "invalid year: $year"
                unless $year =~ /^\d{4}$/;

            croak "invalid options for year/month load: " . join(",", keys %opts) if %opts;

            my $dt = DateTime->new(year => $year, month => $month);
            my $start_time = $dt->epoch;
            my $end_time   = $dt->add(months => 1)->epoch;

            $msg_rows = $owner_u->selectall_hashref
                ("SELECT msgid, class_key, type, status, to_number, from_number, timecreate " .
                 "FROM sms_msg WHERE userid=? AND timecreate>=? AND timecreate<?",
                 'msgid', undef, $uid, $start_time, $end_time) || {};
            die $owner_u->errstr if $owner_u->err;

        # not sure what args they're giving
        } else {
            croak "invalid parameters: " . join(",", keys %opts)
                if %opts;
        }

        # which messageids matched the above constraint?
        @msgids = sort {$a <=> $b} keys %$msg_rows;

    } else {
        @msgids = @_;
        croak "invalid msgid: $_"
            if grep { ! $_ || int($_) <= 0 } @msgids;

        $bind = join(",", map { "?" } @msgids);
        $msg_rows = $owner_u->selectall_hashref
            ("SELECT msgid, class_key, type, status, to_number, from_number, timecreate " .
             "FROM sms_msg WHERE userid=? AND msgid IN ($bind)",
             'msgid', undef, $uid, @msgids) || {};
        die $owner_u->errstr if $owner_u->err;

        @msgids = grep { exists $msg_rows->{$_} } @msgids;
    }

    return wantarray ? () : undef unless scalar @msgids;

    # now update $bind to be consistent with the @msgids value found above
    $bind = join(",", map { "?" } @msgids);

    my $text_rows = $owner_u->selectall_hashref
        ("SELECT msgid, msg_raw, msg_decoded FROM sms_msgtext WHERE userid=? AND msgid IN ($bind)",
         'msgid', undef, $uid, @msgids) || {};
    die $owner_u->errstr if $owner_u->err;

    my $error_rows = $owner_u->selectall_hashref
        ("SELECT msgid, error FROM sms_msgerror WHERE userid=? AND msgid IN ($bind)",
         'msgid', undef, $uid, @msgids) || {};
    die $owner_u->errstr if $owner_u->err;

    my $tm = $class->typemap;

    my $prop_rows = {};
    my $sth = $owner_u->prepare
        ("SELECT msgid, propid, propval FROM sms_msgprop WHERE userid=? AND msgid IN ($bind)");
    $sth->execute($uid, @msgids);
    while (my ($msgid, $propid, $propval) = $sth->fetchrow_array) {
        my $propname = $tm->typeid_to_class($propid)
            or die "no propname for propid: $propid";

        $prop_rows->{$msgid}->{$propname} = $propval;
    }

    # load message acks for all messages
    my @acks = LJ::SMS::MessageAck->load($owner_u, @msgids);
    my %acks_by_msgid = ();
    foreach my $ack (@acks) {
        push @{$acks_by_msgid{$ack->msgid}}, $ack;
    }

    my @ret_msgs = ();
    foreach my $msgid (@msgids) {
        my $msg_row   = $msg_rows->{$msgid};
        my $text_row  = $text_rows->{$msgid};
        my $error_row = $error_rows->{$msgid};
        my $props     = $prop_rows->{$msgid};

        push @ret_msgs, $class->new
            ( owner      => $owner_u,
              msgid      => $msgid,
              error      => $error_row->{error},
              meta       => $props,
              acks       => $acks_by_msgid{$msgid},
              from       => $msg_row->{from_number},
              to         => $msg_row->{to_number},
              class_key  => $msg_row->{class_key},
              type       => $msg_row->{type},
              status     => $msg_row->{status},
              timecreate => $msg_row->{timecreate},
              body_text  => $text_row->{msg_decoded},
              body_raw   => $text_row->{msg_raw},
              );
    }

    return wantarray() ? @ret_msgs : $ret_msgs[0];
}

sub load_by_uniq {
    my $class = shift;
    croak "load is a class method"
        unless $class eq __PACKAGE__;

    my $msg_uniq = shift;
    croak "invalid msg_uniq: must not be empty"
        unless length $msg_uniq;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master";

    my ($userid, $msgid) = $dbh->selectrow_array
        ("SELECT userid, msgid FROM smsuniqmap WHERE msg_uniq=?",
         undef, $msg_uniq);
    die $dbh->errstr if $dbh->err;

    my $owner_u = LJ::load_userid($userid)
        or die "invalid owner for uniq: $msg_uniq";

    return $class->load($owner_u, $msgid);
}

sub register_uniq {
    my $self     = shift;
    my $msg_uniq = shift;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master";

    my $owner_u = $self->owner_u;

    my $rv = $dbh->do("REPLACE INTO smsuniqmap SET msg_uniq=?, userid=?, msgid=?",
                      undef, $msg_uniq, $owner_u->id, $self->msgid);
    die $dbh->errstr if $dbh->err;

    return $rv;
}

sub recv_ack {
    my $self = shift;
    my $ack  = shift;
    my $meta = shift;
    croak "invalid ack for recv_ack: $ack"
        unless $ack && $ack->isa("LJ::SMS::MessageAck");
    croak "invalid meta arg: $meta"
        if $meta && ref $meta ne 'HASH';

    # warn if we receive an ack for a message which is no longer awaiting acks
    unless ($self->is_awaiting_ack) {
        my $userid = $self->owner_u->id;
        my $msgid  = $self->msgid;
        warn "message not awaiting ack: uid=$userid, msgid=$msgid";
    }

    # save this ack to the db if it hasn't been done already
    $ack->save_to_db;

    # take metadata from DSMS ack and append it to the message's 'meta' fieldset
    if ($meta) {
        my %to_append = ();
        while (my ($k, $v) = each %{$meta||{}}) {
            next unless $v;
            $to_append{uc(join("_", "ACK", $ack->type, $k))} = $v;
        }

        $self->meta(%to_append);
    }

    # gateway ack's don't indicate final success,
    # return early unless the ack is from the smsc
    return 1 unless $ack->type eq 'smsc';

    # our status flag is now that of the ack which was
    # received:  success, error, unknown
    if ($ack->status_flag eq 'error') {
        $self->status('error' => $ack->status_text);
    } else {
        $self->status($ack->status_flag);
    }

    return LJ::run_hook("sms_recv_ack", $self, $ack);

    return 1;
}

sub gateway {
    my $self = shift;

    if (@_) {
        my $gw = shift;
        croak "invalid gateway param"
            unless $gw;

        # setting a gateway object
        if (ref $gw) {
            croak "invalid gateway object: $gw"
                unless $gw->isa("DSMS::Gateway");

            return $self->{gateway} = $gw;

        # setting a new object via gw key
        } else {
            return $self->{gateway} = LJ::sms_gateway($gw);
        }
    }

    return $self->{gateway};
}

sub typemap {
    my $class = shift;

    return LJ::Typemap->new
        ( table      => 'sms_msgproplist',
          classfield => 'name',
          idfield    => 'propid',
          );
}

sub normalize_num {
    my $class = shift;
    my $arg = shift;
    $arg = ref $arg ? $arg->[0] : $arg;

    # add +1 if it's a US number
    $arg = "+1$arg" if $arg =~ /^\d{10}$/;

    return $arg;
}

sub meta {
    my $self = shift;
    my $key  = shift;
    my $val  = shift;

    my $meta = $self->{meta} || {};

    # if a value was specified for a set, handle that here
    if ($key && $val) {

        my %to_set = ($key => $val, @_);

        # if saved to the db, go ahead and write out now
        if ($self->msgid) {

            my $tm    = $self->typemap;
            my $u     = $self->owner_u;
            my $uid   = $u->id;
            my $msgid = $self->id;

            my @vals = ();
            while (my ($k, $v) = each %to_set) {
                next if $v eq $meta->{$k};

                my $propid = $tm->class_to_typeid($k);
                push @vals, ($uid, $msgid, $propid, $v);
            }

            if (@vals) {
                my $bind = join(",", map { "(?,?,?,?)" } (1..@vals/4));

                $u->do("REPLACE INTO sms_msgprop (userid, msgid, propid, propval) VALUES $bind",
                       undef, @vals);
                die $u->errstr if $u->err;
            }
        }

        # update elements in memory
        while (my ($k, $v) = each %to_set) {
            $meta->{$k} = $v;
        }

        # return new set value of the first element passed
        return $meta->{$key};
    }

    # if a specific key was specified, return that element
    # ... otherwise return a hashref of all k/v pairs
    return $key ? $meta->{$key} : $meta;
}

sub owner_u {
    my $self = shift;

    # load user obj if valid uid and return
    my $uid = $self->{owner_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub to_num {
    my $self = shift;
    return $self->{to_num};
}

sub to_u {
    my $self = shift;

    # load userid from db unless the cache key exists
    $self->{to_uid} = LJ::SMS->num_to_uid($self->{to_num}, verified_only => 0)
        unless exists $self->{to_uid};

    # load user obj if valid uid and return
    my $uid = $self->{to_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub from_num {
    my $self = shift;
    return $self->{from_num};
}

sub from_u {
    my $self = shift;

    # load userid from db unless the cache key exists
    $self->{_from_uid} = LJ::SMS->num_to_uid($self->{from_num}, verified_only => 0)
        unless exists $self->{_from_uid};

    # load user obj if valid uid and return
    my $uid = $self->{_from_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub class_key {
    my $self = shift;

    if (@_) {
        my $val = shift;
        croak "invalid value for 'class_key': $val"
            unless length $val;

        if ($self->msgid && $val ne $self->{class_key}) {
            my $owner_u = $self->owner_u;
            $owner_u->do("UPDATE sms_msg SET class_key=? WHERE userid=? AND msgid=?",
                         undef, $val, $owner_u->{userid}, $self->msgid);
            die $owner_u->errstr if $owner_u->err;
        }

        return $self->{class_key} = $val;
    }

    return $self->{class_key};
}

sub type {
    my $self = shift;

    if (@_) {
        my $val = shift;
        croak "invalid value for 'status': $val"
            unless $val =~ /^(?:incoming|outgoing)$/;

        if ($self->msgid && $val ne $self->{type}) {
            my $owner_u = $self->owner_u;
            $owner_u->do("UPDATE sms_msg SET type=? WHERE userid=? AND msgid=?",
                         undef, $val, $owner_u->{userid}, $self->msgid);
            die $owner_u->errstr if $owner_u->err;
        }

        return $self->{type} = $val;
    }

    return $self->{type};
}

sub timecreate {
    my $self = shift;
    return $self->{timecreate};
}

sub msgid {
    my $self = shift;
    return $self->{msgid};
}
*id = \&msgid;

sub status {
    my $self = shift;

    if (@_) {
        my $val = shift;
        croak "invalid value for 'status': $val"
            unless $val =~ /^(?:success|ack_wait|error|unknown)$/;

        if ($self->msgid && $val ne $self->{status}) {
            my $owner_u = $self->owner_u;
            $owner_u->do("UPDATE sms_msg SET status=? WHERE userid=? AND msgid=?",
                         undef, $val, $owner_u->{userid}, $self->msgid);
            die $owner_u->errstr if $owner_u->err;
        }

        # third argument to call as $self->('error' => $err_str);
        if (@_ && $val eq 'error') {
            my $val_arg = shift;
            $self->error($val_arg);
        }

        return $self->{status} = $val;
    }

    return $self->{status};
}

sub error {
    my $self = shift;

    if (@_) {
        my $errstr = shift;

        # changing an errstr on an object that lives in the db?
        if ($self->msgid && $errstr ne $self->{error}) {
            my $owner_u = $self->owner_u;
            $owner_u->do("REPLACE INTO sms_msgerror SET userid=?, msgid=?, error=?",
                         undef, $owner_u->{userid}, $self->msgid, $errstr);
            die $owner_u->errstr if $owner_u->err;
        }

        return $self->{error} = $errstr;
    }

    return $self->{error};
}

sub is_success {
    my $self = shift;
    return $self->status eq 'success' ? 1 : 0;
}

sub is_error {
    my $self = shift;
    return $self->status eq 'error' ? 1 : 0;
}

sub is_awaiting_ack {
    my $self = shift;
    return $self->status eq 'ack_wait' ? 1 : 0;
}

sub body_text {
    my $self = shift;

    return $self->{body_text} unless $LJ::IS_DEV_SERVER;

    # shared test gateway requires prefix of "lj " before
    # any message to ensure it is delivered to us
    my $body_text = $self->{body_text} || '';
    $body_text =~ s/^lj\s+//i;
    return $body_text;
}

sub body_raw {
    my $self = shift;
    return $self->{body_raw};
}

sub save_to_db {
    my $self = shift;

    # do nothing if already saved to db
    return 1 if $self->{msgid};

    my $u = $self->owner_u
        or die "no owner object found";
    my $uid = $u->{userid};

    # allocate a user counter id for this messaGe
    my $msgid = LJ::alloc_user_counter($u, "G")
        or die "Unable to allocate msgid for user: " . $self->owner_u->{user};

    # insert main sms_msg row
    my $timestamp = $LJ::_T_SMS_NOTIF_LIMIT_TIME_OVERRIDE ? time() : 'UNIX_TIMESTAMP()';
    $u->do("INSERT INTO sms_msg SET userid=?, msgid=?, class_key=?, type=?, " .
           "status=?, to_number=?, from_number=?, timecreate=$timestamp",
           undef, $uid, $msgid, $self->class_key, $self->type, $self->status,
           $self->to_num, $self->from_num);
    die $u->errstr if $u->err;

    # save blob parts to their table
    $u->do("INSERT INTO sms_msgtext SET userid=?, msgid=?, msg_raw=?, msg_decoded=?",
           undef, $uid, $msgid, $self->body_raw, $self->body_text);
    die $u->errstr if $u->err;

    # save error string if any
    if ($self->error) {
        $u->do("INSERT INTO sms_msgerror SET userid=?, msgid=?, error=?",
               undef, $u->{userid}, $msgid, $self->error);
        die $u->errstr if $u->err;
    }

    # save msgid into this object
    $self->{msgid} = $msgid;

    # write props out to db...
    $self->save_props_to_db;

    # acks are read-only, inserted elsewhere

    return 1;
}

sub save_props_to_db {
    my $self    = shift;

    my $tm = $self->typemap;

    my $u     = $self->owner_u;
    my $uid   = $u->id;
    my $msgid = $self->id;

    my @vals = ();
    while (my ($propname, $propval) = each %{$self->meta}) {
        my $propid = $tm->class_to_typeid($propname);
        push @vals => $uid, $msgid, $propid, $propval;
    }

    if (@vals) {
        my $bind = join(",", map { "(?,?,?,?)" } (1..@vals/4));

        $u->do("REPLACE INTO sms_msgprop (userid, msgid, propid, propval) VALUES $bind",
               undef, @vals);
        die $u->errstr if $u->err;
    }

    return 1;
}

sub respond {
    my $self = shift;
    my $body_text = shift;
    my %opts = @_;

    my $resp = LJ::SMS::Message->new
        ( owner     => $self->owner_u,
          from      => $self->to_num,
          to        => $self->from_num,
          body_text => $body_text );

    # set class key if one was specified via opts or
    # one can be inferred via the message we're responding to
    {
        my $class_key = delete $opts{class_key};

        # explicit class_key
        my $explicit = 1 if $class_key;

        # fall back to other means
        $class_key ||=
            $self->class_key             || # class_key set on $self
            $self->meta('handler_type');    # handler_type meta set by incoming MessageHandler

        if ($class_key) {
            if ($explicit) {
                $resp->class_key($class_key);
            } else {
                # inferred class_key could have been "Request", we'll strip that and tack on "Response"
                $class_key =~ s/\-Request$//i;
                $resp->class_key($class_key . "-Response");
            }
        }
    }

    # send response message
    $resp->send(%opts);

    return $resp;
}

sub send {
    my $self = shift;
    my %opts = @_;

    my $err = sub {
        my $errmsg = shift;
        $self->status('error' => $errmsg);
        $self->save_to_db;
        return undef;
    };

    # is SMS disabled?
    return $err->("SMS is disabled") if $LJ::DISABLED{sms};

    # verify type of this message
    $self->type('outgoing');

    # need a destination $u in order to send a message
    my $to_u = $self->to_u;
    return $err->("no user to for message send")
        unless $to_u;

    # do not send a message to a user with no quota remaining
    return $err->("no quota remaining")
        unless $LJ::DISABLED{sms_quota_check} || $opts{no_quota} || $to_u->sms_quota_remaining || $LJ::_T_NO_SMS_QUOTA;

    # do not send message to this user unless they are confirmed and active
    return $err->("sms not active for user: $to_u->{user}")
        unless $opts{force} || $to_u->sms_active;

    if (my $cv = $LJ::_T_SMS_SEND) {

        # whenever a message is sent, we'll give an opportunity
        # for local hooks to catch the event and act accordingly
        LJ::run_hook('sms_deduct_quota', $self, %opts);

        # pretend this was successful.
        $self->status('success');
        $self->save_to_db;

        return $cv->($self);
    }

    # find where quota is being deducted from
    my $quota_type = LJ::run_hook('sms_deduct_quota', $self, %opts);

    # set gateway if quota-type was returned, otherwise () to call as getter
    my $gw = $self->gateway($quota_type || ())
        or die "unable to instantiate SMS gateway object";

    my $dsms_msg = DSMS::Message->new
        (
         to        => $self->to_num,
         from      => $self->from_num,
         type      => "outgoing",
         body_text => $self->body_text,
         meta      => $self->meta,
         ) or die "unable to construct DSMS::Message to send";

    my $rv = eval {
        my @verify_delivery = $opts{verify_delivery} ? ( verify_delivery => 1 ) : ();
        $gw->send_msg($dsms_msg, @verify_delivery);
    };

    # mark error status if there was a problem sending
    if ($@) {
        $self->status('error' => $@);

    # mark 'success' if status was previously 'unknown', but
    # not if it was ack_wait, in which case we'll have to
    # wait for a final ack from the gateway before setting
    # the final message status
    } elsif ($self->status eq 'unknown') {
        $self->status('success');
    }

    # absorb metadata from DSMS message which is now sent
    my $dsms_meta = $dsms_msg->meta || {};
    $self->meta(%$dsms_meta);

    # this message has been sent, log it to the db
    $self->save_to_db;

    # message is created, register it in the global smsuniqmap table
    if ($dsms_msg->uniq_key) {
        $self->register_uniq($dsms_msg->uniq_key);
    }

    return 1;
}

sub should_enqueue { 1 }

sub as_string {
    my $self = shift;
    return "from=$self->{from}, text=$self->{body_text}\n";
}

1;
