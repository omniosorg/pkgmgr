#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../thirdparty/lib/perl5";
use lib "$FindBin::Bin/../lib";

use Test::More;

my $config = {
    REPOS   => {
        no_stage => {
            src_repo     => 'src',
            dst_repo     => 'dst',
        },
        stage    => {
            src_repo     => 'src',
            staging_repo => 'staging',
            dst_repo     => 'dst',
        },
    }
};
my @stage = (
    { src     => 1 },
    { staging => 1 },
);
my @noStage = (
    { src     => 1 },
);
my @repoStage = (
    { src     => 'staging' },
    { staging => 'dst'     },
);
my @repoNoStage = (
    { src     => 'dst'     },
);
my @t;

use_ok 'PkgMgr';

my $t = PkgMgr->new();

is (ref $t, 'PkgMgr', 'Instantiation');

@t = map { $t->getSrc($config, 'stage', { $_ => 1 })    } qw(stage publish);
is_deeply (\@stage, \@t, 'staging');

@t = map { $t->getSrc($config, 'no_stage', { $_ => 1 }) } qw(publish);
is_deeply (\@noStage, \@t, 'no staging');

@t = map { { $t->getSrcDstRepos($config, 'stage', { $_ => 1 }) }    } qw(stage publish);
is_deeply (\@repoStage, \@t, 'staging repos');

@t = map { { $t->getSrcDstRepos($config, 'no_stage', { $_ => 1 }) } } qw(publish);
is_deeply (\@repoNoStage, \@t, 'no staging repos');

done_testing();

exit 0;

