#!/usr/bin/perl -w

# apt-get install libheap-perl libio-async-loop-epoll-perl libnet-prometheus-perl libplack-perl
# cpan install Device::ELM327 Net::MQTT::Simple Net::Async::HTTP::Server

use strict;
use Device::ELM327;
use Data::Dumper;
use Net::MQTT::Simple("127.0.0.1");
use JSON;
use IO::Async::Timer::Countdown;
use IO::Async::Loop;
use Net::Prometheus;
use Plack::Builder;

my $debug = 0;
my @pids = (
	{pid => "2211b6", name => "TR",	   descr => "Transmission Range Status",	offset => 0, bits => 8,  scale => 1 / 2, fmt => "%d", type => "bits"},
	{pid => "2216b5", name => "TR_D",  descr => "Transmission Range Bits",		offset => 0, bits => 8,  fmt => "0x%02X", type => "bits"},
	{pid => "221105", name => "SOL",   descr => "PCM solenoids",			offset => 0, bits => 8,  fmt => "0x%02X", type => "sol"},
	{pid => "221105", name => "SS1",   descr => "SS1 solenoid",			offset => 0, bits => 8,  mask => 0x10, fmt => "%d", type => "sol"},
	{pid => "221105", name => "SS2",   descr => "SS2 solenoid",			offset => 0, bits => 8,  mask => 0x20, fmt => "%d", type => "sol"},
	{pid => "221105", name => "CSS",   descr => "Coast Clutch solenoid",		offset => 0, bits => 8,  mask => 0x80, fmt => "%d", type => "sol"},
	{pid => "2211b3", name => "GEAR",  descr => "trans gear state",			offset => 0, bits => 8,  scale => 1/2, fmt => "%d", type => "gear"},
	{pid => "2211b0", name => "TCC",   descr => "torque conv clutch control",	offset => 0, bits => 16, scale => 1/32768*100, fmt => "%d%%", type => "percent"},
	{pid => "22110e", name => "TCCA",  descr => "torque conv internal ckt monitor",	offset => 0, bits => 8,  mask => 0x80, fmt => "%d", type => "monitor"},
	{pid => "2211c0", name => "EPC",   descr => "trans line pressure control",	offset => 0, bits => 8,  scale => 5, fmt => "%d psi", type => "pressure"},
	{pid => "2211b2", name => "EPC_V", descr => "trans line pressure ctl voltage",	offset => 0, bits => 16, scale => 1/256/10, fmt => "%.1f V", type => "voltage"},
	{pid => "2211bd", name => "TFT_V", descr => "trans fluid temp input voltage",	offset => 0, bits => 16, scale => 1/13168, fmt => "%.1f V", type => "voltage"},
	{pid => "221154", name => "TP_V",  descr => "throttle position",		offset => 0, bits => 16, scale => 1/256*100, fmt => "%d %%", type => "percent"},
#	{pid => "221629", name => "TPB_V", descr => "2nd throttle voltage",		offset => 0, bits => 16, scale => 1/256/10, fmt => "%.1f V", type => "voltage"},
	{pid => "2211b4", name => "TSS",   descr => "turbine shaft speed",		offset => 0, bits => 16, scale => 1 / 4, fmt => "%d rpm", type => "rpm"},
	{pid => "2211b5", name => "OSS",   descr => "output shaft speed",		offset => 0, bits => 16, scale => 1 / 4, fmt => "%d rpm", type => "rpm"},
	{pid => "221310", name => "EOT",   descr => "engine oil temp",			offset => 0, bits => 16, scale => 9 / 5 / 100, bias => -40, fmt => "%d degF", type => "temp"},
	{pid => "221101", name => "TCS",   descr => "overdrive enabled",		offset => 0, bits => 8,  mask => 0x10, fmt => "%d", type => "gate"},
	{pid => "221104", name => "TCIL",  descr => "overdrive OFF light",		offset => 0, bits => 8,  mask => 0x04, fmt => "%d", type => "gate"},
	{pid => "221101", name => "PSP",   descr => "Power steering pressure sw input",	offset => 0, bits => 8,  mask => 0x80, fmt => "%d", type => "gate"},
	{pid => "221101", name => "BPP",   descr => "Brake pedal position input",	offset => 0, bits => 8,  mask => 0x02, fmt => "%d", type => "gate"},
	{pid => "221101", name => "ACCS",  descr => "A/C cycling swith input",		offset => 0, bits => 8,  mask => 0x01, fmt => "%d", type => "gate"},
	{pid => "221104", name => "WAC",   descr => "A/C clutch command",		offset => 0, bits => 8,  mask => 0x01, fmt => "%d", type => "gate"},
	{pid => "221434", name => "IPR",   descr => "IPR duty cycle",			offset => 0, bits => 8,  scale => 0x3e8 / 0xFF / 100, fmt => "%.1f %%", type => "percent"},
	{pid => "221446", name => "ICP",   descr => "injection control pressure",	offset => 0, bits => 16, scale => 0x47 / 0x7d, fmt => "%d psi", type => "pressure"},
	{pid => "221412", name => "MFD",   descr => "mass fuel desired",		offset => 0, bits => 16, scale => 0x64 / 0x10 / 10, fmt => "%.1f mg", type => "fuel"},
	{pid => "221411", name => "VFD",   descr => "volume fuel desired",		offset => 0, bits => 16, scale => 0x64 / 0x10 / 10,fmt => "%.1f cu mm", type => "fuel"},
	{pid => "221410", name => "FPW",   descr => "fuel pulse width",			offset => 0, bits => 16, scale => 4 / 5 / 10, fmt => "%.1f ms", type => "fuel"},
	{pid => "221445", name => "EBP",   descr => "exhaust back pressure",		offset => 0, bits => 16, scale => 0x1d / 0x50 / 100, fmt => "%.1f psi", type => "pressure"},
	{pid => "221440", name => "BST",   descr => "boost",				offset => 0, bits => 16, scale => 0x1d / 0x50 / 10, bias => -11.89, fmt => "%.2f psi", type => "pressure"},
#	{pid => "221127", name => "BAR",   descr => "barometric pressure",		offset => 0, bits => 8,  fmt => "%g inches Hg", type => "pressure"},
);

