requires 'perl', '5.008001';
requires 'Storable';
requires 'POSIX';
requires 'Text::VisualWidth::PP', 0.03;
requires 'Class::Accessor::Lite', 0.05;
requires 'Term::ReadKey', 2.30;

on 'test' => sub {
    requires 'Test::More', '0.98';
};

