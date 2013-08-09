package Caroline;
use 5.008005;
use strict;
use warnings;
use POSIX qw(termios_h);
use Storable;
use Text::VisualWidth::PP 0.02;

our $VERSION = "0.01";

our @EXPORT = qw( caroline );

my $HISTORY_NEXT = 0;
my $HISTORY_PREV = 1;

sub new {
    my $class = shift;
    my %args = @_==1? %{$_[0]} : @_;
    my $self = bless {
        history => [],
        debug => !!$ENV{CAROLINE_DEBUG},
        %args
    }, $class;
    return $self;
}

sub debug {
    my ($self, $stuff) = @_;
    return unless $self->{debug};

    require JSON::PP;
    open my $fh, '>>:utf8', 'caroline.debug.log';
    print $fh JSON::PP->new->allow_nonref(1)->encode($stuff) . "\n";
    close $fh;
}

sub history { shift->{history} }

sub history_len {
    my $self = shift;
    0+@{$self->{history}};
}

sub DESTROY {
    my $self = shift;
    $self->disable_raw_mode();
}

sub readline {
    my ($self, $prompt) = @_;
    $prompt = '> ' unless defined $prompt;
    STDOUT->autoflush(1);

    local $Text::VisualWidth::PP::EastAsian = 1;

    if ($self->is_supported && -t STDIN) {
        return $self->read_raw($prompt);
    } else {
        print STDOUT $prompt;
        STDOUT->flush;
        my $line = <STDIN>;
        $line =~ s/\n$//;
        return $line;
    }
}

# linenoiseRaw
sub read_raw {
    my ($self, $prompt) = @_;

    my $ret;
    {
        $self->enable_raw_mode();
        $ret = $self->edit($prompt);
        $self->disable_raw_mode();
    }
    print STDOUT "\n";
    STDOUT->flush;
    return $ret;
}

sub enable_raw_mode {
    my $self = shift;

    my $termios = POSIX::Termios->new;
    $termios->getattr(0);
    $self->{rawmode} = [$termios->getiflag, $termios->getoflag, $termios->getcflag, $termios->getlflag, $termios->getcc(VMIN), $termios->getcc(VTIME)];
    $termios->setiflag($termios->getiflag & ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON));
    $termios->setoflag($termios->getoflag & ~(OPOST));
    $termios->setcflag($termios->getcflag | ~(CS8));
    $termios->setlflag($termios->getlflag & ~(ECHO|ICANON|IEXTEN | ISIG));
    $termios->setcc(VMIN, 1);
    $termios->setcc(VTIME, 0);
    $termios->setattr(0, TCSAFLUSH);
    return undef;
}

sub disable_raw_mode {
    my $self = shift;
    if (my $r = delete $self->{rawmode}) {
        my $termios = POSIX::Termios->new;
        $termios->getattr(0);
        $termios->setiflag($r->[0]);
        $termios->setoflag($r->[1]);
        $termios->setcflag($r->[2]);
        $termios->setlflag($r->[3]);
        $termios->setcc(VMIN, $r->[4]);
        $termios->setcc(VTIME, $r->[5]);
        $termios->setattr(0, TCSAFLUSH);
    }
    return undef;
}

sub history_add {
    my ($self, $line) = @_;
    push @{$self->{history}}, $line;
}

