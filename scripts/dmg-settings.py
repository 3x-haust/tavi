# dmgbuild settings for the Tavi installer window. Invoked by package-dmg.sh with
# -D app=<path to Tavi.app> from the repository root. Icon centres must match
# tools/render_dmg_background.py.
import os.path

app = defines['app']

format = 'UDZO'
files = [app]
symlinks = {'Applications': '/Applications'}
icon = os.path.join(app, 'Contents', 'Resources', 'Tavi.icns')
icon_locations = {'Tavi.app': (160, 160), 'Applications': (480, 160)}

background = 'Resources/dmg/background.png'
window_rect = ((200, 120), (640, 400))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 112
text_size = 13
