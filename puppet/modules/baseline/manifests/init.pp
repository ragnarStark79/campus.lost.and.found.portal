# @summary Baseline node configuration for Campus Lost and Found Portal nodes (Ubuntu 24.04 LTS).
#
# Configures essential system services, time synchronization (chrony),
# administrative utilities, and the system login message (MOTD).
#
class baseline (
  Array[String[1]] $packages = [
    'chrony',
    'wget',
    'jq',
    'htop',
    'net-tools',
  ],
) {
  # ── 1. Core Operating System Packages ───────────────────────────────────────
  package { $packages:
    ensure => installed,
  }

  # ── 2. Time Synchronization (Chrony) ────────────────────────────────────────
  # Time synchronization is mandatory to prevent SSL/TLS certificate timestamp skew
  # between the Puppet Master and Puppet Agent nodes.
  service { 'chrony':
    ensure  => running,
    enable  => true,
    require => Package['chrony'],
  }

  # ── 3. System Login Banner (/etc/motd) ──────────────────────────────────────
  $fqdn_candidate = $facts.dig('networking', 'fqdn')
  $host_candidate = $facts.dig('networking', 'hostname')
  $fqdn_fact = if $fqdn_candidate =~ String[1] {
    $fqdn_candidate
  } elsif $host_candidate =~ String[1] {
    $host_candidate
  } else {
    'puppet-node'
  }

  $ip_candidate = $facts.dig('networking', 'ip')
  $ip_fact = if $ip_candidate =~ String[1] {
    $ip_candidate
  } else {
    'Unknown'
  }

  $os_candidate = $facts.dig('os', 'distro', 'description')
  $os_fact = if $os_candidate =~ String[1] {
    $os_candidate
  } else {
    'Ubuntu 24.04 LTS'
  }

  file { '/etc/motd':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @("MOTD"/L)
      ================================================================================
        Campus Lost and Found Portal — DevOps Advanced Configuration Management
        Course: INT333 | Phase 4: Puppet 8 Master-Agent Architecture
      ================================================================================
        Node FQDN   : ${fqdn_fact}
        Private IP  : ${ip_fact}
        OS Platform : ${os_fact}
        Environment : ${environment}
        Managed By  : Puppet 8 (Master-Agent Architecture)
      ================================================================================
      | MOTD
  }
}
