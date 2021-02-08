use utf8;
package DW::Schema::Result::MlText;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::MlText

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

=head1 TABLE: C<ml_text>

=cut

__PACKAGE__->table("ml_text");

=head1 ACCESSORS

=head2 dmid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 txtid

  data_type: 'mediumint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 lnid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 itid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 text

  data_type: 'text'
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dmid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "txtid",
  {
    data_type => "mediumint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "lnid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "itid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "text",
  { data_type => "text", is_nullable => 0 },
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</dmid>

=item * L</txtid>

=back

=cut

__PACKAGE__->set_primary_key("dmid", "txtid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:21u3/jirkkeCOkDR4esNLw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
