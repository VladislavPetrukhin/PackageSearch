using Gtk;
using Adw;
using GLib;
using Gdk;
using Intl; // for _() i18n helper

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    [GtkChild] private unowned Adw.ToastOverlay     toast_overlay;
    [GtkChild] private unowned Gtk.Revealer         loading_revealer;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;

    // Tunables kept close to usage
    private const int  MAX_CHANGE_PREVIEW = 200;
    private const int DIALOG_W = 800;
    private const int DIALOG_H = 560;

    // Simple string helpers
    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    // Safe URL normalizer: adds scheme if missing
    private static string normalize_url (string raw) {
        string url = (raw ?? "").strip ();
        if (url.length == 0) return url;
        if (!(url.has_prefix ("http://") || url.has_prefix ("https://")))
            url = "https://" + url;
        return url;
    }

    // Adds info row if value is present
    private void add_info_row_if_nonempty (string title, string? value) {
        if (is_nonempty (value))
            info_group.add (new Adw.ActionRow () { title = title, subtitle = value });
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        // Show basic title early; will be refined after details fetch
        this.title = group.name;
        load_details.begin ();
    }

    private void set_loading (bool on) {
        // Drives spinner/placeholder revealer in the template
        loading_revealer.reveal_child = on;
    }

    // Remove all rows from a group
    private void clear_group (Adw.PreferencesGroup grp) {
        for (var child = grp.get_first_child (); child != null; ) {
            var next = child.get_next_sibling ();
            var row = child as Adw.PreferencesRow;
            if (row != null) grp.remove (row);
            child = next;
        }
    }

    // Utility for tests / sanity checks (not used at runtime)
    private int count_rows (Adw.PreferencesGroup grp) {
        int n = 0;
        for (var child = grp.get_first_child (); child != null; child = child.get_next_sibling ())
            if (child is Adw.PreferencesRow) n++;
        return n;
    }

    // Minimalistic text dialog to show a full changelog entry
    private void show_changelog_dialog (string head, string body) {
        var dlg = new Adw.Dialog ();
        dlg.set_content_width (DIALOG_W);
        dlg.set_content_height (DIALOG_H);

        // Header
        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        header.set_margin_top (12);
        header.set_margin_start (12);
        header.set_margin_end (12);

        var title_lbl = new Gtk.Label (head ?? "") { xalign = 0.0f };
        title_lbl.add_css_class ("title-3");
        title_lbl.set_hexpand (true);
        header.append (title_lbl);

        var copy_btn = new Gtk.Button.with_label (_("Copy"));
        //copy_btn.add_css_class ("flat");
        copy_btn.clicked.connect (() => {
            // Copy body text to system clipboard
            var disp = Gdk.Display.get_default ();
            if (disp != null) {
                var cb = disp.get_clipboard ();
                cb.set_text (body ?? "");
            }
        });
        header.append (copy_btn);

        var close_btn = new Gtk.Button.with_label (_("Close"));
        //close_btn.add_css_class ("flat");
        close_btn.add_css_class ("suggested-action");
        close_btn.clicked.connect (() => dlg.close ());
        header.append (close_btn);

        // Body
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

    // Loads details and fills 3 groups: info, binaries, changelog
    private async void load_details () {
        set_loading (true);
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            // Compose "name version-release" title if available
            var vr = (d.version ?? "");
            if (is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;

            // Info group
            clear_group (info_group);
            add_info_row_if_nonempty (_("Version"),     d.version);
            add_info_row_if_nonempty (_("Release"),     d.release);
            add_info_row_if_nonempty (_("Maintainer"),  d.maintainer);
            add_info_row_if_nonempty (_("Group"),       d.group);
            add_info_row_if_nonempty (_("License"),     d.license);

            // Clickable homepage row (opens in default browser)
            if (is_nonempty (d.homepage)) {
                string url = normalize_url (d.homepage ?? "");
                if (url.length > 0) {
                    var row_home = new Adw.ActionRow () { title = _("Homepage"), subtitle = url };
                    row_home.activatable = true;
                    row_home.activated.connect (() => {
                        try { AppInfo.launch_default_for_uri (url, null); }
                        catch (Error e) { warning ("open url failed: %s", e.message); }
                    });
                    info_group.add (row_home);
                }
            }

            add_info_row_if_nonempty (_("Summary"),     d.summary);
            add_info_row_if_nonempty (_("Description"), d.description);

            // Binaries group
            clear_group (bins_group);
            foreach (var bp in d.binaries) {
                // Show "name" + arch (if present) as a compact row
                var subtitle = (bp.arch ?? "");
                bins_group.add (new Adw.ActionRow () { title = bp.name, subtitle = subtitle });
            }

            // Changelog group
            clear_group (changelog_group);
            try {
                var log = yield api.get_changelog (branch, group.name, 50);
                var exp = new Adw.ExpanderRow () { title = _("Changelog") };

                bool any = false;
                foreach (var it in log.changelog) {
                    any = true;

                    // Header: "date — nick [evr]"
                    string head = "";
                    if (is_nonempty (it.date)) head = it.date;
                    if (is_nonempty (it.nick)) head = (head == "") ? it.nick : head + " — " + it.nick;
                    if (is_nonempty (it.evr))  head = (head == "") ? ("[" + it.evr + "]") : head + " [" + it.evr + "]";

                    // One-line preview (first line, trimmed, ellipsized)
                    string preview = (it.message ?? "").strip ();
                    int nl = preview.index_of_char ('\n');
                    if (nl >= 0) preview = preview.substring (0, nl);
                    if (preview.length > MAX_CHANGE_PREVIEW)
                        preview = preview.substring (0, MAX_CHANGE_PREVIEW) + "…";
                    preview = GLib.Markup.escape_text (preview, -1);

                    var row = new Adw.ActionRow () {
                        title = (head != "") ? head : _("Change"),
                        subtitle = preview
                    };
                    row.set_subtitle_lines (1);
                    row.activatable = true;
                    row.activated.connect (() => {
                        // Show full message in a scrollable dialog
                        show_changelog_dialog (row.title, it.message ?? "");
                    });

                    exp.add_row (row);
                }

                if (!any)
                    exp.add_row (new Adw.ActionRow () { title = _("No changes found") });

                changelog_group.add (exp);
            } catch (Error ce) {
                warning ("[DetailsPage] changelog failed: %s", ce.message);
                changelog_group.add (new Adw.ActionRow () {
                    title = _("Changelog unavailable"),
                    subtitle = ce.message
                });
            }
        } catch (Error e) {
            // Surface a toast and keep the page responsive
            warning (@"[DetailsPage] load failed: %s", e.message);
            toast_overlay.add_toast (new Adw.Toast (_("Failed to load package details")));
        } finally {
            set_loading (false);
        }
    }
}

