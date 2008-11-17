#!/usr/local/bin/perl

=head1 modify-web.pl

Change a virtual server's web configuration

This script can update the PHP and web forwarding settings for one or more virtual servers. Like other scripts, the servers to change are selecting using the C<--domain> or C<--all-domains> parameters.

To change the method Virtualmin uses to run CGI scripts, use the C<--mode>
parameter followed by one of C<--mod_php>, C<--cgi> or C<--fcgid>. To enable
or disable the use of Suexec for running CGI scripts, give either the
C<--suexec> or C<--no-suexec> parameter.

The C<--proxy> parameter can be used to have the website proxy all requests to another URL, which must follow C<--proxy>. To disable this, the C<--no-proxy> parameter must be given.

The C<--framefwd> parameter similarly can be used to forward requests to the virtual server to another URL, using a hidden frame rather than proxying. To turn it off, using the C<--no-framefwd> option. To specify a title for the forwarding frame page, use C<--frametitle>.

If your system has more than one version of PHP installed, the version to use
for a domain can be set with the C<--php-version> parameter, followed by a
number (4 or 5).

If Virtualmin runs PHP via fastCGI, you can set the number of PHP sub-processes
with the C<--php-children> parameter, or turn off the automatic startup of
sub-processes with C<--no-php-children>. Similarly, the maximum run-time of 
a PHP script can be set with C<--php-timeout>, or set to unlimited with
C<--no-php-timeout>.

If Ruby is installed, the execution mode for scripts in that language can be
set with the C<--ruby-mode> flag, followed by either C<--mod_ruby>, C<--cgi> or
C<--fcgid>. This has no effect on scripts using the Rails framework though,
as they always run via a Mongrel proxy.

You can also replace a website's pages using one of Virtualmin's content
styles, specified using the C<--style> parameter and a style name (which
C<list-styles.pl> can provide). If so the C<--content> parameter must also
be given, followed by the text to use in the style-generated web pages.

To enable the webmail and admin DNS entries for the selected domains
(which redirect to Usermin and Webmin by default), the C<--webmail> flag
can be used. This will make both the DNS and Apache configuration changes
needed. To turn them off, use the C<--no-webmail> flag.

To have Apache configured to accept requests for any sub-domain, use the
C<--matchall> command-line flag. This will also add a C<*> DNS entry if needed.
To turn this feature off, use the C<--no-matchall> flag.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-web.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-web.pl must be run as root";
	}
@OLDARGV = @ARGV;
$config{'web'} || &usage("Web serving is not enabled for Virtualmin");

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--mode") {
		$mode = shift(@ARGV);
		}
	elsif ($a eq "--ruby-mode") {
		$rubymode = shift(@ARGV);
		}
	elsif ($a eq "--php-children") {
		$children = shift(@ARGV);
		$children > 0 || &usage("Invalid number of PHP sub-processes");
		$children > $max_php_fcgid_children && &usage("Too many PHP sub-processes - maximum is $max_php_fcgid_children");
		}
	elsif ($a eq "--no-php-children") {
		$children = 0;
		}
	elsif ($a eq "--php-timeout") {
		$timeout = shift(@ARGV);
		$timeout =~ /^[1-9]\d*$/ ||
			&usage("Invalid PHP script timeout in seconds");
		}
	elsif ($a eq "--no-php-timeout") {
		$timeout = 0;
		}
	elsif ($a eq "--php-version") {
		$version = shift(@ARGV);
		}
	elsif ($a eq "--proxy") {
		$proxy = shift(@ARGV);
		$proxy =~ /^(http|https):\/\/\S+$/ ||
			&usage($text{'frame_eurl'});
		}
	elsif ($a eq "--no-proxy") {
		$proxy = "";
		}
	elsif ($a eq "--framefwd") {
		$framefwd = shift(@ARGV);
		$framefwd =~ /^(http|https):\/\/\S+$/ ||
			&usage($text{'frame_eurl'});
		}
	elsif ($a eq "--frametitle") {
		$frametitle = shift(@ARGV);
		}
	elsif ($a eq "--no-framefwd") {
		$framefwd = "";
		}
	elsif ($a eq "--suexec") {
		$suexec = 1;
		}
	elsif ($a eq "--no-suexec") {
		$suexec = 0;
		}
	elsif ($a eq "--style") {
		$stylename = shift(@ARGV);
		}
	elsif ($a eq "--content") {
		$content = shift(@ARGV);
		}
	elsif ($a eq "--webmail") {
		$webmail = 1;
		}
	elsif ($a eq "--no-webmail") {
		$webmail = 0;
		}
	elsif ($a eq "--matchall") {
		$matchall = 1;
		}
	elsif ($a eq "--no-matchall") {
		$matchall = 0;
		}
	else {
		&usage();
		}
	}
