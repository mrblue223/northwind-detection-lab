#cloud-config
package_update: true
packages:
  - docker.io

runcmd:
  - systemctl enable --now docker
  - >
    docker run -d --restart=unless-stopped --name twingate-connector
    --sysctl net.ipv4.ping_group_range="0 2147483647"
    -e TWINGATE_NETWORK="${network_name}"
    -e TWINGATE_ACCESS_TOKEN="${access_token}"
    -e TWINGATE_REFRESH_TOKEN="${refresh_token}"
    -e TWINGATE_LABEL_HOSTNAME=$(hostname)
    twingate/connector:1
