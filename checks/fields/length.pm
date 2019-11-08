# fields/length -- lintian check script -*- perl -*-
#
# Copyright © 2019 Sylvestre Ledru
#
# Parts of the code were taken from the old check script, which
# was Copyright (C) 1998 Richard Braakman (also licensed under the
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

package Lintian::fields::length;

use strict;
use warnings;
use autodie;

use constant QUOTE => q{'};

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub always {
    my ($self) = @_;

    my $info = $self->info;

    my $maximum = 5_000;

    # Ensure fields aren't too long
    for my $name (keys %{$info->field}) {

        my $length = length $info->field($name);

        next
          unless $length > $maximum;

        my $label = QUOTE . $name . QUOTE;
        $label =~ s/\b(\w)/\U$1/g;

        $self->tag('field-too-long', $label, "($length chars > $maximum)");
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et