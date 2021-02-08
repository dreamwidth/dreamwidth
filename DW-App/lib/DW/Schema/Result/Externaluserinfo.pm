use utf8;
package DW::Schema::Result::Externaluserinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Externaluserinfo

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

=head1 TABLE: C<externaluserinfo>

=cut

__PACKAGE__->table("externaluserinfo");

=head1 ACCESSORS

=head2 site

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 user

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 last

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 type

  data_type: 'char'
  is_nullable: 1
  size: 1

=cut

__PACKAGE__->add_columns(
  "site",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "user",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "last",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "type",
  { data_type => "char", is_nullable => 1, size => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</site>

=item * L</user>

=back

=cut

__PACKAGE__->set_primary_key("site", "user");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:TM3F+fnsLlLw12O9bkfejw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
