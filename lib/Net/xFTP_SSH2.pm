package Net::xFTP::SSH2;

use Fcntl ':mode';
use File::Copy;

my $bummer = ($^O =~ /Win/);
my @permvec = ('---','--x','-w-','-wx','r--','r-x','rw-','rwx');

sub new_ssh2
{
	my $subclass = shift;
	my $pkg = shift;
	my $host = shift;
	my %args = @_;
	my %xftp_args;
	my $xftp = bless { }, $subclass;
	$xftp->{BlockSize} = 10240;
	if (defined $args{BlockSize})
	{
		$xftp->{BlockSize} = $args{BlockSize} || 10240;
		delete($args{BlockSize});
	}	
	my $saveEnvHome = $ENV{HOME};
#		$ENV{HOME} = $xftp_args{home}  if ($xftp_args{home});
	$xftp->{xftp} = Net::SSH2->new();
	unless (defined $xftp->{xftp})
	{
		$xftp->{xftp_lastmsg} = $@;
		return;
	}
#		$ENV{HOME} = $saveEnvHome || '';
	if ($xftp->{xftp})
	{
		my $ok = $xftp->{xftp}->connect($host);		
		unless (defined($ok) && $ok)
		{
			$xftp->{xftp_lastmsg} = "new:connect($host):Could not connect to host("
					.join(' ', $xftp->{xftp}->error()).")!";
			return;
		}
		if (defined $args{user})
		{
			$args{user} ||= 'anonymous';
			$args{password} ||= 'anonymous@'  if ($args{user} eq 'anonymous');
			my @loginargs = ($args{user});
			push (@loginargs, $args{password})  if (defined $args{password});
			push (@loginargs, $args{account})  if (defined $args{account});
			if ($xftp->{xftp}->auth_password(@loginargs))
			{
				$xftp->{sshsftp} = $xftp->{xftp}->sftp();					
				unless ($xftp->{sshsftp})					
				{
					$xftp->{xftp_lastmsg} = 'new:auth_password:Could not authenticate, bad password('
							.join(' ', $xftp->{xftp}->error()).')?';
					return;						
				}
				my $cwd = $xftp->{sshsftp}->realpath('.');
				$xftp->{cwd} = $cwd  if ($cwd);					
				return $xftp;
			}
		}
		else
		{
			if ($xftp->{xftp}->auth_keyboard())				
			{				
				$xftp->{sshsftp} = $xftp->{xftp}->sftp();					
				unless ($xftp->{sshsftp})					
				{
					$xftp->{xftp_lastmsg} = 'new:sftp:Could not create sftp object('
							.join(' ', $xftp->{xftp}->error()).")!";
					return;						
				}
				my $cwd = $xftp->{xftp}->realpath('.');
				$xftp->{cwd} = $cwd  if ($cwd);
				return $xftp;
			}
		}
		$@ ||= 'Invalid Password?';
		return;
	}
}

