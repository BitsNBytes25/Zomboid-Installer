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
import logging
import random
import string
from warlock_manager.apps.steam_app import SteamApp
from warlock_manager.services.socket_service import SocketService
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs import utils
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


class GameApp(SteamApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Zomboid'
		self.desc = 'Project Zomboid'
		self.service_handler = GameService
		self.steam_id = '380870'
		self.service_prefix = 'zomboid-'
		self.disabled_features = {'create_service'}

		self.configs = {
			'manager': INIConfig('manager', os.path.join(utils.get_app_directory(), '.settings.ini'))
		}
		self.load()

		self.steam_branch = self.get_option_value('Steam Branch')

	def first_run(self) -> bool:
		"""
		Perform any first-run configuration needed for this game

		:return:
		"""
		if os.geteuid() != 0:
			logging.error('Please run this script with sudo to perform first-run configuration.')
			return False

		super().first_run()

		# Install the game with Steam.
		# It's a good idea to ensure the game is installed on first run.
		self.update()

		utils.makedirs(os.path.join(utils.get_app_directory(), 'mods'))

		# First run is a great time to auto-create some services for this game too
		services = self.get_services()
		if len(services) == 0:
			# No services detected, create one.
			logging.info('No services detected, creating one...')
			self.create_service('zomboid-server')
		else:
			logging.info('Detected %d services, skipping first-run service creation.' % len(services))

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

	def get_option_options(self, option: str) -> list:
		"""
		Get the list of possible options for a configuration option
		:param option:
		:return:
		"""

		if option == 'Steam Branch':
			return self.get_steam_branches()
		else:
			return super().get_option_options(option)


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
			'zomboid': PropertiesConfig('zomboid', os.path.join(self.get_app_directory(), 'Server/servertest.ini'))
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
			'PATH': f'${game_dir}/jre64/bin:/usr/bin:/bin',
			'LD_LIBRARY_PATH': ':'.join(include_paths),
			'LD_PRELOAD': 'libjsig.so'
		}


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
					command = cmd[:cmd.find(' : ')]
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
		:return:
		"""
		return [
			('Default Port', 'udp', '%s data port' % self.game.desc),
			('UDP Port', 'udp', '%s game port' % self.game.desc),
			('RCON Port', 'tcp', '%s RCON port' % self.game.desc)
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

		logging.debug('Checking for first-run password prompt...')
		password_asked = False

		def watch1(line):
			nonlocal random_password
			nonlocal password_asked
			if 'Initialising Server Systems' in line:
				# Generally indicates the server has started and is in the final steps of loading.
				logging.debug('Server initialization started, dropping out of password check')
				return False
			if 'Enter new administrator password:' in line:
				# Password asked in the terminal; send it via cmd
				password_asked = True
				logging.debug('Server asked for password once!  Sending password.')
				self.write_socket(random_password)
				return False


		def watch2(line):
			nonlocal random_password
			if 'Initialising Server Systems' in line:
				# Generally indicates the server has started and is in the final steps of loading.
				logging.debug('Server initialization started, dropping out of password check')
				return False
			if 'Confirm the password:' in line:
				# Password confirmation asked in the terminal; send it via cmd
				logging.debug('Server asked for password twice')
				self.write_socket(random_password)
				return False

		self.watch(watch1, 60)
		if password_asked:
			self.watch(watch2)

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


if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
