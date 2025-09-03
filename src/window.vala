/* window.vala
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.ToolbarView    toolbar_view;
    [GtkChild] private unowned Adw.NavigationView nav_view;

    [GtkChild] private unowned Gtk.Button         back_btn;
    [GtkChild] private unowned Gtk.DropDown       branch_dropdown;
    [GtkChild] private unowned Gtk.SearchEntry    search_entry;
    [GtkChild] private unowned Gtk.Stack          header_stack;
    [GtkChild] private unowned Gtk.Label          title_lbl;
    [GtkChild] private unowned Gtk.MenuButton     menu_btn;

    private SearchPage search_page;

    /* Actions для меню */
    private const GLib.ActionEntry[] WIN_ACTIONS = {
        { "language", on_action_language },
        { "about",    on_action_about    },
        { "quit",     on_action_quit     }
    };

    public MainWindow (Adw.Application app) {
        Object (application: app);

        /* Регистрируем actions для menu-model */
        this.add_action_entries (WIN_ACTIONS, this);

        search_page = new SearchPage ();
        search_page.open_details.connect ((g, b) => {
            show_details (g, b);
        });

        var page = new Adw.NavigationPage (search_page, _("Search"));
        nav_view.push (page);

        setup_header_controls ();
        update_header_for_visible_page ();

        nav_view.notify["visible-page"].connect (update_header_for_visible_page);

        try {
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
        } catch (Error e) {
            warning ("CSS for headerbar failed: %s", e.message);
        }
    }

    /* === Handlers для menu actions === */
    private void on_action_language () { open_language_dialog (); }
    private void on_action_about ()    { open_about_dialog (); }
    private void on_action_quit ()     { quit_app (); }

    private void setup_header_controls () {
        var branches_model = new Gtk.StringList (null);
        string[] branch_names = { "sisyphus", "p11" };
        foreach (string b in branch_names) branches_model.append (b);
        branch_dropdown.model = branches_model;
        branch_dropdown.selected = 0;

        search_page.set_branch (get_current_branch ());
        search_page.set_query ((search_entry.text ?? "").strip ());

        search_entry.search_changed.connect (() => {
            search_page.set_query ((search_entry.text ?? "").strip ());
            search_page.trigger_search_debounced ();
        });
        search_entry.activate.connect (() => {
            search_page.set_query ((search_entry.text ?? "").strip ());
            search_page.trigger_search_now ();
        });
        branch_dropdown.notify["selected"].connect (() => {
            search_page.set_branch (get_current_branch ());
            search_page.trigger_search_now ();
        });

        back_btn.clicked.connect (() => {
            var vpage = nav_view.get_visible_page ();
            if (vpage != null && vpage.get_child () is DetailsPage)
                nav_view.pop ();
        });
    }

    private string get_current_branch () {
        int idx = (int) branch_dropdown.selected;
        var m = branch_dropdown.model as Gtk.StringList;
        if (m == null || idx < 0) return "sisyphus";
        return m.get_string ((uint) idx);
    }

    private void update_header_for_visible_page () {
        var vpage = nav_view.get_visible_page ();
        bool on_details = (vpage != null) && (vpage.get_child () is DetailsPage);

        back_btn.visible = on_details;
        branch_dropdown.visible = !on_details;

        if (on_details) {
            header_stack.set_visible_child_name ("title");
            var dp = vpage.get_child () as DetailsPage;
            title_lbl.label = dp != null ? (dp.title ?? _("Details")) : _("Details");
        } else {
            header_stack.set_visible_child_name ("search");
            title_lbl.label = "PackageSearch";
        }
    }

    public void show_details (Data.SourceGroup group, string branch) {
        var details = new DetailsPage (group, branch, this);
        var details_page = new Adw.NavigationPage (details, _("Details"));
        nav_view.push (details_page);
        update_header_for_visible_page ();
    }

    public void open_about_dialog () {
        var about = new Adw.AboutDialog ();
        about.set_application_name ("PackageSearch");
        about.set_application_icon ("org.example.PackageSearch");
        about.set_developer_name ("Vladislav Petrukhin");
        about.set_version ("0.1");
        about.set_issue_url ("https://altlinux.space/vladislavpetrukhin/PackageScan");
        about.set_license_type (Gtk.License.GPL_3_0);
        about.set_comments (_("GTK4/Libadwaita application for searching for packages in the ALT Linux Sisyphus and p11 repositories and viewing detailed package information."));
        about.set_website ("https://altlinux.space/vladislavpetrukhin/PackageScan");
        about.present (this);
    }

    public void quit_app () {
        var a = this.application as Adw.Application;
        if (a != null) a.quit ();
    }

    private void open_language_dialog () {
        var dlg = new Adw.AlertDialog (_("Language"), _("Choose interface language"));
        dlg.add_response ("sys", _("System"));
        dlg.add_response ("en",  "English");
        dlg.add_response ("ru",  "Русский");

        var lang = Environment.get_variable ("LANGUAGE");
        string def = "sys";
        if (lang != null && lang != "") {
            if (lang.has_prefix ("en")) def = "en";
            else if (lang.has_prefix ("ru")) def = "ru";
        }
        dlg.set_default_response (def);
        dlg.set_close_response ("close");

        dlg.response.connect ((resp) => {
            string? code = null;
            switch (resp) {
                case "sys": code = null; break;
                case "en":  code = "en";  break;
                case "ru":  code = "ru";  break;
                default: return;
            }
            apply_language (code);
        });

        dlg.present (this);
    }

    public void apply_language (string? lang_code) {
        var cur = Environment.get_variable ("LANGUAGE");
        if ((lang_code == null || lang_code == "")
            ? (cur == null || cur == "")
            : (cur != null && cur.has_prefix (lang_code)))
            return;

        if (lang_code == null || lang_code == "")
            Environment.unset_variable ("LANGUAGE");
        else
            Environment.set_variable ("LANGUAGE", lang_code, true);

        PackageSearchApp.init_gettext ();

        var app = (Adw.Application) this.application;
        var newwin = new MainWindow (app);
        newwin.present ();

        Idle.add (() => {
            this.destroy ();
            return Source.REMOVE;
        });
    }
}

