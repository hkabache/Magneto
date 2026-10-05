# Réglages dmgbuild de la fenêtre du DMG. dmgbuild écrit le .DS_Store lui-même au lieu de
# piloter le Finder par AppleScript, ce qui marche sur un runner sans session graphique.
# Les positions sont celles que background.swift dessine : les deux fichiers bougent ensemble.
import os.path

app = defines["app"]  # noqa: F821, fourni par dmgbuild -D app=…
background_tiff = defines["background"]  # noqa: F821

files = [app]
symlinks = {"Applications": "/Applications"}

format = "UDZO"

background = background_tiff
window_rect = ((200, 120), (640, 490))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
# Entre 10 et 16 : hors de cette plage, le Finder rejette tout le bloc d'options de
# présentation, fond et taille d'icônes compris.
text_size = 13
label_pos = "bottom"
hide_extensions = [os.path.basename(app)]
icon_locations = {
    os.path.basename(app): (170, 190),
    "Applications": (470, 190),
}