sub edit {
    my ($self, $prompt) = @_;
    print STDOUT $prompt;
    STDOUT->flush;

    $self->history_add('');

    my $state = Caroline::State->new;
    $state->{prompt} = $prompt;

    while (1) {
        my $c;
        if (CORE::read(STDIN, $c, 1) <= 0) {
            return $state->buf;
        }
        my $cc = ord($c);

        if ($cc == 9 && defined $self->{completion_callback}) {
            $c = $self->complete_line($state);
            return undef unless defined $c;
            $cc = ord($c);
            next if $cc == 0;
        }

        if ($cc == 13) { # enter
            pop @{$self->{history}};
            return $state->buf;
        } elsif ($cc==3) { # ctrl-c
            return undef;
        } elsif ($cc == 127 || $cc == 8) { # backspace or ctrl-h
            $self->edit_backspace($state);
        } elsif ($cc == 4) { # ctrl-d
            if (length($state->buf) > 0) {
                $self->edit_delete($state);
            } else {
                return undef;
            }
        } elsif ($cc == 20) { # ctrl-t
            # swaps current character with prvious
            if ($state->pos > 0 && $state->pos < $state->len) {
                my $aux = substr($state->buf, $state->pos-1, 1);
                substr($state->{buf}, $state->pos-1, 1) = substr($state->{buf}, $state->pos, 1);
                substr($state->{buf}, $state->pos, 1) = $aux;
                if ($state->pos != $state->len -1) {
                    $state->{pos}++;
                }
            }
            $self->refresh_line($state);
        } elsif ($cc == 2) { # ctrl-b
            $self->edit_move_left($state);
        } elsif ($cc == 6) { # ctrl-f
            $self->edit_move_right($state);
        } elsif ($cc == 16) { # ctrl-p
            $self->edit_history_next($state, $HISTORY_PREV);
        } elsif ($cc == 14) { # ctrl-n
            $self->edit_history_next($state, $HISTORY_NEXT);
        } elsif ($cc == 27) { # escape sequence
            # Read the next two bytes representing the escape sequence
            CORE::read(*STDIN, my $buf, 2)==2 or return undef;
            if ($buf eq "[D") { # left arrow
                $self->edit_move_left($state);
            } elsif ($buf eq "[C") { # right arrow
                $self->edit_move_right($state);
            } elsif ($buf eq "[A") { # up arrow
                $self->edit_history_next($state, $HISTORY_PREV);
            } elsif ($buf eq "[B") { # down arrow
                $self->edit_history_next($state, $HISTORY_NEXT);
            }
#           else if (seq[0] == 91 && seq[1] > 48 && seq[1] < 55) {
#               /* extended escape, read additional two bytes. */
#               if (read(fd,seq2,2) == -1) break;
#               if (seq[1] == 51 && seq2[0] == 126) {
#                   /* Delete key. */
#                   linenoiseEditDelete(&l);
#               }
#           }
        } elsif ($cc == 21) { # ctrl-u
            # delete the whole line.
            $state->{buf} = '';
            $state->{pos} = 0;
            $self->refresh_line($state);
        } elsif ($cc == 11) { # ctrl-k
            substr($state->{buf}, $state->{pos}) = '';
            $self->refresh_line($state);
        } elsif ($cc == 1) { # ctrl-a
            $state->{pos} = 0;
            $self->refresh_line($state);
        } elsif ($cc == 5) { # ctrl-e
            $state->{pos} = length($state->buf);
            $self->refresh_line($state);
        } elsif ($cc == 12) { # ctrl-l
            $self->clear_screen();
            $self->refresh_line($state);
        } elsif ($cc == 23) { # ctrl-w
            $self->edit_delete_prev_word($state);
        } else {
            $self->edit_insert($state, $c);
        }
    }
    return $state->buf;
}

sub edit_delete {
    my ($self, $status) = @_;
    if ($status->len > 0 && $status->pos < $status->len) {
        substr($status->{buf}, $status->pos, 1) = '';
        $self->refresh_line($status);
    }
}

sub complete_line {
    my ($self, $state) = @_;

    my @ret = grep { defined $_ } $self->{completion_callback}->($state->buf);
    unless (@ret) {
        $self->beep;
        return "\0";
    }

    my $i = 0;
    while (1) {
        # Show completion or original buffer
        if ($i < @ret) {
            my $cloned = Storable::dclone($state);
            $cloned->{buf} = $ret[$i];
            $cloned->{pos} = length($cloned->{buf});
            $self->refresh_line($cloned);
        } else {
            $self->refresh_line($state);
        }

        CORE::read(*STDIN, my $c, 1) ==1 or return undef;
        my $cc = ord($c);
        if ($cc == 9) { # tab
            $i = ($i+1) % (1+@ret);
            if ($i==@ret) {
                $self->beep();
            }
        } elsif ($cc == 27) { # escape
            # Re-show original buffer
            if ($i<@ret) {
                $self->refresh_line($state);
            }
            return $c;
        } else {
            # Update buffer and return
            if ($i<@ret) {
                $state->{buf} = $ret[$i];
                $state->{pos} = length($state->{buf});
            }
            return $c;
        }
    }
}

sub beep {
    print STDERR "\x7";
    STDERR->flush;
}

sub edit_delete_prev_word {
    my ($self, $state) = @_;

    my $old_pos = $state->pos;
    while ($state->pos > 0 && substr($state->buf, $state->pos-1, 1) eq ' ') {
        $state->{pos}--;
    }
    while ($state->pos > 0 && substr($state->buf, $state->pos-1, 1) ne ' ') {
        $state->{pos}--;
    }
    my $diff = $old_pos - $state->pos;
    substr($state->{buf}, $state->pos, $diff) = '';
    $self->refresh_line($state);
}

