using Gtk;
using Adw;
using GLib;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    [GtkChild] private unowned Gtk.Label              title_lbl;
    [GtkChild] private unowned Adw.PreferencesGroup   info_group;
    [GtkChild] private unowned Adw.PreferencesGroup   bins_group;

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

            // Заголовок страницы и тайтл
            var vr = (d.version ?? "");
            if (d.release != null && d.release.strip () != "")
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;

            // Инфоблок
            clear_group (info_group);
            if (d.version     != null) info_group.add (new Adw.ActionRow () { title = "Version",     subtitle = d.version });
            if (d.release     != null) info_group.add (new Adw.ActionRow () { title = "Release",     subtitle = d.release });
            if (d.maintainer  != null) info_group.add (new Adw.ActionRow () { title = "Maintainer",  subtitle = d.maintainer });
            if (d.group       != null) info_group.add (new Adw.ActionRow () { title = "Group",       subtitle = d.group });
            if (d.license     != null) info_group.add (new Adw.ActionRow () { title = "License",     subtitle = d.license });
            if (d.homepage    != null) info_group.add (new Adw.ActionRow () { title = "Homepage",    subtitle = d.homepage });
            if (d.summary     != null) info_group.add (new Adw.ActionRow () { title = "Summary",     subtitle = d.summary });
            if (d.description != null) info_group.add (new Adw.ActionRow () { title = "Description", subtitle = d.description });

            // Бинарники
            clear_group (bins_group);
            foreach (var bp in d.binaries) {
                var subtitle = (bp.arch ?? "");
                var row = new Adw.ActionRow () { title = bp.name, subtitle = subtitle };
                bins_group.add (row);
            }

            message ("[DetailsPage] filled: info_rows=%u, bins=%u",
                     count_rows (info_group), count_rows (bins_group));

           // changelog
        /*    try {
                 var log = yield api.get_changelog (branch, group.name, 20);
                 var exp = new Adw.ExpanderRow () { title = "Changelog (last 20)" };
                 foreach (var it in log.items) {
                     var t = @"%(it.date ?? \"\") — %(it.author ?? \"\")";
                     exp.add_row (new Adw.ActionRow () { title = t, subtitle = it.message ?? "" });
                 }
                 info_group.add (exp);
             } catch (Error ce) {
                 warning ("[DetailsPage] changelog failed: %s", ce.message);
             }*/

        } catch (Error e) {
            warning (@"[DetailsPage] load failed: %s", e.message);
        }
    }
}

