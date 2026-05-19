/* test_package_manager_logic.vala — tests for the pure decision logic
 * that PackageManager.needs_update relies on. Spawning rpm/apt-repo is
 * out of scope for unit tests; here we verify the EVR-comparison rule:
 *   needs_update == compare_evr(installed, repo) < 0
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Business;

// Mimics PackageManager.needs_update without subprocess I/O.
private static bool needs_update_pure (string installed_evr, string repo_evr) {
    return VersionCompare.compare_evr (installed_evr, repo_evr) < 0;
}

private static void t_no_update_when_equal () {
    assert (!needs_update_pure ("0:1.2.3-alt1", "0:1.2.3-alt1"));
    assert (!needs_update_pure ("1.2.3-alt1",   "1.2.3-alt1"));
}

private static void t_no_update_when_installed_newer () {
    assert (!needs_update_pure ("1.2.4-alt1", "1.2.3-alt1"));
    assert (!needs_update_pure ("1:1.0-alt1", "0:9.9-alt1"));
}

private static void t_update_when_installed_older () {
    assert (needs_update_pure ("1.2.3-alt1", "1.2.4-alt1"));
    assert (needs_update_pure ("1.2.3-alt1", "1.2.3-alt2"));
    assert (needs_update_pure ("0:9.9-alt1", "1:0.1-alt1"));
}

private static void t_update_from_rc_to_release () {
    // Installed RC must be considered older than the final release
    assert (needs_update_pure ("1.0~rc1-alt1", "1.0-alt1"));
}

private static void t_no_update_with_caret_snapshot () {
    // A caret snapshot is newer than its base — installed snapshot
    // shouldn't be "updated" back to the base version.
    assert (!needs_update_pure ("1.0^20240101-alt1", "1.0-alt1"));
}

private static void t_install_result_enum () {
    // Sanity check that the public enum is reachable and has 3 distinct values.
    assert (InstallResult.SUCCESS   != InstallResult.CANCELLED);
    assert (InstallResult.CANCELLED != InstallResult.FAILED);
    assert (InstallResult.SUCCESS   != InstallResult.FAILED);
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/business/package_manager/needs_update/equal",         t_no_update_when_equal);
    GLib.Test.add_func ("/business/package_manager/needs_update/installed_newer", t_no_update_when_installed_newer);
    GLib.Test.add_func ("/business/package_manager/needs_update/installed_older", t_update_when_installed_older);
    GLib.Test.add_func ("/business/package_manager/needs_update/rc_to_release",   t_update_from_rc_to_release);
    GLib.Test.add_func ("/business/package_manager/needs_update/caret_snapshot",  t_no_update_with_caret_snapshot);
    GLib.Test.add_func ("/business/package_manager/install_result/enum",          t_install_result_enum);

    return GLib.Test.run ();
}
