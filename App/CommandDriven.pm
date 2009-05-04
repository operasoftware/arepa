package App::CommandDriven;

sub new {
    my ($class, @args) = @_;
    my $self = {
        global_options => {list          => [],
                           getopt_spec   => [],
                           help_messages => {}},
        commands => [],
    };
    return bless $self, $class;
}

sub global_options {
    my ($self, @opt_definition) = @_;

    for (my $i = 0; $i < scalar $#opt_definition; $i+=2) {
        push @{$self->{global_options}->{list}}, $opt_definition[$i];
        $self->{global_options}->{spec}->{$opt_definition[$i]} =
            $opt_definition[$i+1];
    }
}

sub global_getopt_spec {
    my ($self) = @_;
    return map {
        my $getopt_spec = $_;
        my $opt_type = $self->{global_options}->{spec}->{$_}->{type};
        if ($opt_type eq 'string') {
            $getopt_spec .= '=s';
        }
        elsif ($opt_type eq 'integer') {
            $getopt_spec .= '=i';
        }
        $getopt_spec;
    }
    @{$self->{global_options}->{list}};
}

sub run {
    my ($self) = @_;

    my $p = Getopt::Long::Parser->new;
    $p->configure('bundling', 'require_order');
    if ($p->getoptions($self->{global_options}->{getopt_spec})) {
        my $command = shift @ARGV;
        my $method  = "dispatch_command_$command";
        if ($self->can($method)) {
            $self->$method;
        }
        else {
            print STDERR "Command '$command' not implemented.\n";
            exit 1;
        }
    }
    else {
        print_help;
        exit 1;
    }
}

sub option_help_line {
    my ($self, $opt, $help_text) = @_;

    my @aliases = sort { (length($a) == 1) <=>
                         (length($b) == 1) }
                       split(/\|/, $opt);
    my $opt_def = join(", ", map { length($_) == 1 ? "-$_" : "--$_" }
                                 @aliases);
    return "  " . $opt_def . (" " x (25 - length($opt_def))) . $help_text . "\n";
}

sub print_help {
    my ($self) = @_;

    print STDERR "SYNTAX: $0 [global_opts] command [command_opts]\n";
    my @global_options = @{$self->{global_options}->{list}};
    if (scalar @global_options) {
        print STDERR "Global options are:\n";
        print STDERR join("",
                          map {
                              $self->option_help_line($_,
                                                      $self->{global_options}->
                                                        {spec}->{$_}->{help})
                          } @global_options);
    }
    print STDERR "command can be:\n";
    print STDERR ""
}

1;

__END__

global_options('verbose|v' => {type => 'flag',
                               help => 'Verbose mode'},
               'version'   => {type => 'flag',
                               help => 'Shows version and exits'},
               'config|c'  => {type => 'string',
                               help => 'Specifies an alternative configuration file'});
register_command('build',
                 'pending|p'   => {type      => 'flag',
                                   help      => 'Builds the pending requests'},
                 'recompile|r' => {type      => 'integer',
                                   help      => "(Re)compiles the given request, even if it's not pending",
                                   conflicts => 'pending'});
register_command('showqueue|show-queue',
                 'status|s' => {type => 'string',
                                help => 'Only shows queue entries with the given status'},
                 'arch|a'   => {type => 'string',
                                help => 'Only shows queue entries with the given architecture'});
