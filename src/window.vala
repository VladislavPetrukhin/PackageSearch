/* window.vala
 *
 * Copyright 2025 Unknown
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
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

    private Gtk.MenuButton menu_btn;

    public MainWindow (Adw.Application app) {
        Object (application: app);

        var hb = new Adw.HeaderBar ();
        toolbar_view.add_top_bar (hb);

        menu_btn = new Gtk.MenuButton () {
            icon_name = "open-menu-symbolic",
            tooltip_text = _("Menu")
        };
        hb.pack_end (menu_btn);

        var pop = new Gtk.Popover ();
        menu_btn.set_popover (pop);

        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vbox.margin_top = 6;
        vbox.margin_bottom = 6;
        vbox.margin_start = 6;
        vbox.margin_end = 6;

        // Верхние пункты меню
        var btn_about = new Gtk.Button.with_label (_("About"));
        btn_about.add_css_class ("flat");
        btn_about.halign = Gtk.Align.FILL;

        var btn_prefs = new Gtk.Button.with_label (_("Preferences"));
        btn_prefs.add_css_class ("flat");
        btn_prefs.halign = Gtk.Align.FILL;

        var sep = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);

        var btn_quit = new Gtk.Button.with_label (_("Quit"));
        btn_quit.add_css_class ("flat");
        btn_quit.halign = Gtk.Align.FILL;

        vbox.append (btn_about);
        vbox.append (btn_prefs);
        vbox.append (sep);
        vbox.append (btn_quit);

        pop.set_child (vbox);

        // Обработчики
        btn_about.clicked.connect (() => { pop.popdown (); show_about (); });
        btn_prefs.clicked.connect (() => { pop.popdown (); var pw = new PrefsWindow (this); pw.present (); });
        btn_quit.clicked.connect  (() => {
            pop.popdown ();
            var a = this.application as Adw.Application;
            if (a != null) a.quit ();
        });

        btn_quit.clicked.connect (() => {
            pop.popdown ();
            var a = this.application as Adw.Application;
            if (a != null) a.quit ();
        });


        // хоткеи
        var shortcuts = new Gtk.ShortcutController ();
        shortcuts.add_shortcut (new Gtk.Shortcut (
            Gtk.ShortcutTrigger.parse_string ("<Control>q"),
            new Gtk.CallbackAction ((self, args) => {
                var a = this.application as Adw.Application;
                if (a != null) a.quit ();
                return true;
            })
        ));
        shortcuts.add_shortcut (new Gtk.Shortcut (
            Gtk.ShortcutTrigger.parse_string ("<Control>comma"),
            new Gtk.CallbackAction ((self, args) => {
                var dlg = new Adw.AlertDialog ("Preferences", _("Not implemented yet"));
                dlg.add_response ("ok", "OK");
                dlg.set_default_response ("ok");
                dlg.present (this);
                return true;
            })
        ));
        this.add_controller (shortcuts);

        // первая страница
        var search = new SearchPage ();
        var search_page = new Adw.NavigationPage (search, "Search");
        nav_view.push (search_page);
    }

    private void show_about () {
        var about = new Adw.AboutDialog ();
        about.set_application_name ("PackageSearch");
        about.set_application_icon ("org.example.PackageSearch");
        about.set_developer_name ("Vladislav Petrukhin");
        about.set_version ("0.1");
        about.set_issue_url ("https://altlinux.space/vladislavpetrukhin/PackageScan");
        about.set_license_type (Gtk.License.GPL_3_0);
        about.present (this);
    }

    public void show_details (Data.SourceGroup group, string branch) {
        var details = new DetailsPage (group, branch, this);
        var details_page = new Adw.NavigationPage (details, "Details");
        nav_view.push (details_page);
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

