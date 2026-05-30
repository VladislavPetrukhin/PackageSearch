bp = find_program('blueprint-compiler', required: true)
i18n = import('i18n')

app_id = 'space.altlinux.PackageSearch'

desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id)

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

ui_maintainer = custom_target(
  'maintainer_page.ui',
  input: files('ui/maintainer_page.blp'),
  output: 'maintainer_page.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_graph = custom_target(
  'dependency_graph_page.ui',
  input: files('ui/dependency_graph_page.blp'),
  output: 'dependency_graph_page.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_task = custom_target(
  'task_details_page.ui',
  input: files('ui/task_details_page.blp'),
  output: 'task_details_page.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_shortcuts = custom_target(
  'shortcuts.ui',
  input: files('ui/shortcuts.blp'),
  output: 'shortcuts.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_bug_row = custom_target(
  'bug_row.ui',
  input: files('ui/bug_row.blp'),
  output: 'bug_row.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_bug_filter_row = custom_target(
  'bug_filter_row.ui',
  input: files('ui/bug_filter_row.blp'),
  output: 'bug_filter_row.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_errata_row = custom_target(
  'errata_row.ui',
  input: files('ui/errata_row.blp'),
  output: 'errata_row.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

ui_link_row = custom_target(
  'link_row.ui',
  input: files('ui/link_row.blp'),
  output: 'link_row.ui',
  command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  build_by_default: true
)

gresource_xml = configure_file(
  input: files('resources.gresource.xml.in'),
  output: 'resources.gresource.xml',
  configuration: { 'PREFIX': '/space/altlinux/PackageSearch' }
)

resources = gnome.compile_resources(
  'packagesearch-resources',
  gresource_xml,
  source_dir: [meson.current_build_dir(), meson.current_source_dir()],
  dependencies: [ui_main, ui_search, ui_details, ui_maintainer, ui_graph, ui_task, ui_shortcuts, ui_bug_row, ui_bug_filter_row, ui_errata_row, ui_link_row],
  c_name: 'packagesearch'
)

subdir('icons')

desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id)

configured_desktop = configure_file(
  input: files('app.desktop.in'),
  output: '@0@.desktop.in'.format(app_id),
  configuration: desktop_conf,
)

i18n.merge_file(
  input: configured_desktop,
  output: '@0@.desktop'.format(app_id),
  po_dir: join_paths(meson.project_source_root(), 'po'),
  install: true,
  install_dir: get_option('datadir') / 'applications',
  type: 'desktop',
)

metainfo_conf = configuration_data()
metainfo_conf.set('APP_ID', app_id)

configured_metainfo = configure_file(
  input: files('app.metainfo.xml.in.in'),
  output: '@0@.metainfo.xml.in'.format(app_id),
  configuration: metainfo_conf,
)

i18n.merge_file(
  input: configured_metainfo,
  output: '@0@.metainfo.xml'.format(app_id),
  po_dir: join_paths(meson.project_source_root(), 'po'),
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
  type: 'xml',
)

# GSettings schema — persistent search history etc.
install_data(
  '@0@.gschema.xml'.format(app_id),
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)
gnome.post_install(glib_compile_schemas: true)

