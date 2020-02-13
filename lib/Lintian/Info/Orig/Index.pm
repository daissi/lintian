# -*- perl -*- Lintian::Info::Orig::Index
#
# Copyright © 2019 Felix Lechner
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

package Lintian::Info::Orig::Index;

use strict;
use warnings;
use autodie;

use Lintian::Index;

use Moo::Role;
use namespace::clean;

=head1 NAME

Lintian::Info::Orig::Index - access to collected data about the upstream (orig) sources

=head1 SYNOPSIS

    use Lintian::Processable;
    my $processable = Lintian::Processable::Binary->new;

=head1 DESCRIPTION

Lintian::Info::Orig::Index provides an interface to collected data about the upstream (orig) sources.

=head1 INSTANCE METHODS

=over 4

=item saved_orig

An index object for orig.tar.gz.

=item orig

Returns the index for orig.tar.gz.

=cut

has saved_orig => (is => 'rw');

sub orig {
    my ($self) = @_;

    unless (defined $self->saved_orig) {

        my $load_info = {
            'index_file' => 'src-orig-index',
            'index_owner_file' => undef,
            'fs_root_sub' => undef,
            # source packages do not have anchored roots as they can be
            # unpacked anywhere...
            'has_anchored_root_dir' => 1,
            'allow_empty' => 1,
        };

        my $orig = Lintian::Index->new('load_info' => $load_info);

        $orig->basedir($self->groupdir);

        $self->saved_orig($orig);
    }

    return $self->saved_orig;
}

=item orig_index (FILE)

Like L</index> except orig_index is based on the "orig tarballs" of
the source packages.

For native packages L</index> and L</orig_index> are generally
identical.

NB: If sorted_index includes a debian packaging, it is was
contained in upstream part of the source package (or the package is
native).

Needs-Info requirements for using I<orig_index>: src-orig-index

=cut

sub orig_index {
    my ($self, $file) = @_;

    return $self->orig->index($file);
}

=item sorted_orig_index

Like L<sorted_index|Lintian::Collect/sorted_index> except
sorted_orig_index is based on the "orig tarballs" of the source
packages.

For native packages L<sorted_index|Lintian::Collect/sorted_index> and
L</sorted_orig_index> are generally identical.

NB: If sorted_orig_index includes a debian packaging, it is was
contained in upstream part of the source package (or the package is
native).

Needs-Info requirements for using I<sorted_orig_index>: L<Same as orig_index|/orig_index ([FILE])>

=cut

sub sorted_orig_index {
    my ($self) = @_;

    return $self->orig->sorted_list;
}

=item orig_index_resolved_path(PATH)

Resolve PATH (relative to the root of the package) and return the
L<entry|Lintian::Path> denoting the resolved path.

The resolution is done using
L<resolve_path|Lintian::Path/resolve_path([PATH])>.

NB: If orig_index_resolved_path includes a debian packaging, it is was
contained in upstream part of the source package (or the package is
native).

Needs-Info requirements for using I<orig_index_resolved_path>: L<Same as orig_index|/orig_index (FILE)>

=cut

sub orig_index_resolved_path {
    my ($self, $path) = @_;

    return $self->orig->index->resolve_path($path);
}

=back

=head1 AUTHOR

Originally written by Felix Lechner <felix.lechner@lease-up.com> for
Lintian.

=head1 SEE ALSO

lintian(1), L<Lintian::Collect>, L<Lintian::Collect::Binary>,
L<Lintian::Collect::Source>

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
