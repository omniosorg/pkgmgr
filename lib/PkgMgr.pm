package PkgMgr;

use strict;
use warnings;

# constants/tools
my $PKGREPO = '/usr/bin/pkgrepo';
my $PKGRECV = '/usr/bin/pkgrecv';
my $PKGSIGN = '/usr/bin/pkgsign';

# private methods
my $getRepoPath = sub {
    my $config = shift;
    my $repo   = shift;
    my $opt    = shift;
    
    exists $config->{REPOS}->{$repo} or die "ERROR: repository '$repo' not defined in config file.\n";

    $opt->{staging} && do {
        exists $config->{REPOS}->{$repo}->{stagingRepo}
            or die "ERROR: no staging repository defined in config file.\n";
        
        return $config->{REPOS}->{$repo}->{stagingRepo};
    };
    
    return $config->{REPOS}->{$repo}->{$opt->{dst} ? 'dstRepo' : 'srcRepo'};
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

sub fetchPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opt    = shift;
    my $fmri   = shift;
    
    $fmri = [ '*' ] if !@$fmri;
    
    my $repoPath = $getRepoPath->($config, $repo, $opt);
    
    my @cmd = ($PKGREPO, qw(list -F json -s), $repoPath, @$fmri);
    open my $cmd, '-|', @cmd or die "ERROR: executing '$PKGREPO': $!\n";

    my ($release, $publisher) = $getReleasePublisher->($config, $repo);
    return [ grep { $_->{branch} eq "0.$release"
        && $extractPublisher->($_) eq $publisher }
        @{JSON::PP->new->decode(<$cmd>)} ];
}

sub signPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $pkgs   = shift;
    
    my $repoPath = $getRepoPath->($config, $repo, { src => 1 });
    
    for my $pkg (@$pkgs) {
        my @cmd = ($PKGSIGN, '-c', $config->{GENERAL}->{certFile}, '-k', $config->{GENERAL}->{keyFile},
            ($opts->{n} ? '-n' : ()), '-s', $repoPath, $pkg);
        
        system (@cmd) && die "ERROR: signing package '$pkg'.\n";
    }
}

sub getSourceDestRepos {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;

    my $srcRepo = $getRepoPath->($config, $repo, ($opts->{staging}
        || !$self->hasStaging($config, $repo) ? { src => 1 } : { staging => 1 }));
    my $dstRepo = $getRepoPath->($config, $repo, ($opts->{staging} ? { staging => 1 } : { dst => 1 }));
    
    return ($srcRepo, $dstRepo);
}

sub publishPackages {
    my $self   = shift;
    my $config = shift;
    my $repo   = shift;
    my $opts   = shift;
    my $pkgs   = shift;
    
    my ($srcRepo, $dstRepo) = $self->getSourceDestRepos($config, $repo, $opts);
    
    for my $pkg (@$pkgs) {
        my @cmd = ($PKGRECV, ($opts->{n} ? '-n' : ()), '-s', $srcRepo, '-d', $dstRepo,
            '--dkey', $config->{GENERAL}->{keyFile}, '--dcert', $config->{GENERAL}->{certFile},
            qw(-m latest), $pkg);
            
        system (@cmd) && die "ERROR: publishing package '$pkg'.\n";
    }
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
