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

    public MainWindow (Adw.Application app) {
        Object (application: app);

        // первая страница
        var search = new SearchPage ();
        var search_page = new Adw.NavigationPage (search, _("Search"));
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
        var details_page = new Adw.NavigationPage (details, _("Details"));
        nav_view.push (details_page);
    }

    public void open_prefs_dialog () {
        var dlg = new Adw.AlertDialog ("Preferences", _("Not implemented yet"));
        dlg.add_response ("ok", "OK");
        dlg.set_default_response ("ok");
        dlg.present (this);
    }

    public void open_about_dialog () {
        show_about ();
    }

    public void quit_app () {
        var a = this.application as Adw.Application;
        if (a != null) a.quit ();
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