sub do_cmd;

my $prom = Net::Prometheus->new;
my $loop = IO::Async::Loop->new;
my $port = 9111;

builder {
	mount "/metrics" => $prom->psgi_app;
};

my %gauges;
my $obd;

#
# get ready
#
print "booting up the ELM327\n";
prep_obd2();

print "starting up the http metrics server\n";
$prom->export_to_IO_Async($loop, (port => $port));

print "begin scanning...";

system("sleep 2; clear");

#
# begin updates
#
my $timer = IO::Async::Timer::Countdown->new(
	delay => .1,
	on_expire => sub {
		my $self = shift;
		update_metrics();
		$self->start;
	},
);
$timer->start;

$loop->add($timer);
$loop->run;

sub prep_obd2 {

	$obd = Device::ELM327->new("/dev/ttyUSB0", $debug);

	die "can't talk to ELM327\n" unless $obd->PortOK();

	do_cmd "at i";
	do_cmd "at h1";
	do_cmd "at sp 1";
	do_cmd "at dp";
	do_cmd "at sh c4 10 f1";
}

sub update_metrics {
	system("tput cup 0 0");
	my %obj = ();
	for my $p (@pids) {
		my $status = do_cmd $p->{pid};
		my $r = $obd->{results}->{"10"}->{result};
		my $val = defined($r->[2]) ? $r->[2] : 0;
		my $valstr;
		if ($p->{bits} == 16 && defined($r->[3])) {
			$val = $val * 256 + $r->[3];
			$valstr = sprintf("%04X", $val);
		} else {
			$valstr = sprintf("%02X", $val);
		}
		if ($p->{scale}) { $val *= $p->{scale}; }
		if ($p->{bias}) { $val += $p->{bias}; }
		if ($p->{mask}) { $val = $val & $p->{mask} ? 1 : 0; }

		$obj{$p->{name}} = $val;

		publish("pids/$p->{name}", "{\"value\":$val}");
		update_gauge($p, $val);

		printf("%s %-4s %-5s %-16s %s\n", $p->{pid}, $valstr, $p->{name}, sprintf($p->{fmt}, $val), $p->{descr});
	}

	publish("obd2", to_json(\%obj));
	sleepms(100);
}

sub update_gauge {
	my ($p, $val) = @_;
	my $ga = "pid_$p->{name}";

	if (!defined($gauges{$ga})) {
		$gauges{$ga} = $prom->new_gauge(name => $ga, help => "PID $p->{pid} $p->{descr}", labels => ["type"]);
	}
	my $g = $gauges{$ga};

	$g->set({type => $p->{type}}, $val);
}

sub do_cmd {
	my $cmd = shift;

	print "+ $cmd\n" if $debug;

	return $obd->Command($cmd);
}

sub sleepms {
	my $ms = shift;

	select(undef, undef, undef, $ms / 1000);
}
