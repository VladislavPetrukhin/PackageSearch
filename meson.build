project('PackageSearch', 'vala', version: '0.1.0', meson_version: '>= 0.61')

fs = import('fs')
gnome = import('gnome')
i18n = import('i18n')

app_id = 'space.altlinux.PackageSearch'

gtk4_dep = dependency('gtk4', version: '>=4.12')
adw_dep  = dependency('libadwaita-1', version: '>=1.4')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
gee_dep  = dependency('gee-0.8')
alt_repo_dep = dependency('libalt-repo-1', required: true)

# blueprint-compiler
bp = find_program('blueprint-compiler', required: true)

subdir('data')
subdir('src')
subdir('po')

localedir = join_paths(get_option('prefix'), get_option('localedir'))
add_project_arguments('-DGETTEXT_PACKAGE="@0@"'.format(app_id), language: 'c')

vala_extra_args = [
  '--target-glib=2.74',
  '--pkg=gtk4',
  '--pkg=libadwaita-1',
  '--pkg=json-glib-1.0',
  '--pkg=gee-0.8',
  '--pkg=libalt-repo-1',
  '--Xcc=-DGETTEXT_PACKAGE="@0@"'.format(app_id),
  '--Xcc=-DLOCALEDIR="@0@"'.format(localedir),
]

executable(
  'packagesearch',
  src,
  resources,
  dependencies: [gtk4_dep, adw_dep, json_dep, gee_dep, alt_repo_dep],
  vala_args: vala_extra_args,
  install: true
)
gnome.post_install(
  glib_compile_schemas: true,
  update_desktop_database: true,
)
