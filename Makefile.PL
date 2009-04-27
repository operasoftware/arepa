use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'                => 'Arepa',
    'VERSION_FROM'        => 'lib/Arepa.pm',
    'PREREQ_PM'           => {}, # e.g., Module::Name => 1.1
    'ABSTRACT_FROM'       => 'lib/Arepa.pm',
    'AUTHOR'              => 'Esteban Manchado Velázquez <estebanm@opera.com>',
);
