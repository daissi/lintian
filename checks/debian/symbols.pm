# debian/symbols -- lintian check script -*- perl -*-
#
# Copyright © 2019 Felix Lechner
#
# Parts of the code were taken from the old check script, which
# was Copyright © 1998 Richard Braakman (also licensed under the
# GPL 2 or higher)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

package Lintian::debian::symbols;

use v5.20;
use warnings;
use utf8;
use autodie;

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub source {
    my ($self) = @_;

    for my $file ($self->processable->patched->sorted_list) {

        # look at symbols files
        $self->check_symbols_file($file)
          if $file->name =~ qr{^debian/(?:.+\.)symbols};
    }

    return;
}

sub check_symbols_file {
    my ($self, $file) = @_;

    return
      unless $file->is_file && $file->is_open_ok;

    open(my $fd, '<', $file->unpacked_path);
    while (<$fd>) {

        chop;
        next
          if m/^\s*$/ or /^#/;

        # meta-information
        if (m/^\*\s(\S+):\s+(\S+)/) {

            my $field = $1;
            my $value = $2;

            $self->tag('package-placeholder-in-symbols-file', "$file, line $.")
              if $field eq 'Build-Depends-Package' && $value =~ /#PACKAGE#/;
        }
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
