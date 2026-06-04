project('PackageSearch', 'vala',
  version: '0.2.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.61',
  default_options: ['warning_level=0'],
)

gnome = import('gnome')
i18n = import('i18n')

app_id = 'space.altlinux.PackageSearch'

conf = configuration_data()
conf.set_quoted('PACKAGE_VERSION', meson.project_version())
config_h = configure_file(output: 'config.h', configuration: conf)

gtk4_dep = dependency('gtk4', version: '>=4.12')
adw_dep  = dependency('libadwaita-1', version: '>=1.5')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
gee_dep  = dependency('gee-0.8')
alt_repo_dep = dependency('libalt-repo-1', required: true)
packagekit_dep = dependency('packagekit-glib2')

# blueprint-compiler
bp = find_program('blueprint-compiler', required: true)

localedir = join_paths(get_option('prefix'), get_option('localedir'))
add_project_arguments(
    '-w',
    '-DGETTEXT_PACKAGE="@0@"'.format(app_id),
    '-DLOCALEDIR="@0@"'.format(localedir),
    language: 'c'
)

subdir('data')
subdir('src')
subdir('po')

vala_extra_args = [
  '--target-glib=2.74',
  '--pkg=gtk4',
  '--pkg=libadwaita-1',
  '--pkg=json-glib-1.0',
  '--pkg=libsoup-3.0',
  '--pkg=gee-0.8',
  '--pkg=libalt-repo-1',
  '--pkg=packagekit-glib2',
]

executable(
  'packagesearch',
  src,
  resources,
  dependencies: [gtk4_dep, adw_dep, json_dep, soup_dep, gee_dep, alt_repo_dep, packagekit_dep],
  vala_args: vala_extra_args,
  include_directories: include_directories('.'),
  install: true
)
gnome.post_install(
  glib_compile_schemas: true,
  update_desktop_database: true,
)
icon_cache_dir = join_paths(get_option('prefix'), get_option('datadir'), 'icons', 'hicolor')

meson.add_install_script(
  'sh', '-c',
  '''
  set -eu
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    if [ -n "${DESTDIR-}" ]; then
      gtk-update-icon-cache -f "$DESTDIR@ICON_DIR@" || true
    else
      gtk-update-icon-cache -f "@ICON_DIR@" || true
    fi
  fi
  '''
  .replace('@ICON_DIR@', icon_cache_dir)
)

subdir('tests')

