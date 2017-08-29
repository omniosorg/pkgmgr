package PkgMgr;

use strict;
use warnings;
use Time::Piece;

# constants/tools
my $PKGREPO = '/usr/bin/pkgrepo';
my $PKGRECV = '/usr/bin/pkgrecv';
my $PKGSIGN = '/usr/bin/pkgsign';
my $PKG     = '/usr/bin/pkg';

my %TIME_FACTOR = (
    s   => 1,
    M   => 60,
    h   => 3600,
    d   => 3600 * 24,
    m   => 3600 * 24 * 30,
    y   => 3600 * 24 * 365,
);

# private methods
my $getRepoPath = sub {
    my $config = shift;
    my $repo   = shift;
    my $opt    = shift;
    
    $opt->{staging} && do {
        exists $config->{REPOS}->{$repo}->{stagingRepo}
            or die "ERROR: no staging repository defined in config file.\n";
        
        return $config->{REPOS}->{$repo}->{stagingRepo};
    };
    
    return $config->{REPOS}->{$repo}->{$opt->{dst} ? 'dstRepo' : 'srcRepo'};
};

my $getEpoch = sub {
    return Time::Piece->strptime(shift, '%Y%m%dT%H%M%SZ')->epoch;
};

my $getOptEpoch = sub {
    my $timeOpt = shift;

    # if $timeOpt is an ISO timestamp
    return $getEpoch->($timeOpt) if ($timeOpt =~ /^\d+T\d+Z$/);

    my ($value, $unit) = $timeOpt =~ /^(\d+)(\w)?$/
        or die "ERROR: invalid interval '$timeOpt'.\n";
    # default to seconds
    $unit //= 's';
    grep { $_ eq $unit } keys %TIME_FACTOR or die "ERROR: invalid time suffix '$unit'.\n";

    return gmtime->epoch - $value * $TIME_FACTOR{$unit};
};

my $extractPublisher = sub {
    return (shift->{'pkg.fmri'} =~ /^pkg:\/\/([^\/]+)/)[0];
};

my $getReleasePublisher = sub {
    my $config = shift;
    my $repo   = shift;
    
    return ($config->{REPOS}->{$repo}->{release}, $config->{REPOS}->{$repo}->{publisher});
};

# constructor
sub new {
    my $class = shift;
    my $self  = { @_ };

    return bless $self, $class
}

sub hasStaging {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    
    return exists $config->{REPOS}->{$repo}->{stagingRepo};
}

sub needsSigning {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    
    return $config->{REPOS}->{$repo}->{signing} eq 'yes';
}

sub isSigned {
    my $self     = shift;
    my $repoPath = shift;
    my $fmri     = shift;

    my @cmd = ($PKG, qw(contents -g), $repoPath, '-m', $fmri);

    open my $pkg, '-|', @cmd or die "ERROR: executing '$PKG'.\n";

    return grep { /^signature/ } (<$pkg>);
}

sub fetchPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $fmri   = shift;

    $fmri = [ '*' ] if !@$fmri;
    my $epoch = $opts->{t} ? $getOptEpoch->($opts->{t}) : 0;

    my $repoPath = $getRepoPath->($config, $repo, $opts);

    my @cmd = ($PKGREPO, qw(list -F json -s), $repoPath, @$fmri);
    open my $cmd, '-|', @cmd or die "ERROR: executing '$PKGREPO': $!\n";

    my ($release, $publisher) = $getReleasePublisher->($config, $repo);

    my $packages = [ grep { $_->{branch} eq "0.$release"
        && $extractPublisher->($_) eq $publisher
        && $getEpoch->($_->{timestamp}) > $epoch }
        @{JSON::PP->new->decode(<$cmd>)} ];

    if ($opts->{long}) {
        for my $p (@$packages) {
            $p->{$_}     = 0 for qw(size csize files);
            $p->{signed} = $self->isSigned($repoPath, $p->{'pkg.fmri'});

            my @cmd = ($PKG, qw(contents -H -g), $repoPath,
                '-o', 'value,pkg.size,pkg.csize', $p->{'pkg.fmri'});

            open my $pkg, '-|', @cmd
                or die "ERROR: executing '$PKG'.\n";

            while (<$pkg>) {
                my ($size, $csize) = /^\s*(\d+)\s+(\d+)/ or next;

                $p->{files}++;
                $p->{size}  += $size;
                $p->{csize} += $csize;
            }
            close $pkg;
        }
    }

    return $packages;
}

