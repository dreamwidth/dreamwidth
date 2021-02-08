use utf8;
package DW::Schema::Result::OauthAccessToken;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::OauthAccessToken

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

=head1 TABLE: C<oauth_access_token>

=cut

__PACKAGE__->table("oauth_access_token");

=head1 ACCESSORS

=head2 consumer_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 token

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 secret

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 createtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 lastaccess

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "consumer_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "token",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "secret",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "createtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "lastaccess",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</consumer_id>

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("consumer_id", "userid");

=head1 UNIQUE CONSTRAINTS

=head2 C<token>

=over 4

=item * L</token>

=back

=cut

__PACKAGE__->add_unique_constraint("token", ["token"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NkAP2cmEnZdrzPEHOZnFuQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
