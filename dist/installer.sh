#!/bin/bash
#
# Install Game Server
#
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
# @WARLOCK-TITLE Zomboid
# @WARLOCK-IMAGE media/zomboid-1920x1080.webp
# @WARLOCK-ICON media/zomboid-128x128.webp
# @WARLOCK-THUMBNAIL media/zomboid-640x360.webp
#
# Supports:
#   Debian 12, 13
#   Ubuntu 24.04
#
# Requirements:
#   None
#
# TRMM Custom Fields:
#   None
#
# Syntax:
#   --uninstall  - Perform an uninstallation
#   --dir=<src> - Use a custom installation directory instead of the default (optional)
#   --skip-firewall  - Do not install or configure a system firewall
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#
# Changelog:
#   20251103 - New installer

############################################
## Parameter Configuration
############################################

# Name of the game (used to create the directory)
INSTALLER_VERSION="v20251127~DEV"
GAME="Zomboid"
GAME_DESC="Project Zomboid Dedicated Server"
REPO="BitsNBytes25/Zomboid-Installer"
WARLOCK_GUID="dd73094b-b84e-475b-b47a-1a97b5b2d850"
STEAM_ID="380870"
GAME_USER="steam"
GAME_DIR="/home/${GAME_USER}/${GAME}"
GAME_SERVICE="zomboid"

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --uninstall  - Perform an uninstallation
    --dir=<src> - Use a custom installation directory instead of the default (optional)
    --skip-firewall  - Do not install or configure a system firewall
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)

Please ensure to run this script as root (or at least with sudo)

@LICENSE AGPLv3
EOD
  exit 1
}

# Parse arguments
MODE_UNINSTALL=0
OVERRIDE_DIR=""
SKIP_FIREWALL=0
NONINTERACTIVE=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--uninstall) MODE_UNINSTALL=1; shift 1;;
		--dir=*)
			OVERRIDE_DIR="${1#*=}";
			[ "${OVERRIDE_DIR:0:1}" == "'" ] && [ "${OVERRIDE_DIR:0-1}" == "'" ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			[ "${OVERRIDE_DIR:0:1}" == '"' ] && [ "${OVERRIDE_DIR:0-1}" == '"' ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			shift 1;;
		--skip-firewall) SKIP_FIREWALL=1; shift 1;;
		--non-interactive) NONINTERACTIVE=1; shift 1;;
		-h|--help) usage;;
	esac
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
##
# Get which firewall is enabled,
# or "none" if none located
function get_enabled_firewall() {
	if [ "$(systemctl is-active firewalld)" == "active" ]; then
		echo "firewalld"
	elif [ "$(systemctl is-active ufw)" == "active" ]; then
		echo "ufw"
	elif [ "$(systemctl is-active iptables)" == "active" ]; then
		echo "iptables"
	else
		echo "none"
	fi
}

