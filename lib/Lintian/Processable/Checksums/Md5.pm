# -*- perl -*-
# Lintian::Processable::Checksums::Md5 -- access to collected md5 data

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

package Lintian::Processable::Checksums::Md5;

use strict;
use warnings;
use autodie;

use BerkeleyDB;
use MLDBM qw(BerkeleyDB::Btree Storable);
use Path::Tiny;

use Moo::Role;
use namespace::clean;

=head1 NAME

Lintian::Processable::Checksums::Md5 - access to collected md5 data

=head1 SYNOPSIS

    use Lintian::Processable;
    my $processable = Lintian::Processable::Binary->new;

=head1 DESCRIPTION

Lintian::Processable::Checksums::Md5 provides an interface to package data for
file checksums in MD5 format.

=head1 INSTANCE METHODS

=over 4

=item md5sums

Returns a hashref mapping a FILE to its md5sum.  The md5sum is
computed by Lintian during extraction and is not guaranteed to match
the md5sum in the "md5sums" control file.

Needs-Info requirements for using I<md5sums>: md5sums

=item saved_md5sums

Returns the cached md5sums.

=cut

has saved_md5sums => (is => 'rwp', default => sub { {} });

sub md5sums {
    my ($self) = @_;

    unless (keys %{$self->saved_md5sums}) {

        my $dbpath = path($self->groupdir)->child('md5sums.db')->stringify;

        my %md5sums;

        tie my %h, 'BerkeleyDB::Btree',-Filename => $dbpath
          or die "Cannot open file $dbpath: $! $BerkeleyDB::Error\n";

        $md5sums{$_} = $h{$_} for keys %h;

        untie %h;

        $self->_set_saved_md5sums(\%md5sums);
    }

    return $self->saved_md5sums;
}

1;

=back

=head1 AUTHOR

Originally written by Felix Lechner <felix.lechner@lease-up.com> for
Lintian.

=head1 SEE ALSO

lintian(1), L<Lintian::Collect>, L<Lintian::Collect::Binary>,
L<Lintian::Collect::Source>

=cut

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et