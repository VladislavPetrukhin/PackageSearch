using Data;

private static GLib.Error err (string msg) {
    return new GLib.Error (GLib.Quark.from_string ("test"), 0, "%s", msg);
}

private static void t_branch_allowed () {
    assert (Validation.branch_allowed ("sisyphus"));
    assert (Validation.branch_allowed ("Sisyphus"));
    assert (Validation.branch_allowed ("p11"));
    assert (Validation.branch_allowed ("c10f2"));
    assert (!Validation.branch_allowed ("p13"));
    assert (!Validation.branch_allowed (""));
    assert (!Validation.branch_allowed (null));
}

private static void t_is_all_digits () {
    assert (Validation.is_all_digits ("123"));
    assert (!Validation.is_all_digits (""));
    assert (!Validation.is_all_digits ("12a"));
    assert (!Validation.is_all_digits (" 12"));
}

private static void t_is_valid_package_name () {
    assert (Validation.is_valid_package_name ("glibc"));
    assert (Validation.is_valid_package_name ("lib-foo_1.2+x"));
    assert (Validation.is_valid_package_name ("0ad"));
    assert (!Validation.is_valid_package_name (""));
    assert (!Validation.is_valid_package_name (null));
    assert (!Validation.is_valid_package_name ("-bad"));
    assert (!Validation.is_valid_package_name ("foo bar"));
    assert (!Validation.is_valid_package_name ("foo/bar"));
}

private static void t_is_no_data_error () {
    assert (Validation.is_no_data_error (err ("No data found in database")));
    assert (Validation.is_no_data_error (err ("Nothing found")));
    assert (Validation.is_no_data_error (err ("HTTP 404 Not Found")));
    assert (Validation.is_no_data_error (err ("Wrong type: expected JSON_NODE_ARRAY")));

    assert (!Validation.is_no_data_error (err ("Node isn't array")));
    assert (!Validation.is_no_data_error (err ("Connection timed out")));
    assert (!Validation.is_no_data_error (err ("")));
}

private static void t_is_rate_limited_error () {
    assert (Validation.is_rate_limited_error (err ("Too Many Requests")));
    assert (Validation.is_rate_limited_error (err ("HTTP 429")));
    assert (!Validation.is_rate_limited_error (err ("Internal Server Error")));
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/data/validation/branch_allowed",        t_branch_allowed);
    GLib.Test.add_func ("/data/validation/is_all_digits",         t_is_all_digits);
    GLib.Test.add_func ("/data/validation/is_valid_package_name", t_is_valid_package_name);
    GLib.Test.add_func ("/data/validation/is_no_data_error",      t_is_no_data_error);
    GLib.Test.add_func ("/data/validation/is_rate_limited_error", t_is_rate_limited_error);

    return GLib.Test.run ();
}
