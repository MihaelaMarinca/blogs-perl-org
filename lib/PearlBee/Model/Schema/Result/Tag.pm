use utf8;
package PearlBee::Model::Schema::Result::Tag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

PearlBee::Model::Schema::Result::Tag - Tag table.

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<tag>

=cut

__PACKAGE__->table("tag");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 slug

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "slug",
  { data_type => "varchar", is_nullable => 1, size => 100 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 post_tags

Type: has_many

Related object: L<PearlBee::Model::Schema::Result::PostTag>

=cut

__PACKAGE__->has_many(
  "post_tags",
  "PearlBee::Model::Schema::Result::PostTag",
  { "foreign.tag_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 posts

Type: many_to_many

Composing rels: L</post_tags> -> post

=cut

__PACKAGE__->many_to_many("posts", "post_tags", "post");


# Created by DBIx::Class::Schema::Loader v0.07039 @ 2015-02-23 16:54:04
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sIW8AAfcXBM0dgcuJrb7iw


# You can replace this text with custom code or comments, and it will be preserved on regeneration

=head2 as_hashref

Return a non-blessed version of a blog database row

=cut

sub as_hashref {
  my ($self)      = @_;
  my $tag_hashref = {
    id          => $self->id,
    name        => $self->name,
    slug        => $self->slug,
    tag_creator =>$self->tag_creator,
  };          
              
  return $tag_hashref;
}

=head2 as_hashref_sanitized

Remove ID from the blog database row

=cut

sub as_hashref_sanitized {
  my ($self) = @_;
  my $href   = $self->as_hashref;

  delete $href->{id};
  return $href;
}

sub tag_creator {
  my ($self, $args) = @_;
  my $schema = $self->result_source->schema;
  my $post_tag = $schema->resultset('PostTag')->find ({ tag_id => $self->id});
  my $post      =$schema->resultset('Post')->find ({ id => $post_tag->post_id});
  my $user       =$schema->resultset('Users')->find ({id => $post->user_id});
  return $user->username;
}

1;
