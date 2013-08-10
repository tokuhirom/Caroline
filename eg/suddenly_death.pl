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

my $encoding = term_encoding();
binmode *STDIN,  ":encoding(${encoding})";
binmode *STDOUT, ":encoding(${encoding})";

my $history_file_name = 'suddenly.hist';

my $c = Caroline->new(
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
    history_max_len => 30,
);
if (-f $history_file_name) {
    $c->read_history_file($history_file_name)
        or warn "Cannot read $history_file_name: $!";
}
while (defined(my $line = $c->readline('hello> '))) {
    if ($line =~ /\S/) {
        print sudden_death($line), "\n";
        $c->history_add($line);
    }
}
END {
    $c->write_history_file($history_file_name);
}
