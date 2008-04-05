package LJ::Setting::EntryEditor;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(editor entryeditor richtext html rich plain plaintext) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    my $editor = $u->prop("entry_editor");
    return "What editor do you want to use when composing new entries? " .
        LJ::html_select({ 'name' => "${key}entryeditor", 'selected' => $editor },
                        'L'            => 'Whatever I last used',
                        'always_rich'  => 'Rich Text',
                        'always_plain' => 'HTML Editor' ) .
                        $class->errdiv($errs, "entryeditor");
}

sub save {
    my ($class, $u, $args) = @_;
    my $editor = $args->{entryeditor};

    # Make sure they chose a valid setting
    $class->errors("entryeditor" => "Invalid option")  unless $editor =~ /^(L|always_rich|always_plain)$/;

    # If they said last used, we really mean no setting at all
    $editor = undef if $editor eq "L";

    my $cur = $u->prop('entry_editor') || '';

    # No change needed if they selected last used and that is what is stored
    return 1 if !$editor && $cur =~ /^(rich|plain)$/;

    # No change needed if their "always" selection is the same
    return 1 if $editor eq $cur;

    # They made a change
    $u->set_prop("entry_editor", $editor);
}

1;
