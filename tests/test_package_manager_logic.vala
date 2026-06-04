using Business;

private static void t_detect_branch () {
    string sisyphus_with_task =
        "rpm https://git.altlinux.org repo/417218/x86_64 task\n"
      + "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/x86_64 classic\n"
      + "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/x86_64-i586 classic\n"
      + "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/noarch classic\n";
    assert (PackageManager.detect_branch (sisyphus_with_task) == "sisyphus");

    string p10 =
        "rpm [p10] http://ftp.altlinux.org/pub/distributions/ALTLinux/p10/branch/x86_64 classic\n";
    assert (PackageManager.detect_branch (p10) == "p10");

    string c10f2 =
        "rpm [c10f2] http://ftp.altlinux.org/pub/distributions/c10f2/x86_64 classic\n";
    assert (PackageManager.detect_branch (c10f2) == "c10f2");

    string task_only =
        "rpm https://git.altlinux.org repo/417218/x86_64 task\n";
    assert (PackageManager.detect_branch (task_only) == "");

    assert (PackageManager.detect_branch ("") == "");
}

private static void t_classify_package () {
    var plan = new InstallPlan ();

    assert (PackageManager.classify_package (Pk.Info.INSTALLING,   "foo", plan) == true);
    assert (PackageManager.classify_package (Pk.Info.REINSTALLING, "bar", plan) == true);
    assert (PackageManager.classify_package (Pk.Info.UPDATING,     "baz", plan) == true);
    assert (PackageManager.classify_package (Pk.Info.DOWNGRADING,  "qux", plan) == true);
    assert (PackageManager.classify_package (Pk.Info.REMOVING,     "old", plan) == false);
    assert (PackageManager.classify_package (Pk.Info.OBSOLETING,   "obs", plan) == false);
    assert (PackageManager.classify_package (Pk.Info.AVAILABLE,    "skip", plan) == false);

    assert (plan.install.size == 2);
    assert (plan.install.contains ("foo"));
    assert (plan.install.contains ("bar"));

    assert (plan.upgrade.size == 2);
    assert (plan.upgrade.contains ("baz"));
    assert (plan.upgrade.contains ("qux"));

    assert (plan.remove.size == 2);
    assert (plan.remove.contains ("old"));
    assert (plan.remove.contains ("obs"));

    assert (!plan.install.contains ("skip"));
    assert (!plan.upgrade.contains ("skip"));
    assert (!plan.remove.contains ("skip"));
}

private static void t_classify_dedup () {
    var plan = new InstallPlan ();
    PackageManager.classify_package (Pk.Info.INSTALLING, "foo", plan);
    PackageManager.classify_package (Pk.Info.INSTALLING, "foo", plan);
    assert (plan.install.size == 1);
}

private static void t_build_summary () {
    var plan = new InstallPlan ();
    plan.install.add ("a");
    plan.install.add ("b");
    plan.upgrade.add ("c");
    plan.remove.add ("d");

    var s = PackageManager.build_summary (plan);
    assert (s.contains ("2"));
    assert (s.contains ("1"));

    assert (PackageManager.build_summary (new InstallPlan ()) == "");
}

private static void t_untrusted_error () {
    assert (PackageManager.is_untrusted_error (Pk.Exit.NEED_UNTRUSTED, Pk.ErrorEnum.UNKNOWN));
    assert (PackageManager.is_untrusted_error (Pk.Exit.KEY_REQUIRED, Pk.ErrorEnum.UNKNOWN));
    assert (PackageManager.is_untrusted_error (Pk.Exit.FAILED, Pk.ErrorEnum.BAD_GPG_SIGNATURE));
    assert (PackageManager.is_untrusted_error (Pk.Exit.FAILED, Pk.ErrorEnum.MISSING_GPG_SIGNATURE));
    assert (PackageManager.is_untrusted_error (Pk.Exit.FAILED, Pk.ErrorEnum.CANNOT_INSTALL_REPO_UNSIGNED));

    assert (!PackageManager.is_untrusted_error (Pk.Exit.SUCCESS, Pk.ErrorEnum.UNKNOWN));
    assert (!PackageManager.is_untrusted_error (Pk.Exit.FAILED, Pk.ErrorEnum.PACKAGE_DOWNLOAD_FAILED));
}

