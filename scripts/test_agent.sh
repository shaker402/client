#!/bin/bash
set -eo pipefail

main() {

source libs/main.sh
rsync -a ../resources/default.env ../workdir/.env
define_paths

set -a
source ../workdir/.env
set +a

source libs/host-dirs.sh
source post-steps.sh
source libs/prerquiests-check.sh

MYIP=${MYIP:-$(curl -s ifconfig.me)}
PROTO=${PROTO:-https}

get_agent_policy_id() {
  local policy_name="$1"
  response=$(curl -s -k -u "elastic:${ELASTIC_PASSWORD}" \
    -H 'kbn-xsrf: true' \
    "${PROTO}://${MYIP}/kibana/api/fleet/agent_policies")
  echo "$response" | jq -r --arg name "$policy_name" '.items[] | select(.name == $name) | .id'
}

linux_policy_id=$(get_agent_policy_id "linux-policy")
windows_policy_id=$(get_agent_policy_id "windows-policy")
mac_policy_id=$(get_agent_policy_id "mac-policy")

echo "DEBUG: linux_policy_id=$linux_policy_id"
echo "DEBUG: windows_policy_id=$windows_policy_id"
echo "DEBUG: mac_policy_id=$mac_policy_id"

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

[ -z "$linux_token" ] || [ "$linux_token" = "null" ] && { echo "Error: Linux enrollment token not generated!"; exit 1; }
[ -z "$windows_token" ] || [ "$windows_token" = "null" ] && { echo "Error: Windows enrollment token not generated!"; exit 1; }
[ -z "$mac_token" ] || [ "$mac_token" = "null" ] && { echo "Error: Mac enrollment token not generated!"; exit 1; }

print_with_border "Creating agent installation scripts..."
AGENT_DIR="${workdir}/risx-mssp/backend/python-scripts/agent_scripts"
mkdir -p "$AGENT_DIR"

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
# --- Winlogbeat Start ---

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
setup.ilm.check_exists: true
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


fields_under_root: true
setup.kibana:
  hosts: ["https://@MYIP@:443"]
  path: "/kibana"
output.elasticsearch:
  hosts: ["https://@MYIP@:443"]
  path: "/elasticsearch"
  username: "elastic"
  password: ${output.elasticsearch.password}
  ssl:
    enabled: true
    verification_mode: none

setup.ilm.enabled: true
setup.ilm.rollover_alias: "winlogbeat"
setup.ilm.policy_name: "winlogbeat"
setup.ilm.overwrite: true

setup.template.settings:
  index.number_of_shards: 1
  index.default_pipeline: "winlogbeat-9.0.1-routing"  # Force pipeline
  index.final_pipeline: "windows_field_normalization"
setup.template.overwrite: true  # Ensure template overwrite
setup.template.enabled: true
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
        "changeme" | & "$installPath\winlogbeat.exe" keystore add "output.elasticsearch.password" --stdin
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


# --- Winlogbeat  END ---

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
    Write-Host "  • Uncheck 'Install Npcap in WinPcap API-compatible Mode' unless you need it." -ForegroundColor Yellow
    Write-Host "  • Leave other defaults as-is." -ForegroundColor Yellow
    Write-Host "==============================================================" -ForegroundColor Yellow
    Start-Process -FilePath $installerPath -Wait -Verbose
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Write-Host "Npcap installer completed. Please verify installation." -ForegroundColor Green
}

EOF

print_green "All the docker services are deployed successfully."
print_with_border "Access the services using below links"
for service in "${APPS_TO_INSTALL[@]}"; do
  for endpoint in "${ENDPOINTS[@]}"; do
    if [[ $endpoint == "$service"* ]]; then
      echo "$endpoint"
    fi
  done
done

sed -i "s/@ELASTIC_VERSION@/${ELASTIC_VERSION}/g" "$AGENT_DIR/windows_install.ps1"
sed -i "s/@MYIP@/${MYIP}/g" "$AGENT_DIR/windows_install.ps1"
sed -i "s/@WINDOWS_TOKEN@/${windows_token}/g" "$AGENT_DIR/windows_install.ps1"

chmod +x "$AGENT_DIR"/*.sh
print_green "Agent scripts created at: $AGENT_DIR"

print_with_border "Validation Checklist:"
echo "1. Verify Fleet Server access: https://${MYIP}:8220"
echo "2. Check agent policies in Kibana -> Fleet"
echo "3. Review installation logs on target hosts"
echo "4. Confirm network connectivity to Elasticsearch/Kibana"
}

main || true

#END
