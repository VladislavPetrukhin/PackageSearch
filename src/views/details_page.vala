using Gtk;
using Adw;
using GLib;
using Gdk;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    private Business.PackageManager pkg_mgr = new Business.PackageManager ();

    /* ---- hero ---- */
    [GtkChild] private unowned Gtk.Label hero_name;
    [GtkChild] private unowned Gtk.Label hero_summary;
    [GtkChild] private unowned Gtk.Box   hero_badges;
    [GtkChild] private unowned Gtk.Box   hero_actions;

    /* ---- banner ---- */
    [GtkChild] private unowned Adw.Banner banner;

    /* ---- toast / title / switcher ---- */
    [GtkChild] private unowned Adw.ToastOverlay   toast_overlay;
    [GtkChild] private unowned Adw.WindowTitle    header_title;

    /* ---- preferences groups, one per tab ---- */
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup deps_group;
    [GtkChild] private unowned Adw.PreferencesGroup security_group;
    [GtkChild] private unowned Adw.PreferencesGroup versions_group;
    [GtkChild] private unowned Adw.PreferencesGroup downloads_group;
    [GtkChild] private unowned Adw.PreferencesGroup spec_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;

    private const int  MAX_CHANGE_PREVIEW = 200;
    private const int  DIALOG_W = 860;
    private const int  DIALOG_H = 600;

    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    private static string normalize_url (string raw) {
        string url = (raw ?? "").strip ();
        if (url.length == 0) return url;
        if (!(url.has_prefix ("http://") || url.has_prefix ("https://")))
            url = "https://" + url;
        return url;
    }

    private static void open_uri (string url) {
        try { AppInfo.launch_default_for_uri (url, null); }
        catch (Error e) { warning ("open url failed: %s", e.message); }
    }

    private void copy_to_clipboard (string text) {
        var disp = Gdk.Display.get_default ();
        if (disp != null) disp.get_clipboard ().set_text (text);
        toast_overlay.add_toast (new Adw.Toast (_("Copied")));
    }

    private void add_info_row_if_nonempty (string title, string? value) {
        if (is_nonempty (value))
            info_group.add (new Adw.ActionRow () {
                title = title,
                subtitle = GLib.Markup.escape_text (value, -1)
            });
    }

    private static void mark_installed (Gtk.Button btn) {
        btn.remove_css_class ("ps-installing");
        btn.remove_css_class ("suggested-action");
        btn.add_css_class ("ps-installed");
        btn.label = _("Installed");
        btn.tooltip_text = _("Package is already installed");
        btn.sensitive = false;
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        Style.ensure ();

        this.title = group.name;

        // Initial hero state (before data arrives)
        hero_name.set_text (group.name ?? "");
        hero_summary.set_text ("");
        header_title.set_title (group.name ?? "");
        header_title.set_subtitle (branch);

        // Immediately show skeletons in every section
        populate_skeletons ();

        load_details.begin ();
    }

    /* ===== Skeleton loaders ===== */

    private void populate_skeletons () {
        clear_group (info_group);
        for (int i = 0; i < 4; i++) info_group.add (make_skeleton_row ());

        clear_group (bins_group);
        for (int i = 0; i < 3; i++) bins_group.add (make_skeleton_row ());

        clear_group (deps_group);
        deps_group.add (make_skeleton_row ());
        deps_group.add (make_skeleton_row ());

        clear_group (security_group);
        security_group.add (make_skeleton_row ());

        clear_group (versions_group);
        for (int i = 0; i < 4; i++) versions_group.add (make_skeleton_row ());

        clear_group (downloads_group);
        downloads_group.add (make_skeleton_row ());
        downloads_group.add (make_skeleton_row ());

        clear_group (spec_group);
        spec_group.add (make_skeleton_row ());

        clear_group (changelog_group);
        for (int i = 0; i < 3; i++) changelog_group.add (make_skeleton_row ());
    }

    private Adw.ActionRow make_skeleton_row () {
        var row = new Adw.ActionRow ();
        row.add_css_class ("skeleton");

        var main = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            hexpand = true,
            valign = Gtk.Align.CENTER,
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 6,
            margin_end = 6
        };

        var l1 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            height_request = 10,
            width_request = 180,
            hexpand = false
        };
        l1.add_css_class ("skeleton-line");

        var l2 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            height_request = 8,
            width_request = 260,
            hexpand = false
        };
        l2.add_css_class ("skeleton-line");

        main.append (l1);
        main.append (l2);
        row.set_child (main);
        return row;
    }

    /* ===== Helpers ===== */

    private void clear_group (Adw.PreferencesGroup grp) {
        for (var child = grp.get_first_child (); child != null; ) {
            var next = child.get_next_sibling ();
            var row = child as Adw.PreferencesRow;
            if (row != null) grp.remove (row);
            child = next;
        }
    }

    private void clear_box (Gtk.Box box) {
        for (var c = box.get_first_child (); c != null; ) {
            var next = c.get_next_sibling ();
            box.remove (c);
            c = next;
        }
    }

    // Tag-like label pointing at a CSS class for color
    private Gtk.Label add_badge (Gtk.Box host, string text, string? css) {
        var l = Style.make_tag (text, css);
        host.append (l);
        return l;
    }

    /* ===== Changelog / generic text dialog ===== */

    private void show_text_dialog (string head, string body, bool monospace = true) {
        var dlg = new Adw.Dialog ();
        dlg.set_content_width (DIALOG_W);
        dlg.set_content_height (DIALOG_H);

        var hb = new Adw.HeaderBar () {
            show_end_title_buttons = true
        };
        hb.set_title_widget (new Adw.WindowTitle (head, ""));

        var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
            tooltip_text = _("Copy"),
            valign = Gtk.Align.CENTER
        };
        copy_btn.add_css_class ("flat");
        copy_btn.clicked.connect (() => {
            var disp = Gdk.Display.get_default ();
            if (disp != null) disp.get_clipboard ().set_text (body ?? "");
            toast_overlay.add_toast (new Adw.Toast (_("Copied")));
        });
        hb.pack_end (copy_btn);

        var tv = new Gtk.TextView () {
            editable = false,
            cursor_visible = false,
            wrap_mode = Gtk.WrapMode.WORD_CHAR,
            top_margin = 8, bottom_margin = 8,
            left_margin = 12, right_margin = 12
        };
        if (monospace) tv.add_css_class ("monospace");
        tv.add_css_class ("spec-view");
        tv.buffer.set_text (body ?? "");

        var sw = new Gtk.ScrolledWindow () { vexpand = true };
        sw.set_child (tv);

        var tb = new Adw.ToolbarView ();
        tb.add_top_bar (hb);
        tb.set_content (sw);

        dlg.set_child (tb);
        dlg.present (this.get_root () as Gtk.Window);
    }

    /* ===== Install flow ===== */

    private async void install_binary (string pkg_name, Gtk.Button btn,
                                       string? repo_evr, bool is_update) {
        btn.remove_css_class ("suggested-action");
        btn.add_css_class ("ps-installing");
        btn.label = is_update ? _("Updating…") : _("Installing…");
        btn.sensitive = false;

        toast_overlay.add_toast (new Adw.Toast (
            (is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name)));

        string? error_msg = null;
        var result = yield pkg_mgr.install_package (pkg_name, repo_evr, out error_msg);

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
                warning ("[DetailsPage] install failed for %s: %s", pkg_name, error_msg);
            }
            toast_overlay.add_toast (new Adw.Toast (
                (is_update ? _("Failed to update %s") : _("Failed to install %s"))
                    .printf (pkg_name)));
            break;
        }
    }

    /* ===== Main loader: Overview + Binaries + Changelog ===== */

    private async void load_details () {
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            // Title bar
            var vr = (d.version ?? "");
            if (is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;
            header_title.set_title (group.name);
            header_title.set_subtitle (
                (vr != "" ? vr + " · " : "") + branch
            );

            // Hero
            hero_name.set_text (group.name ?? "");
            hero_summary.set_text (d.summary ?? d.description ?? "");

            clear_box (hero_badges);
            if (is_nonempty (d.license))
                add_badge (hero_badges, d.license, "accent");
            if (is_nonempty (d.group))
                add_badge (hero_badges, d.group, "neutral");
            add_badge (hero_badges, branch, "success");
            if (vr != "")
                add_badge (hero_badges, vr, "neutral");

            // Info group
            clear_group (info_group);
            add_info_row_if_nonempty (_("Version"),    d.version);
            add_info_row_if_nonempty (_("Release"),    d.release);
            add_info_row_if_nonempty (_("Maintainer"), d.maintainer);
            add_info_row_if_nonempty (_("Group"),      d.group);
            add_info_row_if_nonempty (_("License"),    d.license);

            if (is_nonempty (d.homepage)) {
                string url = normalize_url (d.homepage ?? "");
                if (url.length > 0) {
                    var row_home = new Adw.ActionRow () {
                        title = _("Homepage"),
                        subtitle = GLib.Markup.escape_text (url, -1)
                    };
                    var open_btn = new Gtk.Button.from_icon_name ("adw-external-link-symbolic") {
                        valign = Gtk.Align.CENTER,
                        tooltip_text = _("Open in browser")
                    };
                    open_btn.add_css_class ("flat");
                    open_btn.clicked.connect (() => { open_uri (url); });
                    row_home.add_suffix (open_btn);
                    row_home.activatable = true;
                    row_home.activated.connect (() => { open_uri (url); });
                    info_group.add (row_home);
                }
            }

            add_info_row_if_nonempty (_("Summary"),     d.summary);
            add_info_row_if_nonempty (_("Description"), d.description);

            // Binaries group
            clear_group (bins_group);

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
                bool have = false;
                foreach (var a in list) { if (a == arch) { have = true; break; } }
                if (!have) list.add (arch);
            }

            var names = new Gee.ArrayList<string> ();
            foreach (var k in by_name.keys) names.add (k);
            names.sort ((a, b) => strcmp (a, b));

            var sys_branch = yield pkg_mgr.get_system_branch ();
            bool can_install = yield pkg_mgr.is_system_branch (branch);

            // Non-system-branch banner
            if (sys_branch.length > 0 && !can_install) {
                banner.title = _("Install is available only for the system repository (%s)")
                    .printf (sys_branch);
                banner.revealed = true;
            } else {
                banner.revealed = false;
            }

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

            // Add a quick "Install main package" button to the hero if the src
            // package has a homonymous binary and we can install it
            clear_box (hero_actions);
            if (can_install && names.contains (group.name)) {
                var install_hero = new Gtk.Button.with_label (_("Install")) {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = _("Install via apt-get (requires authentication)")
                };
                install_hero.add_css_class ("suggested-action");
                install_hero.add_css_class ("pill");

                bool is_installed = installed.has_key (group.name);
                bool needs_update = false;
                if (is_installed && repo_evr.length > 0) {
                    needs_update = Business.VersionCompare.compare_evr (
                        installed.get (group.name), repo_evr) < 0;
                }
                if (is_installed && !needs_update) {
                    mark_installed (install_hero);
                } else {
                    string captured_evr = repo_evr;
                    if (needs_update) {
                        install_hero.label = _("Update");
                        install_hero.tooltip_text = _("Update via apt-get (requires authentication)");
                    }
                    install_hero.clicked.connect (() => {
                        install_binary.begin (group.name, install_hero, captured_evr, needs_update);
                    });
                }
                hero_actions.append (install_hero);
            }

            foreach (var name in names) {
                var arches = by_name.get (name);
                var row = new Adw.ActionRow () { title = name };

                // arches as badges on the row
                var badges_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                    valign = Gtk.Align.CENTER,
                    halign = Gtk.Align.END
                };
                foreach (var a in arches) {
                    badges_box.append (Style.make_tag (a, "neutral"));
                }
                row.add_suffix (badges_box);

                if (can_install) {
                    var install_btn = new Gtk.Button.with_label (_("Install")) {
                        valign = Gtk.Align.CENTER
                    };
                    install_btn.add_css_class ("suggested-action");
                    install_btn.add_css_class ("pill");
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

                bool any = false;
                foreach (var it in log.changelog) {
                    any = true;

                    string head = "";
                    if (is_nonempty (it.date)) head = it.date;
                    if (is_nonempty (it.nick)) head = (head == "") ? it.nick : head + " — " + it.nick;

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

                    if (is_nonempty (it.evr)) {
                        var tag = Style.make_tag (it.evr, "neutral");
                        tag.valign = Gtk.Align.CENTER;
                        row.add_suffix (tag);
                    }

                    string captured_title = row.title;
                    string captured_body  = it.message ?? "";
                    row.activated.connect (() => {
                        show_text_dialog (captured_title, captured_body, false);
                    });
                    changelog_group.add (row);
                }

                if (!any)
                    changelog_group.add (new Adw.ActionRow () { title = _("No changes found") });
            } catch (Error ce) {
                warning ("[DetailsPage] changelog failed: %s", ce.message);
                changelog_group.add (new Adw.ActionRow () {
                    title = _("Changelog unavailable"),
                    subtitle = GLib.Markup.escape_text (ce.message, -1)
                });
            }
        } catch (Error e) {
            warning (@"[DetailsPage] load failed: %s", e.message);
            toast_overlay.add_toast (new Adw.Toast (_("Failed to load package details")));
        }

        // Lazy sections — failures don't block the page
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

        var build_exp = new Adw.ExpanderRow () {
            title = _("Build dependencies"),
            subtitle = _("Packages required to build %s").printf (group.name)
        };
        try {
            var builds = yield api.get_build_depends (branch, group.name, "x86_64");
            if (builds == null || builds.size == 0) {
                build_exp.add_row (new Adw.ActionRow () { title = _("No dependencies found") });
            } else {
                build_exp.set_subtitle (_("%d packages").printf (builds.size));
                foreach (var d in builds) {
                    var vr = (d.version ?? "");
                    if (is_nonempty (d.release)) vr = (vr == "") ? d.release : vr + "-" + d.release;
                    var r = new Adw.ActionRow () { title = d.name };
                    if (vr != "") {
                        var t = Style.make_tag (vr, "neutral");
                        t.valign = Gtk.Align.CENTER;
                        r.add_suffix (t);
                    }
                    build_exp.add_row (r);
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

        var rev_exp = new Adw.ExpanderRow () {
            title = _("Reverse dependencies"),
            subtitle = _("Source packages that depend on %s").printf (group.name)
        };
        try {
            var revs = yield api.get_reverse_depends (branch, group.name, "both");
            if (revs == null || revs.size == 0) {
                rev_exp.add_row (new Adw.ActionRow () { title = _("No reverse dependencies") });
            } else {
                rev_exp.set_subtitle (_("%d packages").printf (revs.size));
                foreach (var d in revs) {
                    var r = new Adw.ActionRow () { title = d.name };
                    if (is_nonempty (d.branch)) {
                        var t = Style.make_tag (d.branch, "accent");
                        t.valign = Gtk.Align.CENTER;
                        r.add_suffix (t);
                    }
                    rev_exp.add_row (r);
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

    /* ===== Security ===== */

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
                    var row = new Adw.ActionRow () {
                        title = "#" + b.id,
                        subtitle = GLib.Markup.escape_text (b.summary ?? "", -1)
                    };
                    row.set_subtitle_lines (2);
                    row.activatable = true;

                    var badges = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                        valign = Gtk.Align.CENTER
                    };
                    if (is_nonempty (b.severity)) {
                        string sv = b.severity;
                        string? cls = "neutral";
                        string lc = sv.down ();
                        if (lc.contains ("critical") || lc.contains ("blocker"))
                            cls = "error";
                        else if (lc.contains ("major") || lc.contains ("normal"))
                            cls = "warning";
                        else if (lc.contains ("minor") || lc.contains ("trivial") || lc.contains ("enhancement"))
                            cls = "accent";
                        badges.append (Style.make_tag (sv, cls));
                    }
                    if (is_nonempty (b.status)) {
                        string st = b.status;
                        string? cls = "neutral";
                        string lc = st.down ();
                        if (lc.contains ("resolved") || lc.contains ("closed"))
                            cls = "success";
                        else if (lc.contains ("new") || lc.contains ("open"))
                            cls = "accent";
                        badges.append (Style.make_tag (st, cls));
                    }
                    row.add_suffix (badges);

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

                var row = new Adw.ActionRow () { title = v.branch };

                var right = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                    valign = Gtk.Align.CENTER
                };
                if (vr != "") {
                    right.append (Style.make_tag (vr, "accent"));
                }
                if (v.branch == branch) {
                    right.append (Style.make_tag (_("current"), "success"));
                    row.add_css_class ("current-branch-row");
                }
                row.add_suffix (right);

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

    private void add_download_row (Adw.ExpanderRow exp, Data.DownloadLink d) {
        var row = new Adw.ActionRow () { title = d.name };

        var right = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            valign = Gtk.Align.CENTER
        };
        if (is_nonempty (d.arch))
            right.append (Style.make_tag (d.arch, "neutral"));
        if (is_nonempty (d.size))
            right.append (Style.make_tag (d.size, "accent"));

        row.add_suffix (right);
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

        var row = new Adw.ActionRow () {
            title = _("View spec file"),
            subtitle = _("Show the RPM spec file used to build this package")
        };
        var view_btn = new Gtk.Button.with_label (_("Open")) {
            valign = Gtk.Align.CENTER
        };
        view_btn.sensitive = false;
        view_btn.add_css_class ("suggested-action");
        view_btn.add_css_class ("pill");
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
                show_text_dialog (title, body, true);
            });

            // Also make the whole row activatable for bigger touch target
            row.activatable = true;
            row.activated.connect (() => {
                show_text_dialog (title, body, true);
            });
        } catch (Error e) {
            warning ("[DetailsPage] specfile failed: %s", e.message);
            row.set_subtitle (_("Spec file unavailable: %s").printf (e.message));
        }
    }
}