private static void t_stale_cache_error () {
    assert (PackageManager.is_stale_cache_error (Pk.ErrorEnum.PACKAGE_DOWNLOAD_FAILED));
    assert (PackageManager.is_stale_cache_error (Pk.ErrorEnum.PACKAGE_NOT_FOUND));
    assert (PackageManager.is_stale_cache_error (Pk.ErrorEnum.NO_MORE_MIRRORS_TO_TRY));
    assert (PackageManager.is_stale_cache_error (Pk.ErrorEnum.FILE_NOT_FOUND));

    assert (!PackageManager.is_stale_cache_error (Pk.ErrorEnum.UNKNOWN));
    assert (!PackageManager.is_stale_cache_error (Pk.ErrorEnum.BAD_GPG_SIGNATURE));
}

private static void t_looks_stale_message () {
    assert (PackageManager.looks_stale_message (
        "E: ftp://ftp.altlinux.org Sisyphus/x86_64/classic fastfetch 2.63.1-alt1 "
      + "is not (yet) available (Unable to fetch file, server said 'Failed to open file.  ')"));
    assert (PackageManager.looks_stale_message ("Failed to fetch http://x 404 Not Found"));
    assert (PackageManager.looks_stale_message ("W: Hash Sum mismatch"));
    assert (PackageManager.looks_stale_message ("No more mirrors to try"));

    assert (!PackageManager.looks_stale_message ("All packages are up to date"));
    assert (!PackageManager.looks_stale_message (null));
}

private static void t_looks_untrusted_message () {
    assert (PackageManager.looks_untrusted_message ("The following packages cannot be authenticated: untrusted"));
    assert (PackageManager.looks_untrusted_message ("GPG error: NO_PUBKEY 1234"));
    assert (PackageManager.looks_untrusted_message ("repository is not signed"));

    assert (!PackageManager.looks_untrusted_message ("Failed to fetch 404"));
    assert (!PackageManager.looks_untrusted_message (null));
}

private static void t_has_debuginfo_source () {
    string with_debug =
        "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/x86_64 classic\n"
      + "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/x86_64 debuginfo\n";
    assert (PackageManager.has_debuginfo_source (with_debug));

    string no_debug =
        "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/x86_64 classic\n"
      + "rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux Sisyphus/noarch classic\n";
    assert (!PackageManager.has_debuginfo_source (no_debug));

    assert (!PackageManager.has_debuginfo_source (""));
}

private static void t_install_result_enum () {
    assert (InstallResult.SUCCESS   != InstallResult.CANCELLED);
    assert (InstallResult.CANCELLED != InstallResult.FAILED);
    assert (InstallResult.SUCCESS   != InstallResult.FAILED);
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/business/package_manager/detect_branch",  t_detect_branch);
    GLib.Test.add_func ("/business/package_manager/classify",       t_classify_package);
    GLib.Test.add_func ("/business/package_manager/classify_dedup", t_classify_dedup);
    GLib.Test.add_func ("/business/package_manager/build_summary",  t_build_summary);
    GLib.Test.add_func ("/business/package_manager/untrusted",      t_untrusted_error);
    GLib.Test.add_func ("/business/package_manager/stale_cache",    t_stale_cache_error);
    GLib.Test.add_func ("/business/package_manager/stale_message",  t_looks_stale_message);
    GLib.Test.add_func ("/business/package_manager/untrusted_msg",  t_looks_untrusted_message);
    GLib.Test.add_func ("/business/package_manager/debuginfo_repo", t_has_debuginfo_source);
    GLib.Test.add_func ("/business/package_manager/install_result", t_install_result_enum);

    return GLib.Test.run ();
}
