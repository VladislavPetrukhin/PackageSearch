// src/views/details_page.vala
using Gtk;
using Adw;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    [GtkChild] private unowned Gtk.Label title_lbl;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        title_lbl.set_text (group.name);

        // загрузим детали асинхронно
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


    private async void load_details () {
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            // Очистим группы и положим строки
            clear_group (info_group);

            info_group.add (new Adw.ActionRow () { title = "Version",    subtitle = d.version     ?? "" });
            info_group.add (new Adw.ActionRow () { title = "Release",    subtitle = d.release     ?? "" });
            info_group.add (new Adw.ActionRow () { title = "Maintainer", subtitle = d.maintainer  ?? "" });
            info_group.add (new Adw.ActionRow () { title = "License",    subtitle = d.license     ?? "" });
            if (d.group != null && d.group.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Group",  subtitle = d.group       ?? "" });
            if (d.homepage != null && d.homepage.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Homepage", subtitle = d.homepage ?? "" });

            if (d.summary != null && d.summary.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Summary", subtitle = d.summary   ?? "" });
            if (d.description != null && d.description.strip () != "")
                info_group.add (new Adw.ActionRow () { title = "Description", subtitle = d.description ?? "" });

            // Бинарные пакеты
            for (var child = bins_group.get_first_child (); child != null; ) {
            var next = child.get_next_sibling ();
            bins_group.remove (child as Adw.PreferencesRow);
            child = next;
        }
            clear_group (bins_group);

            // Обновим заголовок секции (если у тебя есть)
            // set_title (@"$(group.name) $(d.version ?? "")-$(d.release ?? "")");

        } catch (Error e) {
            warning (@"[DetailsPage] load failed: $(e.message)");
        }
    }
}