sub signPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $pkgs   = shift;

    my $repoPath = $getRepoPath->($config, $repo, { src => 1 });

    for my $fmri (@$pkgs) {
        next if $self->isSigned($repoPath, $fmri);

        my @cmd = ($PKGSIGN, '-c', $config->{GENERAL}->{certFile}, '-k', $config->{GENERAL}->{keyFile},
            ($opts->{n} ? '-n' : ()), '-s', $repoPath, $fmri);

        system (@cmd) && die "ERROR: signing package '$fmri'.\n";
    }
}

sub getSrcDstRepos {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;

    return ($getRepoPath->($config, $repo, $opts), $opts->{d})
        if $opts->{export};

    my $srcRepo = $getRepoPath->($config, $repo,
                  $opts->{pull}                                          ? { dst => 1 }
                : $self->hasStaging($config, $repo) && !$opts->{staging} ? { staging => 1 }
                : { src => 1 }
                );
        
    my $dstRepo = $getRepoPath->($config, $repo,
                  $opts->{pull}    ? { src => 1 } 
                : $opts->{staging} ? { staging => 1 }
                : { dst => 1 }
                );

    return ($srcRepo, $dstRepo);
}

sub filterOnHold {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $pkgs   = shift;

    # nothing 'on hold'. we are done.
    return $pkgs if !exists $config->{REPOS}->{$repo}->{on_hold};

    # build a package list excluding packages that match an 'on hold' pattern
    my @pkgs = ();
    PKG: for my $pkg (@$pkgs) {
        $pkg =~ /$_/ && next PKG for @{$config->{REPOS}->{$repo}->{on_hold}};
        push @pkgs, $pkg;
    }

    return \@pkgs;
}

sub publishPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $pkgs   = shift;

    my ($srcRepo, $dstRepo) = $self->getSrcDstRepos($config, $repo, $opts);

    my @cert = $opts->{pull} || $opts->{export} ? ()
        : ('--dkey', $config->{GENERAL}->{keyFile}, '--dcert', $config->{GENERAL}->{certFile});

    # set timeout env variables
    $ENV{PKG_CLIENT_CONNECT_TIMEOUT}  = $config->{GENERAL}->{connectTimeout};
    $ENV{PKG_CLIENT_LOWSPEED_TIMEOUT} = $config->{GENERAL}->{lowSpeedTimeout};

    my @cmd = ($PKGRECV, ($opts->{n} ? '-n' : ()), ($opts->{export} ? '-a' : ()),
        '-s', $srcRepo, '-d', $dstRepo, @cert, qw(-m latest), @$pkgs);

    system (@cmd) && die 'ERROR: ' . ($opts->{pull} ? 'pulling' : 'publishing') . " packages: $!\n";
}

sub removePackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $pkgs   = shift;

    my $repoPath = $getRepoPath->($config, $repo, { src => 1 });

    my @cmd = ($PKGREPO, qw(remove -s), $repoPath, ($opts->{n} ? '-n' : ()), @$pkgs);

    system (@cmd) && die "ERROR: cannot remove packages from repo '$repoPath'.\n";
}

sub rebuildRepo {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;

    my $repoPath = $getRepoPath->($config, $repo, $opts);

    my @cmd = ($PKGREPO, qw(rebuild -s), $repoPath, ($opts->{staging} || $opts->{dst} ? ('--key',
        $config->{GENERAL}->{keyFile}, '--cert', $config->{GENERAL}->{certFile}) : ()));

    system (@cmd) && die "ERROR: rebuilding repo '$repoPath'.\n";
}

1;
