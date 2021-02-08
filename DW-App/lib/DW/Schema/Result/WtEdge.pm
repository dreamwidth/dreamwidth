use utf8;
package DW::Schema::Result::WtEdge;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::WtEdge

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

=head1 TABLE: C<wt_edges>

=cut

__PACKAGE__->table("wt_edges");

=head1 ACCESSORS

=head2 from_userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 to_userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 fgcolor

  data_type: 'mediumint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 bgcolor

  data_type: 'mediumint'
  default_value: 16777215
  extra: {unsigned => 1}
  is_nullable: 0

=head2 groupmask

  data_type: 'bigint'
  default_value: 1
  extra: {unsigned => 1}
  is_nullable: 0

=head2 showbydefault

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "from_userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "to_userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "fgcolor",
  {
    data_type => "mediumint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "bgcolor",
  {
    data_type => "mediumint",
    default_value => 16777215,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "groupmask",
  {
    data_type => "bigint",
    default_value => 1,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "showbydefault",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</from_userid>

=item * L</to_userid>

=back

=cut

__PACKAGE__->set_primary_key("from_userid", "to_userid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+BiuQ9Wai5r/wa4QkZpgQg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