@dnames || $all_doms || usage();
$mode || $rubymode || defined($proxy) || defined($framefwd) ||
  defined($suexec) || $stylename || defined($children) || $version ||
  defined($webmail) || defined($matchall) || defined($timeout) ||
  &usage("Nothing to do");
$proxy && $framefwd && &error("Both proxying and frame forwarding cannot be enabled at once");

# Validate fastCGI options
@modes = &supported_php_modes($d);
if (defined($timeout)) {
	&indexof("fcgid", @modes) >= 0 ||
		&usage("The PHP script timeout can only be set on systems ".
		       "that support fcgid");
	}
if (defined($children)) {
	&indexof("fcgid", @modes) >= 0 ||
		&usage("The number of PHP children can only be set on systems ".
		       "that support fcgid");
	}

# Validate style
if ($stylename) {
	($style) = grep { $_->{'name'} eq $stylename } &list_content_styles();
	$style || &usage("Style $stylename does not exist");
	$content || &usage("--content followed by some initial text for the website must be specified when using --style");
	if ($content =~ /^\//) {
		$content = &read_file_contents($content);
		$content || &usage("--content file does not exist");
		}
	$content =~ s/\r//g;
	$content =~ s/\\n/\n/g;
	}

# Check if webmail is supported
if (defined($webmail) && !&has_webmail_rewrite()) {
	&usage("This system does not support mod_rewrite, needed for webmail redirects");
	}

# Get domains to update
if ($all_doms) {
	@doms = grep { $_->{'web'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'web'} || &usage("Virtual server $n does not have a web site enabled");
		push(@doms, $d);
		}
	}

# Make sure proxy and frame settings don't clash
foreach $d (@doms) {
	if ($framefwd && $d->{'proxy_pass_mode'} == 1) {
		&usage("Frame forwarding cannot be enabled for $d->{'dom'}, as it is currently using proxying");
		}
	if ($proxy && $d->{'proxy_pass_mode'} == 2) {
		&usage("Proxying cannot be enabled for $d->{'dom'}, as it is currently using frame forwarding");
		}
	}

# Make sure suexec and PHP / Ruby settings don't clash
foreach $d (@doms) {
	$p = $mode || &get_domain_php_mode($d);
	$r = $rubymode || &get_domain_ruby_mode($d);
	$s = defined($suexec) ? $suexec : &get_domain_suexec($d);
	if ($p eq "cgi" && !$s) {
		&usage("For PHP to be run as the domain owner in $d->{'dom'}, suexec must also be enabled");
		}
	if ($r eq "cgi" && !$s) {
		&usage("For Ruby to be run as the domain owner in $d->{'dom'}, suexec must also be enabled");
		}
	@supp = &supported_php_modes($d);
	!$mode || &indexof($mode, @supp) >= 0 ||
		&usage("The selected PHP exection mode cannot be used with $d->{'dom'}");
	if ($version) {
		$mode eq "mod_php" &&
			&usage("The PHP version cannot be set for $d->{'dom'}, as it is using mod_php");
		@avail = map { $_->[0] } &list_available_php_versions($d);
		&indexof($version, @avail) >= 0 ||
			&usage("Only the following PHP version are available for $d->{'dom'} : ".join(" ", @avail));
		}
	@rubysupp = &supported_ruby_modes($d);
	!$rubymode || $rubymode eq "none" ||
	    &indexof($rubymode, @rubysupp) >= 0 ||
		&usage("The selected Ruby exection mode cannot be used with $d->{'dom'}");
	}

