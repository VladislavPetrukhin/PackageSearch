# Unit tests for the business and data layers.
# These tests deliberately exclude UI / network / libalt-repo dependencies —
# they only exercise pure logic (version comparison, model defaults).
# Shared static library `lib_testable_dep` is defined in src/meson.build.

gio_dep = dependency('gio-2.0')

test_vala_args = [
  '--target-glib=2.74',
  '--pkg=gio-2.0',
  '--pkg=gee-0.8',
]

test_deps = [lib_testable_dep, gio_dep, gee_dep]

test_version_compare = executable(
  'test_version_compare',
  sources: [ 'test_version_compare.vala' ],
  dependencies: test_deps,
  vala_args: test_vala_args,
  install: false,
)
test('version_compare', test_version_compare, protocol: 'tap',
     args: ['--tap'])

test_models = executable(
  'test_models',
  sources: [ 'test_models.vala' ],
  dependencies: test_deps,
  vala_args: test_vala_args,
  install: false,
)
test('models', test_models, protocol: 'tap',
     args: ['--tap'])

test_package_manager_logic = executable(
  'test_package_manager_logic',
  sources: [ 'test_package_manager_logic.vala' ],
  dependencies: test_deps,
  vala_args: test_vala_args,
  install: false,
)
test('package_manager_logic', test_package_manager_logic, protocol: 'tap',
     args: ['--tap'])
