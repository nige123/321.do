use strict;
use warnings;
use Test::More;
use Deploy::SSH;

my $ssh = Deploy::SSH->new(
    user     => 'deploy',
    host     => 'example.com',
    key      => '/home/deploy/.ssh/id_ed25519',
    perlbrew => 'perl-5.42.0',
);

# 1. _ssh_cmd: builds correct ssh command with perlbrew wrapping
{
    my $cmd = $ssh->_ssh_cmd('echo hello');
    like $cmd, qr/\bssh\b/,                          '_ssh_cmd: contains ssh';
    like $cmd, qr/-i \S*id_ed25519/,                 '_ssh_cmd: contains key flag';
    like $cmd, qr/deploy\@example\.com/,             '_ssh_cmd: contains user@host';
    like $cmd, qr/perlbrew/,                         '_ssh_cmd: contains perlbrew wrapping';
    like $cmd, qr/echo hello/,                       '_ssh_cmd: contains actual command';
}

# 2. _ssh_cmd without perlbrew: no perlbrew wrapping
{
    my $plain = Deploy::SSH->new(
        user => 'bob',
        host => 'host.example.com',
        key  => '/home/bob/.ssh/id_rsa',
    );
    my $cmd = $plain->_ssh_cmd('ls -la');
    unlike $cmd, qr/perlbrew/,   '_ssh_cmd no perlbrew: no perlbrew in cmd';
    like   $cmd, qr/\bssh\b/,    '_ssh_cmd no perlbrew: still has ssh';
    like   $cmd, qr/ls -la/,     '_ssh_cmd no perlbrew: contains command';
}

# 3. _scp_cmd: builds correct scp command
{
    my $cmd = $ssh->_scp_cmd('/local/path/file.tar.gz', '/remote/deploy/file.tar.gz');
    like $cmd, qr/\bscp\b/,                            '_scp_cmd: contains scp';
    like $cmd, qr/-i \S*id_ed25519/,                   '_scp_cmd: contains key flag';
    like $cmd, qr{/local/path/file\.tar\.gz},          '_scp_cmd: contains local path';
    like $cmd, qr{deploy\@example\.com:/remote/deploy/file\.tar\.gz}, '_scp_cmd: contains user@host:remote';
}

# 4. _ssh_cmd_in_dir: wraps with cd $dir && $cmd
{
    my $cmd = $ssh->_ssh_cmd_in_dir('/srv/app', 'make test');
    like $cmd, qr{cd /srv/app},  '_ssh_cmd_in_dir: contains cd';
    like $cmd, qr/make test/,    '_ssh_cmd_in_dir: contains command';
    like $cmd, qr/&&/,           '_ssh_cmd_in_dir: uses && to chain';
}

# 5. _shell_escape: escapes single quotes correctly
{
    my $plain = Deploy::SSH->new(user => 'u', host => 'h', key => '/k');
    is $plain->_shell_escape("hello"),       "hello",        "_shell_escape: plain string unchanged";
    is $plain->_shell_escape("it's"),        "it'\\''s",     "_shell_escape: single quote escaped";
    is $plain->_shell_escape("don't stop"),  "don'\\''t stop", "_shell_escape: mid-word quote escaped";
}

done_testing;
