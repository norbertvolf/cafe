package Mojolicious::Cafe::Plugin::SMS::Test;

use Mojo::Base 'Mojolicious::Plugin';
use Ecs::SMS;
use DateTime;

sub register {
	my ($self, $app) = @_;
	$app->helper( 
		sendsms => sub {
			my $c = shift;
			my $to = shift;
			my $message = shift;
			my %params;
			%params = @_ if ( scalar(@_) );

			#Prepare default patameters 
			#sender means name in the sms message header
			$params{sender} = $params{sender} // $c->app->config->{sms_sender};
			$params{sender} = $params{sender} // 'Bata';

			#flash means that content is private and to database 
			#is saved just '*'
			$params{flash} = $params{flash} // 0;

			#Prepare SMS 
			my $sms = Ecs::SMS->new($c);
			$sms->message($message);
			$sms->phonenumber($to);
			$sms->stateuser(0);
			$sms->sentstamp(DateTime->now);
			$sms->billed(0);
			$sms->locale('');
			$sms->parts(1);

			$to =~ s/[+ ]//g;
			$sms->dbh->begin_work();
			$c->app->log->debug("Phone:$to Message:$message");
			$sms->message('*') if ($params{flash});
			$sms->save();
			$sms->dbh->commit();

			return(1);
		},
	);
}

1;
