packagescan_sources = [
  'main.vala',
  'application.vala',
  'window.vala',
]

packagescan_deps = [
  config_dep,
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.4'),
]

packagescan_sources += gnome.compile_resources('packagescan-resources',
  'packagescan.gresource.xml',
  c_name: 'packagescan'
)

executable('packagescan', packagescan_sources,
  dependencies: packagescan_deps,
  include_directories: config_inc,
       install: true,
)