{
	no warnings 'redefine';
	sub cwd  #SET THE "CURRENT" DIRECTORY.
	{
		my $self = shift;
		my $cwd = shift || '/';

		my $ok;
		$ok = $self->{sshsftp}->realpath($cwd);
		$self->{cwd} = $ok  if ($ok);
		return $ok ? 1 : undef;
	}

	sub copy
	{
		my $self = shift;

		return undef  unless (@_ >= 2);
		my @args = @_;
		for (my $i=0;$i<=1;$i++)
		{
			$args[$i] = $self->{cwd} . '/' . $args[$i]  unless ($args[$i] =~ m#^(?:[a-zA-Z]\:|\/)#o);
		}
		if ($self->isadir($args[1]))
		{
			my $filename = $1  if ($args[0] =~ m#([^\/]+)$#o);
			$args[1] .= '/'  unless ($args[1] =~ m#\/$#o);
			$args[1] .= $filename;
		}

		my $ok;
		my ($tmp, $t, $bytecnt);
		my $fromHandle;
		eval { $fromHandle = $self->{sshsftp}->open($args[0], 0) };
		if ($fromHandle)
		{
			my $err;
			$t = '';
			my $offset = 0;
			while (1)
			{
				$bytecnt = $fromHandle->read($tmp, $self->{BlockSize});
				last  unless (defined($bytecnt) && $bytecnt > 0);
				$t .= $tmp;
				$offset += $bytecnt;
				$fromHandle->seek($offset);
			}
			return 1  if ($offset);
			$self->{xftp_lastmsg} = "copy:open($args[0], 0):Could not get data into filehandle("
					.join(' ', $self->{sshsftp}->error()).")!";
			return undef;
		}
		else
		{
			$self->{xftp_lastmsg} = "copy:open($args[0], 0):Could not open remote file to copy from("
					.join(' ', $self->{sshsftp}->error()).")!";
			return undef;
		}
		my $toHandle;
		eval
		{
			no strict 'subs';
			my $openFlags = O_RDWR|O_CREAT|O_TRUNC;
			$toHandle = $self->{sshsftp}->open($args[1], $openFlags);
		};
		if ($toHandle)
		{
			my $bytecnt = $toHandle->write($t);
			return 1  if ($bytecnt);
			$self->{xftp_lastmsg} = "copy:open($args[1]):Could not copy file("
					.join(' ', $self->{sshsftp}->error()).")!";
			return undef;
		}
		else
		{
			$self->{xftp_lastmsg} = $@ || 'Could not open remote handle for unknown reasons!';
			return undef;
		}
		return $ok ? 1 : undef;
	}

	sub move
	{
		my $self = shift;

		return undef  unless (@_ >= 2);
		return ($self->copy(@_) && $self->delete($_[0])) ? 1 : undef;
	}
}

sub ascii
{
	my $self = shift;

	return undef;
}

sub binary
{
	my $self = shift;

	return undef;
}

sub quit
{
	my $self = shift;
	$self->{xftp} = undef;
	delete($self->{xftp});

	return;
}

sub ls
{
	my $self = shift;
	my $path = shift || '';
	my $showall = shift || 0;
	my @dirlist;
	my $realpath = $self->{sshsftp}->realpath($path||$self->{cwd}||'.');
#		chomp $realpath;
	$realpath = $self->{cwd} . '/' . $realpath  unless ($realpath =~ m#^(?:[a-zA-Z]\:|\/)#o);
	my $sshdir = $self->{sshsftp}->opendir($realpath);
	if ($sshdir)
	{
		my ($h, @tm, $mtimeStr, $filetype);
		while ($h = $sshdir->read())
		{
			next  if ($h->{name} =~ /\d \.\.$/o && $path eq '/');
			next  if (!$showall && $h->{name} =~ /^\.[^\.]\S*$/o);
			$filetype = &getPermStr($h->{mode});
			@tm = localtime($h->{mtime});
			push (@dirlist, $h->{name});
		}
	}
	else
	{
		$self->{xftp_lastmsg} = "ls:opendir($realpath):Could not open directory("
				.join(' ', $self->{sshsftp}->error()).')!';
		return;
	}
	@dirlist = sort @dirlist;

	##ON SOME SERVERS, THESE DON'T GET ADDED ON, SO ADD THEM HERE!
	#unshift (@dirlist, '..')  unless ($path eq '/' || $dirlist[1] eq '..');
	#unshift (@dirlist, '.')  unless ($dirlist[0] eq '.');

	return wantarray ? @dirlist : \@dirlist;
}

sub dir
{
	my $self = shift;
	my $path = shift || '';
	my $showall = shift || 0;
	my @dirlist;
	my $realpath = $self->{sshsftp}->realpath($path||$self->{cwd}||'.');
#		chomp $realpath;
	$realpath = $self->{cwd} . '/' . $realpath  unless ($realpath =~ m#^(?:[a-zA-Z]\:|\/)#o);
	my $sshdir = $self->{sshsftp}->opendir($realpath);
	if ($sshdir)
	{
		my ($h, @tm, $mtimeStr, $filetype);
		while ($h = $sshdir->read())
		{
			next  if ($h->{name} =~ /\d \.\.$/o && $path eq '/');
			next  if (!$showall && $h->{name} =~ /^\.[^\.]\S*$/o);
			$filetype = &getPermStr($h->{mode});
			@tm = localtime($h->{mtime});
			push (@dirlist, sprintf "%s\x02%10s %2d %8s %8s %4d-%2.2d-%2.2d %2.2d:%2.2d %s\n", 
					$h->{name}, $filetype, $h->{uid}, $h->{gid}, $h->{size}, 
					$tm[5]+1900, $tm[4]+1, $tm[3], $tm[2], $tm[1], $h->{name});
		}
		@dirlist = sort(@dirlist);
		for (my $i=0;$i<=$#dirlist;$i++)
		{
			$dirlist[$i] =~ s/^[^\x02]*\x02//so;
		}
	}
	else
	{
		$self->{xftp_lastmsg} = "dir:opendir($realpath):Could not open directory("
				.join(' ', $self->{sshsftp}->error()).')!';
		return;
	}

	##ON SOME SERVERS, THESE DON'T GET ADDED ON, SO ADD THEM HERE!
	#unshift (@dirlist, '..')  unless ($path eq '/' || $dirlist[1] =~ /\d \.\.$/);
	#unshift (@dirlist, '.')  unless ($dirlist[0] =~ /\d \.$/);

	return wantarray ? @dirlist : \@dirlist;
}

sub pwd  #GET AND RETURN THE "CURRENT" DIRECTORY.
{
	my $self = shift;

	return $self->{cwd};
}

sub get    #(Remote, => Local)
{
	my $self = shift;

	return undef  unless (@_ >= 1);
	my @args = @_;
	$args[0] = $self->{cwd} . '/' . $args[0]  unless ($args[0] =~ m#^(?:[a-zA-Z]\:|\/)#o);
	if (@args >= 2)
	{
		$args[1] = \$_[1]  if (ref(\$args[1]) =~ /GLOB/io);
	}
	else
	{
		if (ref(\$args[0]) =~ /GLOB/io)
		{
			$self->{xftp_lastmsg} = 'Must specify a remote filename (2 arguments) since 1st arg. is a filehandle!';
			return undef;
		}
		$args[1] = $args[0];
		$args[1] = $1  if ($args[1] =~ m#([^\/\\]+)$#o);
	}
	my $ok;
	if (ref(\$_[1]) =~ /GLOB/io)
	{
		my $remoteHandle;
		my $offset = 0;
		my $buff;
		my $bytecnt;
		my $unsubscriptedFH = $_[1];
		eval { $remoteHandle = $self->{sshsftp}->open($args[0], 0) };
		if ($remoteHandle)
		{
			my $err;
			while (1)
			{
				$bytecnt = $remoteHandle->read($buff, $self->{BlockSize});
				last  unless (defined($bytecnt) && $bytecnt > 0);
				print $unsubscriptedFH $buff;
				$offset += $bytecnt;
				$remoteHandle->seek($offset);
			}
			return 1  if ($offset);
			$self->{xftp_lastmsg} = "get:open($args[0]):Could not get data into filehandle("
					.join(' ', $self->{sshsftp}->error()).')!';
			return undef;
		}
		else
		{
			$self->{xftp_lastmsg} = $@ || "get:open($args[0]):Could not open remote handle for unknown reasons!";
			return undef;
		}
	}
	else
	{
		$ok = $self->{xftp}->scp_get(@args);
		return 1  if ($ok);
		$self->{xftp_lastmsg} = "get:scp_get(".join(',',@args)
				."):Could not get file from remote host("
				.join(' ', $self->{xftp}->error()).')!';
		return undef;
	}
	return $ok ? 1 : undef;
}

sub put    #(LOCAL => REMOTE) SFTP returns OK=1 on SUCCESS.
{
	my $self = shift;

	return undef  unless (@_ >= 1);
	my @args = @_;
	if (@args >= 2)
	{
		$args[0] = \$_[0]  if (ref(\$args[0]) =~ /GLOB/io);
	}
	else
	{
		if (ref(\$args[0]) =~ /GLOB/io)
		{
			$self->{xftp_lastmsg} = 'Must specify a remote filename (2 arguments) since 1st arg. is a filehandle!';
			return undef;
		}
		$args[1] = $args[0];
		$args[1] = $1  if ($args[1] =~ m#([^\/\\]+)$#o);
	}
	$args[1] = $self->{cwd} . '/' . $args[1]  unless ($args[1] =~ m#^(?:[a-zA-Z]\:|\/)#o);

	my $ok;
	if (ref(\$_[0]) =~ /GLOB/io)
	{
		my $remoteHandle;
		my $offset = 0;
		my $buff;
		my $unsubscriptedFH = $_[0];
		eval
		{
			no strict 'subs';
			my $openFlags = O_RDWR|O_CREAT|O_TRUNC;
			$remoteHandle = $self->{sshsftp}->open($args[1], $openFlags);
		};
		if ($remoteHandle)
		{
			my $t;
			while ($buff = <$unsubscriptedFH>)
			{
				$t .= $buff;
			}
			my $bytecnt = $remoteHandle->write($t);
			return 1  if ($bytecnt);
			$self->{xftp_lastmsg} = "put:open($args[1]):Could not put data to remote host("
					.join(' ', $self->{sshsftp}->error()).')!';
			return undef;
		}
		else
		{
			$self->{xftp_lastmsg} = $@ || 'Could not open remote handle for unknown reasons!';
			return undef;
		}
	}
	else
	{
		eval { $ok = $self->{xftp}->put(@args) };
		$self->{xftp_lastmsg} = $@  if ($@);
	}
	return $ok ? 1 : undef;
}

sub delete       #RETURNED OK=2 WHEN LAST FAILED.
{
	my $self = shift;
	my $path = shift;

	my $ok;
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	eval { $ok = $self->{sshsftp}->unlink($path) };
	$self->{xftp_lastmsg} = $@  if ($@);
	return $@ ? undef : 1;
}

sub rename
{
	my $self = shift;
	return undef  unless (@_ == 2);

	my ($oldfile, $newfile) = @_;

	my $ok;
	$oldfile = $self->{cwd} . '/' . $oldfile  unless ($oldfile =~ m#^(?:[a-zA-Z]\:|\/)#o);
	$newfile = $self->{cwd} . '/' . $newfile  unless ($newfile =~ m#^(?:[a-zA-Z]\:|\/)#o);
	eval { $ok = $self->{sshsftp}->rename($oldfile, $newfile) };
	$self->{xftp_lastmsg} = $@  if ($@);
	return $@ ? undef : 1;
}

sub mkdir
{
	my $self = shift;
	my $path = shift;
	my $tryRecursion = shift||0;
	$path =~ s#[\/\\]$##o  unless ($path eq '/');

	my @pathStack;
	my $ok = '';
	my $orgPath = $path;
	my $didRecursion = 0;
	my $errored = 0;
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	while ($path)
	{
		eval { $ok = $self->{sshsftp}->mkdir($path) };
		$self->{xftp_lastmsg} = $@  if ($@);
		last  if ($ok);
		if ($tryRecursion)
		{
			push (@pathStack, $path);
			$path =~ s#[^\/\\]+$##o;
			$path =~ s#[\/\\]$##o;
			$didRecursion = 1;
		}
		else
		{
			$self->{xftp_lastmsg} = "mkdir:mkdir($path):Could not create subdirectory("
					.join(' ', $self->{sshsftp}->error()).')!';
			$errored = 1;
			last;
		}
	}
	if ($didRecursion)
	{
		while (@pathStack)
		{
			$path = pop @pathStack;
			next  if ($self->{sshsftp}->mkdir($path));
			$self->{xftp_lastmsg} = "mkdir:mkdir($path):Could not recursively create subdirectory("
					.join(' ', $self->{sshsftp}->error()).')!';
			return undef;

		}
		return 1;
	}
#		return (defined($ok) && $ok) ? 1 : undef;
	return $errored ? 1 : undef;
}

sub rmdir
{
	my $self = shift;
	my $path = shift;
	$path =~ s#[\/\\]$##o  unless ($path eq '/');

	my $ok;
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	eval { $ok = $self->{sshsftp}->rmdir($path) };
	$self->{xftp_lastmsg} = $@  if ($@);
	return $@ ? undef : 1;
}

sub message
{
	my $self = shift;

	chomp $self->{xftp_lastmsg};
	return $self->{xftp_lastmsg};
}

sub mdtm
{
	my $self = shift;
	my $path = shift;

	my $ok;
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	my %statHash = $self->{sshsftp}->stat($path);
	unless (defined $statHash{mtime})
	{
		$self->{xftp_lastmsg} = "mdtm:stat($path):Could not fetch file mdtm("
				.join(' ', $self->{sshsftp}->error()).')!';
		return undef;
	}
	return $statHash{'mtime'};
}

sub size
{
	my $self = shift;
	my $path = shift;

	my $ok;
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	my %statHash = $self->{sshsftp}->stat($path);
	unless (defined $statHash{'size'})
	{
		$self->{xftp_lastmsg} = "size:stat($path):Could not fetch file size("
				.join(' ', $self->{sshsftp}->error()).')!';
		return undef;
	}
	return $statHash{'size'};
}

sub isadir
{
	my $self = shift;
	my $path = shift;

	my $ok;
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	eval { $ok = $self->{sshsftp}->opendir($path) };
	if (defined($ok) && $ok)
	{
			eval { $self->{xftp}->do_close($ok) };
		return 1;
	}
	return 0;
}

sub chmod
{
	my $self = shift;
	my $permissions = shift;
	my $path = shift;

	my ($ok, $attrs);
	$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^(?:[a-zA-Z]\:|\/)#o);
	my %statHash = $self->{sshsftp}->stat($path);
	unless (defined $statHash{mode})
	{
		$self->{xftp_lastmsg} = "chmod:stat($path):Could not fetch current file permissions("
				.join(' ', $self->{sshsftp}->error()).')!';
		return undef;
	}
	my $filetype = int($statHash{mode} / 4096);
	eval "\$permissions = 0$permissions";
	$statHash{mode} = ($filetype*4096) + $permissions;
	$ok = $self->{sshsftp}->setstat($path, mode => $statHash{mode});
	unless (defined($ok) && $ok)
	{
		$self->{xftp_lastmsg} = "chmod:setstat($path, mode => $statHash{mode}):Invalid permissions (0-777) - $@ ("
				.join(' ', $self->{sshsftp}->error()).')!';
		return undef;
	}
	return 1;
}

sub getPermStr
{
	my $mode = shift;

	my (%ftypes);
	$ftypes{(S_IFDIR)} = "d";
	$ftypes{(S_IFCHR)} = "c";
	$ftypes{(S_IFREG)} = "-"  if (defined S_IFREG);
	if ($bummer)   #FOR SOME REASON WINDOWS FCNTL DOES NOT HAVE THESE, BUT WE NEED -
	{              #THEM WHEN LOOKING AT SPECIAL FILES ON OTHER UNIX SYSTEMS:
		$ftypes{24576} = "b";
		$ftypes{4096} = "p";
		$ftypes{40960} = "l";
		$ftypes{49152} = "s";
	}
	else
	{
		$ftypes{(S_IFBLK)} = "b";
		$ftypes{(S_IFIFO)} = "p";
		$ftypes{(S_IFLNK)} = "l";
		$ftypes{(S_IFSOCK)} = "s";
	}
	my @fsperms = ('----', '---t', '--s-', '--st', '-s--', '-s-t', '-ss-', '-sst');	
	
	my $permissions = sprintf "%04o", S_IMODE($mode);
	my @permissions = split(//o, sprintf("%04o", S_IMODE($mode)));	
	my @spermissions = split(//o, $fsperms[$permissions[0]]);	
	my $pstr = $ftypes{S_IFMT($mode)};
	my $ps;
	for (my $i=1;$i<=3;$i++)
	{
		$ps = $permvec[$permissions[$i]];		#r-x
		if ($spermissions[$i] =~ /\w/o)
		{
			my $loc = substr($ps,2,2);
			if ($loc =~ /\w/o)
			{
				$loc = $spermissions[$i];
			}
			else
			{
				$loc = uc($spermissions[$i]);
			}				
			$ps =~ s/^(..).$/$1$loc/;			
		}
		$pstr .= $ps;
	}		
	return $pstr;
}	

1
