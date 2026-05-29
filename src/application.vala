using Gtk;
using Adw;
using Intl;
using GLib;

public class PackageSearchApp : Adw.Application {
    private const string DOMAIN = "space.altlinux.PackageSearch";

    public PackageSearchApp () {
        Object (application_id: "space.altlinux.PackageSearch",
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void startup () {
        base.startup ();

        var display = Gdk.Display.get_default();
        if (display != null) {
            var theme = Gtk.IconTheme.get_for_display(display);
            theme.add_resource_path ("/space/altlinux/PackageSearch/icons");
        }
    }

    private static string detect_locale_dir () {
        var locdir = Environment.get_variable ("LOCALEDIR");
        if (locdir != null && locdir != "") return locdir;

        string[] candidates = {
            Environment.get_home_dir () + "/.local/share/locale",
            "/usr/local/share/locale",
            "/usr/share/locale",
        };
        foreach (var d in candidates)
            if (FileUtils.test (d, FileTest.IS_DIR)) return d;

        return "/usr/share/locale";
    }

    public static void init_gettext () {
        Intl.setlocale (LocaleCategory.ALL, "");
        var locdir = detect_locale_dir ();
        Intl.bindtextdomain (DOMAIN, locdir);
        Intl.bind_textdomain_codeset (DOMAIN, "UTF-8");
        Intl.textdomain (DOMAIN);
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
        if (Environment.get_variable ("PACKAGESEARCH_NEVER") != null) {
            _("Repository"); _("Search mode"); _("Type a package name…");
            _("Search"); _("Search packages");
            _("Start typing a source package name, then pick it from the results.");
            _("No results"); _("Try refining your query or choose another search mode.");
            _("Connection error"); _("Failed to fetch data. Check your connection and try again.");
            _("Retry"); _("Recent searches"); _("Main menu");
            _("Clear search history"); _("About PackageSearch");
            _("Details"); _("Information"); _("Binary packages");
            _("Dependencies"); _("Security"); _("Versions across branches");
            _("Downloads"); _("Spec file"); _("Changelog"); _("Loading data…");
        }
    }
}

int main (string[] args) {
    return new PackageSearchApp ().run (args);
}
