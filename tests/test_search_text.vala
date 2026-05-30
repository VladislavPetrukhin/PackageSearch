using Data;

private static void t_norm () {
    assert (SearchText.norm ("Foo.Bar-1") == "foobar1");
    assert (SearchText.norm ("GTK+") == "gtk");
    assert (SearchText.norm ("  a_b c ") == "abc");
    assert (SearchText.norm ("---") == "");
}

private static void t_lev () {
    assert (SearchText.lev ("", "") == 0);
    assert (SearchText.lev ("abc", "abc") == 0);
    assert (SearchText.lev ("", "abc") == 3);
    assert (SearchText.lev ("kitten", "sitting") == 3);
}

private static void t_first_word_prefix_pos () {
    assert (SearchText.first_word_prefix_pos ("firefox", "fire") == 0);
    assert (SearchText.first_word_prefix_pos ("lib-fire", "fire") == 4);
    assert (SearchText.first_word_prefix_pos ("xfire", "fire") == -1);
}

private static void t_score_name_tiers () {
    double exact   = SearchText.score_name ("fire", "fire");
    double prefix  = SearchText.score_name ("firefox", "fire");
    double word    = SearchText.score_name ("lib-fire", "fire");
    double infix   = SearchText.score_name ("xfire", "fire");
    double fuzzy   = SearchText.score_name ("abcd", "wxyz");

    assert (exact == 1000.0);
    assert (prefix == 897.0);
    assert (word == 856.0);
    assert (infix == 798.5);
    assert (fuzzy == 0.0);

    assert (exact > prefix);
    assert (prefix > word);
    assert (word > infix);
    assert (infix > fuzzy);
}

private static void t_score_name_prefix_prefers_shorter () {
    assert (SearchText.score_name ("fire", "fire") > SearchText.score_name ("firefox", "fire"));
    assert (SearchText.score_name ("fired", "fire") > SearchText.score_name ("firefox", "fire"));
}

private static void t_normalize_layout () {
    assert (SearchText.normalize_layout ("фыва") == "asdf");
    assert (SearchText.normalize_layout ("firefox") == "firefox");
    assert (SearchText.normalize_layout ("") == "");
    assert (SearchText.normalize_layout ("ГТК") == "unr");
}

public static int main (string[] args) {
    GLib.Test.init (ref args);

    GLib.Test.add_func ("/data/search_text/norm",                   t_norm);
    GLib.Test.add_func ("/data/search_text/lev",                    t_lev);
    GLib.Test.add_func ("/data/search_text/first_word_prefix_pos",  t_first_word_prefix_pos);
    GLib.Test.add_func ("/data/search_text/score_name/tiers",       t_score_name_tiers);
    GLib.Test.add_func ("/data/search_text/score_name/shorter",     t_score_name_prefix_prefers_shorter);
    GLib.Test.add_func ("/data/search_text/normalize_layout",       t_normalize_layout);

    return GLib.Test.run ();
}
