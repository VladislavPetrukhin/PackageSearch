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

[GtkTemplate (ui = "/org/example/PackageSearch/ui/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.ToolbarView toolbar_view;
    [GtkChild] private unowned Adw.NavigationView nav_view;

    public MainWindow (Adw.Application app) {
        Object (application: app);

        var hb = new Adw.HeaderBar ();
        toolbar_view.add_top_bar (hb);

        var search = new Views.SearchPage ();
        var search_page = new Adw.NavigationPage (search, "Search");
        nav_view.push (search_page);
    }

    public void show_details (Data.SourceGroup group, string branch) {
        var details = new DetailsPage (group, branch, this);
        var details_page = new Adw.NavigationPage (details, "Details");
        nav_view.push (details_page);
    }
}