# Lock them all
foreach $d (@doms) {
	&obtain_lock_web($d);
	&obtain_lock_dns($d) if (defined($webmail) || defined($matchall));
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();

	# Update PHP mode
	if ($mode && !$d->{'alias'}) {
		&save_domain_php_mode($d, $mode);
		}

	# Update PHP fCGId children
	if (defined($children) && !$d->{'alias'}) {
		&save_domain_php_children($d, $children);
		}

	# Update PHP maximum time
	if (defined($timeout) && !$d->{'alias'}) {
		$oldtimeout = &get_fcgid_max_execution_time($d);
		if ($timeout != $oldtimeout) {
			&set_fcgid_max_execution_time($d, $timeout);
			&set_php_max_execution_time($d, $timeout);
			}
		}

	# Update PHP version
	if ($version && !$d->{'alias'}) {
		&save_domain_php_directory($d,  &public_html_dir($d), $version);
		}

	# Update Ruby mode
	if ($rubymode && !$d->{'alias'}) {
		&save_domain_ruby_mode($d,
			$rubymode eq "none" ? undef : $rubymode);
		}

	# Update suexec setting
	if (defined($suexec) && !$d->{'alias'}) {
		&save_domain_suexec($d, $suexec);
		}

	local $oldd = { %$d };
	if (defined($proxy)) {
		# Update proxy mode
		if ($proxy) {
			$d->{'proxy_pass'} = $proxy;
			$d->{'proxy_pass_mode'} = 1;
			}
		else {
			$d->{'proxy_pass'} = undef;
			$d->{'proxy_pass_mode'} = 0;
			}
		}

	if (defined($framefwd)) {
		# Update frame forwarding mode
		if ($framefwd) {
			$d->{'proxy_pass'} = $framefwd;
			$d->{'proxy_pass_mode'} = 2;
			}
		else {
			$d->{'proxy_pass'} = undef;
			$d->{'proxy_pass_mode'} = 0;
			}
		}
	if (defined($frametitle)) {
		$d->{'proxy_title'} = $frametitle;
		}
	if (defined($frametitle) || $framefwd) {
		&$first_print($text{'frame_gen'});
		&create_framefwd_file($d);
		&$second_print($text{'setup_done'});
		}

	if ($style && !$d->{'alias'}) {
		# Apply content style
		&$first_print(&text('setup_styleing', $style->{'desc'}));
		&apply_content_style($d, $style, $content);
		&$second_print($text{'setup_done'});
		}

	if (defined($webmail) && $d->{'web'} && !$d->{'alias'}) {
		# Enable or disable webmail redirects
		local @oldwm = &get_webmail_redirect_directives($d);
		if ($webmail && !@oldwm) {
			&$first_print("Adding webmail and admin redirects ..");
			&add_webmail_redirect_directives($d);
			if ($d->{'dns'}) {
				&add_webmail_dns_records($d);
				}
			&$second_print(".. done");
			}
		elsif (!$webmail && @oldwm) {
			&$first_print(
				"Removing webmail and admin redirects ..");
			&remove_webmail_redirect_directives($d);
			if ($d->{'dns'}) {
				&remove_webmail_dns_records($d);
				}
			&$second_print(".. done");
			}
		}

	if (defined($matchall) && $d->{'web'}) {
		# Enable or disable *.domain.com serveralias
		local $oldmatchall = &get_domain_web_star($d);
		if ($matchall && !$oldmatchall) {
			&$first_print(
			    "Adding all sub-domains to Apache config ..");
			&save_domain_web_star($d, 1);
			if ($d->{'dns'}) {
				&save_domain_matchall_record($d, 1);
				}
			&$second_print(".. done");
			}
		elsif (!$matchall && $oldmatchall) {
			&$first_print(
			    "Removing all sub-domains from Apache config ..");
			&save_domain_web_star($d, 0);
			if ($d->{'dns'}) {
				&save_domain_matchall_record($d, 0);
				}
			&$second_print(".. done");
			}
		}

	if (defined($proxy) || defined($framefwd)) {
		# Save the domain
		&modify_web($d, $oldd);
		if ($d->{'ssl'}) {
			&modify_ssl($d, $oldd);
			}

		&$first_print($text{'save_domain'});
		&save_domain($d);
		&$second_print($text{'setup_done'});
		}

	&$outdent_print();
	&$second_print(".. done");
	}

foreach $d (@doms) {
	&release_lock_dns($d) if (defined($webmail) || defined($matchall));
	&release_lock_web($d);
	}
&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes web server settings for one or more domains.\n";
print "\n";
print "usage: modify-web.pl [--domain name] | [--all-domains]\n";
print "                     [--mode mod_php | cgi | fcgid]\n";
print "                     [--php-children number | --no-php-children]\n";
print "                     [--php-version num]\n";
print "                     [--php-timeout seconds | --no-php-timeout]\n";
print "                     [--ruby-mode none | mod_ruby | cgi | fcgid]\n";
print "                     [--suexec | --no-suexec]\n";
print "                     [--proxy http://... | --no-proxy]\n";
print "                     [--framefwd http://... | --no-framefwd]\n";
print "                     [--framefwd \"title\" ]\n";
print "                     [--style name]\n";
print "                     [--content text|filename]\n";
if (&has_webmail_rewrite()) {
	print "                     [--webmail | --no-webmail]\n";
	}
print "                     [--matchall | --no-matchall]\n";
exit(1);
}