##
# Get which firewall is available on the local system,
# or "none" if none located
#
# CHANGELOG:
#   2025.04.10 - Switch from "systemctl list-unit-files" to "which" to support older systems
function get_available_firewall() {
	if which -s firewall-cmd; then
		echo "firewalld"
	elif which -s ufw; then
		echo "ufw"
	elif systemctl list-unit-files iptables.service &>/dev/null; then
		echo "iptables"
	else
		echo "none"
	fi
}
##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_debian() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'debian' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'debian' ]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_ubuntu() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_rhel() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'rhel' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'fedora' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'centos' ]]; then echo 1; return; fi
		if [ "$ID" == 'rhel' ]; then echo 1; return; fi
		if [ "$ID" == 'fedora' ]; then echo 1; return; fi
		if [ "$ID" == 'centos' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_suse() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'suse' ]]; then echo 1; return; fi
		if [ "$ID" == 'suse' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_arch() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'arch' ]]; then echo 1; return; fi
		if [ "$ID" == 'arch' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_bsd() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_macos() {
	if [ "$(uname -s)" == 'Darwin' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Install a package with the system's package manager.
#
# Uses Redhat's yum, Debian's apt-get, and SuSE's zypper.
#
# Usage:
#
# ```syntax-shell
# package_install apache2 php7.0 mariadb-server
# ```
#
# @param $1..$N string
#        Package, (or packages), to install.  Accepts multiple packages at once.
#
#
# CHANGELOG:
#   2025.04.10 - Set Debian frontend to noninteractive
#
function package_install (){
	echo "package_install: Installing $*..."

	TYPE_BSD="$(os_like_bsd)"
	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_RHEL="$(os_like_rhel)"
	TYPE_ARCH="$(os_like_arch)"
	TYPE_SUSE="$(os_like_suse)"

	if [ "$TYPE_BSD" == 1 ]; then
		pkg install -y $*
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif [ "$TYPE_RHEL" == 1 ]; then
		yum install -y $*
	elif [ "$TYPE_ARCH" == 1 ]; then
		pacman -Syu --noconfirm $*
	elif [ "$TYPE_SUSE" == 1 ]; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		exit 1
	fi
}
##
# Simple download utility function
#
# Uses either cURL or wget based on which is available
#
# Downloads the file to a temp location initially, then moves it to the final destination
# upon a successful download to avoid partial files.
#
# Returns 0 on success, 1 on failure
#
# CHANGELOG:
#   2025.11.23 - Download to a temp location to verify download was successful
#              - use which -s for cleaner checks
#   2025.11.09 - Initial version
#
function download() {
	local SOURCE="$1"
	local DESTINATION="$2"
	local TMP=$(mktemp)

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if which -s curl; then
		if curl -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif which -s wget; then
		if wget -q "$SOURCE" -O "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: wget failed to download $SOURCE" >&2
			return 1
		fi
	else
		echo "download: Neither curl nor wget is installed, cannot download!" >&2
		return 1
	fi
}
##
# Determine if the current shell session is non-interactive.
#
# Checks NONINTERACTIVE, CI, DEBIAN_FRONTEND, TERM, and TTY status.
#
# Returns 0 (true) if non-interactive, 1 (false) if interactive.
#
# CHANGELOG:
#   2025.11.23 - Initial version
#
function is_noninteractive() {
	# explicit flags
	case "${NONINTERACTIVE:-}${CI:-}" in
		1*|true*|TRUE*|True*|*CI* ) return 0 ;;
	esac

	# debian frontend
	if [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then
		return 0
	fi

	# dumb terminal or no tty on stdin/stdout
	if [ "${TERM:-}" = "dumb" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
		return 0
	fi

	return 1
}

##
# Prompt user for a text response
#
# Arguments:
#   --default="..."   Default text to use if no response is given
#
# Returns:
#   text as entered by user
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.01.01 - Initial version
#
function prompt_text() {
	local DEFAULT=""
	local PROMPT="Enter some text"
	local RESPONSE=""

	while [ $# -ge 1 ]; do
		case $1 in
			--default=*) DEFAULT="${1#*=}";;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	echo -n '> : ' >&2

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		echo $DEFAULT
		return
	fi

	read RESPONSE
	if [ "$RESPONSE" == "" ]; then
		echo "$DEFAULT"
	else
		echo "$RESPONSE"
	fi
}

##
# Prompt user for a yes or no response
#
# Arguments:
#   --invert            Invert the response (yes becomes 0, no becomes 1)
#   --default-yes       Default to yes if no response is given
#   --default-no        Default to no if no response is given
#   -q                  Quiet mode (no output text after response)
#
# Returns:
#   1 for yes, 0 for no (or inverted if --invert is set)
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.11.09 - Add -q (quiet) option to suppress output after prompt (and use return value)
#   2025.01.01 - Initial version
#
function prompt_yn() {
	local TRUE=0 # Bash convention: 0 is success/true
	local YES=1
	local FALSE=1 # Bash convention: non-zero is failure/false
	local NO=0
	local DEFAULT="n"
	local DEFAULT_CODE=1
	local PROMPT="Yes or no?"
	local RESPONSE=""
	local QUIET=0

	while [ $# -ge 1 ]; do
		case $1 in
			--invert) YES=0; NO=1 TRUE=1; FALSE=0;;
			--default-yes) DEFAULT="y";;
			--default-no) DEFAULT="n";;
			-q) QUIET=1;;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	if [ "$DEFAULT" == "y" ]; then
		DEFAULT="$YES"
		DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT="$NO"
		DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		if [ $QUIET -eq 0 ]; then
			echo $DEFAULT
		fi
		return $DEFAULT_CODE
	fi

	read RESPONSE
	case "$RESPONSE" in
		[yY]*)
			if [ $QUIET -eq 0 ]; then
				echo $YES
			fi
			return $TRUE;;
		[nN]*)
			if [ $QUIET -eq 0 ]; then
				echo $NO
			fi
			return $FALSE;;
		*)
			if [ $QUIET -eq 0 ]; then
				echo $DEFAULT
			fi
			return $DEFAULT_CODE;;
	esac
}
##
# Print a header message
#
# CHANGELOG:
#   2025.11.09 - Port from _common to bz_eval_tui
#   2024.12.25 - Initial version
#
function print_header() {
	local header="$1"
	echo "================================================================================"
	printf "%*s\n" $(((${#header}+80)/2)) "$header"
    echo ""
}

##
# Install UFW
#
function install_ufw() {
	if [ "$(os_like_rhel)" == 1 ]; then
		# RHEL/CentOS requires EPEL to be installed first
		package_install epel-release
	fi

	package_install ufw

	# Auto-enable a newly installed firewall
	ufw --force enable
	systemctl enable ufw
	systemctl start ufw

	# Auto-add the current user's remote IP to the whitelist (anti-lockout rule)
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		ufw allow from $TTY_IP comment 'Anti-lockout rule based on first install of UFW'
	fi
}
##
# Install the management script from the project's repo
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#
function install_warlock_manager() {
	print_header "Performing install_management"

	# Install management console and its dependencies
	local SRC=""
	local REPO="$1"
	local INSTALLER_VERSION="$2"

	if [[ "$INSTALLER_VERSION" == *"~DEV"* ]]; then
		# Development version, pull from dev branch
		SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/dev/dist/manage.py"
		echo "Trying to download manage.py from dev branch on $REPO"
	else
		# Stable version, pull from tagged release
		SRC="https://raw.githubusercontent.com/${REPO}/refs/tags/${INSTALLER_VERSION}/dist/manage.py"
		echo "Trying to download manage.py from $INSTALLER_VERSION tag on $REPO"
	fi

	if ! download "$SRC" "$GAME_DIR/manage.py"; then
		# Fallback to main branch
		echo "Download failed, falling back to main branch..." >&2
		SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/main/dist/manage.py"
		if ! download "$SRC" "$GAME_DIR/manage.py"; then
			echo "Could not download management script!" >&2
			exit 1
		fi
	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/manage.py"
	chmod +x "$GAME_DIR/manage.py"

	# Install configuration definitions
	cat > "$GAME_DIR/configs.yaml" <<EOF
manager:
  - name: Steam Branch
    section: Steam
    key: steam_branch
    type: str
    default: public
    help: "The Steam branch to install the server from (e.g., stable, experimental)."
    options:
      - public
  - name: Steam Branch Password
    section: Steam
    key: steam_branch_password
    type: str
    default: ""
    help: "The password for accessing a private Steam branch, if applicable."
  - name: Shutdown Warning 5 Minutes
    section: Messages
    key: shutdown_5min
    type: str
    default: Server is shutting down in 5 minutes
    help: "Custom message broadcasted to players 5 minutes before server shutdown."
  - name: Shutdown Warning 4 Minutes
    section: Messages
    key: shutdown_4min
    type: str
    default: Server is shutting down in 4 minutes
    help: "Custom message broadcasted to players 4 minutes before server shutdown."
  - name: Shutdown Warning 3 Minutes
    section: Messages
    key: shutdown_3min
    type: str
    default: Server is shutting down in 3 minutes
    help: "Custom message broadcasted to players 3 minutes before server shutdown."
  - name: Shutdown Warning 2 Minutes
    section: Messages
    key: shutdown_2min
    type: str
    default: Server is shutting down in 2 minutes
    help: "Custom message broadcasted to players 2 minutes before server shutdown."
  - name: Shutdown Warning 1 Minute
    section: Messages
    key: shutdown_1min
    type: str
    default: Server is shutting down in 1 minute
    help: "Custom message broadcasted to players 1 minute before server shutdown."
  - name: Shutdown Warning 30 Seconds
    section: Messages
    key: shutdown_30sec
    type: str
    default: Server is shutting down in 30 seconds!
    help: "Custom message broadcasted to players 30 seconds before server shutdown."
  - name: Shutdown Warning NOW
    section: Messages
    key: shutdown_now
    type: str
    default: Server is shutting down NOW!
    help: "Custom message broadcasted to players immediately before server shutdown."
  - name: Instance Started (Discord)
    section: Discord
    key: instance_started
    type: str
    default: "{instance} has started! :rocket:"
    help: "Custom message sent to Discord when the server starts, use '{instance}' to insert the map name"
  - name: Instance Stopping (Discord)
    section: Discord
    key: instance_stopping
    type: str
    default: ":small_red_triangle_down: {instance} is shutting down"
    help: "Custom message sent to Discord when the server stops, use '{instance}' to insert the map name"
  - name: Discord Enabled
    section: Discord
    key: enabled
    type: bool
    default: false
    help: "Enables or disables Discord integration for server status updates."
  - name: Discord Webhook URL
    section: Discord
    key: webhook
    type: str
    default: ""
    help: "The webhook URL for sending server status updates to a Discord channel."
zomboid:
  - name: PVP
    key: PVP
    type: bool
    default: true
    help: "Players can hurt and kill other players"
  - name: Pause When Empty
    key: PauseEmpty
    type: bool
    default: true
    help: "Game time stops when there are no players online"
  - name: Global Chat Enabled
    key: GlobalChat
    type: bool
    default: true
    help: "Toggles global chat on or off."
  - name: Chat Streams
    key: ChatStreams
    type: str
    default: "s,r,a,w,y,sh,f,all"
    help: "Comma-separated chat streams. Keep as a single string; parser will split on commas if needed."
  - name: Open Server
    key: Open
    type: bool
    default: true
    help: "Clients may join without an account on the whitelist. If false, admins must create accounts."
  - name: Server Welcome Message
    key: ServerWelcomeMessage
    type: str
    default: "Welcome to Project Zomboid Multiplayer! <LINE> <LINE> To interact with the Chat panel: press Tab, T, or Enter. <LINE> <LINE> The Tab key will change the target stream of the message. <LINE> <LINE> Global Streams: /all <LINE> Local Streams: /say, /yell <LINE> Special Steams: /whisper, /safehouse, /faction. <LINE> <LINE> Press the Up arrow to cycle through your message history. Click the Gear icon to customize chat. <LINE> <LINE> Happy surviving!"
    help: "First welcome message visible in chat. Supports <LINE> and <RGB:r,g,b> markers."
  - name: Auto Create User In Whitelist
    key: AutoCreateUserInWhiteList
    type: bool
    default: false
    help: "Add unknown usernames to the whitelist when players join (only for Open=true servers)."
  - name: Display User Name
    key: DisplayUserName
    type: bool
    default: true
    help: "Display usernames above player's heads in-game."
  - name: Show First And Last Name
    key: ShowFirstAndLastName
    type: bool
    default: false
    help: "Display first & last name above player's heads."
  - name: Spawn Point
    key: SpawnPoint
    type: str
    default: "0,0,0"
    help: "Force new players to spawn at specific x,y,z coordinates. Use '0,0,0' to ignore."
  - name: Safety System
    key: SafetySystem
    type: bool
    default: true
    help: "Players can enter/leave PVP individually; governs when players can hurt each other."
  - name: Show Safety Icon
    key: ShowSafety
    type: bool
    default: true
    help: "Display a skull icon over the head of players who have entered PVP mode."
  - name: Safety Toggle Timer
    key: SafetyToggleTimer
    type: int
    default: 2
    help: "Time it takes for a player to enter/leave PVP mode (in seconds)."
  - name: Safety Cooldown Timer
    key: SafetyCooldownTimer
    type: int
    default: 3
    help: "Delay before a player can re-enter/change PVP state (in seconds)."
  - name: Spawn Items
    key: SpawnItems
    type: str
    default: ""
    help: "Comma-separated item types new players spawn with (example: Base.Axe,Base.Bag_BigHikingBag). Stored as string."
  - name: Default Port
    key: DefaultPort
    type: int
    default: 16261
    help: "Default starting port for player data (UDP)."
  - name: UDP Port
    key: UDPPort
    type: int
    default: 16262
    help: "Secondary UDP port used by the server."
  - name: Reset ID
    key: ResetID
    type: int
    default: 6530796
    help: "Soft-reset identifier used to force clients to recreate characters if mismatched."
  - name: Mods
    key: Mods
    type: str
    default: ""
    help: "Mod loading ID or list; keep as string."
  - name: Map
    key: Map
    type: str
    default: "Muldraugh, KY"
    help: "Folder name of the map to load."
  - name: Do Lua Checksum
    key: DoLuaChecksum
    type: bool
    default: true
    help: "Kick clients whose game files don't match the server's."
  - name: Deny Login On Overloaded Server
    key: DenyLoginOnOverloadedServer
    type: bool
    default: true
    help: "Deny logins when server is overloaded."
  - name: Public Server
    key: Public
    type: bool
    default: false
    help: "Show the server on the in-game browser; Steam-enabled servers are always visible."
  - name: Public Name
    key: PublicName
    type: str
    default: "My PZ Server"
    help: "Name displayed in the server browser."
  - name: Public Description
    key: PublicDescription
    type: str
    default: ""
    help: "Description displayed in public server browser; use \n for newlines."
  - name: Max Players
    key: MaxPlayers
    type: int
    default: 32
    help: "Maximum number of players allowed on the server (excluding admins)."
  - name: Ping Limit
    key: PingLimit
    type: int
    default: 400
    help: "Ping limit in milliseconds before a player is kicked (100 disables)."
  - name: Hours For Loot Respawn
    key: HoursForLootRespawn
    type: int
    default: 0
    help: "Hours after which containers will respawn loot (0 disables)."
  - name: Max Items For Loot Respawn
    key: MaxItemsForLootRespawn
    type: int
    default: 4
    help: "Containers with this many items or more will not respawn."
  - name: Construction Prevents Loot Respawn
    key: ConstructionPreventsLootRespawn
    type: bool
    default: true
    help: "Items will not respawn in buildings that players have barricaded or built in."
  - name: Drop Off Whitelist After Death
    key: DropOffWhiteListAfterDeath
    type: bool
    default: false
    help: "Remove player accounts from whitelist after death (prevents new character creation)."
  - name: No Fire
    key: NoFire
    type: bool
    default: false
    help: "Disable all forms of fire except campfires."
  - name: Announce Death
    key: AnnounceDeath
    type: bool
    default: false
    help: "Display a global message when a player dies."
  - name: Minutes Per Page
    key: MinutesPerPage
    type: float
    default: 1.0
    help: "Number of in-game minutes to read one page."
  - name: Save World Every Minutes
    key: SaveWorldEveryMinutes
    type: int
    default: 0
    help: "Map save interval in real-world minutes (0 for disabled)."
  - name: Player Safehouse
    key: PlayerSafehouse
    type: bool
    default: false
    help: "Allow both admins and players to claim safehouses."
  - name: Admin Safehouse
    key: AdminSafehouse
    type: bool
    default: false
    help: "Only admins can claim safehouses."
  - name: Safehouse Allow Trespass
    key: SafehouseAllowTrepass
    type: bool
    default: true
    help: "Allow non-members to enter safehouses without invitation."
  - name: Safehouse Allow Fire
    key: SafehouseAllowFire
    type: bool
    default: true
    help: "Allow fire to damage safehouses."
  - name: Safehouse Allow Loot
    key: SafehouseAllowLoot
    type: bool
    default: true
    help: "Allow non-members to take items from safehouses."
  - name: Safehouse Allow Respawn
    key: SafehouseAllowRespawn
    type: bool
    default: false
    help: "Players will respawn in a safehouse they were a member of before dying."
  - name: Safehouse Day Survived To Claim
    key: SafehouseDaySurvivedToClaim
    type: int
    default: 0
    help: "Number of in-game days a player must survive before claiming a safehouse."
  - name: Safehouse Removal Time Hours
    key: SafeHouseRemovalTime
    type: int
    default: 144
    help: "Hours before inactive safehouses are automatically removed."
  - name: Safehouse Allow Non Residential
    key: SafehouseAllowNonResidential
    type: bool
    default: false
    help: "Allow players to claim non-residential buildings as safehouses."
  - name: Allow Destruction By Sledgehammer
    key: AllowDestructionBySledgehammer
    type: bool
    default: true
    help: "Allow players to destroy world objects with sledgehammers."
  - name: Sledgehammer Only In Safehouse
    key: SledgehammerOnlyInSafehouse
    type: bool
    default: false
    help: "Allow destruction by sledgehammer only inside safehouses."
  - name: Kick Fast Players
    key: KickFastPlayers
    type: bool
    default: false
    help: "Kick players moving faster than expected (may be buggy)."
  - name: Server Player ID
    key: ServerPlayerID
    type: int
    default: 1661794134
    help: "ServerPlayerID used to identify characters from this server."
  - name: RCON Port
    key: RCONPort
    type: int
    default: 27015
    help: "Port for the RCON (Remote Console)."
  - name: RCON Password
    key: RCONPassword
    type: str
    default: ""
    help: "RCON password (pick a strong password)."
  - name: Discord Enable
    key: DiscordEnable
    type: bool
    default: false
    help: "Enable global text chat integration with Discord."
  - name: Discord Token
    key: DiscordToken
    type: str
    default: ""
    help: "Discord bot access token."
  - name: Discord Channel
    key: DiscordChannel
    type: str
    default: ""
    help: "Discord channel name (use channel ID option if needed)."
  - name: Discord Channel ID
    key: DiscordChannelID
    type: str
    default: ""
    help: "Discord channel ID (alternative to channel name)."
  - name: Server Password
    key: Password
    type: str
    default: ""
    help: "Password clients must know to join the server (ignored for Host button)."
  - name: Max Accounts Per User
    key: MaxAccountsPerUser
    type: int
    default: 0
    help: "Limit on different accounts one Steam user may create (0 = unlimited)."
  - name: Allow Coop
    key: AllowCoop
    type: bool
    default: true
    help: "Allow co-op / splitscreen players."
  - name: Sleep Allowed
    key: SleepAllowed
    type: bool
    default: false
    help: "Players are allowed to sleep when tired (not required)."
  - name: Sleep Needed
    key: SleepNeeded
    type: bool
    default: false
    help: "Players get tired and need to sleep (ignored if SleepAllowed=false)."
  - name: Knocked Down Allowed
    key: KnockedDownAllowed
    type: bool
    default: true
    help: "Allow knocked down state."
  - name: Sneak Mode Hide From Other Players
    key: SneakModeHideFromOtherPlayers
    type: bool
    default: true
    help: "Hide sneaking players from others."
  - name: Workshop Items
    key: WorkshopItems
    type: str
    default: ""
    help: "Semicolon-separated list of Workshop Mod IDs; keep as string."
  - name: Steam Scoreboard
    key: SteamScoreboard
    type: str
    default: "true"
    help: "Show Steam usernames/avatars in players list; can be true/false/admin. Stored as string to preserve 'admin' option."
  - name: Steam VAC
    key: SteamVAC
    type: bool
    default: true
    help: "Enable Steam VAC system."
  - name: UPnP
    key: UPnP
    type: bool
    default: true
    help: "Attempt to configure UPnP port forwarding."
  - name: Voice Enable
    key: VoiceEnable
    type: bool
    default: true
    help: "Enable VOIP."
  - name: Voice Min Distance
    key: VoiceMinDistance
    type: float
    default: 10.0
    help: "Minimum tile distance over which VOIP can be heard."
  - name: Voice Max Distance
    key: VoiceMaxDistance
    type: float
    default: 100.0
    help: "Maximum tile distance over which VOIP can be heard."
  - name: Voice 3D
    key: Voice3D
    type: bool
    default: true
    help: "Toggle directional audio for VOIP."
  - name: Speed Limit
    key: SpeedLimit
    type: float
    default: 70.0
    help: "Speed limit configuration (game-specific)."
  - name: Login Queue Enabled
    key: LoginQueueEnabled
    type: bool
    default: false
    help: "Enable login queue feature."
  - name: Login Queue Connect Timeout
    key: LoginQueueConnectTimeout
    type: int
    default: 60
    help: "Timeout for login queue connections (seconds)."
  - name: Server Browser Announced IP
    key: server_browser_announced_ip
    type: str
    default: ""
    help: "IP address to broadcast for server browser (useful on multi-homed hosts)."
  - name: Player Respawn With Self
    key: PlayerRespawnWithSelf
    type: bool
    default: false
    help: "Players can respawn at the coordinates where they died."
  - name: Player Respawn With Other
    key: PlayerRespawnWithOther
    type: bool
    default: false
    help: "Players can respawn at a split-screen/Remote Play player's location."
  - name: Fast Forward Multiplier
    key: FastForwardMultiplier
    type: float
    default: 40.0
    help: "Multiplier for how fast time passes while players sleep."
  - name: Disable Safehouse When Player Connected
    key: DisableSafehouseWhenPlayerConnected
    type: bool
    default: false
    help: "Safehouse acts like a normal house if a member is connected."
  - name: Faction Enabled
    key: Faction
    type: bool
    default: true
    help: "Players can create factions when true."
  - name: Faction Day Survived To Create
    key: FactionDaySurvivedToCreate
    type: int
    default: 0
    help: "Days a player must survive before creating a faction."
  - name: Faction Players Required For Tag
    key: FactionPlayersRequiredForTag
    type: int
    default: 1
    help: "Number of players required before creating a faction tag."
  - name: Disable Radio Staff
    key: DisableRadioStaff
    type: bool
    default: false
    help: "Disable radio transmissions from staff-level access."
  - name: Disable Radio Admin
    key: DisableRadioAdmin
    type: bool
    default: true
    help: "Disable radio transmissions from admin-level access."
  - name: Disable Radio GM
    key: DisableRadioGM
    type: bool
    default: true
    help: "Disable radio transmissions from GM-level access."
  - name: Disable Radio Overseer
    key: DisableRadioOverseer
    type: bool
    default: false
    help: "Disable radio transmissions from overseer-level access."
  - name: Disable Radio Moderator
    key: DisableRadioModerator
    type: bool
    default: false
    help: "Disable radio transmissions from moderator-level access."
  - name: Disable Radio Invisible
    key: DisableRadioInvisible
    type: bool
    default: true
    help: "Disable radio transmissions from invisible players."
  - name: Client Command Filter
    key: ClientCommandFilter
    type: str
    default: "-vehicle.*;+vehicle.damageWindow;+vehicle.fixPart;+vehicle.installPart;+vehicle.uninstallPart"
    help: "Semicolon-separated filter for commands excluded/included in cmd.txt log; keep as string."
  - name: Client Action Logs
    key: ClientActionLogs
    type: str
    default: "ISEnterVehicle;ISExitVehicle;ISTakeEngineParts;"
    help: "Semicolon-separated list of actions written to ClientActionLogs.txt."
  - name: Perk Logs
    key: PerkLogs
    type: bool
    default: true
    help: "Track changes in player perk levels in PerkLog.txt."
  - name: Item Numbers Limit Per Container
    key: ItemNumbersLimitPerContainer
    type: int
    default: 0
    help: "Maximum number of items per container (0 = no limit)."
  - name: Blood Splat Lifespan Days
    key: BloodSplatLifespanDays
    type: int
    default: 0
    help: "Days before old blood splats are removed (0 = never)."
  - name: Allow Non ASCII Username
    key: AllowNonAsciiUsername
    type: bool
    default: false
    help: "Allow use of non-ASCII characters in usernames."
  - name: Ban Kick Global Sound
    key: BanKickGlobalSound
    type: bool
    default: true
    help: "Play a global sound for ban/kick events."
  - name: Remove Player Corpses On Corpse Removal
    key: RemovePlayerCorpsesOnCorpseRemoval
    type: bool
    default: false
    help: "Also remove player corpses when corpse removal triggers."
  - name: Trash Delete All
    key: TrashDeleteAll
    type: bool
    default: false
    help: "Allow players to use the 'delete all' button on bins."
  - name: PVP Melee While Hit Reaction
    key: PVPMeleeWhileHitReaction
    type: bool
    default: false
    help: "Allow players to hit again when struck by another player."
  - name: Mouse Over To See Display Name
    key: MouseOverToSeeDisplayName
    type: bool
    default: true
    help: "Require mouse-over to see player's display name."
  - name: Hide Players Behind You
    key: HidePlayersBehindYou
    type: bool
    default: true
    help: "Automatically hide players you can't see (e.g., behind you)."
  - name: PVP Melee Damage Modifier
    key: PVPMeleeDamageModifier
    type: float
    default: 30.0
    help: "Damage multiplier for PVP melee attacks."
  - name: PVP Firearm Damage Modifier
    key: PVPFirearmDamageModifier
    type: float
    default: 50.0
    help: "Damage multiplier for PVP ranged attacks."
  - name: Car Engine Attraction Modifier
    key: CarEngineAttractionModifier
    type: float
    default: 0.5
    help: "Modify the range of zombie attraction to cars; lower values reduce lag."
  - name: Player Bump Player
    key: PlayerBumpPlayer
    type: bool
    default: false
    help: "Whether players can bump and knock over other players when running through them."
  - name: Map Remote Player Visibility
    key: MapRemotePlayerVisibility
    type: int
    default: 1
    help: "Controls display of remote players on the map (1=Hidden,2=Friends,3=Everyone)."
  - name: Backups Count
    key: BackupsCount
    type: int
    default: 5
    help: "Minimum backups to keep."
  - name: Backups On Start
    key: BackupsOnStart
    type: bool
    default: true
    help: "Create a backup when the server starts."
  - name: Backups On Version Change
    key: BackupsOnVersionChange
    type: bool
    default: true
    help: "Create a backup when the server version changes."
  - name: Backups Period
    key: BackupsPeriod
    type: int
    default: 0
    help: "Periodic backup interval (in minutes); 0 disables periodic backups."
  - name: AntiCheat Protection Type 1
    key: AntiCheatProtectionType1
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 1."
  - name: AntiCheat Protection Type 2
    key: AntiCheatProtectionType2
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 2."
  - name: AntiCheat Protection Type 3
    key: AntiCheatProtectionType3
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 3."
  - name: AntiCheat Protection Type 4
    key: AntiCheatProtectionType4
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 4."
  - name: AntiCheat Protection Type 5
    key: AntiCheatProtectionType5
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 5."
  - name: AntiCheat Protection Type 6
    key: AntiCheatProtectionType6
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 6."
  - name: AntiCheat Protection Type 7
    key: AntiCheatProtectionType7
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 7."
  - name: AntiCheat Protection Type 8
    key: AntiCheatProtectionType8
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 8."
  - name: AntiCheat Protection Type 9
    key: AntiCheatProtectionType9
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 9."
  - name: AntiCheat Protection Type 10
    key: AntiCheatProtectionType10
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 10."
  - name: AntiCheat Protection Type 11
    key: AntiCheatProtectionType11
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 11."
  - name: AntiCheat Protection Type 12
    key: AntiCheatProtectionType12
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 12."
  - name: AntiCheat Protection Type 13
    key: AntiCheatProtectionType13
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 13."
  - name: AntiCheat Protection Type 14
    key: AntiCheatProtectionType14
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 14."
  - name: AntiCheat Protection Type 15
    key: AntiCheatProtectionType15
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 15."
  - name: AntiCheat Protection Type 16
    key: AntiCheatProtectionType16
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 16."
  - name: AntiCheat Protection Type 17
    key: AntiCheatProtectionType17
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 17."
  - name: AntiCheat Protection Type 18
    key: AntiCheatProtectionType18
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 18."
  - name: AntiCheat Protection Type 19
    key: AntiCheatProtectionType19
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 19."
  - name: AntiCheat Protection Type 20
    key: AntiCheatProtectionType20
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 20."
  - name: AntiCheat Protection Type 21
    key: AntiCheatProtectionType21
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 21."
  - name: AntiCheat Protection Type 22
    key: AntiCheatProtectionType22
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 22."
  - name: AntiCheat Protection Type 23
    key: AntiCheatProtectionType23
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 23."
  - name: AntiCheat Protection Type 24
    key: AntiCheatProtectionType24
    type: bool
    default: true
    help: "Disable/enable anti-cheat protection type 24."
  - name: AntiCheat Type 2 Threshold Multiplier
    key: AntiCheatProtectionType2ThresholdMultiplier
    type: float
    default: 3.0
    help: "Threshold multiplier for anti-cheat protection type 2."
  - name: AntiCheat Type 3 Threshold Multiplier
    key: AntiCheatProtectionType3ThresholdMultiplier
    type: float
    default: 1.0
    help: "Threshold multiplier for anti-cheat protection type 3."
  - name: AntiCheat Type 4 Threshold Multiplier
    key: AntiCheatProtectionType4ThresholdMultiplier
    type: float
    default: 1.0
    help: "Threshold multiplier for anti-cheat protection type 4."
  - name: AntiCheat Type 9 Threshold Multiplier
    key: AntiCheatProtectionType9ThresholdMultiplier
    type: float
    default: 1.0
    help: "Threshold multiplier for anti-cheat protection type 9."
  - name: AntiCheat Type 15 Threshold Multiplier
    key: AntiCheatProtectionType15ThresholdMultiplier
    type: float
    default: 1.0
    help: "Threshold multiplier for anti-cheat protection type 15."
  - name: AntiCheat Type 20 Threshold Multiplier
    key: AntiCheatProtectionType20ThresholdMultiplier
    type: float
    default: 1.0
    help: "Threshold multiplier for anti-cheat protection type 20."
  - name: AntiCheat Type 22 Threshold Multiplier
    key: AntiCheatProtectionType22ThresholdMultiplier
    type: float
    default: 1.0
    help: "Threshold multiplier for anti-cheat protection type 22."
  - name: AntiCheat Type 24 Threshold Multiplier
    key: AntiCheatProtectionType24ThresholdMultiplier
    type: float
    default: 6.0
    help: "Threshold multiplier for anti-cheat protection type 24."
EOF
	chown $GAME_USER:$GAME_USER "$GAME_DIR/configs.yaml"

	# Most games use .settings.ini for manager settings
	touch "$GAME_DIR/.settings.ini"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.settings.ini"

	# If a pyenv is required:
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install pyyaml
}

##
# Get the operating system version
#
# Just the major version number is returned
#
function os_version() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		local _V="$(uname -K)"
		if [ ${#_V} -eq 6 ]; then
			echo "${_V:0:1}"
		elif [ ${#_V} -eq 7 ]; then
			echo "${_V:0:2}"
		fi

	elif [ -f '/etc/os-release' ]; then
		local VERS="$(egrep '^VERSION_ID=' /etc/os-release | sed 's:VERSION_ID=::')"

		if [[ "$VERS" =~ '"' ]]; then
			# Strip quotes around the OS name
			VERS="$(echo "$VERS" | sed 's:"::g')"
		fi

		if [[ "$VERS" =~ \. ]]; then
			# Remove the decimal point and everything after
			# Trims "24.04" down to "24"
			VERS="${VERS/\.*/}"
		fi

		if [[ "$VERS" =~ "v" ]]; then
			# Remove the "v" from the version
			# Trims "v24" down to "24"
			VERS="${VERS/v/}"
		fi

		echo "$VERS"

	else
		echo 0
	fi
}

##
# Install SteamCMD
function install_steamcmd() {
	echo "Installing SteamCMD..."

	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_UBUNTU="$(os_like_ubuntu)"
	OS_VERSION="$(os_version)"

	# Preliminary requirements
	if [ "$TYPE_UBUNTU" == 1 ]; then
		add-apt-repository -y multiverse
		dpkg --add-architecture i386
		apt update

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		apt install -y steamcmd
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		dpkg --add-architecture i386
		apt update

		if [ "$OS_VERSION" -le 12 ]; then
			apt install -y software-properties-common apt-transport-https dirmngr ca-certificates lib32gcc-s1

			# Enable "non-free" repos for Debian (for steamcmd)
			# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
			add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free
			if [ $? -ne 0 ]; then
				echo "Workaround failed to add non-free repos, trying new method instead"
				apt-add-repository -y non-free
			fi
		else
			# Debian Trixie and later
			if [ -e /etc/apt/sources.list ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list
				fi
			elif [ -e /etc/apt/sources.list.d/debian.sources ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list.d/debian.sources; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list.d/debian.sources
				fi
			else
				echo "Could not find a sources.list file to enable non-free repos" >&2
				exit 1
			fi
		fi

		# Install steam repo
		download http://repo.steampowered.com/steam/archive/stable/steam.gpg /usr/share/keyrings/steam.gpg
		echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		# Install steam binary and steamcmd
		apt update
		apt install -y steamcmd
	else
		echo 'Unsupported or unknown OS' >&2
		exit 1
	fi
}

print_header "$GAME_DESC *unofficial* Installer ${INSTALLER_VERSION}"

############################################
## Installer Actions
############################################

##
# Install the game server
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#   STEAM_ID     - Steam App ID of the game
#   GAME_DESC    - Description of the game (for logging purposes)
#   GAME_SERVICE - Service name to install with Systemd
#   SAVE_DIR     - Directory to store game save files
#
function install_application() {
	print_header "Performing install_application"

	# Create the game user account
	# This will create the account with no password, so if you need to log in with this user,
	# run `sudo passwd $GAME_USER` to set a password.
	if [ -z "$(getent passwd $GAME_USER)" ]; then
		useradd -m -U $GAME_USER
	fi

	# Preliminary requirements
	package_install curl sudo python3-venv

	if [ "$FIREWALL" == "1" ]; then
		if [ "$(get_enabled_firewall)" == "none" ]; then
			# No firewall installed, go ahead and install UFW
			install_ufw
		fi
	fi

	[ -e "$GAME_DIR/AppFiles" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles"

	install_steamcmd
	
	# Install the management script
	install_warlock_manager "$REPO" "$INSTALLER_VERSION"
	sudo -u $GAME_USER $GAME_DIR/.venv/bin/pip install rcon
	
	# Use the management script to install the game server
	if ! $GAME_DIR/manage.py --update; then
		echo "Could not install $GAME_DESC, exiting" >&2
		exit 1
	fi
	
	# If you need to configure the firewall for this game service here,
	# ensure you include the following header
	# Ideally the management script should handle this if possible to provide the operator with an easy way to change the port.
	#  # scriptlet:_common/firewall_allow.sh
	# and then run
	# firewall_allow --port ${PORT} --udp --comment "${GAME_DESC} Game Port"

	# Install system service file to be loaded by systemd
    cat > /etc/systemd/system/${GAME_SERVICE}.service <<EOF
[Unit]
# DYNAMICALLY GENERATED FILE! Edit at your own risk
Description=$GAME_DESC
After=network.target

[Service]
Type=simple
LimitNOFILE=10000
User=$GAME_USER
Group=$GAME_USER
Sockets=zomboid.socket
StandardInput=socket
StandardOutput=journal
StandardError=journal
WorkingDirectory=${GAME_DIR}/AppFiles
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $GAME_USER)
Environment=PATH="${GAME_DIR}/AppFiles/jre64/bin:/usr/bin:/bin"
Environment=LD_LIBRARY_PATH="${GAME_DIR}/AppFiles/linux64:${GAME_DIR}/AppFiles/natives:${GAME_DIR}/AppFiles:${GAME_DIR}/AppFiles/jre64/lib/server"
Environment=LD_PRELOAD="libjsig.so"
# Only required for games which utilize Proton
#Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_DIR"
ExecStart=$GAME_DIR/AppFiles/ProjectZomboid64
ExecStop=$GAME_DIR/manage.py --pre-stop --service ${GAME_SERVICE}
ExecStartPost=$GAME_DIR/manage.py --post-start --service ${GAME_SERVICE}
Restart=on-failure
RestartSec=1800s
TimeoutStartSec=600s

[Install]
WantedBy=multi-user.target
EOF
	cat > /etc/systemd/system/${GAME_SERVICE}.socket <<EOF
[Unit]
# DYNAMICALLY GENERATED FILE! Edit at your own risk
BindsTo=zomboid.service

[Socket]
ListenFIFO=/var/run/$GAME_SERVICE.socket
Service=$GAME_SERVICE.service
RemoveOnStop=true
SocketMode=0660
SocketUser=$GAME_USER
EOF
    systemctl daemon-reload

	if [ -n "$WARLOCK_GUID" ]; then
		# Register Warlock
		[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
		echo -n "$GAME_DIR" > "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

function postinstall() {
	print_header "Performing postinstall"

	# First run setup
	$GAME_DIR/manage.py --first-run
}

##
# Uninstall the game server
#
# Expects the following variables:
#   GAME_DIR     - Directory where the game is installed
#   GAME_SERVICE - Service name used with Systemd
#   SAVE_DIR     - Directory where game save files are stored
#
function uninstall_application() {
	print_header "Performing uninstall_application"

	systemctl disable $GAME_SERVICE
	systemctl stop $GAME_SERVICE

	# Service files
	[ -e "/etc/systemd/system/${GAME_SERVICE}.service" ] && rm "/etc/systemd/system/${GAME_SERVICE}.service"

	# Game files
	[ -d "$GAME_DIR" ] && rm -rf "$GAME_DIR/AppFiles"

	# Management scripts
	[ -e "$GAME_DIR/manage.py" ] && rm "$GAME_DIR/manage.py"
	[ -e "$GAME_DIR/configs.yaml" ] && rm "$GAME_DIR/configs.yaml"
	[ -d "$GAME_DIR/.venv" ] && rm -rf "$GAME_DIR/.venv"

	if [ -n "$WARLOCK_GUID" ]; then
		# unregister Warlock
		[ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] && rm "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

############################################
## Pre-exec Checks
############################################

if [ $MODE_UNINSTALL -eq 1 ]; then
	MODE="uninstall"
else
	# Default to install mode
	MODE="install"
fi


if systemctl -q is-active $GAME_SERVICE; then
	echo "$GAME_DESC service is currently running, please stop it before running this installer."
	echo "You can do this with: sudo systemctl stop $GAME_SERVICE"
	exit 1
fi

if [ -n "$OVERRIDE_DIR" ]; then
	# User requested to change the install dir!
	# This changes the GAME_DIR from the default location to wherever the user requested.
	if [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] ; then
		# Check for existing installation directory based on Warlock registration
		GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
		if [ "$GAME_DIR" != "$OVERRIDE_DIR" ]; then
			echo "ERROR: $GAME_DESC already installed in $GAME_DIR, cannot override to $OVERRIDE_DIR" >&2
			echo "If you want to move the installation, please uninstall first and then re-install to the new location." >&2
			exit 1
		fi
	fi

	GAME_DIR="$OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ]; then
	# Check for existing installation directory based on service file
	GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
fi

if [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
	EXISTING=1
else
	EXISTING=0
fi

############################################
## Installer
############################################


if [ "$MODE" == "install" ]; then

	if [ $SKIP_FIREWALL -eq 1 ]; then
		FIREWALL=0
	elif [ $EXISTING -eq 0 ] && prompt_yn -q --default-yes "Install system firewall?"; then
		FIREWALL=1
	else
		FIREWALL=0
	fi

	install_application

	postinstall

	# Print some instructions and useful tips
    print_header "$GAME_DESC Installation Complete"
fi

if [ "$MODE" == "uninstall" ]; then
	if [ $NONINTERACTIVE -eq 0 ]; then
		if prompt_yn -q --invert --default-no "This will remove all game binary content"; then
			exit 1
		fi
		if prompt_yn -q --invert --default-no "This will remove all player and map data"; then
			exit 1
		fi
	fi

	if prompt_yn -q --default-yes "Perform a backup before everything is wiped?"; then
		$GAME_DIR/manage.py --backup
	fi

	uninstall_application
fi
