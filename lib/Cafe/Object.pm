package Cafe::Object;

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Carp;

$Data::Dumper::Maxdepth = 4;

#{{{ new
sub new {
	my ($self) = @_;

	my ($instance) = {};
	bless($instance);
}
#}}}
#{{{ die
sub die {
	my $self = shift;
	my $sub;
	my $msg;
	my $line;
	
	$self->print_stack;
	if ( scalar( @_ ) == 3 ) {
		$sub = $_[0];
		$msg = $_[1];
		$line = $_[2];
	} elsif ( scalar( @_ ) == 2 ) {
		$sub = ref($self);
		$msg = $_[0];
		$line = $_[1];
	}
	my $message = "Error $sub : $msg." . ($line ? " (line $line)" : "");
	die $message;
}
#}}}
#{{{ print_stack
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
1;
