
# script_phppgadmin_desc()
sub script_phppgadmin_desc
{
return "phpPgAdmin";
}

sub script_phppgadmin_uses
{
return ( "php" );
}

# script_phppgadmin_longdesc()
sub script_phppgadmin_longdesc
{
return "A browser-based PostgreSQL database management interface.";
}

# script_phppgadmin_versions()
sub script_phppgadmin_versions
{
return ( "4.1" );
}

sub script_phppgadmin_category
{
return "Database";
}

sub script_phppgadmin_php_vers
{
return ( 4, 5 );
}

sub script_phppgadmin_php_modules
{
return ("pgsql");
}

# script_phppgadmin_depends(&domain, version)
sub script_phppgadmin_depends
{
local ($d, $ver) = @_;
local @dbs = &domain_databases($d, [ "postgres" ]);
return "phpPgAdmin requires a PostgreSQL database" if (!@dbs);
return undef;
}

# script_phppgadmin_params(&domain, version, &upgrade-info)
# Returns HTML for table rows for options for installing PHP-NUKE
sub script_phppgadmin_params
{
local ($d, $ver, $upgrade) = @_;
local $rv;
local $hdir = &public_html_dir($d, 1);
if ($upgrade) {
	# Options are fixed when upgrading
	$rv .= &ui_table_row("Default database", $upgrade->{'opts'}->{'db'});
	local $dir = $upgrade->{'opts'}->{'dir'};
	$dir =~ s/^$d->{'home'}\///;
	$rv .= &ui_table_row("Install directory", $dir);
	}
else {
	# Show editable install options
	local @dbs = &domain_databases($d, [ "postgres" ]);
	$rv .= &ui_table_row("Default database to manage",
		     &ui_select("db", undef,
			[ [ "template1", "&lt;PostgreSQL default&gt;" ],
			  map { [ $_->{'name'} ] } @dbs ]));
	$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
			     &ui_opt_textbox("dir", "phppgadmin", 30,
					     "At top level"));
	}
return $rv;
}

# script_phppgadmin_parse(&domain, version, &in, &upgrade-info)
# Returns either a hash ref of parsed options, or an error string
sub script_phppgadmin_parse
{
local ($d, $ver, $in, $upgrade) = @_;
if ($upgrade) {
	# Options are always the same
	return $upgrade->{'opts'};
	}
else {
	local $hdir = &public_html_dir($d, 0);
	$in{'dir_def'} || $in{'dir'} =~ /\S/ && $in{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
	local $dir = $in{'dir_def'} ? $hdir : "$hdir/$in{'dir'}";
	return { 'db' => $in{'db'},
		 'dir' => $dir,
		 'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}", };
	}
}

# script_phppgadmin_check(&domain, version, &opts, &upgrade-info)
# Returns an error message if a required option is missing or invalid
sub script_phppgadmin_check
{
local ($d, $ver, $opts, $upgrade) = @_;
$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
$opts->{'db'} || return "Missing database";
if (-r "$opts->{'dir'}/conf/config.inc.php") {
	return "phpPgAdmin appears to be already installed in the selected directory";
	}
return undef;
}

# script_phppgadmin_files(&domain, version, &opts, &upgrade-info)
# Returns a list of files needed by PHP-Nuke, each of which is a hash ref
# containing a name, filename and URL
sub script_phppgadmin_files
{
local ($d, $ver, $opts, $upgrade) = @_;
if ($ver <= 2.2) {
	$ver = $ver."-php";
	}
local @files = ( { 'name' => "source",
	   'file' => "phpPgAdmin-$ver.zip",
	   'url' => "http://osdn.dl.sourceforge.net/sourceforge/phppgadmin/phpPgAdmin-$ver.zip" } );
return @files;
}

# script_phppgadmin_install(&domain, version, &opts, &files, &upgrade-info)
# Actually installs phpPgAdmin, and returns either 1 and an informational
# message, or 0 and an error
sub script_phppgadmin_install
{
local ($d, $version, $opts, $files, $upgrade) = @_;
local ($out, $ex);
&has_command("unzip") ||
	return (0, "The unzip command is needed to extract the phpPgAdmin source");
local @dbs = split(/\s+/, $opts->{'db'});
local $dbuser = &postgres_user($d);
local $dbpass = &postgres_pass($d);
local $dbhost = &get_database_host("postgres");

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
		return (0, "Failed to create directory : <tt>$out</tt>.");
	}

# Extract zip file to temp dir
local $temp = &transname();
mkdir($temp, 0755);
chown($d->{'uid'}, $d->{'gid'}, $temp);
$out = &run_as_domain_user($d, "cd ".quotemeta($temp).
			       " && unzip $files->{'source'}");
-r "$temp/phpPgAdmin-$ver/conf/config.inc.php-dist" ||
	return (0, "Failed to extract source : <tt>$out</tt>.");

# Move source dir to target
$out = &run_as_domain_user($d, "cp -rp ".quotemeta($temp)."/phpPgAdmin-$ver/* ".
			       quotemeta($opts->{'dir'}));
local $cfileorig = "$opts->{'dir'}/conf/config.inc.php-dist";
local $cfile = "$opts->{'dir'}/conf/config.inc.php";
-r $cfileorig || return (0, "Failed to copy source : <tt>$out</tt>.");

if (!-r $cfile) {
	# Copy and update the config file
	&run_as_domain_user($d, "cp ".quotemeta($cfileorig)." ".
				      quotemeta($cfile));
	local $lref = &read_file_lines($cfile);
	local $l;
	foreach $l (@$lref) {
		if ($l =~ /^\s*\$conf\['servers'\]\[0\]\['defaultdb'\]/) {
			$l = "\$conf['servers'][0]['defaultdb'] = '$opts->{'db'}';";
			}
		if ($l =~ /^\s*\$conf\['servers'\]\[0\]\['host'\]/ &&
		    $dbhost ne 'localhost') {
			$l = "\$conf['servers'][0]['host'] = '$dbhost';";
			}
		}
	&flush_file_lines($cfile);
	}

# Return a URL for the user
local $url = &script_path_url($d, $opts);
local $rp = $opts->{'dir'};
$rp =~ s/^$d->{'home'}\///;
return (1, "phpPgAdmin installation complete. It can be accessed at <a href='$url'>$url</a>.", "Under $rp", $url);
}

# script_phppgadmin_uninstall(&domain, version, &opts)
# Un-installs a phpPgAdmin installation, by deleting the directory.
# Returns 1 on success and a message, or 0 on failure and an error
sub script_phppgadmin_uninstall
{
local ($d, $version, $opts) = @_;

# Remove the contents of the target directory
local $derr = &delete_script_install_directory($d, $opts);
return (0, $derr) if ($derr);

return (1, "phpPgAdmin directory deleted.");
}

# script_phppgadmin_latest(version)
# Returns a URL and regular expression or callback func to get the version
sub script_phppgadmin_latest
{
local ($ver) = @_;
return ( "http://phppgadmin.sourceforge.net/",
	 "latest\\s+version:\\s+<.*>([0-9\\.]+)" );
}

1;

