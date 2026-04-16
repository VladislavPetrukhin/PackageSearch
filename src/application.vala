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

        // Fallback to system-wide default
        return "/usr/share/locale";
    }

    // Initialize gettext for the app
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
        if (false) {
            // DetailsPage
            _("Details"); _("Back"); _("Info"); _("Binaries"); _("Changelog"); _("Loading data…");
            _("Install"); _("Installing…"); _("Installed");
            _("Update");  _("Updating…");
            _("Install via apt-get (requires authentication)");
            _("Update via apt-get (requires authentication)");
            _("Package is already installed");
            _("Installing %s…"); _("Installed %s"); _("Failed to install %s");
            _("Updating %s…");   _("Updated %s");   _("Failed to update %s");
            _("Installation cancelled"); _("Failed to launch installer: %s");
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

