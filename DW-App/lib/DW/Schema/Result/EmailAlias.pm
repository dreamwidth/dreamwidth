use utf8;
package DW::Schema::Result::EmailAlias;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::EmailAlias

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

=head1 TABLE: C<email_aliases>

=cut

__PACKAGE__->table("email_aliases");

=head1 ACCESSORS

=head2 alias

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 rcpt

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "alias",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "rcpt",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</alias>

=back

=cut

__PACKAGE__->set_primary_key("alias");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:JW/mT2w9kueHGaDtGjxZPg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
