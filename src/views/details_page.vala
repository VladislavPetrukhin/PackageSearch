using Gtk;
using Adw;
using GLib;
using Gdk;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    [GtkChild] private unowned Gtk.Label            title_lbl;
    [GtkChild] private unowned Gtk.MenuButton       menu_btn;
    [GtkChild] private unowned Gtk.Button           close_btn;
    [GtkChild] private unowned Adw.ToastOverlay     toast_overlay;
    [GtkChild] private unowned Gtk.Revealer         loading_revealer;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;

    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    protected override void constructed () {
        base.constructed ();

        var pop = new Gtk.Popover ();
        menu_btn.set_popover (pop);

        var pv = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        pv.margin_top = 6;
        pv.margin_bottom = 6;
        pv.margin_start = 6;
        pv.margin_end = 6;

        var btn_lang = new Gtk.Button.with_label (_("Language…"));
        btn_lang.add_css_class ("flat");
        btn_lang.halign = Gtk.Align.FILL;
        btn_lang.clicked.connect (() => {
            pop.popdown ();
            open_language_dialog ();
        });

        var btn_about = new Gtk.Button.with_label (_("About"));
        btn_about.add_css_class ("flat");
        btn_about.halign = Gtk.Align.FILL;

        var btn_quit_menu = new Gtk.Button.with_label (_("Quit"));
        btn_quit_menu.add_css_class ("flat");
        btn_quit_menu.halign = Gtk.Align.FILL;

        pv.append (btn_lang);
        pv.append (btn_about);
        pv.append (btn_quit_menu);
        pop.set_child (pv);

        btn_about.clicked.connect (() => {
            pop.popdown ();
            var root = this.get_root () as MainWindow;
            if (root != null) root.open_about_dialog ();
        });
        btn_quit_menu.clicked.connect (() => {
            pop.popdown ();
            var root = this.get_root () as MainWindow;
            if (root != null) root.quit_app ();
        });

        close_btn.clicked.connect (() => {
            var root = this.get_root () as MainWindow;
            if (root != null) root.quit_app ();
        });
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        title_lbl.set_text (group.name);
        load_details.begin ();
    }

    // ---------- Language dialog ----------
    private void open_language_dialog () {
        var dlg = new Adw.AlertDialog (_("Language"), _("Choose interface language"));
        dlg.add_response ("sys", _("System"));
        dlg.add_response ("en",  "English");
        dlg.add_response ("ru",  "Русский");

        var lang = Environment.get_variable ("LANGUAGE");
        string def = "sys";
        if (lang != null && lang != "") {
            if (lang.has_prefix ("en")) def = "en";
            else if (lang.has_prefix ("ru")) def = "ru";
        }
        dlg.set_default_response (def);
        dlg.set_close_response ("close");

        dlg.response.connect ((resp) => {
            string? code = null;
            switch (resp) {
                case "sys": code = null; break;
                case "en":  code = "en"; break;
                case "ru":  code = "ru"; break;
                default: return;
            }
            var root = this.get_root () as MainWindow;
            if (root != null) root.apply_language (code);
        });

        dlg.present (this.get_root () as Gtk.Window);
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

    private void show_changelog_dialog (string head, string body) {
        var dlg = new Adw.Dialog ();
        dlg.set_content_width (800);
        dlg.set_content_height (560);

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        header.set_margin_top (12);
        header.set_margin_start (12);
        header.set_margin_end (12);

        var title = new Gtk.Label (head ?? "") { xalign = 0.0f };
        title.add_css_class ("title-3");
        title.set_hexpand (true);
        header.append (title);

        var copy_btn = new Gtk.Button.with_label (_("Copy"));
        copy_btn.clicked.connect (() => {
            var disp = Gdk.Display.get_default ();
            if (disp != null) {
                var cb = disp.get_clipboard ();
                cb.set_text (body ?? "");
            }
        });
        header.append (copy_btn);

        var close_btn = new Gtk.Button.with_label (_("Close"));
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

            title_lbl.set_text (group.name);

            var vr = (d.version ?? "");
            if (is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;

            clear_group (info_group);
            if (is_nonempty (d.version))     info_group.add (new Adw.ActionRow () { title = _("Version"),     subtitle = d.version });
            if (is_nonempty (d.release))     info_group.add (new Adw.ActionRow () { title = _("Release"),     subtitle = d.release });
            if (is_nonempty (d.maintainer))  info_group.add (new Adw.ActionRow () { title = _("Maintainer"),  subtitle = d.maintainer });
            if (is_nonempty (d.group))       info_group.add (new Adw.ActionRow () { title = _("Group"),       subtitle = d.group });
            if (is_nonempty (d.license))     info_group.add (new Adw.ActionRow () { title = _("License"),     subtitle = d.license });
            if (is_nonempty (d.homepage))    info_group.add (new Adw.ActionRow () { title = _("Homepage"),    subtitle = d.homepage });
            if (is_nonempty (d.summary))     info_group.add (new Adw.ActionRow () { title = _("Summary"),     subtitle = d.summary });
            if (is_nonempty (d.description)) info_group.add (new Adw.ActionRow () { title = _("Description"), subtitle = d.description });

            clear_group (bins_group);
            foreach (var bp in d.binaries) {
                var subtitle = (bp.arch ?? "");
                bins_group.add (new Adw.ActionRow () { title = bp.name, subtitle = subtitle });
            }

            clear_group (changelog_group);
            try {
                var log = yield api.get_changelog (branch, group.name, 50);
                var exp = new Adw.ExpanderRow () { title = _("Changelog") };

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
                        title = (head != "") ? head : _("Change"),
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
                    exp.add_row (new Adw.ActionRow () { title = _("No changes found") });
                }

                changelog_group.add (exp);
            } catch (Error ce) {
                warning ("[DetailsPage] changelog failed: %s", ce.message);
                changelog_group.add (new Adw.ActionRow () {
                    title = _("Changelog unavailable"),
                    subtitle = ce.message
                });
            }

            message ("[DetailsPage] filled: info_rows=%u, bins=%u, changelog_rows=%u",
                     count_rows (info_group), count_rows (bins_group), count_rows (changelog_group));

        } catch (Error e) {
            warning (@"[DetailsPage] load failed: %s", e.message);
            toast_overlay.add_toast (new Adw.Toast (_("Failed to load package details")));
        } finally {
            set_loading (false);
        }
    }
}

