use utf8;
package DW::Schema::Result::ExternalSiteMood;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::ExternalSiteMood

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<external_site_moods>

=cut

__PACKAGE__->table("external_site_moods");

=head1 ACCESSORS

=head2 siteid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 mood

  data_type: 'varchar'
  is_nullable: 0
  size: 40

=head2 moodid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "siteid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "mood",
  { data_type => "varchar", is_nullable => 0, size => 40 },
  "moodid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</siteid>

=item * L</mood>

=back

=cut

__PACKAGE__->set_primary_key("siteid", "mood");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:c3at4JKYYZ34ZukwcPx99w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
