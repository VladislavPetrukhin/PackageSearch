/* test_models.vala — unit tests for Data namespace models
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Data;

private static void t_source_group_constructor () {
    var sg = new SourceGroup ("glibc");
    assert (sg.name == "glibc");
    assert (sg.version == null);
    assert (sg.release == null);

    sg.version = "2.39";
    sg.release = "alt1";
    assert (sg.version == "2.39");
    assert (sg.release == "alt1");
}

private static void t_binary_package_defaults () {
    var bp = new BinaryPackage ();
    bp.name = "libfoo";
    assert (bp.name == "libfoo");
    assert (bp.version == null);
    assert (bp.arch == null);
    assert (bp.src_name == null);
}

private static void t_task_result_defaults () {
    var tr = new TaskResult ();
    assert (tr.task_id == 0);
    assert (tr.state == "");
    assert (tr.owner == "");
    assert (tr.repo == "");
}

private static void t_errata_info_collections_initialized () {
    var ei = new ErrataInfo ();
    // Constructor must allocate the references list
    assert (ei.references != null);
    assert (ei.references.size == 0);

    var r = new ErrataRef ();
    r.id = "CVE-2024-0001";
    r.ref_type = "cve";
    ei.references.add (r);

    assert (ei.references.size == 1);
    assert (ei.references[0].id == "CVE-2024-0001");
    assert (ei.references[0].ref_type == "cve");
}

private static void t_package_details_collections_initialized () {
    var pd = new PackageDetails ();
    // Constructor must allocate the binaries list
    assert (pd.binaries != null);
    assert (pd.binaries.size == 0);

    var b = new BinaryPackage ();
    b.name = "glibc-locales";
    pd.binaries.add (b);
    assert (pd.binaries.size == 1);
    assert (pd.binaries[0].name == "glibc-locales");
}

private static void t_search_mode_values () {
    // Enum sanity: distinct values, default ordering
    assert (SearchMode.PACKAGE != SearchMode.BINARY);
    assert (SearchMode.PACKAGE != SearchMode.FILE);
    assert ((int) SearchMode.PACKAGE == 0);
}

private static void t_vulnerability_item_defaults () {
    var v = new VulnerabilityItem ();
    assert (v.id == "");
    assert (v.score == 0.0);
    assert (v.rejected == false);
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/data/models/source_group/constructor",         t_source_group_constructor);
    GLib.Test.add_func ("/data/models/binary_package/defaults",          t_binary_package_defaults);
    GLib.Test.add_func ("/data/models/task_result/defaults",             t_task_result_defaults);
    GLib.Test.add_func ("/data/models/errata_info/collections",          t_errata_info_collections_initialized);
    GLib.Test.add_func ("/data/models/package_details/collections",      t_package_details_collections_initialized);
    GLib.Test.add_func ("/data/models/search_mode/values",               t_search_mode_values);
    GLib.Test.add_func ("/data/models/vulnerability_item/defaults",      t_vulnerability_item_defaults);

    return GLib.Test.run ();
}
