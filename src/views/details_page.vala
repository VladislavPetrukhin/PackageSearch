using Gtk;
using Adw;
using GLib;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    [GtkChild] private unowned Gtk.Button          back_btn;
    [GtkChild] private unowned Gtk.Label            title_lbl;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;

    protected override void constructed () {
        base.constructed ();
        // Кнопка «Назад»
        back_btn.clicked.connect (() => {
            var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
            if (nav != null) {
                var prev = nav.get_previous_page (nav.get_visible_page ());
                if (prev != null)
                    nav.pop ();
            }
        });
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        title_lbl.set_text (group.name);
        message ("[DetailsPage] open %s (%s)", group.name, branch);

        load_details.begin ();
    }

    private void clear_group (Adw.PreferencesGroup grp) {
        for (var child = grp.get_first_child (); child != null; ) {
            var next = child.get_next_sibling ();
            var row = child as Adw.PreferencesRow;
            if (row != null) grp.remove (row);
            child = next;
        }
    }

    private uint count_rows (Adw.PreferencesGroup grp) {
        uint n = 0;
        for (var child = grp.get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (child is Adw.PreferencesRow) n++;
        }
        return n;
    }

    private async void load_details () {
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            // Заголовок
            var vr = (d.version ?? "");
            if (d.release != null && d.release.strip () != "")
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;

            // Инфо
            clear_group (info_group);
            if (d.version     != null && d.version.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Version",     subtitle = d.version });
            if (d.release     != null && d.release.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Release",     subtitle = d.release });
            if (d.maintainer  != null && d.maintainer.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Maintainer",  subtitle = d.maintainer });
            if (d.group       != null && d.group.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Group",       subtitle = d.group });
            if (d.license     != null && d.license.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "License",     subtitle = d.license });
            if (d.homepage    != null && d.homepage.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Homepage",    subtitle = d.homepage });
            if (d.summary     != null && d.summary.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Summary",     subtitle = d.summary });
            if (d.description != null && d.description.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Description", subtitle = d.description });

            // Бинарники
            clear_group (bins_group);
            foreach (var bp in d.binaries) {
                var subtitle = (bp.arch ?? "");
                bins_group.add (new Adw.ActionRow () { title = bp.name, subtitle = subtitle });
            }

            // Changelog
            clear_group (changelog_group);
            try {
                var log = yield api.get_changelog (branch, group.name, 20); // 1..100
                var exp = new Adw.ExpanderRow () { title = "Changelog (last 20)" };

                bool any = false;
                foreach (var it in log.changelog) {
                    any = true;

                    string head = "";
                    if (it.date != null && it.date.strip () != "")
                        head = it.date;
                    if (it.nick != null && it.nick.strip () != "")
                        head = (head == "") ? it.nick : head + " — " + it.nick;
                    if (it.evr != null && it.evr.strip () != "")
                        head = (head == "") ? ("[" + it.evr + "]") : head + " [" + it.evr + "]";

                    var row = new Adw.ActionRow () {
                        title = (head != "") ? head : "Change",
                        subtitle = (it.message != null) ? it.message : ""
                    };
                    exp.add_row (row);
                }

                if (!any) {
                    exp.add_row (new Adw.ActionRow () { title = "No changes found" });
                }

                changelog_group.add (exp);
            } catch (Error ce) {
                warning ("[DetailsPage] changelog failed: %s", ce.message);
                changelog_group.add (new Adw.ActionRow () {
                    title = "Changelog unavailable",
                    subtitle = ce.message
                });
            }

            message ("[DetailsPage] filled: info_rows=%u, bins=%u, changelog_rows=%u",
                     count_rows (info_group), count_rows (bins_group), count_rows (changelog_group));

        } catch (Error e) {
            warning (@"[DetailsPage] load failed: %s", e.message);
        }
    }

}

