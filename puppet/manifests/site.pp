# ==============================================================================
# Puppet 8 Master Manifest — Campus Lost and Found Portal
# Course: INT333 — DevOps Advanced Configuration Management
# Environment: production
# Supported OS: Ubuntu Server 24.04 LTS (Noble)
# ==============================================================================

# Common baseline configuration applied to every node in the infrastructure
node default {
  include baseline
}

# ── Puppet Master Node ───────────────────────────────────────────────────────
node 'puppet-master', /^puppet-master/ {
  include baseline

  file { '/var/log/puppet-master-baseline.marker':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "Puppet Master node active and managing production environment.\nNode: ${facts['networking']['fqdn']}\n",
    require => Class['baseline'],
  }
}

# ── Puppet Agent & Application Host Node ────────────────────────────────────
node 'puppet-agent', /^puppet-agent/ {
  include baseline

  # Durable Application Configuration via Hiera (Master-side persistence):
  # Hiera common.yaml on the Master stores the durable desired image and configuration.
  # If secret_key is supplied via Hiera or facts, instantiate the lostandfound module.
  # When absent (Phase 4), manage storage directories directly and emit verification notice.
  $fallback_secret = if $facts['lostandfound_secret_key'] != undef and $facts['lostandfound_secret_key'] != '' {
    $facts['lostandfound_secret_key']
  } else {
    undef
  }
  $app_secret = lookup('lostandfound::secret_key', {
    'default_value' => $fallback_secret,
  })

  if $app_secret != undef and $app_secret != '' {
    $fallback_image = if $facts['lostandfound_image'] != undef and $facts['lostandfound_image'] != '' {
      $facts['lostandfound_image']
    } else {
      'ghcr.io/ragnarstark79/campus.lost.and.found.portal:sha-0bf459f'
    }
    $app_image = lookup('lostandfound::image', {
      'default_value' => $fallback_image,
    })

    $fallback_private = $facts['lostandfound_image_private'] ? {
      'true'  => true,
      true    => true,
      default => false,
    }
    $is_private = lookup('lostandfound::image_is_private', {
      'default_value' => $fallback_private,
    })

    $host_port = lookup('lostandfound::host_port', {
      'default_value' => 5001,
    })
    $container_port = lookup('lostandfound::container_port', {
      'default_value' => 5000,
    })
    $app_dir = lookup('lostandfound::app_dir', {
      'default_value' => '/opt/lostandfound',
    })
    $data_dir = lookup('lostandfound::data_dir', {
      'default_value' => '/opt/lostandfound/data',
    })
    $flask_env = lookup('lostandfound::flask_env', {
      'default_value' => 'production',
    })

    class { 'lostandfound':
      image            => $app_image,
      image_is_private => $is_private,
      host_port        => $host_port,
      container_port   => $container_port,
      app_dir          => $app_dir,
      data_dir         => $data_dir,
      flask_env        => $flask_env,
      secret_key       => $app_secret,
    }
  } else {
    # Phase 4 baseline: manage storage directories when Phase 5 module is not yet active
    file { '/opt/lostandfound':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    file { '/opt/lostandfound/data':
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => File['/opt/lostandfound'],
    }

    notify { 'phase4_agent_status':
      message => 'Phase 4: Puppet Agent baseline configuration applied successfully. Application container deployment deferred to Phase 5.',
    }
  }
}
