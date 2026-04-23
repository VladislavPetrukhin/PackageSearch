/* window.vala
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.NavigationSplitView split_view;

    private SearchPage   search_page;
    private DetailsPage? current_details = null;

    private const GLib.ActionEntry[] WIN_ACTIONS = {
        { "about",     on_action_about     },
        { "quit",      on_action_quit      },
        { "shortcuts", on_action_shortcuts },
        { "focus-search", on_action_focus_search },
        { "refresh",      on_action_refresh      },
        { "close-details", on_action_close_details }
    };

    public MainWindow (Adw.Application app) {
        Object (application: app);

        // Ensure the global CSS (tags, cards, hero, etc) is loaded.
        Style.ensure ();

        // Register window actions
        this.add_action_entries (WIN_ACTIONS, this);

        // Build and attach the sidebar
        search_page = new SearchPage ();
        search_page.open_details.connect ((g, b) => show_details (g, b));
        search_page.wants_clear.connect (() => {
            search_page.focus_search_entry ();
        });
        split_view.sidebar = search_page;

        // Start with no content: only the sidebar is shown.
        // collapsed=true makes the split act like a navigation stack, so
        // the sidebar fills the whole window until the user picks a package.
        split_view.collapsed = true;

        // Keyboard shortcuts
        install_accels ();

        // Global focus: defer to an idle callback so the widget is mapped
        // before we try to grab focus in the search field.
        Idle.add (() => {
            search_page.focus_search_entry ();
            return Source.REMOVE;
        });
    }

    /* ===== Action handlers ===== */

    private void on_action_about ()     { open_about_dialog (); }
    private void on_action_quit ()      { quit_app (); }
    private void on_action_shortcuts () { show_shortcuts_window (); }

    private void on_action_focus_search () {
        // If on narrow screens details was shown, go back to sidebar first
        if (split_view.collapsed && split_view.show_content)
            split_view.show_content = false;
        search_page.focus_search_entry ();
    }

    private void on_action_refresh () {
        search_page.trigger_search_now ();
    }

    private void on_action_close_details () {
        if (split_view.collapsed && split_view.show_content)
            split_view.show_content = false;
    }

    private void install_accels () {
        var app = this.application as Gtk.Application;
        if (app == null) return;

        app.set_accels_for_action ("win.focus-search",  new string[] { "<Primary>f", "slash" });
        app.set_accels_for_action ("win.refresh",       new string[] { "F5", "<Primary>r" });
        app.set_accels_for_action ("win.close-details", new string[] { "Escape", "<Primary>w" });
        app.set_accels_for_action ("win.shortcuts",     new string[] { "<Primary>question" });
        app.set_accels_for_action ("win.quit",          new string[] { "<Primary>q" });
    }

    /* ===== Public: show details page ===== */

    public void show_details (Data.SourceGroup group, string branch) {
        var details = new DetailsPage (group, branch, this);
        current_details = details;
        split_view.content = details;
        // On wide screens: reveal the split so sidebar + details are visible
        // side-by-side. On narrow screens the breakpoint keeps collapsed=true,
        // and show_content=true slides details over the sidebar.
        split_view.collapsed = false;
        split_view.show_content = true;
    }

    /* ===== Dialogs ===== */

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
        // Translators: NAME <EMAIL>, YEAR1, YEAR2
        about.set_translator_credits (_("translator-credits"));
        about.present (this);
    }

    private void show_shortcuts_window () {
        var dlg = new Adw.Dialog ();
        dlg.set_content_width (420);
        dlg.set_content_height (420);
        dlg.set_title (_("Keyboard Shortcuts"));

        var hb = new Adw.HeaderBar () { show_end_title_buttons = true };
        hb.set_title_widget (new Adw.WindowTitle (_("Keyboard Shortcuts"), ""));

        var grp = new Adw.PreferencesGroup () { title = _("General") };
        grp.add (make_shortcut_row (_("Focus search"),             "Ctrl+F  /"));
        grp.add (make_shortcut_row (_("Refresh search"),           "F5  Ctrl+R"));
        grp.add (make_shortcut_row (_("Close details / back"),     "Esc  Ctrl+W"));
        grp.add (make_shortcut_row (_("Show keyboard shortcuts"),  "Ctrl+?"));
        grp.add (make_shortcut_row (_("Quit"),                     "Ctrl+Q"));

        var page = new Adw.PreferencesPage ();
        page.add (grp);

        var tb = new Adw.ToolbarView ();
        tb.add_top_bar (hb);
        tb.set_content (page);

        dlg.set_child (tb);
        dlg.present (this);
    }

    private static Adw.ActionRow make_shortcut_row (string title, string keys) {
        var row = new Adw.ActionRow () { title = title };
        var tag = Style.make_tag (keys, "accent");
        tag.valign = Gtk.Align.CENTER;
        row.add_suffix (tag);
        return row;
    }

    public void quit_app () {
        var a = this.application as Adw.Application;
        if (a != null) a.quit ();
    }
}

