# -*- perl -*- Lintian::Index::Control::Scripts
#
# Copyright © 2020 Felix Lechner
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

package Lintian::Index::Control::Scripts;

use strict;
use warnings;
use autodie;

use BerkeleyDB;
use MLDBM qw(BerkeleyDB::Btree Storable);
use Path::Tiny;

use constant EMPTY => q{};
use constant SPACE => q{ };
use constant NEWLINE => qq{\n};

use Moo::Role;
use namespace::clean;

=head1 NAME

Lintian::Index::Control::Scripts - information about maintainer scripts.

=head1 SYNOPSIS

    use Lintian::Processable;
    my $processable = Lintian::Processable::Binary->new;

=head1 DESCRIPTION

Lintian::Index::Control::Scripts information about maintainer scripts.

=head1 INSTANCE METHODS

=over 4

=item add_scripts

=cut

sub add_scripts {
    my ($self, $pkg, $type, $dir) = @_;

    # maintainer scripts
    my $control_dbpath = "$dir/control-scripts.db";
    unlink $control_dbpath
      if -e $control_dbpath;

    tie my %control, 'BerkeleyDB::Btree',
      -Filename => $control_dbpath,
      -Flags    => DB_CREATE
      or die "Cannot open file $control_dbpath: $! $BerkeleyDB::Error\n";

    for my $path ($self->lookup->children) {

        next
          unless $path->is_open_ok;

        # skip anything other than maintainer scripts
        next
          unless $path =~ m/^(?:(?:pre|post)(?:inst|rm)|config)$/;

        # allow elf binary
        if ($path->magic(4) eq "\x7FELF") {
            $control{$path} = 'ELF';
            next;
        }

        # check for hashbang
        my $interpreter = $path->get_interpreter // EMPTY;

        # get base command without options
        $interpreter =~ s/\s++ .++ \Z//xsm;

        $control{$path} = $interpreter;
    }

    untie %control;

    return;
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
