# NAME

Caroline - Yet another line editing library 

# SYNOPSIS

    use Caroline;

    my $c = Caroline->new;
    while (defined(my $line = $c->read('> ')) {
        if ($line =~ /\S/) {
            print eval $line;
        }
    }

# DESCRIPTION

Caroline is yet another line editing library like [Term::ReadLine::Gnu](http://search.cpan.org/perldoc?Term::ReadLine::Gnu).

This module supports

- History handling
- Complition

# Multi byte character support

If you want to support multi byte characters, you need to set binmode to STDIN.
You can add the following code before call Caroline.

    use Term::Encoding qw(term_encoding);
    my $encoding = term_encoding();
    binmode *STDIN, ":encoding(${encoding})";

# LICENSE

Copyright (C) tokuhirom.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# TODO

- Multi line mode
- Win32 Support
- Search with C-r

# SEE ALSO

[https://github.com/antirez/linenoise/blob/master/linenoise.c](https://github.com/antirez/linenoise/blob/master/linenoise.c)

# AUTHOR

tokuhirom <tokuhirom@gmail.com>
