bp = find_program('blueprint-compiler', required: true)

ui_main = custom_target(
  'main_window.ui',
  input: files('ui/main_window.blp'),
  output: 'main_window.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_search = custom_target(
  'search_page.ui',
  input: files('ui/search_page.blp'),
  output: 'search_page.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_details = custom_target(
  'details_page.ui',
  input: files('ui/details_page.blp'),
  output: 'details_page.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

gresource_xml = configure_file(
  input: files('resources.gresource.xml.in'),
  output: 'resources.gresource.xml',
  configuration: { 'PREFIX': '/org/example/PackageSearch' }
)

resources = gnome.compile_resources(
  'packagesearch-resources',
  gresource_xml,
  source_dir: meson.current_build_dir(),
  dependencies: [ui_main, ui_search, ui_details],
  c_name: 'packagesearch'
)
