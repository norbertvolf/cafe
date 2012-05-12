package Mojolicious::Cafe::Class::Versioned;

use Mojo::Base 'Mojolicious::Cafe::Class';

#{{{ new
#Create new instance of Cafe::Mojo::Class
sub new {
	my $class = shift;
	my $c = shift;
	my $definition = shift;
	my $self = $class->SUPER::new($c, $definition);
	Mojo::Exception->throw("To enable Mojolicious::Cafe::Class::Versioned must be defined just one column as primary key.") if ( scalar($self->pkc) > 1 );
	Mojo::Exception->throw("To enable Mojolicious::Cafe::Class::Versioned must be defined primary key.") if ( scalar($self->pkc) < 1 );
	Mojo::Exception->throw("To enable Mojolicious::Cafe::Class::Versioned column statestamp must be defined.") if ( ! exists($self->definition->{columns}->{statestamp}) );
	Mojo::Exception->throw("To enable Mojolicious::Cafe::Class::Versioned column stateuser must be defined.") if ( ! exists($self->definition->{columns}->{stateuser}) );
	Mojo::Exception->throw("To enable Mojolicious::Cafe::Class::Versioned column state must be defined.") if ( ! exists($self->definition->{columns}->{state}) );
	return($self);
}
#}}}
#{{{ save
#Save to database instance of Cafe::Mojo::Class. Class must 
#You must also define columns in directives
sub save {
	my $self = shift;
	$self->SUPER::save();
	my $sth = $self->c->dbh->prepare( q(INSERT INTO public.revision( tablename, id, json, state, stateuser, statestamp ) VALUES ( ?, ?, ?, ?, ?, ? ) ) );
	eval { 
		$sth->execute($self->entity, $self->pkv, $self->json, $self->state, $self->stateuser, $self->statestamp);
	}; 
	if ( $@ ) {
		Mojo::Exception->throw("$@" . $self->c->caller );
	}

}
#}}}

1;

__END__
