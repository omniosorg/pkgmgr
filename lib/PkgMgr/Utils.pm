package PkgMgr::Utils;

use strict;
use warnings;

use POSIX qw(isatty);

# constructor
sub new {
    my $class = shift;
    my $self  = { @_ };

    return bless $self, $class
}

# public methods
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

    my @units = qw/bytes KiB MiB GiB TiB/;
    my $i;

    for ($i = 0; $size > 1023; $i++) {
        $size /= 1024.0;
    }

    return sprintf("%.2f %s", $size, $units[$i]);
}

1;
