using Gtk;
using Adw;
using GLib;
using Gdk;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    // From template (details_page.blp)
    [GtkChild] private unowned Gtk.Button           back_btn;
    [GtkChild] private unowned Gtk.Label            title_lbl;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;
    [GtkChild] private unowned Adw.ToastOverlay     toast_overlay;
    [GtkChild] private unowned Gtk.Revealer         loading_revealer;

    //utils
    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    protected override void constructed () {
        base.constructed ();

        // Back button
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

    private void set_loading (bool on) {
        loading_revealer.reveal_child = on;
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

    // Dialog with a full changelog entry
    private void show_changelog_dialog (string head, string body) {
        var dlg = new Adw.Dialog ();
        dlg.set_content_width (800);
        dlg.set_content_height (560);

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

        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        vbox.append (header);
        vbox.append (sw);

        dlg.set_child (vbox);
        dlg.present (this.get_root () as Gtk.Window);
    }

    private async void load_details () {
        set_loading (true);
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            // Header title
            title_lbl.set_text (group.name);

            // NavigationPage title (small, in NavigationView)
            var vr = (d.version ?? "");
            if (is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;

            // Info group
            clear_group (info_group);
            if (is_nonempty (d.version))     info_group.add (new Adw.ActionRow () { title = "Version",     subtitle = d.version });
            if (is_nonempty (d.release))     info_group.add (new Adw.ActionRow () { title = "Release",     subtitle = d.release });
            if (is_nonempty (d.maintainer))  info_group.add (new Adw.ActionRow () { title = "Maintainer",  subtitle = d.maintainer });
            if (is_nonempty (d.group))       info_group.add (new Adw.ActionRow () { title = "Group",       subtitle = d.group });
            if (is_nonempty (d.license))     info_group.add (new Adw.ActionRow () { title = "License",     subtitle = d.license });
            if (is_nonempty (d.homepage))    info_group.add (new Adw.ActionRow () { title = "Homepage",    subtitle = d.homepage });
            if (is_nonempty (d.summary))     info_group.add (new Adw.ActionRow () { title = "Summary",     subtitle = d.summary });
            if (is_nonempty (d.description)) info_group.add (new Adw.ActionRow () { title = "Description", subtitle = d.description });

            // Binaries
            clear_group (bins_group);
            int bins = 0;
            foreach (var bp in d.binaries) {
                var subtitle = (bp.arch ?? "");
                bins_group.add (new Adw.ActionRow () { title = bp.name, subtitle = subtitle });
                bins++;
            }

            // Changelog
            clear_group (changelog_group);
            try {
                var log = yield api.get_changelog (branch, group.name, 50); // 1..100
                var exp = new Adw.ExpanderRow () { title = "Changelog" };

                bool any = false;
                foreach (var it in log.changelog) {
                    any = true;

                    string head = "";
                    if (is_nonempty (it.date)) head = it.date;
                    if (is_nonempty (it.nick)) head = (head == "") ? it.nick : head + " — " + it.nick;
                    if (is_nonempty (it.evr))  head = (head == "") ? ("[" + it.evr + "]") : head + " [" + it.evr + "]";

                    string preview = it.message ?? "";
                    preview = preview.strip ();
                    int nl = preview.index_of_char ('\n');
                    if (nl >= 0) preview = preview.substring (0, nl);
                    const int MAX_PREVIEW = 200;
                    if (preview.length > MAX_PREVIEW) preview = preview.substring (0, MAX_PREVIEW) + "…";
                    preview = GLib.Markup.escape_text (preview, -1);

                    var row = new Adw.ActionRow () {
                        title = (head != "") ? head : "Change",
                        subtitle = preview
                    };
                    row.set_subtitle_lines (1);

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

            message ("[DetailsPage] filled: info_rows=%u, bins=%u, changelog_rows=%u",
                     count_rows (info_group), count_rows (bins_group), count_rows (changelog_group));

        } catch (Error e) {
            warning (@"[DetailsPage] load failed: %s", e.message);
            toast_overlay.add_toast (new Adw.Toast ("Failed to load package details"));
        } finally {
            set_loading (false);
        }
    }
}