sub edit_history_next {
    my ($self, $state, $dir) = @_;
    if ($self->history_len > 1) {
        $self->history->[$self->history_len-1-$state->{history_index}] = $state->buf;
        $state->{history_index} += ( ($dir == $HISTORY_PREV) ? 1 : -1 );
        if ($state->{history_index} < 0) {
            $state->{history_index} = 0;
            return;
        } elsif ($state->{history_index} >= $self->history_len) {
            $state->{history_index} = $self->history_len-1;
            return;
        }
        $state->{buf} = $self->history->[$self->history_len - 1 - $state->{history_index}];
        $state->{pos} = $state->len;
        $self->refresh_line($state);
    }
}

sub edit_backspace {
    my ($self, $state) = @_;
    if ($state->pos > 0 && length($state->buf) > 0) {
        substr($state->{buf}, $state->pos-1, 1) = '';
        $state->{pos}--;
        $self->refresh_line($state);
    }
}

sub clear_screen {
    my ($self) = @_;
    print STDOUT "\x1b[H\x1b[2J";
}

sub refresh_line {
    my ($self, $state) = @_;
    if ($self->{multi_line}) {
        $self->refresh_multi_line($state);
    } else {
        $self->refresh_single_line($state);
    }
}

sub refresh_multi_line {
    my ($self, $state) = @_;
    die "Not implemented yet.";
}

sub refresh_single_line {
    my ($self, $state) = @_;
    print STDOUT "\x1b[0G"; # cursor to left edge
    print STDOUT $state->{prompt};
    print STDOUT $state->buf;
    print STDOUT "\x1b[0K"; # erase to right

    # Move cursor to original position
    printf "\x1b[0G\x1b[%dC", $state->cursor_pos;
}

sub edit_move_right {
    my ($self, $state) = @_;
    if ($state->pos != length($state->buf)) {
        $state->{pos}++;
        $self->refresh_line($state);
    }
}

sub edit_move_left {
    my ($self, $state) = @_;
    if ($state->pos > 0) {
        $state->{pos}--;
        $self->refresh_line($state);
    }
}


sub edit_insert {
    my ($self, $state, $c) = @_;
    if (length($state->buf) == $state->pos) {
        $state->{buf} .= $c;
        $state->{pos}++;
        if (not $self->{multi_line}) {
            print STDOUT $c;
            STDOUT->flush;
         #  $self->refresh_line($state);
        } else {
            $self->refresh_line($state);
        }
    }
}

sub is_supported {
    my ($self) = @_;
    my $term = $ENV{'TERM'};
    return 0 unless defined $term;
    return 0 if $term eq 'dumb';
    return 0 if $term eq 'cons25';
    return 1;
}

package Caroline::State;

use Class::Accessor::Lite 0.05 (
    rw => [qw(buf pos)],
);

sub new {
    my $class = shift;
    bless {
        buf => '',
        pos => 0,
        history_index => 0,
    }, $class;
}
use Text::VisualWidth::PP;

sub len { length(shift->buf) }

sub cursor_pos {
    my $self = shift;
    return (
        length($self->{prompt})
        + Text::VisualWidth::PP::width(substr($self->buf, 0, $self->pos))
    );
}

1;
__END__

=for stopwords binmode

=encoding utf-8

=head1 NAME

Caroline - Yet another line editing library 

=head1 SYNOPSIS

    use Caroline;

    my $c = Caroline->new;
    while (defined(my $line = $c->readline('> ')) {
        if ($line =~ /\S/) {
            print eval $line;
        }
    }

=head1 DESCRIPTION

Caroline is yet another line editing library like L<Term::ReadLine::Gnu>.

This module supports

=over 4

=item History handling

=item Complition

=back

=head1 METHODS

=over 4

=item my $caroline = Caroline->new();

Create new Caroline instance.

=item my $line = $caroline->read($prompt);

Read line with C<$prompt>.

Trailing newline is removed. Returns undef on EOF.

=back

=head1 Multi byte character support

If you want to support multi byte characters, you need to set binmode to STDIN.
You can add the following code before call Caroline.

    use Term::Encoding qw(term_encoding);
    my $encoding = term_encoding();
    binmode *STDIN, ":encoding(${encoding})";

=head1 LICENSE

Copyright (C) tokuhirom.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 TODO

=over 4

=item Multi line mode

=item Win32 Support

=item Search with C-r

=back

=head1 SEE ALSO

L<https://github.com/antirez/linenoise/blob/master/linenoise.c>

=head1 AUTHOR

tokuhirom E<lt>tokuhirom@gmail.comE<gt>

=cut

