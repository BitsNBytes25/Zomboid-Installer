#!/usr/bin/env python3
import pwd
import random
import string
from scriptlets._common.firewall_allow import *
from scriptlets._common.firewall_remove import *
from scriptlets.bz_eval_tui.prompt_yn import *
from scriptlets.bz_eval_tui.prompt_text import *
from scriptlets.bz_eval_tui.table import *
from scriptlets.bz_eval_tui.print_header import *
from scriptlets._common.get_wan_ip import *
# import:org_python/venv_path_include.py
import yaml
# Game application source - what type of game is being installed?
# from scriptlets.warlock.base_app import *
from scriptlets.warlock.steam_app import *
# Game services are usually either an RCON, HTTP, or base type service.
# Include the necessary type and remove the rest.
# from scriptlets.warlock.base_service import *
# from scriptlets.warlock.http_service import *
from scriptlets.warlock.rcon_service import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.properties_config import *
from scriptlets.warlock.default_run import *

# For games that use Steam, this provides a quick method for checking for updates
# from scriptlets.steam.steamcmd_check_app_update import *

here = os.path.dirname(os.path.realpath(__file__))


class GameApp(SteamApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Zomboid'
		self.desc = 'Project Zomboid'
		self.steam_id = '380870'
		self.services = ('zomboid',)

		self.configs = {
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

		self.steam_branch = self.get_option_value('Steam Branch')

	def get_save_files(self) -> Union[list, None]:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		files = ['banned-ips.json', 'banned-players.json', 'ops.json', 'whitelist.json']
		for service in self.get_services():
			files.append(service.get_name())
		return files

	def get_save_directory(self) -> Union[str, None]:
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(here, 'AppFiles')


class GameService(RCONService):
	"""
	Service definition and handler
	"""
	def __init__(self, service: str, game: GameApp):
		"""
		Initialize and load the service definition
		:param file:
		"""
		super().__init__(service, game)
		self.service = service
		self.game = game
		self.configs = {
			'zomboid': PropertiesConfig('zomboid', os.path.join(here, 'Server/servertest.ini'))
		}
		self.load()

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
				firewall_remove(int(previous_value), 'tcp')
			firewall_allow(int(new_value), 'udp', '%s data port' % self.game.desc)
		elif option == 'UDP Port':
			# Update firewall for game port change
			if previous_value:
				firewall_remove(int(previous_value), 'udp')
			firewall_allow(int(new_value), 'udp', '%s game port' % self.game.desc)

	def is_api_enabled(self) -> bool:
		"""
		Check if API is enabled for this service
		:return:
		"""
		return (
			self.get_option_value('RCON Port') != '' and
			self.get_option_value('RCON Password') != ''
		)

	def get_api_port(self) -> int:
		"""
		Get the API port from the service configuration
		:return:
		"""
		return self.get_option_value('RCON Port')

	def get_api_password(self) -> str:
		"""
		Get the API password from the service configuration
		:return:
		"""
		return self.get_option_value('RCON Password')

	def get_player_count(self) -> Union[int, None]:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		try:
			ret = self._api_cmd('players')
			# ret should contain 'There are N of a max...' where N is the player count.
			if ret is None:
				return None
			# Players connected (0):
			elif 'Players connected ' in ret:
				return int(ret.split('(')[1].split(')')[0])
			else:
				return None
		except:
			return None

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

	def get_port(self) -> Union[int, None]:
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
		self._api_cmd('/servermsg %s' % message)

	def save_world(self):
		"""
		Force the game server to save the world via the game API
		:return:
		"""
		self._api_cmd('save')

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
		if os.path.exists(os.path.join(here, 'admin.passwd')):
			with open(os.path.join(here, 'admin.passwd'), 'r') as f:
				random_password = f.read().strip()
		else:
			random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
			with open(os.path.join(here, 'admin.passwd'), 'w') as f:
				f.write(random_password)

		counter = 0
		while counter < 60:
			counter += 1
			log = self.get_logs(1)
			logs = self.get_logs(10)

			# The server prompts for admin password on first run
			if 'Enter new administrator password:' in log or 'Confirm the password:' in log:
				with open('/var/run/zomboid.socket', 'w') as f:
					f.write(random_password + '\n')
			elif '##########' in logs:
				# Generally indicates the server has started and is in the final steps of loading.
				break

			time.sleep(1)

		return super().post_start()



def menu_first_run(game: GameApp):
	"""
	Perform first-run configuration for setting up the game server initially

	:param game:
	:return:
	"""
	print_header('First Run Configuration')

	if os.geteuid() != 0:
		print('ERROR: Please run this script with sudo to perform first-run configuration.')
		sys.exit(1)

	svc = game.get_services()[0]

	print('Starting the server for initial setup...')
	subprocess.Popen(['systemctl', 'start', svc.service])
	time.sleep(10)

	counter = 0
	while counter < 300:
		counter += 1
		if svc.is_running():
			break

		time.sleep(1)

	print('First start finished, stopping game server...')
	subprocess.Popen(['systemctl', 'stop', svc.service])
	time.sleep(10)
	svc.load()

	if os.path.exists(os.path.join(here, 'admin.passwd')):
		with open(os.path.join(here, 'admin.passwd'), 'r') as f:
			random_password = f.read().strip()
	else:
		random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
		with open(os.path.join(here, 'admin.passwd'), 'w') as f:
			f.write(random_password)

	# Allow default game ports
	firewall_allow(int(svc.get_option_value('Default Port')), 'udp', 'Allow %s data port' % svc.game.desc)
	firewall_allow(int(svc.get_option_value('UDP Port')), 'udp', 'Allow %s game port' % svc.game.desc)
	if not svc.option_has_value('RCON Password'):
		# Generate a random password for RCON

		svc.set_option('RCON Password', random_password)

if __name__ == '__main__':
	game = GameApp()
	run_manager(game)
