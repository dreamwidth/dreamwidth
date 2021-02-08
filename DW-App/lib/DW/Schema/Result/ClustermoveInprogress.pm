use utf8;
package DW::Schema::Result::ClustermoveInprogress;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::ClustermoveInprogress

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

=head1 TABLE: C<clustermove_inprogress>

=cut

__PACKAGE__->table("clustermove_inprogress");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 locktime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 dstclust

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 moverhost

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 moverport

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 moverinstance

  data_type: 'char'
  is_nullable: 0
  size: 22

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "locktime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "dstclust",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "moverhost",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "moverport",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "moverinstance",
  { data_type => "char", is_nullable => 0, size => 22 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("userid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:kowCSu5mZmBnr6WBdYduEA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
