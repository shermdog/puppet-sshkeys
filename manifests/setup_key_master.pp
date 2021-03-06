# Create/regenerate/remove a key pair on the keymaster.
# This definition is private, i.e. it is not intended to be called
# directly by users. sshkeys::create_key calls it to create virtual
# keys, which are realized in sshkeys::keymaster.
define sshkeys::setup_key_master (
  $ensure,
  $force,
  $keytype,
  $length,
  $maxdays,
  $mindate,
  $email
) {

  Exec { path => "/usr/bin:/usr/sbin:/bin:/sbin" }
  File {
    owner => puppet,
    group => puppet,
    mode  => 600,
  }

  $keydir = "${sshkeys::keymaster_storage}/${title}"
  
  $keyfile = "${keydir}/${title}"

  file {
    "$keydir":
      ensure => directory,
      mode   => 644;
    "$keyfile":
      ensure => $ensure;
    "${keyfile}.pub":
      ensure => $ensure,
      mode   => 644;
  }

  if $ensure == "present" {

    # Remove the existing key pair, if
    # * $force is true, or
    # * $maxdays or $mindate criteria aren't met, or
    # * $keytype or $length have changed

    $keycontent = file("${keyfile}.pub", "/dev/null")
    if $keycontent {

      if $force {
        $reason = "force=true"
      }
      if !$reason and $mindate and
         generate("/usr/bin/find", $keyfile, "!", "-newermt", "${mindate}") {
        $reason = "created before ${mindate}"
      }
      if !$reason and $maxdays and
         generate("/usr/bin/find", $keyfile, "-mtime", "+${maxdays}") {
        $reason = "older than ${maxdays} days"
      }
      if !$reason and $keycontent =~ /^ssh-... [^ ]+ (...) (\d+)$/ {
        if $keytype != $1 {
	  $reason = "keytype changed: $1 -> $keytype"
	} else {
	  if $length != $2 {
	    $reason = "length changed: $2 -> $length"
	  }
	}
      }
      if $reason {
        exec { "Revoke previous key ${title}: ${reason}":
          command => "rm $keyfile ${keyfile}.pub",
          before  => Exec["Create key $title: $keytype, $length bits"],
        }
      }
    }

    # Create the key pair.
    # We "repurpose" the comment field in public keys on the keymaster to
    # store data about the key, i.e. $keytype and $length.  This avoids
    # having to rerun ssh-keygen -l on every key at every run to determine
    # the key length.
    exec { "Create key $title: $keytype, $length bits":
      command => "ssh-keygen -t ${keytype} -b ${length} -f ${keyfile} -C \"${keytype} ${length}\" -N \"\"",
      user    => "puppet",
      group   => "puppet",
      creates => $keyfile,
      require => File[$keydir],
      before  => File[$keyfile, "${keyfile}.pub"],
    }
    
    if $email {
	    # Command to email key to user
	    # Idea courtesy of http://www.warden.pl/2012/09/05/puppet-send-an-email-to-the-client-when-a-new-key-is-generated/
	    exec { "Notify user ${email}":
	      command => "/usr/bin/python /common/puppet/emailKey.py ${keyfile} ${email}",	      
	      timeout => 30,
	      tries => 3,
	      try_sleep => 10,
	      require => File[$keyfile],
	      subscribe => Exec["Create key $title: $keytype, $length bits"],
	      refreshonly => true
	    }      
    }
  }
}

# I am Vinz, Vinz Clortho, Keymaster of Gozer...Volguus Zildrohoar, Lord of the Seboullia. Are you the Gatekeeper?
