package PkgMgr;

use strict;
use warnings;
use Time::Piece;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

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
    exists $TIME_FACTOR{$unit} or die "ERROR: invalid time suffix '$unit'.\n";

    return gmtime->epoch - $value * $TIME_FACTOR{$unit};
};

my $extractPublisher = sub {
    return (shift->{'pkg.fmri'} =~ m|^pkg://([^/]+)|)[0];
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

    return exists $config->{REPOS}->{$repo}->{staging_repo};
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

sub getRepoPath {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opt    = shift;

    $opt->{staging} && do {
        exists $config->{REPOS}->{$repo}->{staging_repo}
            or die "ERROR: no staging repository defined in config file.\n";

        return $config->{REPOS}->{$repo}->{staging_repo};
    };

    return $config->{REPOS}->{$repo}->{$opt->{dst} ? 'dst_repo' : 'src_repo'};
}

sub fetchPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $fmri   = shift;

    $fmri = [ '*' ] if !@$fmri;
    my $epoch = $opts->{t} ? $getOptEpoch->($opts->{t}) : 0;

    my $repoPath = $self->getRepoPath($config, $repo, $opts);

    my @cert = $config->{REPOS}->{$repo}->{restricted} ne 'yes' ? ()
        : ('--key',  $config->{GENERAL}->{key_file},
           '--cert', $config->{GENERAL}->{cert_file});

    my @cmd = ($PKGREPO, qw(list -F json -s), $repoPath, @cert, @$fmri);
    open my $cmd, '-|', @cmd or die "ERROR: executing '$PKGREPO': $!\n";

    my ($release, $publisher) = $getReleasePublisher->($config, $repo);

    my $packages = [
        grep { $_->{branch} =~ /^(?:$release\.\d+|\d+\.$release)$/
            && $extractPublisher->($_) eq $publisher
            && $getEpoch->($_->{timestamp}) > $epoch
        } @{JSON::PP->new->decode(<$cmd> // '[]')}
    ];

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

    my $repoPath = $self->getRepoPath($config, $repo, $opts);

    my @cert = $opts->{src} ? ()
        : ('--dkey',  $config->{GENERAL}->{key_file},
           '--dcert', $config->{GENERAL}->{cert_file});

    my @cmd = ($PKGSIGN, '-c', $config->{GENERAL}->{cert_file},
        '-k', $config->{GENERAL}->{key_file},
        ($opts->{n} ? '-n' : ()), '-s', $repoPath, @cert, @$pkgs);

    system (@cmd) && die "ERROR: signing packages: $!\n";
}

sub getSrc {
    my $self    = shift;
    my $config  = shift;
    my $repo    = shift;
    my $opts    = shift;

    return ($opts->{pull} && !$opts->{staging})
           || (($opts->{export} || $opts->{sign}) && $opts->{dst})     ? { dst     => 1 }
         : $opts->{pull}
           || ($opts->{publish} && $self->hasStaging($config, $repo))
           || (($opts->{export} || $opts->{sign}) && $opts->{staging}) ? { staging => 1 }
         :                                                               { src     => 1 }
}

sub getSrcDstRepos {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;

    return ($self->getRepoPath($config, $repo, $opts), $opts->{d})
        if $opts->{export};

    my $srcRepo = $self->getRepoPath($config, $repo,
                  $opts->{pull} && !$opts->{staging}      ? { dst     => 1 }
                : $self->hasStaging($config, $repo)
                    && (!$opts->{stage} || $opts->{pull}) ? { staging => 1 }
                :                                           { src     => 1 }
    );

    my $dstRepo = $self->getRepoPath($config, $repo,
                  $opts->{pull}  ? { src     => 1 }
                : $opts->{stage} ? { staging => 1 }
                :                  { dst     => 1 }
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
        : ('--dkey',  $config->{GENERAL}->{key_file},
           '--dcert', $config->{GENERAL}->{cert_file});

    push @cert, $config->{REPOS}->{$repo}->{restricted} ne 'yes' ? ()
        : ('--key',  $config->{GENERAL}->{key_file},
           '--cert', $config->{GENERAL}->{cert_file});

    # set timeout env variables
    $ENV{PKG_CLIENT_CONNECT_TIMEOUT}  = $config->{GENERAL}->{connect_timeout};
    $ENV{PKG_CLIENT_LOWSPEED_TIMEOUT} = $config->{GENERAL}->{lowspeed_timeout};

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

    my $repoPath = $self->getRepoPath($config, $repo, { src => 1 });

    my @cmd = ($PKGREPO, qw(remove -s), $repoPath, ($opts->{n} ? '-n' : ()), @$pkgs);

    system (@cmd) && die "ERROR: cannot remove packages from repo '$repoPath'.\n";
}

sub rebuildRepo {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;

    my $repoPath = $self->getRepoPath($config, $repo, $opts);

    my @cmd = ($PKGREPO, qw(rebuild -s), $repoPath, ($opts->{staging} || $opts->{dst} ? ('--key',
        $config->{GENERAL}->{key_file}, '--cert', $config->{GENERAL}->{cert_file}) : ()));

    system (@cmd) && die "ERROR: rebuilding repo '$repoPath'.\n";
}

sub checkUname {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $pkgs   = shift;

    my ($srcRepo, $dstRepo)   = $self->getSrcDstRepos($config, $repo, $opts);
    my ($release, $publisher) = $getReleasePublisher->($config, $repo);
    my $branch = $release =~ /[13579]$/ ? 'master' : "r$release";

    my ($pkg, $ver) =
        map { local $_ = $_; s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%0X", ord $1 /eg; $_ }
        map { local $_ = $_; s|^pkg://$publisher/||; split /\@/, $_, 2 }
        grep { m|system/kernel/platform| } @$pkgs or return;

    # only checking if publishing from local repository
    return if $srcRepo =~ /^http/;

    print "Checking uname...\n\n";

    open my $fh, '<', "$srcRepo/publisher/$publisher/pkg/$pkg/$ver"
        or die "ERROR: cannot open manifest: $!\n";

    my ($hash, $pref) = map {
        m|^\S+\s+((\S{2})\S+).*path=platform/i86pc/kernel/amd64/unix.*debug\.illumos=false|
            ? ($1, $2) : ()
    } (<$fh>)
        or die "ERROR: hash file missing\n";

    close $fh;

    my $contents;
    gunzip "$srcRepo/publisher/$publisher/file/$pref/$hash" => \$contents
        or die "ERROR: gunzip hash file failed: $GunzipError\n";

    my ($uname) = $contents =~ /(omnios-.+?-[\da-f]{10})/
        or die "ERROR: cannot extract uname.\n";

    $uname =~ /^omnios-$branch/
        or die "ERROR: publishing from wrong branch: $uname\n";
}

1;

__END__

=head1 COPYRIGHT

Copyright 2019 OmniOS Community Edition (OmniOSce) Association.

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
