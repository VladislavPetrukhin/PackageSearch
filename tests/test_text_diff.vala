using Business;

private static void t_identical_no_output () {
    assert (TextDiff.only_differences ("a\nb\nc", "a\nb\nc") == "");
    assert (TextDiff.only_differences ("", "") == "");
}

private static void t_pure_addition () {
    assert (TextDiff.only_differences ("a", "a\nb") == "+ b\n");
}

private static void t_pure_deletion () {
    assert (TextDiff.only_differences ("a\nb", "a") == "- b\n");
}

private static void t_replacement_shows_both_sides () {
    string d = TextDiff.only_differences ("a\nb\nc", "a\nX\nc");
    assert (d.contains ("- b"));
    assert (d.contains ("+ X"));
    assert (!d.contains ("a"));
    assert (!d.contains ("c"));
}

private static void t_separator_between_diff_blocks () {
    string a = "D1\ncommon1\ncommon2\nD2";
    string b = "XD1\ncommon1\ncommon2\nXD2";
    string d = TextDiff.only_differences (a, b);
    assert (d.contains ("⋯"));
    assert (d.contains ("- D1"));
    assert (d.contains ("+ XD1"));
    assert (d.contains ("- D2"));
    assert (d.contains ("+ XD2"));
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/business/text_diff/identical",   t_identical_no_output);
    GLib.Test.add_func ("/business/text_diff/addition",    t_pure_addition);
    GLib.Test.add_func ("/business/text_diff/deletion",    t_pure_deletion);
    GLib.Test.add_func ("/business/text_diff/replacement", t_replacement_shows_both_sides);
    GLib.Test.add_func ("/business/text_diff/separator",   t_separator_between_diff_blocks);

    return GLib.Test.run ();
}
