src = files(
  'application.vala',
  'window.vala',
  'views/search_page.vala',
  'views/details_page.vala',
  'views/maintainer_page.vala',
  'views/dependency_graph_page.vala',
  'views/task_details_page.vala',
  'views/security_rows.vala',
  'data/models.vala',
  'data/search_text.vala',
  'data/validation.vala',
  'data/altrepo_client.vala',
  'business/version_compare.vala',
  'business/text_diff.vala',
  'business/package_manager.vala',
)

# Static library with the subset of sources that have no UI / network /
# libalt-repo dependencies — used by the unit tests in tests/.
lib_testable = static_library(
  'testable',
  sources: [
    'data/models.vala',
    'data/search_text.vala',
    'data/validation.vala',
    'business/version_compare.vala',
    'business/text_diff.vala',
    'business/package_manager.vala',
  ],
  dependencies: [
    dependency('gio-2.0'),
    gee_dep,
  ],
  vala_args: [
    '--target-glib=2.74',
    '--pkg=gio-2.0',
    '--pkg=gee-0.8',
  ],
  install: false,
)

# Exposes lib_testable plus the build dir where valac dropped the generated
# testable.h so dependent targets (tests/) can #include it.
lib_testable_dep = declare_dependency(
  link_with:           lib_testable,
  include_directories: include_directories('.'),
)
