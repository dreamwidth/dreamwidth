use utf8;
package DW::Schema::Result::Extuser;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Extuser

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

=head1 TABLE: C<extuser>

=cut

__PACKAGE__->table("extuser");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 siteid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 extuser

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 extuserid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "siteid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "extuser",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "extuserid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("userid");

=head1 UNIQUE CONSTRAINTS

=head2 C<extuser>

=over 4

=item * L</siteid>

=item * L</extuser>

=back

=cut

__PACKAGE__->add_unique_constraint("extuser", ["siteid", "extuser"]);

=head2 C<extuserid>

=over 4

=item * L</siteid>

=item * L</extuserid>

=back

=cut

__PACKAGE__->add_unique_constraint("extuserid", ["siteid", "extuserid"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Jhy58K+QvtDJq8ACBO2F/A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
