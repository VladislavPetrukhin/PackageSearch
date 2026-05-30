using Business;

private const string SAMPLE_OUTPUT =
    "Reading package lists...\n"
  + "Building dependency tree...\n"
  + "The following extra packages will be installed:\n"
  + "  extra1 extra2\n"
  + "The following packages will be upgraded:\n"
  + "  baz\n"
  + "The following NEW packages will be installed:\n"
  + "  foo libbar\n"
  + "The following packages will be REMOVED:\n"
  + "  oldpkg\n"
  + "1 upgraded, 2 newly installed, 1 to remove and 0 not upgraded.\n"
  + "Need to get 1234 kB of archives.\n"
  + "After unpacking 5678 kB of additional disk space will be used.\n";

private static void t_parse_sections () {
    var plan = PackageManager.parse_apt_simulation (SAMPLE_OUTPUT);

    assert (plan.ok);
    assert (!plan.is_empty ());

    assert (plan.install.size == 2);
    assert (plan.install.contains ("foo"));
    assert (plan.install.contains ("libbar"));

    assert (plan.upgrade.size == 1);
    assert (plan.upgrade.contains ("baz"));

    assert (plan.remove.size == 1);
    assert (plan.remove.contains ("oldpkg"));

    assert (!plan.install.contains ("extra1"));
    assert (!plan.install.contains ("extra2"));

    assert (plan.summary.length > 0);
    assert (plan.download.contains ("1234"));
    assert (plan.disk.contains ("5678"));
}

private static void t_parse_empty () {
    var plan = PackageManager.parse_apt_simulation ("");
    assert (plan.ok);
    assert (plan.is_empty ());
    assert (plan.install.size == 0);
}

private static void t_looks_like_stale_index () {
    assert (PackageManager.looks_like_stale_index ("Failed to fetch http://x 404 Not Found"));
    assert (PackageManager.looks_like_stale_index ("W: Hash Sum mismatch"));
    assert (PackageManager.looks_like_stale_index ("size mismatch"));
    assert (!PackageManager.looks_like_stale_index ("All packages are up to date"));
}

private static void t_install_result_enum () {
    assert (InstallResult.SUCCESS   != InstallResult.CANCELLED);
    assert (InstallResult.CANCELLED != InstallResult.FAILED);
    assert (InstallResult.SUCCESS   != InstallResult.FAILED);
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/business/package_manager/parse/sections", t_parse_sections);
    GLib.Test.add_func ("/business/package_manager/parse/empty",    t_parse_empty);
    GLib.Test.add_func ("/business/package_manager/stale_index",    t_looks_like_stale_index);
    GLib.Test.add_func ("/business/package_manager/install_result", t_install_result_enum);

    return GLib.Test.run ();
}
