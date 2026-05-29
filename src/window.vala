using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.NavigationView nav_view;

    private SearchPage   search_page;
    private DetailsPage? current_details = null;

    private const GLib.ActionEntry[] WIN_ACTIONS = {
        { "about",         on_action_about         },
        { "quit",          on_action_quit          },
        { "focus-search",  on_action_focus_search  },
        { "refresh",       on_action_refresh       },
        { "back",          on_action_back          },
        { "clear-history", on_action_clear_history }
    };

    public MainWindow (Adw.Application app) {
        Object (application: app);

        this.add_action_entries (WIN_ACTIONS, this);

        search_page = new SearchPage ();
        search_page.open_details.connect ((g, b) => show_details (g, b));
        nav_view.add (search_page);

        install_accels ();

        Idle.add (() => {
            search_page.focus_search_entry ();
            return Source.REMOVE;
        });
    }

    private void on_action_about ()    { open_about_dialog (); }
    private void on_action_quit ()     { quit_app (); }

    private void on_action_focus_search () {
        if (nav_view.visible_page == search_page)
            search_page.focus_search_entry ();
    }

    private void on_action_refresh () {
        search_page.trigger_search_now ();
    }

    private void on_action_back () {
        if (nav_view.visible_page != search_page)
            nav_view.pop ();
    }

    private void on_action_clear_history () {
        search_page.clear_history ();
    }

    private void install_accels () {
        var app = this.application as Gtk.Application;
        if (app == null) return;

        app.set_accels_for_action ("win.focus-search", new string[] { "<Primary>f", "slash" });
        app.set_accels_for_action ("win.refresh",      new string[] { "F5", "<Primary>r" });
        app.set_accels_for_action ("win.back",         new string[] { "<Primary>w" });
        app.set_accels_for_action ("win.quit",         new string[] { "<Primary>q" });
    }

    public void show_details (Data.SourceGroup group, string branch) {
        if (current_details != null) current_details.cancel_loading ();

        var details = new DetailsPage (group, branch, this);
        current_details = details;
        nav_view.push (details);
    }

    public void show_maintainer (string nick, string branch) {
        nav_view.push (new MaintainerPage (this, nick, branch));
    }

    public void show_dependency_graph (string pkg_name, string branch) {
        nav_view.push (new DependencyGraphPage (this, pkg_name, branch));
    }

    public void open_about_dialog () {
        var about = new Adw.AboutDialog ();
        about.set_application_icon ("space.altlinux.PackageSearch");
        about.set_application_name ("PackageSearch");
        about.set_developer_name ("Vladislav Petrukhin");
        about.set_version ("0.1");
        about.set_issue_url ("https://altlinux.space/vladislavpetrukhin/PackageSearch/-/issues");
        about.set_license_type (Gtk.License.GPL_3_0);
        about.set_comments (_("Search and inspect source packages across the ALT Linux Sisyphus, p11, p10, p9, c10f2 and c9f2 repositories."));
        about.set_website ("https://altlinux.space/vladislavpetrukhin/PackageSearch");
        about.set_copyright ("© 2025 Vladislav Petrukhin");
        about.set_developers (new string[] { "Vladislav Petrukhin" });
        about.set_translator_credits (_("translator-credits"));
        about.present (this);
    }

    public void quit_app () {
        var a = this.application as Adw.Application;
        if (a != null) a.quit ();
    }
}
