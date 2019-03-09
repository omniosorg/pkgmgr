package PkgMgr::Config;

use strict;
use warnings;

use JSON::PP;
use FindBin;
use File::Basename qw(basename);
use PkgMgr::Utils;
use Data::Processor;

# constants
my $CONFILE = "$FindBin::RealBin/../etc/" . basename($0) . '.conf'; # CONFFILE

my $SCHEMA = sub {
    my $sv = PkgMgr::Utils->new();

    return {
    GENERAL => {
        optional => 1,
        members  => {
            cert_file        => {
                description  => 'path to certificate file',
                example      => '"cert_file" : "/omniosorg/ssl/certs/ooce_cert.pem"',
                validator    => $sv->x509Cert,
            },
            key_file         => {
                description  => 'path to certificate key file',
                example      => '"key_file" : "/omniosorg/ssl/private/ooce_key.pem"',
                validator    => $sv->file('<', 'Cannot open file'),
            },
            connect_timeout  => {
                optional     => 1,
                description  => 'Seconds to wait trying to connect during transport operations.',
                example      => '"connect_timeout" : "60"',
                default      => 60,
                validator    => $sv->regexp(qr/^\d+$/, 'not a number'),
            },
            lowspeed_timeout => {
                optional     => 1,
                description  => 'Seconds below the lowspeed limit (1024 bytes/second) during '
                              . 'transport operations before the client aborts the operation.',
                example      => '"lowspeed_timeout" : "30"',
                default      => 30,
                validator    => $sv->regexp(qr/^\d+$/, 'not a number'),
            },
            auto_rebuild     => {
                optional     => 1,
                description  => 'automatically rebuild catalog/index after publishing',
                example      => '"auto_rebuild" : "yes"',
                validator    => $sv->elemOf(qw(yes no)),
            },
        },
    },
    REPOS   => {
        members  => {
            '\S+'   => {
                regex   => 1,
                members => {
                    signing     => {
                        description => 'sign packages (yes/no)',
                        example     => '"signing" : "yes"',
                        validator   => $sv->elemOf(qw(yes no)),
                    },
                    src_repo     => {
                        description => 'source (local) repository',
                        example     => '"src_repo" : "/omniosorg/_r22_repo"',
                        validator   => $sv->regexp(qr|^[-\w/.:_]+$|, 'not a valid repo path/URL'),
                    },
                    dst_repo     => {
                        description => 'destination (remote) repository',
                        example     => '"dst_repo" : "https://pkg.omniosce.org/r151022/core"',
                        validator   => $sv->regexp(qr|^[-\w/.:_]+$|, 'not a valid repo path/URL'),
                    },
                    staging_repo => {
                        optional    => 1,
                        description => 'staging repository',
                        example     => '"staging_repo" : "https://pkg.omniosce.org/r151022/staging"',
                        validator   => $sv->regexp(qr|^[-\w/.:_]+$|, 'not a valid repo path/URL'),
                    },
                    publisher   => {
                        description => 'publisher name',
                        example     => '"publisher" : "omnios"',
                        validator   => $sv->regexp(qr/^[\w.]+$/, 'not a valid publisher name'),
                    },
                    release     => {
                        description => 'release',
                        example     => '"release" : "r151022"',
                        transformer => sub { return (shift =~ /^r?(.*)$/)[0]; }, # remove leading 'r' if given
                        validator   => $sv->regexp(qr/^1510\d{2}$/, 'not a valid release'),
                    },
                    on_hold     => {
                        optional    => 1,
                        array       => 1,
                        description => 'list of FMRI patterns (regexp) not to stage or publish',
                        example     => '"on_hold" : [ "binutils", "cherrypy" ]',
                        validator   => sub { return undef },
                    },
                    pull_src    => {
                        optional    => 1,
                        members     => {
                            '\S+'   => {
                                regex       => 1,
                                description => 'pull source',
                                example     => '"host1" : "user@build-host:/build/repo"',
                                validator   => $sv->regexp(qr/^.*$/, 'expected a string'),
                            },
                        },
                    },
                    restricted => {
                        optional    => 1,
                        description => 'restricted repository; authentication needed (yes/no)',
                        example     => '"restricted" : "no"',
                        default     => 'no',
                        validator   => $sv->elemOf(qw(yes no)),
                    },
                },
            },
        },
    },
    }
};

# constructor
sub new {
    my $class = shift;
    my $self  = { @_ };

    $self->{cfg} = Data::Processor->new($SCHEMA->());

    return bless $self, $class;
}

sub loadConfig {
    my $self     = shift;
    my $repo     = shift;
    my $confFile = shift // $CONFILE;

    open my $fh, '<', $confFile or die "ERROR: opening config file '$confFile': $!\n";
    my $configJSON = do { local $/; <$fh>; };
    close $fh;

    my $config = JSON::PP->new->decode($configJSON);

    my $ec = $self->{cfg}->validate($config);
    $ec->count and die join ("\n", map { $_->stringify } @{$ec->{errors}}) . "\n";

    exists $config->{REPOS}->{$repo}
        or die "ERROR: repository '$repo' not defined in config file.\n";

    return $config;
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
