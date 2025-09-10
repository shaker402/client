#!/bin/bash
set -eo pipefail

main() {

source libs/main.sh
rsync -a ../resources/default.env ../workdir/.env
#define_env ../workdir/.env
define_paths

set -a
source ../workdir/.env
set +a

source libs/host-dirs.sh
source post-steps.sh

source libs/prerquiests-check.sh

# Function to deploy the services
make_common_dirs

# ------------------ ELK/Fleet server config and agent integration workflow ------------------

print_with_border "Updating Kibana Configuration"
KIBANA_CONFIG="${workdir}/elk/kibana/config/kibana.yml"

# First, remove any duplicate SSL configurations that might exist
sed -i '/ssl:/{N;N;d;}' "$KIBANA_CONFIG"

# 1. Update the Fleet Server host URL from http://fleet-server:8220 to use your MYIP with HTTPS
sed -i "s|http://fleet-server:8220|https://${MYIP}:8220|g" "$KIBANA_CONFIG"

# 2. Update the Elasticsearch hosts line from [ http://elasticsearch:9200 ] to [ https://${MYIP}/elasticsearch ]
sed -i "s|hosts: \[ http://elasticsearch:9200 \]|hosts: [ https://${MYIP}/elasticsearch ]|g" "$KIBANA_CONFIG"

# 3. Add the SSL configuration (ssl.verification_mode: none) under the xpack.fleet.outputs block.
#    This command adds the SSL lines immediately after the line containing 'is_default_monitoring: true'
#    Only add if it doesn't already exist
if ! grep -q "verification_mode: none" "$KIBANA_CONFIG"; then
    sed -i '/is_default_monitoring: true/ a\
    ssl:\
      verification_mode: none' "$KIBANA_CONFIG"
fi

# Wait for Elasticsearch to be ready first
print_with_border "Waiting for Elasticsearch to be ready..."
wait_for_elasticsearch() {
    local timeout=600
    local start_time=$(date +%s)
    
    while :; do
        if [ $(( $(date +%s) - start_time )) -ge $timeout ]; then
            print_yellow "Elasticsearch readiness check timed out after 10 minutes"
            return 1
        fi
        
        # Check if Elasticsearch is responding
        if curl -s -k "https://${MYIP}/elasticsearch" -u "elastic:${ELASTIC_PASSWORD}" | grep -q "number"; then
            print_green "Elasticsearch is ready!"
            break
        fi
        print_yellow "Elasticsearch not ready yet. Retrying in 15 seconds..."
        sleep 15
    done
}

wait_for_elasticsearch

# Restart Kibana for the changes to take effect
print_with_border "Restarting Kibana"
(cd "${workdir}/elk" && docker compose restart kibana)

# Helper functions
print_with_border() {
    local msg="$1"
    local len=$((${#msg}+4))
    printf "\n%${len}s\n" | tr ' ' '#'
    echo "# $msg #"
    printf "%${len}s\n\n" | tr ' ' '#'
}

print_yellow() {
    echo -e "\033[1;33m$1\033[0m"
}

print_green() {
    echo -e "\033[1;32m$1\033[0m"
}

# Wait for ELK to be ready
print_with_border "Waiting for ELK to be ready..."
sleep 60

# Check Kibana readiness with timeout
print_with_border "Checking Kibana readiness..."
timeout=600
start_time=$(date +%s)

while :; do
    now=$(date +%s)
    if [ $((now - start_time)) -ge $timeout ]; then
        print_yellow "Kibana readiness check timed out after 10 minutes"
        return 1
    fi

    response=$(curl -s -k "${PROTO}://${MYIP}/kibana/api/status" -u "elastic:${ELASTIC_PASSWORD}") || true
    if echo "$response" | grep -q '"overall":{"level":"available"'; then
        print_green "Kibana is ready!"
        break
    fi
    print_yellow "Kibana not ready yet. Retrying in 15 seconds..."
    sleep 15
done

# Create agent policies with retries
create_agent_policy() {
  local policy_name="$1"
  local retries=3
  local count=0

  while [ $count -lt $retries ]; do
    response=$(curl -s -k -X POST "${PROTO}://${MYIP}/kibana/api/fleet/agent_policies?sys_monitoring=true" \
      -u "elastic:${ELASTIC_PASSWORD}" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -d '{"name":"'"$policy_name"'", "namespace":"default", "description":"'"$policy_name"' agents"}')

    policy_id=$(echo "$response" | jq -r '.item.id')
    if [ -n "$policy_id" ] && [ "$policy_id" != "null" ]; then
      echo "$policy_id"
      return 0
    fi

    print_yellow "Retrying policy creation for $policy_name..."
    sleep 10
    ((count++))
  done

  print_yellow "Failed to create $policy_name after $retries attempts"
  return 1
}

print_with_border "Creating agent policies..."
linux_policy_id=$(create_agent_policy "linux-policy")
windows_policy_id=$(create_agent_policy "windows-policy")
mac_policy_id=$(create_agent_policy "mac-policy")

# Enhanced integration handler
add_integration() {
  local policy_id="$1"
  local policy_type="$2"
  local integration="$3"
  local integration_name="${policy_type}-${integration}-integration"

  pkg_info=$(curl -s -k "${PROTO}://${MYIP}/kibana/api/fleet/epm/packages/${integration}" \
    -u "elastic:${ELASTIC_PASSWORD}")

  if echo "$pkg_info" | grep -q 'NotFoundError'; then
    print_yellow "WARNING: Package $integration not found. Skipping..."
    return 1
  fi

  response=$(curl -s -k -X POST "${PROTO}://${MYIP}/kibana/api/fleet/package_policies" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -d '{
      "policy_id": "'"$policy_id"'",
      "package": {
        "name": "'"$integration"'",
        "version": "'"$(echo "$pkg_info" | jq -r '.item.version')"'"
      },
      "name": "'"${integration_name}"'",
      "namespace": "default"
    }')

  if echo "$response" | grep -q '"statusCode":'; then
    print_yellow "Failed to add $integration: $(echo "$response" | jq -r '.message')"
    return 1
  fi

  print_green "Successfully added $integration"
  sleep 1
}

# Platform integrations
print_with_border "Adding integrations..."

# Linux integrations
linux_integrations=(
  "system" "system_audit" "sysmon_linux" "osquery_manager"
  "fim" "suricata" "zeek" "network_traffic" "elastic_agent" "endpoint"
)

print_with_border "Adding Linux integrations..."
for integ in "${linux_integrations[@]}"; do
  add_integration "$linux_policy_id" "linux" "$integ" || true
done

# Windows integrations
windows_integrations=(
  "windows" "winlog" "osquery_manager" "fim"
  "network_traffic" "elastic_agent" "zeek" "suricata"
)

print_with_border "Adding Windows integrations..."
for integ in "${windows_integrations[@]}"; do
  add_integration "$windows_policy_id" "windows" "$integ" || true
done

print_with_border "Custom integrations for Windows policy installed."

# macOS integrations
mac_integrations=(
  "system" "osquery_manager" "fim" "network_traffic"
  "elastic_agent" "zeek" "suricata"
)

print_with_border "Adding macOS integrations..."
for integ in "${mac_integrations[@]}"; do
  add_integration "$mac_policy_id" "mac" "$integ" || true
done

# Generate enrollment tokens
create_enrollment_token() {
  local policy_id="$1"
  response=$(curl -s -k -X POST "${PROTO}://${MYIP}/kibana/api/fleet/enrollment-api-keys" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -d '{"policy_id":"'"$policy_id"'"}')
  echo "$response" | jq -r '.item.api_key'
}

print_with_border "Generating enrollment tokens..."
linux_token=$(create_enrollment_token "$linux_policy_id")
windows_token=$(create_enrollment_token "$windows_policy_id")
mac_token=$(create_enrollment_token "$mac_policy_id")

# Create installation scripts with --insecure --force
print_with_border "Creating agent installation scripts..."
AGENT_DIR="${workdir}/risx-mssp/backend/python-scripts/agent_scripts"
mkdir -p "$AGENT_DIR"

# Linux installer
# --- Elastic Agent Installers (tar and deb) ---
cat <<EOF > "$AGENT_DIR/linux_install.tar.sh"
#!/bin/bash
set -e

# Install Elastic Agent (tarball)
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_VERSION}-linux-x86_64.tar.gz
tar xzvf elastic-agent-${ELASTIC_VERSION}-linux-x86_64.tar.gz
cd elastic-agent-${ELASTIC_VERSION}-linux-x86_64
sudo ./elastic-agent install --url=https://${MYIP}:8220 --enrollment-token=$linux_token --insecure --force
cd ..
EOF

cat <<EOF > "$AGENT_DIR/linux_install.deb.sh"
#!/bin/bash
set -e

# Install Elastic Agent (deb)
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_VERSION}-amd64.deb
sudo dpkg -i elastic-agent-${ELASTIC_VERSION}-amd64.deb
sudo elastic-agent enroll --url=https://${MYIP}:8220 --enrollment-token=$linux_token --insecure --force
sudo systemctl enable elastic-agent
sudo systemctl start elastic-agent
EOF

# --- Wazuh Agent Installer (deb only) ---
cat <<EOF > "$AGENT_DIR/wazuh_install.deb.sh"
#!/bin/bash
set -e

wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.9.0-1_amd64.deb
sudo WAZUH_MANAGER=${MYIP} dpkg -i ./wazuh-agent_4.9.0-1_amd64.deb
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
EOF

# --- Zip all scripts into one archive ---
zip -j "$AGENT_DIR/linux_scripts.zip" \
    "$AGENT_DIR/linux_install.tar.sh" \
    "$AGENT_DIR/linux_install.deb.sh" \
    "$AGENT_DIR/wazuh_install.deb.sh"

# --- BEGIN: Winlogbeat role and user creation (to be run before Windows installer section) ---

cat <<EOF > "$AGENT_DIR/setup_winlogbeat_role_and_user.sh"
#!/bin/bash
set -e

# Create winlogbeat_writer_new2 role
curl -k -u elastic:changeme -X PUT "https://${MYIP}:443/elasticsearch/_security/role/winlogbeat_writer_new2" \\
  -H 'Content-Type: application/json' \\
  -d '
{
  "cluster": [
    "monitor",
    "read_ilm",
    "read_pipeline",
    "manage_index_templates",
    "manage_ilm"
  ],
  "indices": [
    {
      "names": ["winlogbeat-*"],
      "privileges": [
        "create_doc",
        "auto_configure",
        "create_index",
        "write",
        "view_index_metadata"
      ]
    }
  ]
}'


# Create winlogbeat_user_new2 user
curl -k -u elastic:changeme -X PUT "https://${MYIP}:443/elasticsearch/_security/user/winlogbeat_user_new2" \\
  -H 'Content-Type: application/json' \\
  -d '
{
  "password" : "YourStrongPasswordHere!",
  "roles" : ["winlogbeat_writer_new2"],
  "full_name" : "Winlogbeat Service Account",
  "email" : "winlogbeat@yourdomain.local"
}'
EOF

chmod +x "$AGENT_DIR/setup_winlogbeat_role_and_user.sh"
# Run the script to create role/user before Windows installer
bash "$AGENT_DIR/setup_winlogbeat_role_and_user.sh"

# --- END: Winlogbeat role and user creation ---

# ... [existing script content above] ...

# Windows installer for Elastic Agent and Wazuh Agent

# === WINLOGBEAT INSTALLER ===

cat <<'EOF' > "$AGENT_DIR/windows_install.ps1"
$ErrorActionPreference = "Continue"

# Function to run a block and always continue (for agent installs)
function Try-Install {
    param([ScriptBlock]$Block)
    try {
        & $Block
    } catch {
        Write-Host "Warning: An agent step failed, continuing." -ForegroundColor Yellow
    }
}

# Choose a dedicated working directory outside system32!
$workdir = "$env:SystemDrive\elastic-agent-install"
if (-not (Test-Path $workdir)) { New-Item -ItemType Directory -Path $workdir | Out-Null }
Set-Location $workdir

# --- Elastic Agent ---
Try-Install {
    $eaZip = "elastic-agent-@ELASTIC_VERSION@-windows-x86_64.zip"
    $eaDir = "elastic-agent-@ELASTIC_VERSION@-windows-x86_64"
    if (Test-Path "$eaDir") { Remove-Item "$eaDir" -Recurse -Force }
    if (Test-Path "$eaZip") { Remove-Item "$eaZip" -Force }
    Write-Host "Downloading Elastic Agent..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://artifacts.elastic.co/downloads/beats/elastic-agent/$eaZip" -OutFile $eaZip -Verbose
    Write-Host "Extracting Elastic Agent archive..." -ForegroundColor Cyan
    Expand-Archive ".\$eaZip" -DestinationPath .
    Set-Location ".\$eaDir"
    Write-Host "Running Elastic Agent installer..." -ForegroundColor Cyan
    & ".\elastic-agent.exe" install --url=https://@MYIP@:8220 --enrollment-token=@WINDOWS_TOKEN@ --insecure --force
    if ($LASTEXITCODE -ne 0) { Write-Host "Elastic Agent install failed!" -ForegroundColor Red }
    Set-Location $workdir
    Remove-Item ".\$eaZip" -Force
    Remove-Item ".\$eaDir" -Recurse -Force
    Write-Host "Elastic Agent step done." -ForegroundColor Green
    Start-Sleep -Seconds 10
}

# --- Wazuh Agent ---
Try-Install {
    $wazuhMsi = "wazuh-agent-4.9.0-1.msi"
    if (Test-Path "$wazuhMsi") { Remove-Item "$wazuhMsi" -Force }
    Write-Host "Downloading Wazuh Agent..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/$wazuhMsi" -OutFile $wazuhMsi -Verbose
    Write-Host "Starting Wazuh Agent installer..." -ForegroundColor Cyan
    $wzProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $wazuhMsi, "WAZUH_MANAGER=@MYIP@" -Wait -PassThru -Verbose
    if ($wzProc.ExitCode -ne 0) { Write-Host "Wazuh Agent install failed!" -ForegroundColor Red }
    Write-Host "Starting Wazuh Service..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    Try { NET START WazuhSvc } Catch { Write-Host "WazuhSvc could not be started, check install logs." -ForegroundColor Yellow }
    Remove-Item ".\$wazuhMsi" -Force
    Write-Host "Wazuh Agent step done." -ForegroundColor Green
    Start-Sleep -Seconds 10
}
# --- Winlogbeat ---
# --- Winlogbeat ---
Try-Install {
    $winlogbeatVersion = "9.0.1"
    $winlogbeatZip = "winlogbeat-$winlogbeatVersion-windows-x86_64.zip"
    $winlogbeatUrl = "https://artifacts.elastic.co/downloads/beats/winlogbeat/$winlogbeatZip"
    $installPath = "C:\Program Files\winlogbeat"
    $zipPath = "$env:TEMP\winlogbeat.zip"
    $ymlPath = "$installPath\winlogbeat.yml"

    # Stop Winlogbeat service if running, to avoid file lock
    $svc = Get-Service -Name winlogbeat -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "Stopping running Winlogbeat service for update/cleanup..."
        Stop-Service -Name winlogbeat -Force
        Start-Sleep -Seconds 4
    }

    # Remove old install if exists
    if (Test-Path $installPath) {
        Remove-Item "$installPath" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null

    # Download and extract
    Write-Host "Downloading Winlogbeat..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $winlogbeatUrl -OutFile $zipPath
    Write-Host "Extracting files..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $installPath -Force

    # Move files from subdir to $installPath
    $extractedDir = Join-Path $installPath "winlogbeat-$winlogbeatVersion-windows-x86_64"
    if (Test-Path $extractedDir) {
        Get-ChildItem "$extractedDir\*" | Move-Item -Destination $installPath
        Remove-Item $extractedDir -Recurse -Force
    }

    # Create config
    Write-Host "Creating configuration file..." -ForegroundColor Cyan
    @'
###################### Winlogbeat Configuration Example ########################
setup.ilm.check_exists: false
winlogbeat.event_logs:
  - name: Application
    ignore_older: 72h
  - name: System
  - name: Security
  - name: Microsoft-Windows-Sysmon/Operational
  - name: Windows PowerShell
    event_id: 400, 403, 600, 800
  - name: Microsoft-Windows-PowerShell/Operational
    event_id: 4103, 4104, 4105, 4106
  - name: Microsoft-Windows-Windows Defender/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-BitLocker/BitLocker Management
    ignore_older: 72h
  - name: Microsoft-Windows-BitLocker-DrivePreparationTool/Admin
    ignore_older: 72h
  - name: Microsoft-Windows-LSA/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-CAPI2/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-EFS/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Security-UserConsentVerifier/Audit
    ignore_older: 72h
  - name: Microsoft-Windows-SmartCard-Audit/Authentication
    ignore_older: 72h
  - name: Microsoft-Windows-User Device Registration/Admin
    ignore_older: 72h
  - name: Microsoft-Windows-WinRM/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Kernel-Boot/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-DriverFrameworks-UserMode/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Kernel-StoreMgr/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-DeviceGuard/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-DNS-Client/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Firewall-CPL/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-WFP/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Windows Firewall With Advanced Security/Firewall
    ignore_older: 72h
  - name: Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-TerminalServices-LocalSessionManager/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-TaskScheduler/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-WindowsUpdateClient/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-GroupPolicy/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-AppLocker/EXE and DLL
    ignore_older: 72h
  - name: Microsoft-Windows-CodeIntegrity/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Security-Mitigations/KernelMode
    ignore_older: 72h
  - name: Microsoft-Windows-Security-Mitigations/UserMode
    ignore_older: 72h
  - name: Microsoft-Windows-Security-Netlogon/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-NTLM/Operational
    ignore_older: 72h
  - name: Microsoft-Windows-Kerberos/Operational
    ignore_older: 72h
  - name: ForwardedEvents
    tags: [forwarded]
setup.template.settings:
  index.number_of_shards: 1
fields_under_root: true
setup.kibana:
  hosts: ["https://@MYIP@:443"]
  path: "/kibana"
output.elasticsearch:
  hosts: ["https://@MYIP@:443"]
  path: "/elasticsearch"
  username: "winlogbeat_user_new2"
  password: ${output.elasticsearch.password}
  ssl:
    enabled: true
    verification_mode: none
processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~
'@ | Set-Content -Path $ymlPath -Encoding UTF8

    Set-Location $installPath
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

    # Keystore
    if (-not (Test-Path "$installPath\winlogbeat.keystore")) {
        Write-Host "Creating keystore..."
        Start-Process -FilePath "$installPath\winlogbeat.exe" -ArgumentList "keystore create" -Wait -NoNewWindow
        Write-Host "Keystore created"
    }
    $keystoreList = & "$installPath\winlogbeat.exe" keystore list
    if (-not $keystoreList -or $keystoreList -notmatch "output.elasticsearch.password") {
        Write-Host "Adding output.elasticsearch.password..."
        "YourStrongPasswordHere!" | & "$installPath\winlogbeat.exe" keystore add "output.elasticsearch.password" --stdin
    }
    if (Test-Path "$installPath\winlogbeat.keystore") {
        icacls "$installPath\winlogbeat.keystore" /grant "SYSTEM:R"
        Write-Host "Set SYSTEM read-only permissions on keystore"
    } else {
        Write-Host "Keystore not found! Permissions not set." -ForegroundColor Red
    }

    # Install Winlogbeat service
    $serviceScriptPath = "$installPath\install-service-winlogbeat.ps1"
    if (-not (Get-Service -Name winlogbeat -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Winlogbeat service..."
        if (Test-Path $serviceScriptPath) {
            & $serviceScriptPath
        } else {
            Write-Host "Service install script missing! Manual installation required." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Winlogbeat service already installed."
    }

    # Start Winlogbeat service
    $service = Get-Service -Name winlogbeat -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Running') {
            Write-Host "Starting Winlogbeat service..."
            $service | Start-Service
            Start-Sleep -Seconds 5
            if ((Get-Service winlogbeat).Status -ne 'Running') {
                Write-Host "Service failed to start. Check event logs." -ForegroundColor Red
            }
        } else {
            Write-Host "Winlogbeat service is already running."
        }
    } else {
        Write-Host "Winlogbeat service not found! Installation failed." -ForegroundColor Red
        exit 1
    }

    # Cleanup zip
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Write-Host "Winlogbeat installation completed!" -ForegroundColor Green
}
# --- Npcap ---
Try-Install {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $downloadUrl    = "https://npcap.com/dist/npcap-1.82.exe"
    $installerPath  = "$env:TEMP\npcap-installer.exe"
    if (-not (
            (New-Object Security.Principal.WindowsPrincipal(
                [Security.Principal.WindowsIdentity]::GetCurrent()
             )).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        ))
    {
        Write-Host "Elevation required: restarting script as Administrator..." -ForegroundColor Yellow
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"" -Verb RunAs
        exit
    }
    Write-Host "Downloading Npcap installer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -Verbose
    Write-Host "Launching Npcap installer..." -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Yellow
    Write-Host "PLEASE COMPLETE THE INSTALLATION MANUALLY:" -ForegroundColor Yellow
    Write-Host "  " Uncheck 'Install Npcap in WinPcap API-compatible Mode' unless you need it." -ForegroundColor Yellow
    Write-Host "  " Leave other defaults as-is." -ForegroundColor Yellow
    Write-Host "==============================================================" -ForegroundColor Yellow
    Start-Process -FilePath $installerPath -Wait -Verbose
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Write-Host "Npcap installer completed. Please verify installation." -ForegroundColor Green
}

EOF

# MAC installer

cat <<EOF > "$AGENT_DIR/mac_install.sh"
#!/bin/bash
set -e

# Install Elastic Agent
curl -L -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_VERSION}-darwin-x86_64.tar.gz
tar xzvf elastic-agent-$ELASTIC_VERSION-darwin-x86_64.tar.gz
cd elastic-agent-$ELASTIC_VERSION-darwin-x86_64
sudo ./elastic-agent install --url="https://${MYIP}:8220" --enrollment-token="$mac_token" --insecure --force
cd ..

# Install Wazuh Agent
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
  echo "Detected Apple Silicon (M1/M2)"
  curl -so wazuh-agent.pkg https://packages.wazuh.com/4.x/macos/wazuh-agent-4.9.0-1.arm64.pkg
else
  echo "Detected Intel"
  curl -so wazuh-agent.pkg https://packages.wazuh.com/4.x/macos/wazuh-agent-4.9.0-1.intel64.pkg
fi
echo "WAZUH_MANAGER=${MYIP}" > /tmp/wazuh_envs
sudo installer -pkg ./wazuh-agent.pkg -target /
sudo /Library/Ossec/bin/wazuh-control start
EOF

chmod +x "$AGENT_DIR"/*.sh
print_green "Agent scripts created at: $AGENT_DIR"

# Final validation
print_with_border "Validation Checklist:"
echo "1. Verify Fleet Server access: https://${MYIP}:8220"
echo "2. Check agent policies in Kibana -> Fleet"
echo "3. Review installation logs on target hosts"
echo "4. Confirm network connectivity to Elasticsearch/Kibana"

print_with_border "Security Note:"
echo "The --insecure flag should only be used for testing environments"
echo "with self-signed certificates. For production, use valid certificates"
echo "and remove the --insecure flag."

# Install and activate default Elastic Security rules

# Helper functions
print_with_border() {
  local msg="$1"
  local len=$((${#msg} + 4))
  printf "\n%${len}s\n" | tr ' ' '#'
  echo "# $msg #"
  printf "%${len}s\n\n" | tr ' ' '#'
}

print_red() {
  echo -e "\033[1;31m$1\033[0m"
}

print_green() {
  echo -e "\033[1;32m$1\033[0m"
}

print_yellow() {
  echo -e "\033[1;33m$1\033[0m"
}

# Wait for detection engine readiness
wait_for_detection_engine() {
  local timeout=300
  local start_time=$(date +%s)

  print_with_border "Waiting for detection engine to be ready..."

  while :; do
    response=$(curl -s -k -o /dev/null -w "%{http_code}" \
      "${PROTO}://${MYIP}/kibana/api/detection_engine/index" \
      -u "elastic:${ELASTIC_PASSWORD}" \
      -H 'kbn-xsrf: true')

    if [ "$response" -eq 200 ]; then
      print_green "Detection engine is ready"
      return 0
    fi

    if [ $(($(date +%s) - start_time)) -ge $timeout ]; then
      print_red "Timeout waiting for detection engine"
      return 1
    fi

    print_yellow "Detection engine not ready yet (HTTP $response). Retrying in 10 seconds..."
    sleep 10
  done
}

# Install prebuilt rules with proper 8.17.0 API
install_prebuilt_rules() {
  local retries=3
  print_with_border "Installing prebuilt detection rules"

  for ((i=1; i<=retries; i++)); do
    response=$(curl -s -k -X POST \
      "${PROTO}://${MYIP}/kibana/api/detection_engine/prebuilt_rules/_perform_install" \
      -u "elastic:${ELASTIC_PASSWORD}" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -d '{"mode": "ALL_RULES"}')

    # Check for valid response
    if http_code=$(curl -s -k -o /dev/null -w "%{http_code}" \
      "${PROTO}://${MYIP}/kibana/api/detection_engine/prebuilt_rules/status" \
      -u "elastic:${ELASTIC_PASSWORD}"); [ "$http_code" -eq 200 ]; then
      print_green "Successfully installed prebuilt rules"
      return 0
    fi

    print_red "Rule installation attempt $i failed. Response: $response"
    sleep 15
  done

  print_red "Failed to install prebuilt rules after $retries attempts"
  return 1
}

# Enable all rules with proper pagination
enable_all_rules() {
  local retries=3
  print_with_border "Enabling all detection rules"

  for ((i=1; i<=retries; i++)); do
    # First get all rule IDs
    rule_ids=$(curl -s -k "${PROTO}://${MYIP}/kibana/api/detection_engine/rules/_find?per_page=10000" \
      -u "elastic:${ELASTIC_PASSWORD}" \
      -H 'kbn-xsrf: true' | jq -r '.data[].id')

    if [ -z "$rule_ids" ]; then
      print_red "No rules found to enable"
      return 1
    fi

    # Enable rules in bulk
    enable_response=$(curl -s -k -X PATCH \
      "${PROTO}://${MYIP}/kibana/api/detection_engine/rules/_bulk_update" \
      -u "elastic:${ELASTIC_PASSWORD}" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -d "$(
        jq -n --argjson ids "$(echo "$rule_ids" | jq -R . | jq -s .)" \
        '{
          "query": { 
            "bool": { 
              "must": [ 
                { "terms": { "ids": $ids } } 
              ] 
            } 
          },
          "actions": { 
            "enable": true,
            "set": [
              { "field": "enabled", "value": true }
            ]
          }
        }'
      )")

    if echo "$enable_response" | jq -e '.updated' >/dev/null; then
      updated_count=$(echo "$enable_response" | jq '.updated')
      print_green "Enabled $updated_count detection rules"
      return 0
    fi

    print_red "Enable rules attempt $i failed. Response: $enable_response"
    sleep 15
  done

  print_red "Failed to enable rules after $retries attempts"
  return 1
}

# Main execution flow
print_with_border "Starting Elastic Security configuration"

# 1. Wait for detection engine to be ready
if ! wait_for_detection_engine; then
  print_red "Aborting security rules setup"
  return 1
fi

# 2. Install prebuilt rules
if ! install_prebuilt_rules; then
  print_red "Failed to install prebuilt rules"
  return 1
fi

# 3. Enable all rules
if ! enable_all_rules; then
  print_red "Failed to enable all rules"
  return 1
fi

# Final validation
print_with_border "Validation checks:"
curl -s -k "${PROTO}://${MYIP}/kibana/api/detection_engine/rules/_find?per_page=1" \
  -u "elastic:${ELASTIC_PASSWORD}" | jq '.data[0] | {name, enabled}'

print_green "Security rules setup completed successfully"

} # End of main function

# --- Custom Rules Import and Enable (ALWAYS RUN LAST) ---
# --- Custom Rules Import and Enable (ALWAYS RUN LAST) ---

import_and_enable_custom_rules() {
  print_with_border "Importing custom detection rules from rules_export.ndjson and rules_export2.ndjson..."

  RULES_FILES=("rules_export.ndjson" "rules_export2.ndjson")
  KIBANA_URL="${PROTO}://${MYIP}/kibana"
  USERNAME="elastic"
  PASSWORD="changeme"
  CURL="curl"
  VERVY="non" # "non" means skip TLS verification

  if [[ "$VERVY" == "non" ]]; then
    CURL="$CURL -k"
  fi

  # Import each rules file
  for RULES_FILE in "${RULES_FILES[@]}"; do
    if [[ ! -f "$RULES_FILE" ]]; then
      print_red "Rules file $RULES_FILE does not exist. Skipping."
      continue
    fi

    print_with_border "Importing $RULES_FILE..."

    IMPORT_RESPONSE=$(
      $CURL -X POST "$KIBANA_URL/api/detection_engine/rules/_import" \
        -u $USERNAME:$PASSWORD \
        -H 'kbn-xsrf: true' \
        -H 'Content-Type: multipart/form-data' \
        --form "file=@$RULES_FILE"
    )

    if echo "$IMPORT_RESPONSE" | jq -e '.success' >/dev/null; then
      print_green "Custom rules from $RULES_FILE imported successfully."
    else
      print_red "Custom rules import from $RULES_FILE failed! Response:"
      echo "$IMPORT_RESPONSE"
      continue  # Continue with other files, do not return 1
    fi

    # Optional wait after each import
    sleep 5
  done

  print_with_border "Enabling all custom imported rules..."

  COMMON_HDRS=(-H "kbn-xsrf: true")

  # Fetch all rule IDs
  all_ids=$(
    $CURL -u $USERNAME:$PASSWORD "${COMMON_HDRS[@]}" \
      -X GET "$KIBANA_URL/api/alerting/rules/_find?per_page=10000" \
    | jq -r '.data[].id'
  )


  print_green "All imported rules have been enabled."
}

# --- End of custom rules import and enable section ---
# --- End of custom rules import and enable section ---



main || true
import_and_enable_custom_rules
