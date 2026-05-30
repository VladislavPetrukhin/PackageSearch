using Business;

private static void t_rpmvercmp_equal () {
    assert (VersionCompare.rpmvercmp ("1.0", "1.0") == 0);
    assert (VersionCompare.rpmvercmp ("", "") == 0);
    assert (VersionCompare.rpmvercmp ("1.2.3", "1.2.3") == 0);
}

private static void t_rpmvercmp_numeric () {
    assert (VersionCompare.rpmvercmp ("1.0", "2.0") < 0);
    assert (VersionCompare.rpmvercmp ("2.0", "1.0") > 0);
    assert (VersionCompare.rpmvercmp ("1.10", "1.2") > 0);
    assert (VersionCompare.rpmvercmp ("1.0.1", "1.0") > 0);
}

private static void t_rpmvercmp_leading_zeros () {
    assert (VersionCompare.rpmvercmp ("007", "7") == 0);
    assert (VersionCompare.rpmvercmp ("1.007", "1.7") == 0);
}

private static void t_rpmvercmp_tilde () {
    assert (VersionCompare.rpmvercmp ("1.0~rc1", "1.0") < 0);
    assert (VersionCompare.rpmvercmp ("1.0", "1.0~rc1") > 0);
    assert (VersionCompare.rpmvercmp ("1.0~alpha", "1.0~beta") < 0);
}

private static void t_rpmvercmp_caret () {
    assert (VersionCompare.rpmvercmp ("1.0^", "1.0") > 0);
    assert (VersionCompare.rpmvercmp ("1.0", "1.0^") < 0);
    assert (VersionCompare.rpmvercmp ("1.0^20240101", "1.0^20240202") < 0);
}

private static void t_rpmvercmp_alpha () {
    assert (VersionCompare.rpmvercmp ("1.0a", "1.0b") < 0);
    assert (VersionCompare.rpmvercmp ("1.0a", "1.0") > 0);
}

private static void t_rpmvercmp_separators_ignored () {
    assert (VersionCompare.rpmvercmp ("1.0", "1_0") == 0);
    assert (VersionCompare.rpmvercmp ("1..0", "1.0") == 0);
}

private static void t_parse_evr_full () {
    int epoch;
    string ver, rel;
    VersionCompare.parse_evr ("2:1.4.5-alt3", out epoch, out ver, out rel);
    assert (epoch == 2);
    assert (ver == "1.4.5");
    assert (rel == "alt3");
}

private static void t_parse_evr_no_epoch () {
    int epoch;
    string ver, rel;
    VersionCompare.parse_evr ("1.4.5-alt3", out epoch, out ver, out rel);
    assert (epoch == 0);
    assert (ver == "1.4.5");
    assert (rel == "alt3");
}

private static void t_parse_evr_no_release () {
    int epoch;
    string ver, rel;
    VersionCompare.parse_evr ("1.4.5", out epoch, out ver, out rel);
    assert (epoch == 0);
    assert (ver == "1.4.5");
    assert (rel == "");
}

private static void t_compare_evr () {
    assert (VersionCompare.compare_evr ("0:9.9-alt1", "1:0.1-alt1") < 0);
    assert (VersionCompare.compare_evr ("1.0-alt1", "1.1-alt1") < 0);
    assert (VersionCompare.compare_evr ("1.0-alt1", "1.0-alt2") < 0);
    assert (VersionCompare.compare_evr ("1.0-alt2", "1.0-alt1") > 0);
    assert (VersionCompare.compare_evr ("1:1.0-alt1", "1:1.0-alt1") == 0);
}

private static void t_compare_evr_pre_release () {
    assert (VersionCompare.compare_evr ("1.0~rc1-alt1", "1.0-alt1") < 0);
}

private static void t_char_classifiers () {
    assert (VersionCompare.is_digit ('5'));
    assert (!VersionCompare.is_digit ('a'));
    assert (VersionCompare.is_alpha ('z'));
    assert (!VersionCompare.is_alpha ('0'));
    assert (VersionCompare.is_alnum ('A'));
    assert (VersionCompare.is_alnum ('7'));
    assert (!VersionCompare.is_alnum ('-'));
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/business/version_compare/equal",          t_rpmvercmp_equal);
    GLib.Test.add_func ("/business/version_compare/numeric",        t_rpmvercmp_numeric);
    GLib.Test.add_func ("/business/version_compare/leading_zeros",  t_rpmvercmp_leading_zeros);
    GLib.Test.add_func ("/business/version_compare/tilde",          t_rpmvercmp_tilde);
    GLib.Test.add_func ("/business/version_compare/caret",          t_rpmvercmp_caret);
    GLib.Test.add_func ("/business/version_compare/alpha",          t_rpmvercmp_alpha);
    GLib.Test.add_func ("/business/version_compare/separators",     t_rpmvercmp_separators_ignored);
    GLib.Test.add_func ("/business/version_compare/parse_evr/full",       t_parse_evr_full);
    GLib.Test.add_func ("/business/version_compare/parse_evr/no_epoch",   t_parse_evr_no_epoch);
    GLib.Test.add_func ("/business/version_compare/parse_evr/no_release", t_parse_evr_no_release);
    GLib.Test.add_func ("/business/version_compare/compare_evr",          t_compare_evr);
    GLib.Test.add_func ("/business/version_compare/compare_evr/prerelease", t_compare_evr_pre_release);
    GLib.Test.add_func ("/business/version_compare/char_classifiers",     t_char_classifiers);

    return GLib.Test.run ();
}
