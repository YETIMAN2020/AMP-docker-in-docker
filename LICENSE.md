<?xml version="1.0"?>
<Container version="2">
  <Name>AMP-Docker-in-Docker</Name>
  <!-- Change this to your own published image (e.g. from the Deploy Production workflow). -->
  <Repository>yetiman2020/amp-docker-in-docker:podman</Repository>
  <Registry>https://hub.docker.com/r/yetiman2020/amp-docker-in-docker</Registry>
  <!--
    Host networking is recommended for this image when running Dune: Awakening:
    the game uses a large/dynamic UDP port pool plus RabbitMQ, and host mode
    exposes them directly (and avoids the random-MAC license reset). Switch to
    "bridge" if you prefer, but then you must map every game port yourself.
  -->
  <Network>host</Network>
  <MyIP/>
  <Shell>bash</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/MitchTalmadge/AMP-dockerized/issues</Support>
  <Project>https://cubecoders.com/AMP</Project>
  <Overview>Community-made image for CubeCoders AMP (Podman variant), bundling Podman for "containerized" instances and an optional dune-admin web panel for a Dune: Awakening private server. UNOFFICIAL and unsupported by CubeCoders.</Overview>
  <Category>GameServers:</Category>
  <WebUI>http://[IP]:8181/</WebUI>
  <TemplateURL/>
  <Icon>https://raw.githubusercontent.com/CorneliousJD/Docker-Templates/master/icons/amp.png</Icon>
  <!--
    Permissions required so Podman can create user namespaces inside the container.
    Use these OR set Privileged to true above (then you can drop the cap-add/seccomp).
    /dev/fuse enables the fuse-overlayfs storage driver for rootless Podman.
  -->
  <ExtraParams>--cap-add=SYS_ADMIN --security-opt seccomp=unconfined --device /dev/fuse</ExtraParams>
  <PostArgs/>
  <CPUset/>
  <DateInstalled/>
  <DonateText/>
  <DonateLink/>
  <Description>Community-made image for CubeCoders AMP (Podman variant). Bundles Podman + the fixes needed to run AMP "containerized" instances, and an optional dune-admin web panel for a Dune: Awakening private server. This is an UNOFFICIAL image and is not endorsed or supported by CubeCoders.</Description>

  <!-- ============================ Storage ============================ -->
  <Config Name="AMP Data" Target="/home/amp" Default="/mnt/user/appdata/amp" Mode="rw,shared" Description="All AMP data (instances, saves, web UI login). Access Mode MUST be RW: Shared for Podman containerized instances." Type="Path" Display="always" Required="true" Mask="false">/mnt/user/appdata/amp</Config>

  <!-- ============================ Core AMP =========================== -->
  <Config Name="User ID (UID)" Target="UID" Default="99" Mode="" Description="Host user that owns the AMP data volume. Unraid default is 99." Type="Variable" Display="always" Required="true" Mask="false">99</Config>
  <Config Name="Group ID (GID)" Target="GID" Default="100" Mode="" Description="Host group for the user above. Unraid default is 100." Type="Variable" Display="always" Required="true" Mask="false">100</Config>
  <Config Name="Timezone (TZ)" Target="TZ" Default="Etc/UTC" Mode="" Description="Timezone, e.g. Europe/London. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones" Type="Variable" Display="always" Required="true" Mask="false">Etc/UTC</Config>
  <Config Name="Admin Username" Target="USERNAME" Default="admin" Mode="" Description="Username of the admin user created on first boot only." Type="Variable" Display="always" Required="false" Mask="false">admin</Config>
  <Config Name="Admin Password" Target="PASSWORD" Default="password" Mode="" Description="Password for the admin user (used only when first created). Change it after first sign-in." Type="Variable" Display="always" Required="false" Mask="true">password</Config>

  <!-- ==================== dune-admin (optional) ====================== -->
  <Config Name="dune-admin: Enable" Target="DUNE_ADMIN_ENABLED" Default="false" Mode="" Description="Set to true to run the dune-admin web panel for a Dune: Awakening server managed by AMP." Type="Variable" Display="always" Required="false" Mask="false">false</Config>
  <Config Name="dune-admin: Web Port" Target="DUNE_ADMIN_PORT" Default="18080" Mode="" Description="Port the dune-admin web panel listens on. Change it if 18080 is already used. (Host networking: binds directly on this port.)" Type="Variable" Display="always" Required="false" Mask="false">18080</Config>
  <Config Name="dune-admin: AMP Instance" Target="DUNE_ADMIN_INSTANCE" Default="Arrakis01" Mode="" Description="AMP instance name of your Dune server (see 'ampinstmgr -l'). The Podman container is assumed to be AMP_&lt;instance&gt;." Type="Variable" Display="always" Required="false" Mask="false">Arrakis01</Config>
  <Config Name="dune-admin: AMP API User" Target="DUNE_ADMIN_API_USER" Default="" Mode="" Description="An AMP panel login, used only for the Server Settings tab. Leave blank to skip." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="dune-admin: AMP API Password" Target="DUNE_ADMIN_API_PASS" Default="" Mode="" Description="Password for the AMP API user above." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="dune-admin: AMP API Port" Target="DUNE_ADMIN_API_PORT" Default="8086" Mode="" Description="The Dune instance's ADS/app port (from 'ampinstmgr -l'). Used for the Server Settings tab." Type="Variable" Display="advanced" Required="false" Mask="false">8086</Config>
  <Config Name="dune-admin: Login Username" Target="DUNE_ADMIN_AUTH_USER" Default="" Mode="" Description="Dashboard login username. Set this AND the password hash below to require a login (strongly recommended — dune-admin has full server control)." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="dune-admin: Login Password Hash" Target="DUNE_ADMIN_AUTH_PASSWORD_HASH" Default="" Mode="" Description="bcrypt hash of the dashboard password. Generate with: /opt/dune-admin/dune-admin --set-password" Type="Variable" Display="advanced" Required="false" Mask="true"/>
</Container>
