#!/usr/bin/env python3
import os
import sys
# Include the virtual environment site-packages in sys.path
here = os.path.dirname(os.path.realpath(__file__))
if not os.path.exists(os.path.join(here, '.venv')):
	print('Python environment not setup')
	exit(1)
sys.path.insert(
	0,
	os.path.join(
		here,
		'.venv',
		'lib',
		'python' + '.'.join(sys.version.split('.')[:2]), 'site-packages'
	)
)
import random
import string
from warlock_manager.apps.steam_app import SteamApp
from warlock_manager.services.socket_service import SocketService
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.logger import logger
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs import utils
from warlock_manager.mods.warlock_nexus_mod import WarlockNexusMod
# To allow running as a standalone script without installing the package, include the venv path for imports.
# This will set the include path for this path to .venv to allow packages installed therein to be utilized.
#
# IMPORTANT - any imports that are needed for the script to run must be after this,
# otherwise the imports will fail when running as a standalone script.


# Import the appropriate type of handler for the game installer.
# Common options are:
# from warlock_manager.apps.base_app import BaseApp

# Import the appropriate type of handler for the game services.
# Common options are:
# from warlock_manager.services.base_service import BaseService
# from warlock_manager.services.rcon_service import RCONService
# from warlock_manager.services.http_service import HTTPService

# Import the various configuration handlers used by this game.
# Common options are:
# from warlock_manager.config.cli_config import CLIConfig
# from warlock_manager.config.json_config import JSONConfig
# from warlock_manager.config.unreal_config import UnrealConfig

# Load the application runner responsible for interfacing with CLI arguments
# and providing default functionality for running the manager.

# If your script manages the firewall, (recommended), import the Firewall library

# Utilities provided by Warlock that are common to many applications

# Select the baseline for mod support
# from warlock_manager.mods.base_mod import BaseMod


class GameMod(WarlockNexusMod):
	def __init__(self):
		super().__init__()

		self.workshop_id : int | None = None
		"""
		Steam Workshop ID of this mod, only applicable after explode has been called.
		"""

	def to_dict(self) -> dict:
		"""
		Returns a dict representation of the mod.
		"""
		ret = super().to_dict()
		# Add objects from this override
		ret['workshop_id'] = self.workshop_id
		return ret

	def explode_mods(self) -> 'list[GameMod]':
		"""
		Project Zomboid workshop items have their Mod ID listed in the description of the mod.
		This allows a mod developer to have a single mod with multiple functions.

		Explode the primary Steam mod into separate mod functions, which individually can be installed.
		:return:
		"""

		ret = []
		# Sometimes a description contains the mod name multiple times.
		mods = []
		maps = []
		for line in self.description.split('\n'):
			line = line.strip()
			if line.startswith('Mod ID: '):
				# Mod ID: 1234567890
				clone = GameMod.from_dict(self.to_dict())
				clone.workshop_id = int(self.id)
				k = line[8:]
				if k.startswith('\\'):
					# Mods in 42+ technically require a backslash, but we can skip it here.
					k = k[1:]
				clone.id = 'mod:' + k
				if k not in mods:
					mods.append(k)
					ret.append(clone)
			elif line.startswith('Map Folder: '):
				# Map Folder: Some Map 123
				clone = GameMod.from_dict(self.to_dict())
				clone.workshop_id = int(self.id)
				k = line[12:]
				clone.id = 'map:' + k
				if k not in maps:
					maps.append(k)
					ret.append(clone)

		return ret

	@classmethod
	def get_mod(cls, source: 'BaseService', provider: str | None, mod_id: str | int) -> 'GameMod | None':
		"""
		Get a specific mod by ID, must be a sponsor to use this.

		:param source:   Source game service to use for reference
		:param provider: Mod provider, e.g. 'curseforge'
		:param mod_id:   Mod ID
		:return:
		"""
		# In this game, a mod requested by a string indicates it's already resolved locally.
		# an int means it's coming directly from Steam.
		if isinstance(mod_id, int) or (isinstance(mod_id, str) and mod_id.isdigit()):
			return super().get_mod(source, provider, mod_id)
		else:
			# Search through local mods
			mods = cls.get_registered_mods()
			for mod in mods:
				if mod.id == mod_id and mod.provider is None:
					return mod
			return None

