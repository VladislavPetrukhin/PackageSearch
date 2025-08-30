using Gtk;
using Adw;
using GLib;
using Gdk;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    // Из шаблона (details_page.blp)
    [GtkChild] private unowned Gtk.Button             back_btn;
    [GtkChild] private unowned Gtk.Label              title_lbl;
    [GtkChild] private unowned Adw.PreferencesGroup   info_group;
    [GtkChild] private unowned Adw.PreferencesGroup   bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup   changelog_group;

    protected override void constructed () {
        base.constructed ();

        // «Назад»
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

    // Диалог с полным описанием одной записи changelog
private void show_changelog_dialog (string head, string body) {
    var dlg = new Adw.Dialog ();
    dlg.set_content_width (800);
    dlg.set_content_height (560);

    // Заголовочная строка: заголовок + кнопки
    var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
    header.set_margin_top (12);
    header.set_margin_start (12);
    header.set_margin_end (12);

    var title = new Gtk.Label (head ?? "") {
        xalign = 0.0f
    };
    title.add_css_class ("title-3");
    title.set_hexpand (true);
    header.append (title);

    var copy_btn = new Gtk.Button.with_label ("Copy");
    copy_btn.clicked.connect (() => {
        var disp = Gdk.Display.get_default ();
        if (disp != null) {
            var cb = disp.get_clipboard ();
            cb.set_text (body ?? "");
        }
    });
    header.append (copy_btn);

    var close_btn = new Gtk.Button.with_label ("Close");
    close_btn.clicked.connect (() => dlg.close ());
    header.append (close_btn);

    // Текст changelog в TextView внутри скролла
    var tv = new Gtk.TextView () {
        editable = false,
        cursor_visible = false,
        wrap_mode = Gtk.WrapMode.WORD_CHAR
    };
    tv.add_css_class ("monospace");
    tv.buffer.set_text (body ?? "");

    var sw = new Gtk.ScrolledWindow () { vexpand = true };
    sw.set_child (tv);
    sw.set_margin_start (12);
    sw.set_margin_end (12);
    sw.set_margin_bottom (12);

    // Вертикальный контейнер диалога
    var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
    vbox.append (header);
    vbox.append (sw);

    dlg.set_child (vbox);
    dlg.present (this.get_root () as Gtk.Window);
}


    private async void load_details () {
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            // Крупный заголовок сверху (в шапке)
            title_lbl.set_text (group.name);

            // Заголовок NavigationPage (мелкий в навигации)
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
            int bins = 0;
            foreach (var bp in d.binaries) {
                message ("[Bins] name='%s' arch='%s'", bp.name ?? "<null>", bp.arch ?? "<null>");
                var subtitle = (bp.arch ?? "");
                bins_group.add (new Adw.ActionRow () { title = bp.name, subtitle = subtitle });
                bins++;
            }
            message ("[Bins] total=%d", bins);

            // Changelog
            clear_group (changelog_group);
            try {
                var log = yield api.get_changelog (branch, group.name, 50); // 1..100
                var exp = new Adw.ExpanderRow () { title = "Changelog" };

                bool any = false;
                foreach (var it in log.changelog) {
                    any = true;

                    // Сборка заголовка
                    string head = "";
                    if (it.date != null && it.date.strip () != "")
                        head = it.date;
                    if (it.nick != null && it.nick.strip () != "")
                        head = (head == "") ? it.nick : head + " — " + it.nick;
                    if (it.evr != null && it.evr.strip () != "")
                        head = (head == "") ? ("[" + it.evr + "]") : head + " [" + it.evr + "]";

                    // ---- превью для списка: первая строка + усечение + экранирование ----
                    string preview = it.message ?? "";
                    preview = preview.strip ();

                    // первая строка
                    int nl = preview.index_of_char ('\n');
                    if (nl >= 0)
                        preview = preview.substring (0, nl);

                    // ограничим длину, чтобы точно влезало в одну строку
                    const int MAX_PREVIEW = 200;
                    if (preview.length > MAX_PREVIEW)
                        preview = preview.substring (0, MAX_PREVIEW) + "…";

                    // экранируем под markup (нужно для ActionRow)
                    preview = GLib.Markup.escape_text (preview, -1);

                    // лог для проверки
                    message ("[Changelog] head='%s' preview='%s' full_len=%u",
                             head, preview, (uint) (it.message != null ? it.message.length : 0));

                    // строка списка
                    var row = new Adw.ActionRow () {
                        title = (head != "") ? head : "Change",
                        subtitle = preview
                    };

                    try {
                        row.set_subtitle_lines (1);
                    } catch (Error e) {

                    }

                    row.activatable = true;
                    row.activated.connect (() => {
                        show_changelog_dialog (row.title, it.message ?? "");
                    });

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

            // отладка
            message ("[DetailsPage] filled: info_rows=%u, bins=%u, changelog_rows=%u",
                     count_rows (info_group), count_rows (bins_group), count_rows (changelog_group));

        } catch (Error e) {
            warning (@"[DetailsPage] load failed: %s", e.message);
        }
    }
}

