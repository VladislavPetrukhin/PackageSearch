/* window.vala
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.ToolbarView    toolbar_view;
    [GtkChild] private unowned Adw.NavigationView nav_view;

    [GtkChild] private unowned Gtk.Button         back_btn;
    [GtkChild] private unowned Gtk.DropDown       branch_dropdown;
    [GtkChild] private unowned Gtk.DropDown       mode_dropdown;
    [GtkChild] private unowned Gtk.SearchEntry    search_entry;
    [GtkChild] private unowned Gtk.Stack          header_stack;
    [GtkChild] private unowned Gtk.Label          title_lbl;
    [GtkChild] private unowned Gtk.MenuButton     menu_btn;

    // --- Internal state ---
    private SearchPage search_page;

    /* Window actions for the app menu */
    private const GLib.ActionEntry[] WIN_ACTIONS = {
        { "about",    on_action_about    },
        { "quit",     on_action_quit     }
    };

    public MainWindow (Adw.Application app) {
        Object (application: app);

        // Register window-scoped actions
        this.add_action_entries (WIN_ACTIONS, this);

        // Initial page: search
        search_page = new SearchPage ();
        search_page.open_details.connect ((g, b) => {
            show_details (g, b);
        });

        var page = new Adw.NavigationPage (search_page, _("Search"));
        nav_view.push (page);

        // Configure header controls and initial state
        setup_header_controls ();
        update_header_for_visible_page ();
        nav_view.notify["visible-page"].connect (update_header_for_visible_page);

        // Small CSS tweak for compact headerbar
        var css = """
        headerbar {
          min-height: 40px;
          padding-top: 0;
          padding-bottom: 0;
        }
        """;
        var provider = new Gtk.CssProvider ();
        provider.load_from_string (css);
        var disp = Gdk.Display.get_default ();
        if (disp != null)
            Gtk.StyleContext.add_provider_for_display (disp, provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    /* ===== Menu action handlers ===== */
    private void on_action_about ()    { open_about_dialog (); }
    private void on_action_quit ()     { quit_app (); }

    /* ===== Header & navigation wiring ===== */

    // Search mode labels (indices match Data.SearchMode enum)
    private const string[] MODE_LABELS = {
        "Package", "Binary", "File", "Maintainer", "Task"
    };

    private const string[] MODE_PLACEHOLDERS = {
        "Type a package name…",
        "Type a binary package name…",
        "Type a file path…",
        "Type a maintainer nickname…",
        "Type a package name or task ID…"
    };

    // Initialize branch dropdown, mode dropdown, search entry callbacks, and back button
    private void setup_header_controls () {
        var branches_model = new Gtk.StringList (null);
        string[] branch_names = { "sisyphus", "p11", "p10", "p9", "c10f2", "c9f2" };
        foreach (string b in branch_names) branches_model.append (b);
        branch_dropdown.model = branches_model;
        branch_dropdown.selected = 0;

        // Mode dropdown
        var modes_model = new Gtk.StringList (null);
        foreach (string m in MODE_LABELS) modes_model.append (_(m));
        mode_dropdown.model = modes_model;
        mode_dropdown.selected = 0;

        mode_dropdown.notify["selected"].connect (() => {
            var mode = (Data.SearchMode) mode_dropdown.selected;
            search_page.set_mode (mode);
            search_entry.set_placeholder_text (_(MODE_PLACEHOLDERS[mode]));
            // Clear and re-search on mode change
            search_page.set_query ((search_entry.text ?? "").strip ());
            search_page.trigger_search_now ();
        });

        // Propagate initial values to the SearchPage
        search_page.set_branch (get_current_branch ());
        search_page.set_mode ((Data.SearchMode) mode_dropdown.selected);
        search_page.set_query ((search_entry.text ?? "").strip ());

        // Live search with debounce on typing
        search_entry.search_changed.connect (() => {
            search_page.set_query ((search_entry.text ?? "").strip ());
            search_page.trigger_search_debounced ();
        });

        // Immediate search on Enter
        search_entry.activate.connect (() => {
            search_page.set_query ((search_entry.text ?? "").strip ());
            search_page.trigger_search_now ();
        });

        // Change branch triggers a fresh search
        branch_dropdown.notify["selected"].connect (() => {
            search_page.set_branch (get_current_branch ());
            search_page.trigger_search_now ();
        });

        // Back button only pops details page
        back_btn.clicked.connect (() => {
            var vpage = nav_view.get_visible_page ();
            if (vpage != null && vpage.get_child () is DetailsPage)
                nav_view.pop ();
        });
    }

    // Read the current branch name from dropdown; defaults to "sisyphus"
    private string get_current_branch () {
        int idx = (int) branch_dropdown.selected;
        var m = branch_dropdown.model as Gtk.StringList;
        if (m == null || idx < 0) return "sisyphus";
        return m.get_string ((uint) idx);
    }

    // Update header content and visibility depending on the current page
    private void update_header_for_visible_page () {
        var vpage = nav_view.get_visible_page ();
        bool on_details = (vpage != null) && (vpage.get_child () is DetailsPage);

        back_btn.visible = on_details;
        branch_dropdown.visible = !on_details;
        mode_dropdown.visible = !on_details;

        if (on_details) {
            header_stack.set_visible_child_name ("title");
            var dp = vpage.get_child () as DetailsPage;
            title_lbl.label = dp != null ? (dp.title ?? _("Details")) : _("Details");
        } else {
            header_stack.set_visible_child_name ("search");
            title_lbl.label = "PackageSearch";
        }
    }

    /* ===== Public helpers (used by SearchPage callback) ===== */

    // Push a new details page and reflect the header state
    public void show_details (Data.SourceGroup group, string branch) {
        var details = new DetailsPage (group, branch, this);
        var details_page = new Adw.NavigationPage (details, _("Details"));
        nav_view.push (details_page);
        update_header_for_visible_page ();
    }

    /* ===== Dialogs and app control ===== */

    public void open_about_dialog () {
        var about = new Adw.AboutDialog ();
        about.set_application_icon ("space.altlinux.PackageSearch");
        about.set_application_name ("PackageSearch");
        about.set_developer_name ("Vladislav Petrukhin");
        about.set_version ("0.1");
        about.set_issue_url ("https://altlinux.space/vladislavpetrukhin/PackageSearch");
        about.set_license_type (Gtk.License.GPL_3_0);
        about.set_comments (_("GTK4/Libadwaita application for searching for packages in the ALT Linux Sisyphus, p11, p10, p9, c10f2 and c9f2 repositories and viewing detailed package information."));
        about.set_website ("https://altlinux.space/vladislavpetrukhin/PackageSearch");
        about.present (this);
    }

    public void quit_app () {
        var a = this.application as Adw.Application;
        if (a != null) a.quit ();
    }
}