class GameApp(SteamApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Zomboid'
		self.desc = 'Project Zomboid'
		self.service_handler = GameService
		self.mod_handler = GameMod
		self.steam_id = '380870'
		self.service_prefix = 'zomboid-'
		self.disabled_features = {'create_service'}

		self.configs = {
			'manager': INIConfig('manager', os.path.join(utils.get_base_directory(), '.settings.ini'))
		}
		self.load()

	def first_run(self) -> bool:
		"""
		Perform any first-run configuration needed for this game

		:return:
		"""
		if os.geteuid() != 0:
			logger.error('Please run this script with sudo to perform first-run configuration.')
			return False

		super().first_run()

		# Install the game with Steam.
		# It's a good idea to ensure the game is installed on first run.
		self.update()

		utils.makedirs(os.path.join(utils.get_base_directory(), 'mods'))

		# First run is a great time to auto-create some services for this game too
		services = self.get_services()
		if len(services) == 0:
			# No services detected, create one.
			logger.info('No services detected, creating one...')
			self.create_service('zomboid-server')
		else:
			for service in services:
				logger.info('Ensuring %s service file is on latest format' % service.service)
				service.build_systemd_config()
				service.reload()

		return True

	def check_update_available(self) -> bool:
		"""
		Check if a SteamCMD update is available for this game

		:return:
		"""
		game_update = super().check_update_available()
		if game_update:
			# There's a Steam update available, no need to check further.
			return game_update

		for svc in self.get_services():
			# Check for mod updates via Steam Workshop
			if svc.check_mod_updates():
				return True

		return False


class GameService(SocketService):
	"""
	Service definition and handler
	"""
	def __init__(self, service: str, game: GameApp):
		"""
		Initialize and load the service definition
		:param file:
		"""
		super().__init__(service, game)
		self.configs = {
			'zomboid': PropertiesConfig('zomboid', os.path.join(utils.get_home_directory(), 'Zomboid/Server/servertest.ini'))
		}
		self.load()

	def get_executable(self) -> str:
		"""
		Get the full executable for this game service
		:return:
		"""
		return self.get_app_directory() + '/ProjectZomboid64'

	def get_environment(self) -> dict:
		"""
		Get the environment variables for this service as a dictionary

		:return:
		"""
		game_dir = self.get_app_directory()
		include_paths = [
			game_dir + '/linux64',
			game_dir + '/natives',
			game_dir + '/jre64/lib/server'
		]

		return {
			'XDG_RUNTIME_DIR': '/run/user/%s' % utils.get_app_uid(),
			'PATH': f'{game_dir}/jre64/bin:/usr/bin:/bin',
			'LD_LIBRARY_PATH': ':'.join(include_paths),
			'LD_PRELOAD': 'libjsig.so'
		}

	def get_save_directory(self) -> str:
		"""
		Get the parent directory that contains the Save files for this game

		Zomboid saves are stored in the user's home directory

		:return:
		"""
		return os.path.join(utils.get_home_directory(), 'Zomboid')


	def get_save_files(self) -> list | None:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		return [
			'db',
			'Saves',
			'Server/servertest_SandboxVars.lua',
			'Server/servertest_spawnpoints.lua',
			'Server/servertest_spawnregions.lua'
		]

	def get_commands(self) -> None | list[str]:
		"""
		Get a list of available commands for this service

		:return:
		"""
		in_cmd = False
		commands = []
		def watch(line):
			nonlocal in_cmd
			if 'List of server commands' in line:
				in_cmd = True
				return True
			if in_cmd and ': * ' in line:
				cmd = line[line.find(': * ')+3:]
				if ' : ' in cmd:
					command = cmd[:cmd.find(' : ')].strip()
					help = cmd[cmd.find(' : ')+3:]
					commands.append({'cmd': command, 'help': help})
				else:
					commands.append(cmd)
				return True

		self.cmd('help')
		self.watch(watch)
		return commands

	def option_value_updated(self, option: str, previous_value, new_value):
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""

		# Special option actions
		if option == 'Default Port':
			# Update firewall for game port change
			if previous_value:
				Firewall.remove(int(previous_value), 'tcp')
			Firewall.allow(int(new_value), 'udp', '%s data port' % self.game.desc)
		elif option == 'UDP Port':
			# Update firewall for game port change
			if previous_value:
				Firewall.remove(int(previous_value), 'udp')
			Firewall.allow(int(new_value), 'udp', '%s game port' % self.game.desc)

	def get_players(self) -> list | None:
		"""
		Get a list of current players on the server, or None if the API is unavailable
		:return:
		"""

		# Expected output:
		# Mar 20 17:41:04 linuxgames ProjectZomboid64[2742986]: LOG  : General      f:128, t:1774028464881, st:9,504,883,591> Players connected (1):
		# Mar 20 17:41:04 linuxgames ProjectZomboid64[2742986]: -admin
		self.cmd('players')
		players = []
		start_players = False
		def watch(line):
			nonlocal start_players
			nonlocal players
			if 'Players connected' in line:
				start_players = True
				return True
			if start_players and ': -' in line:
				players.append({'player_name': line[line.find(': -')+3:]})
				return True
		self.watch(watch)

		return players if start_players else None

	def get_player_max(self) -> int:
		"""
		Get the maximum player count allowed on the server
		:return:
		"""
		return self.get_option_value('Max Players')

	def get_name(self) -> str:
		"""
		Get the name of this game server instance
		:return:
		"""
		return self.get_option_value('Public Name')

	def get_port(self) -> int | None:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		return self.get_option_value('Default Port')

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""

		# For services that do not have a helper wrapper, it's the same as the process PID
		return self.get_pid()

	def send_message(self, message: str):
		"""
		Send a message to all players via the game API
		:param message:
		:return:
		"""
		self.cmd('servermsg "%s"' % message.replace('"', "'"))

	def save_world(self):
		"""
		Force the game server to save the world via the game API
		:return:
		"""
		self.cmd('save')

	def get_port_definitions(self) -> list:
		"""
		Get a list of port definitions for this service

		Each entry in the returned list should contain 3 or 4 items:

		* Config name or integer of port (for non-definable ports)
		* 'UDP' or 'TCP' to indicate protocol
		* Short description of the port purpose
		* Optional boolean to indicate if this is an optional port (ie: not checked at startup)

		Example:

		```python
		return [
			('Game Port', 'UDP', 'Primary game port for clients to connect to', False),
			(25565, 'TCP', 'RCON port, statically assigned and cannot be changed', True)
		]
		```

		:return:
		"""
		return [
			('Default Port', 'udp', '%s data port' % self.game.desc),
			('UDP Port', 'udp', '%s game port' % self.game.desc),
			('RCON Port', 'tcp', '%s RCON port' % self.game.desc, True)
		]

	def post_start(self) -> bool:
		# Start the service for the first time to generate default config files
		# and to let the server prompt for the first run options.
		#
		# The server prompts for admin password on first run
		if os.path.exists(os.path.join(self.get_app_directory(), 'admin.passwd')):
			with open(os.path.join(self.get_app_directory(), 'admin.passwd'), 'r') as f:
				random_password = f.read().strip()
		else:
			random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
			with open(os.path.join(self.get_app_directory(), 'admin.passwd'), 'w') as f:
				f.write(random_password)
			utils.ensure_file_ownership(os.path.join(self.get_app_directory(), 'admin.passwd'))

		logger.debug('Checking for first-run password prompt...')
		password_asked1 = False
		password_asked2 = False

		def watch1(line):
			nonlocal random_password
			nonlocal password_asked1
			if 'Initialising Server Systems' in line:
				# Generally indicates the server has started and is in the final steps of loading.
				logger.debug('Server initialization started, dropping out of password check')
				return False
			if 'Enter new administrator password:' in line:
				# Password asked in the terminal; send it via cmd
				password_asked1 = True
				logger.debug('Server asked for password once!  Sending password.')
				self.write_socket(random_password)
				return False


		def watch2(line):
			nonlocal random_password
			nonlocal password_asked2
			if 'Initialising Server Systems' in line:
				# Generally indicates the server has started and is in the final steps of loading.
				logger.debug('Server initialization started, dropping out of password check')
				return False
			if 'Confirm the password:' in line:
				# Password confirmation asked in the terminal; send it via cmd
				password_asked2 = True
				logger.debug('Server asked for password twice')
				self.write_socket(random_password)
				return False

		self.watch(watch1, 60)
		if password_asked1:
			self.watch(watch2)

		if password_asked1:
			if password_asked2:
				logger.info('First-run password prompt completed successfully')
			else:
				logger.error('First-run password prompt failed!')
				return False
		else:
			logger.info('First-run password prompt not detected, continuing with startup')

		return super().post_start()

	def check_mod_updates(self) -> bool:
		"""
		Check for mod updates via the Steam Workshop
		:return:
		"""

		opt = self.get_option_value('Mod Workshop IDs')
		if opt == '' or opt is None:
			# If there are no mods installed, nothing to check.
			return False

		update_needed = False


		def watch(line):
			nonlocal update_needed
			if 'CheckModsNeedUpdate: Mods need update' in line:
				update_needed = True
				return False
			if 'CheckModsNeedUpdate: Mods updated' in line:
				return False

		# Ask the server via RCON if there are mods that need updating
		self.cmd('checkModsNeedUpdate')
		self.watch(watch)
		return update_needed

	def get_enabled_mods(self) -> list[GameMod]:
		"""
		Get all enabled mods that are locally available on this service

		:return:
		"""

		# This game stores enabled mod IDs in WorkshopItems (which is mapped to Mod Workshop IDs)
		# but the actual lookups should be done from Mod Names (Mods) and Mod Maps (Map).
		# First, lookup the Steam ID of the mod so we have the necessary metadata.
		workshop_ids = self.get_option_value('Mod Workshop IDs')
		if workshop_ids == '' or workshop_ids is None:
			return []
		raw_mods = []
		workshop_ids = workshop_ids.split(';')
		for workshop_id in workshop_ids:
			mod = GameMod.get_mod(self, 'steam', int(workshop_id))
			if mod is None:
				logger.warning('Could not find mod with workshop ID %s' % workshop_id)
				continue
			else:
				for sub_mod in mod.explode_mods():
					raw_mods.append(sub_mod)
		# raw_mods now contains all the available Mod Names and Map Names across workshop items installed

		ret = []
		opt = self.get_option_value('Mod Names')
		if opt != '' and opt is not None:
			names = opt.split(';')
			for mod_name in names:
				if mod_name == '':
					continue
				if mod_name.startswith('\\'):
					# This is probable, but not required here
					mod_name = mod_name[1:]
				for raw_mod in raw_mods:
					if raw_mod.id == 'mod:' + mod_name:
						ret.append(raw_mod)

		opt = self.get_option_value('Mod Maps')
		if opt != '' and opt is not None:
			maps = opt.split(';')
			for map_name in maps:
				if map_name == 'Muldraugh, KY':
					# This is the vanilla map.
					continue
				for raw_mod in raw_mods:
					if raw_mod.id == 'map:' + map_name:
						ret.append(raw_mod)
		return ret

	def rebuild_mods(self, mods: 'list[GameMod]'):
		"""
		Rebuild the configuration options based on the incoming mods list.

		:param mods:
		:return:
		"""
		current_maps = self.get_option_value('Mod Maps').split(';')
		use_default_map = 'Muldraugh, KY' in current_maps

		new_mods = []
		new_ids = []
		new_maps = []
		for mod in mods:
			mod.register()
			mod_type = mod.id[0:3]
			mod_key = mod.id[4:]
			workshop_id = str(mod.workshop_id)

			if mod_type == 'mod' and not mod_key.startswith('\\'):
				# B42+ requires mods to start with a backslash.
				mod_key = '\\' + mod_key

			if mod_type == 'map' and mod_key not in new_maps:
				# This is a map; add it to the list of maps to install.
				new_maps.append(mod_key)

			if mod_type == 'mod' and mod_key not in new_mods:
				# This is a mod; add it to the list of mods to install.
				new_mods.append(mod_key)

			if workshop_id not in new_ids:
				# Every mod will have a Workshop ID, (which may be duplicated if a mod has multiple mods)
				new_ids.append(workshop_id)

		if use_default_map:
			new_maps.append('Muldraugh, KY')

		# Save everything back to the game config.
		self.set_option('Mod Names', ';'.join(new_mods))
		self.set_option('Mod Workshop IDs', ';'.join(new_ids))
		self.set_option('Mod Maps', ';'.join(new_maps))

	def add_mod(self, mod: 'GameMod', force: bool = False) -> bool:
		"""
		Install a mod

		:param mod: Mod to install
		:param force: Force the installation even if the mod is already installed
		:return:
		"""
		# Split the incoming mod into its sub_mod parts
		mods = mod.explode_mods()
		enabled_mods = self.get_enabled_mods()

		# Append the incoming mods to the list of enabled mods, the parser will handle duplicates.
		self.rebuild_mods(enabled_mods + mods)
		return True

	def remove_mod(self, mod: 'GameMod') -> bool:
		"""
		Remove a mod

		Will completely uninstall the requested mod

		:param mod:
		:return:
		"""
		new_mods = []
		enabled_mods = self.get_enabled_mods()
		for enabled_mod in enabled_mods:
			if isinstance(mod.id, int) or (isinstance(mod.id, str) and mod.id.isdigit()):
				# Incoming mod to remove is a Steam mod; it may match multiple PZ mods
				if enabled_mod.workshop_id != mod.id:
					new_mods.append(enabled_mod)
			else:
				# Incoming mod is a single PZ mod.
				if enabled_mod.id != mod.id:
					new_mods.append(enabled_mod)
		self.rebuild_mods(new_mods)
		return True


if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
