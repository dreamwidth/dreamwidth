use utf8;
package DW::Schema::Result::SessionsData;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::SessionsData

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

=head1 TABLE: C<sessions_data>

=cut

__PACKAGE__->table("sessions_data");

=head1 ACCESSORS

=head2 userid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 sessid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 skey

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 sval

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 0 },
  "sessid",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 0 },
  "skey",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "sval",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</sessid>

=item * L</skey>

=back

=cut

__PACKAGE__->set_primary_key("userid", "sessid", "skey");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/5MEbmmqkxdX335psxgubg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
