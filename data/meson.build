bp = find_program('blueprint-compiler', required: true)
i18n = import('i18n')

app_id = 'space.altlinux.PackageSearch'

desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id)

blueprints = [
  'main_window',
  'search_page',
  'details_page',
  'maintainer_page',
  'dependency_graph_page',
  'task_details_page',
  'shortcuts',
  'bug_row',
  'bug_filter_row',
  'errata_row',
  'link_row',
  'lazy_expander_row',
  'install_progress_dialog',
  'text_dialog',
  'version_compare_dialog',
  'package_hero',
  'source_result_row',
  'task_result_row',
  'history_popover',
]

ui_targets = []
foreach name : blueprints
  ui_targets += custom_target(
    name + '.ui',
    input: files('ui' / (name + '.blp')),
    output: name + '.ui',
    command: [bp, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
    build_by_default: true,
  )
endforeach

gresource_xml = configure_file(
  input: files('resources.gresource.xml.in'),
  output: 'resources.gresource.xml',
  configuration: { 'PREFIX': '/space/altlinux/PackageSearch' }
)

resources = gnome.compile_resources(
  'packagesearch-resources',
  gresource_xml,
  source_dir: [meson.current_build_dir(), meson.current_source_dir()],
  dependencies: ui_targets,
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

desktop_file = i18n.merge_file(
  input: configured_desktop,
  output: '@0@.desktop'.format(app_id),
  po_dir: join_paths(meson.project_source_root(), 'po'),
  install: true,
  install_dir: get_option('datadir') / 'applications',
  type: 'desktop',
)

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test('validate-desktop', desktop_file_validate, args: [desktop_file])
endif

metainfo_conf = configuration_data()
metainfo_conf.set('APP_ID', app_id)

configured_metainfo = configure_file(
  input: files('app.metainfo.xml.in.in'),
  output: '@0@.metainfo.xml.in'.format(app_id),
  configuration: metainfo_conf,
)

metainfo_file = i18n.merge_file(
  input: configured_metainfo,
  output: '@0@.metainfo.xml'.format(app_id),
  po_dir: join_paths(meson.project_source_root(), 'po'),
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
  type: 'xml',
)

appstream_util = find_program('appstream-util', required: false)
appstreamcli = find_program('appstreamcli', required: false)
if appstream_util.found()
  test('validate-metainfo', appstream_util,
       args: ['validate-relax', '--nonet', metainfo_file])
elif appstreamcli.found()
  test('validate-metainfo', appstreamcli,
       args: ['validate', '--no-net', metainfo_file])
endif

# GSettings schema — persistent search history etc.
install_data(
  '@0@.gschema.xml'.format(app_id),
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

