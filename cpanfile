requires 'perl', '5.008001';
requires 'Storable';
requires 'POSIX';
requires 'Text::VisualWidth::PP', 0.03;
requires 'Class::Accessor::Lite', 0.05;
requires 'Term::ReadKey', 2.30;
requires 'IO::Handle';
recommends 'Term::ReadLine';

if ($^O eq 'MSWin32') {
    require Win32::API;
    require Encode;
    require Term::Encoding;
    require Win32::Console::ANSI;
}

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'File::Temp';
};

