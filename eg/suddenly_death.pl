#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.010000;
use autodie;
use FindBin;
use lib "$FindBin::Bin/../lib/";
use Caroline;
use Data::Dumper;
use Acme::SuddenlyDeath;
use Term::Encoding qw(term_encoding);

use Getopt::Long;

my $encoding = term_encoding();
binmode *STDIN,  ":encoding(${encoding})";
binmode *STDOUT, ":encoding(${encoding})";

my $p = Getopt::Long::Parser->new(
    config => [qw(posix_default no_ignore_case auto_help)]
);
$p->getoptions(
    'multiline!'       => \my $multiline,
);

my $c = Caroline->new(
    multi_line => $multiline,
    completion_callback => sub {
        my ($line) = @_;
        if ($line eq 'h') {
            return (
                'hello',
                'hello there'
            );
        } elsif ($line eq 'm') {
            return (
                '突然のmattn'
            );
        }
        return;
    },
);
while (defined(my $line = $c->readline('hello> '))) {
    if ($line =~ /\S/) {
        print sudden_death($line), "\n";
        $c->history_add($line);
    }
}
