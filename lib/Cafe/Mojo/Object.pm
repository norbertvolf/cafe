package Cafe::Mojo::Object;

use Mojo::Base -base;
use Data::Dumper;
use Carp;

has 'root';

#{{{ new
sub new {
	my $class = shift;
	my $root = shift;

	my $self = $class->SUPER::new();
	#Add root to default object
	$self->root($root);
	return($self);
}
#}}}
#{{{ die
sub die {
	my $self = shift;
	my $sub;
	my $msg;
	my $line;
	
	$self->print_stack;
	if ( scalar( @_ ) == 2 ) {
		$sub = ref($self);
		$msg = $_[0];
		$line = $_[1];
	}
	my $message = "Error $sub : $msg." . ($line ? " (line $line)" : "");
	die $message;
}
#}}}
#{{{ print_stack
=head3 print_stack 

Print called function stack

=cut
sub print_stack {
	my $self = shift;
	my $max_depth = 30;
	my $i = 1;
	print(STDERR "\n--- Begin stack trace ---\n");
	while ( (my @call_details = (caller($i++))) && ($i<$max_depth) ) {
		print(STDERR "$call_details[1] line $call_details[2] in function $call_details[3]\n");
	}
	print(STDERR "--- End stack trace ---\n\n");
}
#}}}
#{{{ debug
=head3 debug

Print to log debug messageo or dump ARRAY or HASH reference

=cut
sub debug {
	my $self = shift;

	while ( my $param = shift ) {
		if ( ref($param) eq "ARRAY" || ref($param) eq "HASH" ) {
			$self->root->app->log->debug(Dumper($param));
		} else {
			$self->root->app->log->debug($param);
		}
	}
}
#}}}

1;
