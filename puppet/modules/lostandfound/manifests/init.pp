# @summary Configures Docker Engine and runs the Campus Lost and Found container from GHCR.
#
# @param image Container image reference published by Phase 2 CI/CD.
# @param container_name Docker container and systemd service name.
# @param host_port Host TCP port mapped on EC2 (matches Terraform security group).
# @param container_port Internal Flask TCP port inside the container (Dockerfile EXPOSE 5000).
# @param app_dir Deployment root directory on the host.
# @param data_dir Persistent EBS-backed host directory mounted to /app/data.
# @param flask_env Flask environment setting inside the container.
# @param secret_key Flask SECRET_KEY supplied via Facter/Hiera (never hardcoded).
# @param image_is_private Set true when pulling a private GHCR package.
# @param ghcr_username GitHub username for private GHCR login.
# @param ghcr_token GitHub PAT (read:packages) supplied via Facter/Hiera when private.
class lostandfound (
  String[1]            $image            = 'ghcr.io/ragnarstark79/campus.lost.and.found.portal:sha-0bf459f',
  String[1]            $container_name   = 'lostandfound_web',
  Integer[1, 65535]    $host_port        = 5001,
  Integer[1, 65535]    $container_port   = 5000,
  String[1]            $app_dir          = '/opt/lostandfound',
  String[1]            $data_dir         = '/opt/lostandfound/data',
  String[1]            $flask_env        = 'production',
  Optional[String[1]]  $secret_key       = $facts['lostandfound_secret_key'],
  Boolean              $image_is_private          = false,
  Optional[String[1]]  $ghcr_username             = $facts['ghcr_username'],
  Optional[String[1]]  $ghcr_token                = $facts['ghcr_token'],
  String[1]            $deployment_status         = 'Successful',
  String[1]            $deployment_message        = 'Successfully deployed through CI/CD pipeline. Puppet Agent pulled and applied the latest configuration from Puppet Master.',
  String[1]            $deployment_timestamp_utc  = '2026-11-18T14:15:00Z',
  String[1]            $deployment_commit         = '0bf459f',
  String[1]            $deployment_commit_message = 'feat(infra): complete Phase 1-5 AWS, Puppet 8, and CI/CD deployment pipeline',
  String[1]            $deployment_image_tag      = 'sha-0bf459f',
  String[1]            $deployment_workflow_run   = 'production',
  Optional[String[1]]  $deployment_json           = undef,
) {
  if $secret_key == undef or $secret_key == '' {
    fail('lostandfound: secret_key must be set via FACTER_lostandfound_secret_key, Hiera, or class parameter.')
  }

  if $image_is_private and (
    $ghcr_username == undef or $ghcr_username == '' or
    $ghcr_token == undef or $ghcr_token == ''
  ) {
    fail('lostandfound: ghcr_username and ghcr_token are required when image_is_private is true.')
  }

  # ── 1. Docker Engine APT Repository & Installation (Ubuntu 24.04 Noble) ────
  package { ['ca-certificates', 'curl', 'gnupg']:
    ensure => installed,
  }

  file { '/etc/apt/keyrings':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  exec { 'download_docker_gpg_key':
    command => '/usr/bin/curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && /bin/chmod a+r /etc/apt/keyrings/docker.asc',
    creates => '/etc/apt/keyrings/docker.asc',
    require => [
      Package['ca-certificates'],
      Package['curl'],
      Package['gnupg'],
      File['/etc/apt/keyrings'],
    ],
  }

  $distro_codename = $facts.get('os.distro.codename', 'noble')
  $arch = $facts.get('os.architecture', 'amd64')

  file { '/etc/apt/sources.list.d/docker.list':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('lostandfound/docker.list.epp', {
      'arch'            => $arch,
      'distro_codename' => $distro_codename,
    }),
    require => Exec['download_docker_gpg_key'],
    notify  => Exec['apt_update_docker'],
  }

  exec { 'apt_update_docker':
    command     => '/usr/bin/apt-get update -y',
    refreshonly => true,
  }

  $docker_packages = [
    'docker-ce',
    'docker-ce-cli',
    'containerd.io',
    'docker-buildx-plugin',
    'docker-compose-plugin',
  ]

  package { $docker_packages:
    ensure  => installed,
    require => Exec['apt_update_docker'],
  }

  service { 'docker':
    ensure  => running,
    enable  => true,
    require => Package[$docker_packages],
  }

  # ── 2. Application & Persistent Data Directories ───────────────────────────
  file { $app_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $data_dir:
    ensure  => directory,
    mode    => '0755',
    require => File[$app_dir],
  }

  # ── 3. Secure Environment File (0600, diff suppressed) ─────────────────────
  file { "${app_dir}/.env":
    ensure    => file,
    owner     => 'root',
    group     => 'root',
    mode      => '0600',
    show_diff => false,
    content   => epp('lostandfound/lostandfound.env.epp', {
      'flask_env'  => $flask_env,
      'secret_key' => $secret_key,
    }),
    require   => File[$app_dir],
    notify    => Service['lostandfound'],
  }

  # ── 3b. Staged Deployment Metadata (Pending Post-Deploy Health Verification) ─
  $deployment_content = $deployment_json ? {
    undef   => epp('lostandfound/deployment.json.epp', {
      'commit'         => $deployment_commit,
      'commit_message' => $deployment_commit_message,
      'image_tag'      => $deployment_image_tag,
      'message'        => $deployment_message,
      'status'         => $deployment_status,
      'timestamp_utc'  => $deployment_timestamp_utc,
      'workflow_run'   => $deployment_workflow_run,
    }),
    default => "${deployment_json}\n",
  }

  file { "${data_dir}/deployment_pending.json":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $deployment_content,
    require => File[$data_dir],
  }

  # Initialize active deployment.json if missing; never overwrite during catalog run
  file { "${data_dir}/deployment.json":
    ensure  => file,
    replace => false,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $deployment_content,
    require => File[$data_dir],
  }

  # ── 4. Optional GHCR Authentication (Private Images Only) ──────────────────
  if $image_is_private {
    exec { 'ghcr_docker_login':
      command     => '/bin/sh -c \'printf "%s" "$GHCR_TOKEN" | /usr/bin/docker login ghcr.io -u "$GHCR_USER" --password-stdin\'',
      environment => [
        "GHCR_USER=${ghcr_username}",
        "GHCR_TOKEN=${ghcr_token}",
      ],
      unless      => '/bin/grep -q "\"ghcr.io\"" /root/.docker/config.json 2>/dev/null',
      require     => Service['docker'],
    }
    $pull_requires = [Service['docker'], Exec['ghcr_docker_login']]
  } else {
    $pull_requires = [Service['docker']]
  }

  # ── 5. Pull Container Image & Align Data Directory UID/GID ─────────────────
  exec { 'pull_lostandfound_image':
    command => "/usr/bin/docker pull ${image}",
    unless  => "/bin/sh -c '/usr/bin/docker image inspect \"${image}\" >/dev/null 2>&1'",
    path    => ['/usr/bin', '/bin'],
    require => $pull_requires,
    notify  => Service['lostandfound'],
  }

  # Dockerfile runs as non-root `appuser`. Query its UID/GID dynamically from
  # the image so bind-mounted /opt/lostandfound/data is writable on Linux.
  file { '/usr/local/bin/lostandfound-sync-owner':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/lostandfound/sync-data-owner.sh',
  }

  exec { 'align_data_dir_ownership':
    command => "/usr/local/bin/lostandfound-sync-owner '${image}' '${data_dir}'",
    unless  => "/bin/sh -c '/usr/local/bin/lostandfound-sync-owner --check \"${image}\" \"${data_dir}\"'",
    path    => ['/usr/local/bin', '/usr/bin', '/bin'],
    require => [
      Exec['pull_lostandfound_image'],
      File[$data_dir],
      File['/usr/local/bin/lostandfound-sync-owner'],
    ],
  }

  # ── 6. Managed Systemd Container Service & Health Check ────────────────────
  file { '/etc/systemd/system/lostandfound.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('lostandfound/lostandfound.service.epp', {
      'app_dir'        => $app_dir,
      'container_name' => $container_name,
      'container_port' => $container_port,
      'data_dir'       => $data_dir,
      'host_port'      => $host_port,
      'image'          => $image,
    }),
    notify  => Exec['systemd_daemon_reload'],
  }

  exec { 'systemd_daemon_reload':
    command     => '/usr/bin/systemctl daemon-reload',
    refreshonly => true,
    notify      => Service['lostandfound'],
  }

  service { 'lostandfound':
    ensure  => running,
    enable  => true,
    require => [
      Service['docker'],
      Exec['pull_lostandfound_image'],
      Exec['align_data_dir_ownership'],
      File["${app_dir}/.env"],
      Exec['systemd_daemon_reload'],
    ],
  }

  exec { 'verify_lostandfound_health':
    command     => "/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do /usr/bin/curl -sf http://127.0.0.1:${host_port}/health && exit 0; sleep 2; done; exit 1'",
    refreshonly => true,
    subscribe   => Service['lostandfound'],
  }
}
