using Gtk;
using Adw;
using Intl;
using GLib;

public class PackageSearchApp : Adw.Application {
    public PackageSearchApp () {
        Object (application_id: "org.example.PackageSearch",
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    public static string detect_locale_dir () {
        var locdir = Environment.get_variable ("LOCALEDIR");
        if (locdir != null && locdir != "") return locdir;

        string[] candidates = {
            Environment.get_home_dir () + "/.local/share/locale",
            "/usr/local/share/locale",
            "/usr/share/locale",
        };
        foreach (var d in candidates) {
            if (FileUtils.test (d, FileTest.IS_DIR)) return d;
        }
        return "/usr/share/locale";
    }

    public static void init_gettext () {
        Intl.setlocale (LocaleCategory.ALL, "");
        var locdir = detect_locale_dir ();
        Intl.bindtextdomain ("org.example.PackageSearch", locdir);
        Intl.bind_textdomain_codeset ("org.example.PackageSearch", "UTF-8");
        Intl.textdomain ("org.example.PackageSearch");
    }

    protected override void activate () {
        init_gettext ();
        Adw.init ();
        mark_blp_strings_for_gettext ();

        var win = this.active_window as MainWindow;
        if (win == null) win = new MainWindow (this);
        win.present ();
    }
    private static void mark_blp_strings_for_gettext () {
    if (false) {
        // DetailsPage
        _("Details"); _("Back"); _("Info"); _("Binaries"); _("Changelog"); _("Loading data…");
        // SearchPage
        _("Search"); _("Type a package name…"); _("Search packages");
        _("Start typing a source package name, then pick it from the results.");
        _("Loading results…"); _("No results"); _("Try refining your query or choose another branch.");
        _("Error"); _("Failed to fetch data. Check your connection and package name.");
    }
}

}

int main (string[] args) {
    return new PackageSearchApp ().run (args);
}

