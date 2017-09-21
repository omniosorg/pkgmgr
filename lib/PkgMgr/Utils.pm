package PkgMgr::Utils;

use strict;
use warnings;

use POSIX qw(isatty);

my @RSYNC = qw(/usr/bin/rsync -ahh --stats --delete-after);

# constructor
sub new {
    my $class = shift;
    my $self  = { @_ };

    return bless $self, $class
}

# public methods
sub getNameVersion {
    my $self = shift;
    return (shift =~ /\/([^\/]+)\@([^,]+),5\.11-0\.1510/);
}

sub file {
    my $self = shift;
    my $op   = shift;
    my $msg  = shift;

    return sub {
        my $file = shift;
        return open (my $fh, $op, $file) ? undef : "$msg '$file': $!";
    }
}

sub regexp {
    my $self = shift;
    my $rx   = shift;
    my $msg  = shift;

    return sub {
        my $value = shift;
        return $value =~ /$rx/ ? undef : "$msg ($value)";
    }
}

sub elemOf {
    my $self = shift;
    my $elems = [ @_ ];

    return sub {
        my $value = shift;
        return (grep { $_ eq $value } @$elems) ? undef
            : 'expected a value from the list: ' . join(', ', @$elems);
    }
}

sub isaTTY {
    my $self = shift;
    return isatty(*STDIN);
}

sub getSTDIN {
    my $self = shift;
    return $self->isaTTY() ? [] : [ split /[\s\n]+/, do { local $/; <STDIN>; } ];
}

sub prettySize {
    my $self = shift;
    my $size = shift;

    my @units = qw(bytes KiB MiB GiB TiB);
    my $i     = $size <= 0 ? 0 : int (log ($size) / log (1024));

    return sprintf("%.2f %s", $size / 1024 ** $i, $units[$i]);
}

sub rsync {
    my $self = shift;

    my @cmd = (@RSYNC, shift, shift);

    system (@cmd) && die "ERROR: executing 'rsync': $!\n";
}

1;

__END__

=head1 COPYRIGHT

Copyright 2017 OmniOS Community Edition (OmniOSce) Association.

=head1 LICENSE

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
You should have received a copy of the GNU General Public License along with
this program. If not, see L<http://www.gnu.org/licenses/>.

=head1 AUTHOR

S<Andy Fiddaman E<lt>omnios@citrus-it.co.ukE<gt>>
S<Dominik Hassler E<lt>hadfl@omniosce.orgE<gt>>

=head1 HISTORY

2017-09-06 had Initial Version

=cut
