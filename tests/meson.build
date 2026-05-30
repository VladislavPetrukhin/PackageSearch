gio_dep = dependency('gio-2.0')

test_vala_args = [
  '--target-glib=2.74',
  '--pkg=gio-2.0',
  '--pkg=gee-0.8',
]

test_deps = [lib_testable_dep, gio_dep, gee_dep]

test_cases = [
  'version_compare',
  'search_text',
  'validation',
  'text_diff',
  'package_manager_logic',
]

foreach case : test_cases
  exe = executable(
    'test_' + case,
    sources: [ 'test_' + case + '.vala' ],
    dependencies: test_deps,
    vala_args: test_vala_args,
    install: false,
  )
  test(case, exe, protocol: 'tap', args: ['--tap'])
endforeach
