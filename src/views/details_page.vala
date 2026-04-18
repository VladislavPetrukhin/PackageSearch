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

    private static bool css_loaded = false;

    // Business-layer service for system package operations
    private Business.PackageManager pkg_mgr = new Business.PackageManager ();

    [GtkChild] private unowned Adw.ToastOverlay     toast_overlay;
    [GtkChild] private unowned Gtk.Revealer         loading_revealer;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup deps_group;
    [GtkChild] private unowned Adw.PreferencesGroup security_group;
    [GtkChild] private unowned Adw.PreferencesGroup versions_group;
    [GtkChild] private unowned Adw.PreferencesGroup downloads_group;
    [GtkChild] private unowned Adw.PreferencesGroup spec_group;
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

    // Open URL in default browser (best-effort)
    private static void open_uri (string url) {
        try { AppInfo.launch_default_for_uri (url, null); }
        catch (Error e) { warning ("open url failed: %s", e.message); }
    }

    // Copy a piece of text to the clipboard
    private void copy_to_clipboard (string text) {
        var disp = Gdk.Display.get_default ();
        if (disp != null) disp.get_clipboard ().set_text (text);
        toast_overlay.add_toast (new Adw.Toast (_("Copied")));
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

    // Animate button while the business layer performs the install, then
    // update UI based on the result.
    private async void install_binary (string pkg_name, Gtk.Button btn,
                                       string? repo_evr, bool is_update) {
        // Enter "installing" visual state
        btn.remove_css_class ("suggested-action");
        btn.add_css_class ("ps-installing");
        btn.label = is_update ? _("Updating…") : _("Installing…");
        btn.sensitive = false;

        toast_overlay.add_toast (new Adw.Toast (
            (is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name)));

        // Delegate to business layer
        string? error_msg = null;
        var result = yield pkg_mgr.install_package (pkg_name, repo_evr,
                                                     out error_msg);

        switch (result) {
        case Business.InstallResult.SUCCESS:
            mark_installed (btn);
            toast_overlay.add_toast (new Adw.Toast (
                (is_update ? _("Updated %s") : _("Installed %s")).printf (pkg_name)));
            break;

        case Business.InstallResult.CANCELLED:
            btn.remove_css_class ("ps-installing");
            btn.add_css_class ("suggested-action");
            btn.label = is_update ? _("Update") : _("Install");
            btn.sensitive = true;
            toast_overlay.add_toast (new Adw.Toast (_("Installation cancelled")));
            break;

        case Business.InstallResult.FAILED:
            btn.remove_css_class ("ps-installing");
            btn.add_css_class ("suggested-action");
            btn.label = is_update ? _("Update") : _("Install");
            btn.sensitive = true;
            if (error_msg != null) {
                warning ("[DetailsPage] install failed for %s: %s",
                         pkg_name, error_msg);
            }
            toast_overlay.add_toast (new Adw.Toast (
                (is_update ? _("Failed to update %s") : _("Failed to install %s"))
                    .printf (pkg_name)));
            break;
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

            // Ask business layer whether install buttons apply
            var sys_branch = yield pkg_mgr.get_system_branch ();
            bool can_install = yield pkg_mgr.is_system_branch (branch);

            // Show a hint when browsing a non-system branch
            if (sys_branch.length > 0 && !can_install) {
                bins_group.set_description (
                    _("Installation is available only for the system repository (%s)")
                        .printf (sys_branch));
            }

            // Prepare installed-packages map and repo EVR via business layer
            Gee.HashMap<string, string>? installed = null;
            string repo_evr = "";
            if (can_install) {
                installed = yield pkg_mgr.get_installed_packages ();

                if (is_nonempty (d.version)) {
                    repo_evr = "0:" + d.version;
                    if (is_nonempty (d.release))
                        repo_evr += "-" + d.release;
                }
            }

            foreach (var name in names) {
                var arches = by_name.get (name);

                var joined = string.joinv (", ", (string[]) arches.to_array ());
                var subtitle = GLib.Markup.escape_text (joined, -1);

                var row = new Adw.ActionRow () {
                    title = name,
                    subtitle = subtitle
                };

                if (can_install) {
                    var install_btn = new Gtk.Button.with_label (_("Install")) {
                        valign = Gtk.Align.CENTER
                    };
                    install_btn.add_css_class ("suggested-action");
                    install_btn.tooltip_text = _("Install via apt-get (requires authentication)");

                    bool is_installed = installed.has_key (name);
                    bool needs_update = false;
                    if (is_installed && repo_evr.length > 0) {
                        string installed_evr = installed.get (name);
                        needs_update = Business.VersionCompare.compare_evr (
                            installed_evr, repo_evr) < 0;
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
                }

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

        // Secondary sections — loaded lazily, failures don't block the page
        load_dependencies.begin ();
        load_security.begin ();
        load_versions.begin ();
        load_downloads.begin ();
        load_specfile.begin ();
    }

    /* ===== Dependencies ===== */
    private async void load_dependencies () {
        var api = new Data.AltRepoClient ();
        clear_group (deps_group);

        // Build dependencies — expander row with one item per dep
        var build_exp = new Adw.ExpanderRow () {
            title = _("Build dependencies"),
            subtitle = _("Packages required to build %s").printf (group.name)
        };
        try {
            var builds = yield api.get_build_depends (branch, group.name, "x86_64");
            if (builds == null || builds.size == 0) {
                build_exp.add_row (new Adw.ActionRow () { title = _("No dependencies found") });
            } else {
                foreach (var d in builds) {
                    var vr = (d.version ?? "");
                    if (is_nonempty (d.release)) vr = (vr == "") ? d.release : vr + "-" + d.release;
                    build_exp.add_row (new Adw.ActionRow () {
                        title = d.name,
                        subtitle = GLib.Markup.escape_text (vr, -1)
                    });
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] build deps failed: %s", e.message);
            build_exp.add_row (new Adw.ActionRow () {
                title = _("Build dependencies unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
        deps_group.add (build_exp);

        // Reverse dependencies — who depends on this source
        var rev_exp = new Adw.ExpanderRow () {
            title = _("Reverse dependencies"),
            subtitle = _("Source packages that depend on %s").printf (group.name)
        };
        try {
            var revs = yield api.get_reverse_depends (branch, group.name, "both");
            if (revs == null || revs.size == 0) {
                rev_exp.add_row (new Adw.ActionRow () { title = _("No reverse dependencies") });
            } else {
                foreach (var d in revs) {
                    rev_exp.add_row (new Adw.ActionRow () {
                        title = d.name,
                        subtitle = GLib.Markup.escape_text (d.branch ?? "", -1)
                    });
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] reverse deps failed: %s", e.message);
            rev_exp.add_row (new Adw.ActionRow () {
                title = _("Reverse dependencies unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
        deps_group.add (rev_exp);
    }

    /* ===== Security (Bugzilla) ===== */
    private async void load_security () {
        var api = new Data.AltRepoClient ();
        clear_group (security_group);

        var bugs_exp = new Adw.ExpanderRow () { title = _("Bugzilla") };
        try {
            var bugs = yield api.get_bugs_by_package (group.name);
            if (bugs == null || bugs.size == 0) {
                bugs_exp.add_row (new Adw.ActionRow () { title = _("No bugs found") });
            } else {
                bugs_exp.set_subtitle (_("%d bug(s) found").printf (bugs.size));
                foreach (var b in bugs) {
                    string head = "#" + b.id;
                    if (is_nonempty (b.severity)) head += "  [" + b.severity + "]";
                    if (is_nonempty (b.status))   head += "  " + b.status;
                    var row = new Adw.ActionRow () {
                        title = head,
                        subtitle = GLib.Markup.escape_text (b.summary ?? "", -1)
                    };
                    row.set_subtitle_lines (2);
                    row.activatable = true;
                    string captured_id = b.id;
                    row.activated.connect (() => {
                        open_uri ("https://bugzilla.altlinux.org/" + captured_id);
                    });
                    bugs_exp.add_row (row);
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] bugs failed: %s", e.message);
            bugs_exp.add_row (new Adw.ActionRow () {
                title = _("Bugzilla unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
        security_group.add (bugs_exp);
    }

    /* ===== Versions across branches ===== */
    private async void load_versions () {
        var api = new Data.AltRepoClient ();
        clear_group (versions_group);
        try {
            var vs = yield api.get_package_versions_all (group.name);
            if (vs == null || vs.size == 0) {
                versions_group.add (new Adw.ActionRow () { title = _("No versions found") });
                return;
            }
            foreach (var v in vs) {
                string vr = (v.version ?? "");
                if (is_nonempty (v.release)) vr = (vr == "") ? v.release : vr + "-" + v.release;
                var row = new Adw.ActionRow () {
                    title = v.branch,
                    subtitle = GLib.Markup.escape_text (vr, -1)
                };
                // Mark current branch with an accent
                if (v.branch == branch) row.add_css_class ("accent");
                versions_group.add (row);
            }
        } catch (Error e) {
            warning ("[DetailsPage] versions failed: %s", e.message);
            versions_group.add (new Adw.ActionRow () {
                title = _("Versions unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    /* ===== Downloads ===== */
    private async void load_downloads () {
        var api = new Data.AltRepoClient ();
        clear_group (downloads_group);

        // Source .src.rpm links
        var src_exp = new Adw.ExpanderRow () { title = _("Source (.src.rpm)") };
        try {
            var src_links = yield api.get_source_downloads (branch, group.name);
            if (src_links == null || src_links.size == 0) {
                src_exp.add_row (new Adw.ActionRow () { title = _("No source downloads") });
            } else {
                foreach (var d in src_links) add_download_row (src_exp, d);
            }
        } catch (Error e) {
            warning ("[DetailsPage] src downloads failed: %s", e.message);
            src_exp.add_row (new Adw.ActionRow () {
                title = _("Source downloads unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
        downloads_group.add (src_exp);

        // Binary .rpm links
        var bin_exp = new Adw.ExpanderRow () { title = _("Binaries (.rpm)") };
        try {
            var bin_links = yield api.get_binary_downloads (branch, group.name);
            if (bin_links == null || bin_links.size == 0) {
                bin_exp.add_row (new Adw.ActionRow () { title = _("No binary downloads") });
            } else {
                foreach (var d in bin_links) add_download_row (bin_exp, d);
            }
        } catch (Error e) {
            warning ("[DetailsPage] bin downloads failed: %s", e.message);
            bin_exp.add_row (new Adw.ActionRow () {
                title = _("Binary downloads unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
        downloads_group.add (bin_exp);
    }

    // Append a row to download expander — row opens the URL on activation,
    // suffix copy button copies the URL to clipboard.
    private void add_download_row (Adw.ExpanderRow exp, Data.DownloadLink d) {
        string sub = "";
        if (is_nonempty (d.arch)) sub = d.arch;
        if (is_nonempty (d.size)) sub = (sub == "") ? d.size : sub + " · " + d.size;

        var row = new Adw.ActionRow () {
            title = d.name,
            subtitle = GLib.Markup.escape_text (sub, -1)
        };
        row.activatable = true;
        if (is_nonempty (d.url)) {
            string captured_url = d.url;
            row.activated.connect (() => { open_uri (captured_url); });

            var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Copy download URL")
            };
            copy_btn.add_css_class ("flat");
            copy_btn.clicked.connect (() => { copy_to_clipboard (captured_url); });
            row.add_suffix (copy_btn);
        }
        exp.add_row (row);
    }

    /* ===== Spec file ===== */
    private async void load_specfile () {
        var api = new Data.AltRepoClient ();
        clear_group (spec_group);

        Adw.ActionRow row = new Adw.ActionRow () {
            title = _("View spec file"),
            subtitle = _("Show the RPM spec file used to build this package")
        };
        var view_btn = new Gtk.Button.with_label (_("Open")) {
            valign = Gtk.Align.CENTER
        };
        view_btn.sensitive = false;
        view_btn.add_css_class ("suggested-action");
        row.add_suffix (view_btn);
        spec_group.add (row);

        try {
            var spec = yield api.get_specfile (branch, group.name);
            if (spec == null || !is_nonempty (spec.content)) {
                row.set_subtitle (_("Spec file not available"));
                return;
            }
            row.set_subtitle (spec.name ?? _("Spec file"));
            view_btn.sensitive = true;

            string title = spec.name ?? (group.name + ".spec");
            string body  = spec.content;
            view_btn.clicked.connect (() => {
                show_changelog_dialog (title, body);
            });
        } catch (Error e) {
            warning ("[DetailsPage] specfile failed: %s", e.message);
            row.set_subtitle (_("Spec file unavailable: %s").printf (e.message));
        }
    }
}

