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
        this.group = group;
        this.branch = branch;
        this.win = win;

        // Заголовок
        title_lbl.set_text(group.src_name);

        // Общее
        info_group.add(new Adw.ActionRow() { title = "Source", subtitle = group.src_name });
        if (group.version != null || group.release != null) {
            info_group.add(new Adw.ActionRow() { title = "Version-Release", subtitle = "%s-%s".printf(group.version ?? "?", group.release ?? "?") });
        }

        // Бинарные пакеты
        foreach (var b in group.binaries) {
            bins_group.add(new Adw.ActionRow() { title = b.name, subtitle = "%s-%s.%s".printf(b.version, b.release, b.arch) });
        }
    }
}

