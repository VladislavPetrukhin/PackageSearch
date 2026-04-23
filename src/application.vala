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
            _("Installation is available only for the system repository (%s)");
            // SearchPage
            _("Search"); _("Type a package name…"); _("Search packages");
            _("Start typing a source package name, then pick it from the results.");
            _("Loading results…"); _("No results"); _("Try refining your query or choose another branch.");
            _("Error"); _("Failed to fetch data. Check your connection and package name.");
            // Search modes
            _("Package"); _("Binary"); _("File"); _("Maintainer"); _("Task");
            _("Type a binary package name…");
            _("Type a file path…"); _("Type a maintainer nickname…"); _("Type a package name or task ID…");
            _("No source package found for binary \"%s\"");
            _("Task #%lld  —  %s");
            // DetailsPage — extended sections
            _("Dependencies"); _("Security"); _("Versions across branches");
            _("Downloads"); _("Spec file");
            _("Build dependencies"); _("Packages required to build %s");
            _("Reverse dependencies"); _("Source packages that depend on %s");
            _("No dependencies found"); _("No reverse dependencies");
            _("Build dependencies unavailable"); _("Reverse dependencies unavailable");
            _("Bugzilla"); _("No bugs found"); _("%d bug(s) found");
            _("Bugzilla unavailable");
            _("No versions found"); _("Versions unavailable");
            _("Source (.src.rpm)"); _("Binaries (.rpm)");
            _("No source downloads"); _("No binary downloads");
            _("Source downloads unavailable"); _("Binary downloads unavailable");
            _("Copy download URL"); _("Copied");
            _("View spec file"); _("Show the RPM spec file used to build this package");
            _("Open"); _("Spec file not available"); _("Spec file unavailable: %s");
            // New UI strings
            _("Welcome to PackageSearch");
            _("Pick a search mode and start typing in the panel on the left.\nSelect a package to see its details here.");
            _("Search mode"); _("Repository branch");
            _("Keyboard Shortcuts"); _("About PackageSearch");
            _("General"); _("Focus search"); _("Refresh search"); _("Close details / back");
            _("Show keyboard shortcuts"); _("Quit");
            _("Clear search"); _("Try another branch"); _("Retry");
            _("Overview"); _("Binary packages"); _("current");
            _("Install is available only for the system repository (%s)");
            _("Open in browser"); _("Copy"); _("%d packages");
            _("Search and inspect source packages across the ALT Linux Sisyphus, p11, p10, p9, c10f2 and c9f2 repositories.");
            _("translator-credits");
        }
    }
}

int main (string[] args) {
    return new PackageSearchApp ().run (args);
}

