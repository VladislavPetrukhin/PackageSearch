project('PackageSearch', 'vala', version: '0.1.0', meson_version: '>= 0.61')

gnome = import('gnome')

app_id = 'org.example.PackageSearch'

gtk4_dep = dependency('gtk4', version: '>=4.12')
adw_dep  = dependency('libadwaita-1', version: '>=1.4')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
gee_dep  = dependency('gee-0.8')

# blueprint-compiler
bp = find_program('blueprint-compiler', required: true)

subdir('data')
subdir('src')

executable(
  'packagesearch',
  src,
  resources,
  dependencies: [gtk4_dep, adw_dep, json_dep, soup_dep, gee_dep],
  vala_args: [
    '--target-glib=2.74',
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gee-0.8',
  ],
  install: true
)