requires 'perl', '5.008001';
requires 'Storable';
requires 'POSIX';
requires 'Text::VisualWidth::PP', 0.02;

on 'test' => sub {
    requires 'Test::More', '0.98';
};

