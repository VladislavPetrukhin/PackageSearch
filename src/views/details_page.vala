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

    // Cached map of installed binary package name -> EVR (epoch:version-release),
    // shared across DetailsPage instances within one process lifetime.
    private static Gee.HashMap<string, string>? installed_cache = null;
    private static bool css_loaded = false;

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
            info_group.add (new Adw.ActionRow () { title = title,
                            subtitle = GLib.Markup.escape_text (value, -1) });
    }

    // Inject CSS once: pulsing green border while a package is installing.
    private static void ensure_css () {
        if (css_loaded) return;
        var css = """
        @keyframes ps-install-pulse {
            0%   { border-color: alpha(@success_color, 0.35); }
            50%  { border-color: @success_color; }
            100% { border-color: alpha(@success_color, 0.35); }
        }
        button.ps-installing {
            border: 2px solid @success_color;
            animation: ps-install-pulse 1.2s ease-in-out infinite;
        }
        """;
        var p = new Gtk.CssProvider ();
        p.load_from_string (css);
        var disp = Gdk.Display.get_default ();
        if (disp != null)
            Gtk.StyleContext.add_provider_for_display (
                disp, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        css_loaded = true;
    }

    // Lazily query rpm for installed packages; cache for the process.
    // Map: package name -> "epoch:version-release"
    private async Gee.HashMap<string, string> get_installed_pkgs () {
        if (installed_cache != null) return installed_cache;
        var map = new Gee.HashMap<string, string> ();
        try {
            var sp = new GLib.Subprocess.newv (
                { "rpm", "-qa", "--queryformat",
                  "%{NAME} %|EPOCH?{%{EPOCH}}:{0}|:%{VERSION}-%{RELEASE}\n" },
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? stdout_buf = null;
            yield sp.communicate_utf8_async (null, null, out stdout_buf, null);
            if (stdout_buf != null) {
                foreach (var line in stdout_buf.split ("\n")) {
                    var t = line.strip ();
                    if (t.length == 0) continue;
                    int sp_idx = t.index_of_char (' ');
                    if (sp_idx <= 0) continue;
                    var nm  = t.substring (0, sp_idx);
                    var evr = t.substring (sp_idx + 1).strip ();
                    map.set (nm, evr);
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] rpm -qa failed: %s", e.message);
        }
        installed_cache = map;
        return map;
    }

    /* ===== RPM version comparison =====
     * Faithful Vala port of rpm's rpmvercmp: segment-wise compare with
     * tilde (~) sorting before everything and caret (^) sorting like
     * tilde but greater than empty.
     */
    private static bool is_digit (char c) { return c >= '0' && c <= '9'; }
    private static bool is_alpha (char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }
    private static bool is_alnum (char c) { return is_digit (c) || is_alpha (c); }

    private static int rpmvercmp (string a, string b) {
        if (a == b) return 0;
        int i = 0, j = 0;
        int la = a.length, lb = b.length;

        while (i < la || j < lb) {
            while (i < la && !is_alnum (a[i]) && a[i] != '~' && a[i] != '^') i++;
            while (j < lb && !is_alnum (b[j]) && b[j] != '~' && b[j] != '^') j++;

            if ((i < la && a[i] == '~') || (j < lb && b[j] == '~')) {
                if (i >= la || a[i] != '~') return 1;
                if (j >= lb || b[j] != '~') return -1;
                i++; j++; continue;
            }
            if ((i < la && a[i] == '^') || (j < lb && b[j] == '^')) {
                if (i >= la) return -1;
                if (j >= lb) return 1;
                if (a[i] != '^') return 1;
                if (b[j] != '^') return -1;
                i++; j++; continue;
            }
            if (i >= la || j >= lb) break;

            int sa = i, sb = j;
            bool isnum = is_digit (a[i]);
            if (isnum) {
                while (i < la && is_digit (a[i])) i++;
                while (j < lb && is_digit (b[j])) j++;
            } else {
                while (i < la && is_alpha (a[i])) i++;
                while (j < lb && is_alpha (b[j])) j++;
            }

            if (sa == i) return -1;
            if (sb == j) return isnum ? 1 : -1; // numeric beats alphabetic

            string seg_a = a.substring (sa, i - sa);
            string seg_b = b.substring (sb, j - sb);

            if (isnum) {
                int za = 0, zb = 0;
                while (za < seg_a.length && seg_a[za] == '0') za++;
                while (zb < seg_b.length && seg_b[zb] == '0') zb++;
                seg_a = seg_a.substring (za);
                seg_b = seg_b.substring (zb);
                if (seg_a.length != seg_b.length)
                    return seg_a.length > seg_b.length ? 1 : -1;
            }
            int rc = strcmp (seg_a, seg_b);
            if (rc != 0) return rc < 0 ? -1 : 1;
        }

        if (i >= la && j >= lb) return 0;
        if (i >= la) return -1;
        return 1;
    }

    // Parse "[epoch:]version[-release]" into its parts (defaults: epoch=0, rel="").
    private static void parse_evr (string s, out int epoch, out string ver, out string rel) {
        epoch = 0;
        string rest = s;
        int colon = s.index_of_char (':');
        if (colon >= 0) {
            epoch = int.parse (s.substring (0, colon));
            rest = s.substring (colon + 1);
        }
        int dash = rest.index_of_char ('-');
        if (dash >= 0) {
            ver = rest.substring (0, dash);
            rel = rest.substring (dash + 1);
        } else {
            ver = rest;
            rel = "";
        }
    }

    // Compare two full EVR strings. <0 if a is older than b.
    private static int compare_evr (string a, string b) {
        int ea, eb;
        string va, vb, ra, rb;
        parse_evr (a, out ea, out va, out ra);
        parse_evr (b, out eb, out vb, out rb);
        if (ea != eb) return ea < eb ? -1 : 1;
        int c = rpmvercmp (va, vb);
        if (c != 0) return c;
        return rpmvercmp (ra, rb);
    }

    // Apply the disabled "Installed" look to a button.
    private static void mark_installed (Gtk.Button btn) {
        btn.remove_css_class ("ps-installing");
        btn.remove_css_class ("suggested-action");
        btn.label = _("Installed");
        btn.tooltip_text = _("Package is already installed");
        btn.sensitive = false;
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        ensure_css ();

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

    // Run `pkexec apt-get install -y <pkg>`, animating the button during the
    // run and switching it to a disabled "Installed" state on success.
    // `repo_evr` is the EVR offered by the current repo branch; cached on
    // success so the row reflects the new state. `is_update` toggles the
    // wording of toasts and the "restore" label between Install/Update.
    private async void install_binary (string pkg_name, Gtk.Button btn,
                                       string? repo_evr, bool is_update) {
        // Enter "installing" visual state: drop accent, show pulsing green border.
        btn.remove_css_class ("suggested-action");
        btn.add_css_class ("ps-installing");
        btn.label = is_update ? _("Updating…") : _("Installing…");
        btn.sensitive = false;

        toast_overlay.add_toast (new Adw.Toast (
            (is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name)));

        bool ok = false;
        bool cancelled = false;
        string? stderr_buf = null;

        try {
            var sp = new GLib.Subprocess.newv (
                { "pkexec", "apt-get", "install", "-y", pkg_name },
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            yield sp.communicate_utf8_async (null, null, null, out stderr_buf);

            ok = sp.get_successful ();
            // pkexec exits 126 when the user cancels the auth prompt
            cancelled = !ok && sp.get_if_exited () && sp.get_exit_status () == 126;
        } catch (Error e) {
            warning ("[DetailsPage] install spawn failed: %s", e.message);
            toast_overlay.add_toast (new Adw.Toast (
                _("Failed to launch installer: %s").printf (e.message)));
        }

        if (ok) {
            if (installed_cache != null && repo_evr != null && repo_evr.length > 0)
                installed_cache.set (pkg_name, repo_evr);
            mark_installed (btn);
            toast_overlay.add_toast (new Adw.Toast (
                (is_update ? _("Updated %s") : _("Installed %s")).printf (pkg_name)));
        } else {
            // Restore the idle look so the user can retry
            btn.remove_css_class ("ps-installing");
            btn.add_css_class ("suggested-action");
            btn.label = is_update ? _("Update") : _("Install");
            btn.sensitive = true;

            if (cancelled) {
                toast_overlay.add_toast (new Adw.Toast (_("Installation cancelled")));
            } else if (stderr_buf != null) {
                warning ("[DetailsPage] apt-get failed for %s: %s",
                         pkg_name, stderr_buf);
                toast_overlay.add_toast (new Adw.Toast (
                    (is_update ? _("Failed to update %s") : _("Failed to install %s"))
                        .printf (pkg_name)));
            }
        }
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
                    var row_home = new Adw.ActionRow () { title = _("Homepage"),
                                                     subtitle = GLib.Markup.escape_text (url, -1)
                     };
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

            // Binaries group (group by package name, list arches in subtitle)
            clear_group (bins_group);

            // Collect arches per binary name
            var by_name = new Gee.HashMap<string, Gee.ArrayList<string>> ();
            foreach (var bp in d.binaries) {
                if (bp == null || bp.name == null) continue;
                var name = bp.name;
                var arch = bp.arch ?? "";

                if (arch.strip ().length == 0) continue;

                var list = by_name.get (name);
                if (list == null) {
                    list = new Gee.ArrayList<string> ();
                    by_name.set (name, list);
                }
                // Deduplicate arches
                bool have = false;
                foreach (var a in list) { if (a == arch) { have = true; break; } }
                if (!have) list.add (arch);
            }

            // Sort names for stable output
            var names = new Gee.ArrayList<string> ();
            foreach (var k in by_name.keys) names.add (k);
            names.sort ((a, b) => strcmp (a, b));

            // Find which binaries are already installed in the system
            var installed = yield get_installed_pkgs ();

            // Build the EVR offered by the current repo branch (epoch 0 — rdb
            // does not expose epoch separately for source packages here).
            string repo_evr = "";
            if (is_nonempty (d.version)) {
                repo_evr = "0:" + d.version;
                if (is_nonempty (d.release))
                    repo_evr += "-" + d.release;
            }

            foreach (var name in names) {
                var arches = by_name.get (name);

                // Join with ", " and escape for markup label
                var joined = string.joinv (", ", (string[]) arches.to_array ());
                var subtitle = GLib.Markup.escape_text (joined, -1);

                var row = new Adw.ActionRow () {
                    title = name,
                    subtitle = subtitle
                };

                var install_btn = new Gtk.Button.with_label (_("Install")) {
                    valign = Gtk.Align.CENTER
                };
                install_btn.add_css_class ("suggested-action");
                install_btn.tooltip_text = _("Install via apt-get (requires authentication)");

                bool is_installed = installed.has_key (name);
                bool needs_update = false;
                if (is_installed && repo_evr.length > 0) {
                    string installed_evr = installed.get (name);
                    needs_update = compare_evr (installed_evr, repo_evr) < 0;
                }

                if (is_installed && !needs_update) {
                    mark_installed (install_btn);
                } else {
                    bool is_update = needs_update;
                    string captured_evr = repo_evr;
                    if (is_update) {
                        install_btn.label = _("Update");
                        install_btn.tooltip_text =
                            _("Update via apt-get (requires authentication)");
                    }
                    install_btn.clicked.connect (() => {
                        install_binary.begin (name, install_btn,
                                              captured_evr, is_update);
                    });
                }

                row.add_suffix (install_btn);
                bins_group.add (row);
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
                    subtitle = GLib.Markup.escape_text (ce.message, -1)
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

