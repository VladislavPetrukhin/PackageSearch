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

    [GtkChild] private unowned Adw.ToastOverlay   toast_overlay;
    [GtkChild] private unowned Adw.WindowTitle    header_title;
    [GtkChild] private unowned Gtk.Box            header_actions;
    [GtkChild] private unowned Adw.Banner         banner;
    [GtkChild] private unowned Gtk.Revealer       loading_revealer;

    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup deps_group;
    [GtkChild] private unowned Adw.PreferencesGroup security_group;
    [GtkChild] private unowned Adw.PreferencesGroup versions_group;
    [GtkChild] private unowned Adw.PreferencesGroup downloads_group;
    [GtkChild] private unowned Adw.PreferencesGroup spec_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;

    private Gee.HashSet<string> selected_branches = new Gee.HashSet<string> ();
    private Gtk.Button?         compare_btn = null;

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    private const int MAX_CHANGE_PREVIEW = 200;

    public void cancel_loading () {
        if (!cancel.is_cancelled ()) cancel.cancel ();
    }

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

    private static string trim_toast (string s) {
        const int LIMIT = 80;
        var clean = s.replace ("\n", " ").strip ();
        if (clean.length <= LIMIT) return clean;
        return clean.substring (0, LIMIT) + "…";
    }

    private void toast (string s) {
        toast_overlay.add_toast (new Adw.Toast (trim_toast (s)));
    }

    private static Gtk.Label dim_label (string text) {
        var l = new Gtk.Label (text) { valign = Gtk.Align.CENTER };
        l.add_css_class ("dim-label");
        return l;
    }

    private Gtk.ListBox? find_listbox (Gtk.Widget w) {
        for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (c is Gtk.ListBox) return (Gtk.ListBox) c;
            var r = find_listbox (c);
            if (r != null) return r;
        }
        return null;
    }

    private void clear_group (Adw.PreferencesGroup grp) {
        var lb = find_listbox (grp);
        if (lb == null) return;
        var to_remove = new Gee.ArrayList<Gtk.Widget> ();
        for (var c = lb.get_first_child (); c != null; c = c.get_next_sibling ())
            to_remove.add (c);
        foreach (var w in to_remove) grp.remove (w);
    }

    private void clear_box (Gtk.Box box) {
        Gtk.Widget? c;
        while ((c = box.get_first_child ()) != null) box.remove (c);
    }

    private void add_info_row_if_nonempty (string title, string? value) {
        if (is_nonempty (value))
            info_group.add (new Adw.ActionRow () {
                title = title,
                subtitle = GLib.Markup.escape_text (value, -1)
            });
    }

    private static void mark_installed (Gtk.Button btn) {
        btn.remove_css_class ("suggested-action");
        btn.label = _("Installed");
        btn.tooltip_text = _("Package is already installed");
        btn.sensitive = false;
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        this.title = group.name;
        header_title.set_title (group.name ?? "");
        header_title.set_subtitle (branch);

        loading_revealer.reveal_child = true;

        load_details.begin ();
    }

    private void show_text_dialog (string head, string body) {
        var dlg = new Adw.Dialog ();
        dlg.set_content_width (820);
        dlg.set_content_height (600);

        var hb = new Adw.HeaderBar () { show_end_title_buttons = true };
        hb.set_title_widget (new Adw.WindowTitle (head, ""));

        var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
            tooltip_text = _("Copy"), valign = Gtk.Align.CENTER
        };
        copy_btn.add_css_class ("flat");
        copy_btn.clicked.connect (() => copy_to_clipboard (body ?? ""));
        hb.pack_end (copy_btn);

        var tv = new Gtk.TextView () {
            editable = false, cursor_visible = false, monospace = true,
            wrap_mode = Gtk.WrapMode.WORD_CHAR,
            top_margin = 8, bottom_margin = 8, left_margin = 12, right_margin = 12
        };
        tv.buffer.set_text (body ?? "");

        var sw = new Gtk.ScrolledWindow () { vexpand = true };
        sw.set_child (tv);

        var tb = new Adw.ToolbarView ();
        tb.add_top_bar (hb);
        tb.set_content (sw);

        dlg.set_child (tb);
        dlg.present (this.get_root () as Gtk.Window);
    }

    private async void install_binary (string pkg_name, Gtk.Button btn,
                                       string? repo_evr, bool is_update) {
        btn.label = is_update ? _("Updating…") : _("Installing…");
        btn.sensitive = false;

        toast ((is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name));

        string? error_msg = null;
        var result = yield pkg_mgr.install_package (pkg_name, repo_evr, out error_msg);

        switch (result) {
        case Business.InstallResult.SUCCESS:
            mark_installed (btn);
            toast ((is_update ? _("Updated %s") : _("Installed %s")).printf (pkg_name));
            break;
        case Business.InstallResult.CANCELLED:
            btn.label = is_update ? _("Update") : _("Install");
            btn.sensitive = true;
            toast (_("Installation cancelled"));
            break;
        case Business.InstallResult.FAILED:
            btn.label = is_update ? _("Update") : _("Install");
            btn.sensitive = true;
            if (error_msg != null)
                warning ("[DetailsPage] install failed for %s: %s", pkg_name, error_msg);
            toast ((is_update ? _("Failed to update %s") : _("Failed to install %s")).printf (pkg_name));
            break;
        }
    }

    private async void load_details () {
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            var vr = (d.version ?? "");
            if (is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;
            header_title.set_title (group.name);
            header_title.set_subtitle ((vr != "" ? vr + " · " : "") + branch);

            clear_group (info_group);
            if (is_nonempty (d.summary))
                info_group.set_description (GLib.Markup.escape_text (d.summary, -1));

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
                        subtitle = GLib.Markup.escape_text (url, -1),
                        activatable = true
                    };
                    row_home.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
                    row_home.activated.connect (() => open_uri (url));
                    info_group.add (row_home);
                }
            }

            add_info_row_if_nonempty (_("Description"), d.description);

            yield populate_binaries (d);

            loading_revealer.reveal_child = false;

            yield load_changelog (api);
        } catch (Error e) {
            loading_revealer.reveal_child = false;
            warning ("[DetailsPage] load failed: %s", e.message);
            toast (_("Failed to load package details"));
        }

        if (cancel.is_cancelled ()) return;
        yield load_dependencies ();
        if (cancel.is_cancelled ()) return;
        yield load_security ();
        if (cancel.is_cancelled ()) return;
        yield load_versions ();
        if (cancel.is_cancelled ()) return;
        yield load_downloads ();
        if (cancel.is_cancelled ()) return;
        yield load_specfile ();
    }

    private async void populate_binaries (Data.PackageDetails d) {
        clear_group (bins_group);

        var by_name = new Gee.HashMap<string, Gee.ArrayList<string>> ();
        foreach (var bp in d.binaries) {
            if (bp == null || bp.name == null) continue;
            var arch = bp.arch ?? "";
            if (arch.strip ().length == 0) continue;
            var list = by_name.get (bp.name);
            if (list == null) { list = new Gee.ArrayList<string> (); by_name.set (bp.name, list); }
            if (!list.contains (arch)) list.add (arch);
        }

        var names = new Gee.ArrayList<string> ();
        foreach (var k in by_name.keys) names.add (k);
        names.sort ((a, b) => strcmp (a, b));

        var sys_branch  = yield pkg_mgr.get_system_branch ();
        bool can_install = yield pkg_mgr.is_system_branch (branch);

        if (sys_branch.length > 0 && !can_install) {
            banner.title = _("Install is available only for the system repository (%s)").printf (sys_branch);
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
                if (is_nonempty (d.release)) repo_evr += "-" + d.release;
            }
        }

        clear_box (header_actions);
        if (can_install && names.contains (group.name)) {
            var install_hero = new Gtk.Button.with_label (_("Install")) {
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Install via apt-get (requires authentication)")
            };
            install_hero.add_css_class ("suggested-action");

            bool is_installed = installed.has_key (group.name);
            bool needs_update = false;
            if (is_installed && repo_evr.length > 0)
                needs_update = Business.VersionCompare.compare_evr (installed.get (group.name), repo_evr) < 0;

            if (is_installed && !needs_update) {
                mark_installed (install_hero);
            } else {
                string captured_evr = repo_evr;
                bool is_update = needs_update;
                if (is_update) {
                    install_hero.label = _("Update");
                    install_hero.tooltip_text = _("Update via apt-get (requires authentication)");
                }
                install_hero.clicked.connect (() => {
                    install_binary.begin (group.name, install_hero, captured_evr, is_update);
                });
            }
            header_actions.append (install_hero);
        }

        foreach (var name in names) {
            var arches = by_name.get (name);
            var row = new Adw.ActionRow () { title = name };

            var arch_str = "";
            foreach (var a in arches) arch_str = (arch_str == "") ? a : arch_str + ", " + a;
            if (arch_str != "") row.add_suffix (dim_label (arch_str));

            if (can_install) {
                var install_btn = new Gtk.Button.with_label (_("Install")) {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = _("Install via apt-get (requires authentication)")
                };
                install_btn.add_css_class ("suggested-action");

                bool is_installed = installed.has_key (name);
                bool needs_update = false;
                if (is_installed && repo_evr.length > 0)
                    needs_update = Business.VersionCompare.compare_evr (installed.get (name), repo_evr) < 0;

                if (is_installed && !needs_update) {
                    mark_installed (install_btn);
                } else {
                    bool is_update = needs_update;
                    string captured_evr = repo_evr;
                    if (is_update) {
                        install_btn.label = _("Update");
                        install_btn.tooltip_text = _("Update via apt-get (requires authentication)");
                    }
                    install_btn.clicked.connect (() => {
                        install_binary.begin (name, install_btn, captured_evr, is_update);
                    });
                }
                row.add_suffix (install_btn);
            }

            bins_group.add (row);
        }

        if (names.size == 0)
            bins_group.add (new Adw.ActionRow () { title = _("No binary packages") });
    }

    private async void load_changelog (Data.AltRepoClient api) {
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

                var row = new Adw.ActionRow () {
                    title = (head != "") ? head : _("Change"),
                    subtitle = GLib.Markup.escape_text (preview, -1),
                    activatable = true
                };
                row.set_subtitle_lines (1);
                if (is_nonempty (it.evr)) row.add_suffix (dim_label (it.evr));

                string captured_title = row.title;
                string captured_body  = it.message ?? "";
                row.activated.connect (() => show_text_dialog (captured_title, captured_body));
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
    }

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
                    if (vr != "") r.add_suffix (dim_label (vr));
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
                    if (is_nonempty (d.branch)) r.add_suffix (dim_label (d.branch));
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

    private async void load_security () {
        var api = new Data.AltRepoClient ();
        clear_group (security_group);

        var errata_exp = new Adw.ExpanderRow () { title = _("Security advisories") };
        try {
            var erratas = yield api.get_errata_for_package (branch, group.name);
            if (erratas == null || erratas.size == 0) {
                errata_exp.add_row (new Adw.ActionRow () { title = _("No security advisories") });
            } else {
                errata_exp.set_subtitle (_("%d advisories").printf (erratas.size));
                foreach (var er in erratas) {
                    var row = new Adw.ActionRow () { title = er.id };

                    string sub = "";
                    if (is_nonempty (er.errata_type)) sub = er.errata_type;
                    if (is_nonempty (er.pkg_version)) {
                        string vr = er.pkg_version;
                        if (is_nonempty (er.pkg_release)) vr += "-" + er.pkg_release;
                        sub = (sub == "") ? vr : sub + " · " + vr;
                    }
                    if (is_nonempty (er.created))
                        sub = (sub == "") ? er.created : sub + " · " + er.created;
                    if (sub != "") row.subtitle = GLib.Markup.escape_text (sub, -1);

                    string refs = "";
                    foreach (var r in er.references)
                        refs = (refs == "") ? r.id : refs + ", " + r.id;
                    if (refs != "") row.add_suffix (dim_label (refs));

                    string? open_url = null;
                    foreach (var r in er.references) {
                        string lc = (r.ref_type ?? "").down ();
                        if (lc == "cve") { open_url = "https://nvd.nist.gov/vuln/detail/" + r.id; break; }
                        if (lc == "bdu") { open_url = "https://bdu.fstec.ru/vul/" + r.id; break; }
                        if (lc == "bug") { open_url = "https://bugzilla.altlinux.org/" + r.id; break; }
                    }
                    if (open_url != null) {
                        row.activatable = true;
                        string captured = open_url;
                        row.activated.connect (() => open_uri (captured));
                    }
                    errata_exp.add_row (row);
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] errata failed: %s", e.message);
            errata_exp.add_row (new Adw.ActionRow () {
                title = _("Advisories unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
        security_group.add (errata_exp);

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
                        subtitle = GLib.Markup.escape_text (b.summary ?? "", -1),
                        activatable = true
                    };
                    row.set_subtitle_lines (2);

                    string st = "";
                    if (is_nonempty (b.severity)) st = b.severity;
                    if (is_nonempty (b.status)) st = (st == "") ? b.status : st + " · " + b.status;
                    if (st != "") row.add_suffix (dim_label (st));

                    string captured_id = b.id;
                    row.activated.connect (() => open_uri ("https://bugzilla.altlinux.org/" + captured_id));
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

    private async void load_versions () {
        var api = new Data.AltRepoClient ();
        clear_group (versions_group);
        selected_branches.clear ();

        compare_btn = new Gtk.Button.with_label (_("Compare selected")) {
            valign = Gtk.Align.CENTER
        };
        compare_btn.add_css_class ("suggested-action");
        compare_btn.sensitive = false;
        compare_btn.clicked.connect (() => {
            if (selected_branches.size != 2) return;
            var picks = new string[2];
            int i = 0;
            foreach (var b in selected_branches) picks[i++] = b;
            show_compare_dialog.begin (picks[0], picks[1]);
        });
        versions_group.set_header_suffix (compare_btn);
        versions_group.set_description (_("Tick two branches to compare versions side by side"));

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
                if (v.branch == branch) row.subtitle = _("current");

                var chk = new Gtk.CheckButton () { valign = Gtk.Align.CENTER };
                string captured_branch = v.branch;
                chk.toggled.connect (() => {
                    if (chk.active) {
                        if (selected_branches.size >= 2) {
                            chk.active = false;
                            toast (_("Only two branches can be compared at a time"));
                            return;
                        }
                        selected_branches.add (captured_branch);
                    } else {
                        selected_branches.remove (captured_branch);
                    }
                    if (compare_btn != null)
                        compare_btn.sensitive = (selected_branches.size == 2);
                });
                row.add_prefix (chk);
                if (vr != "") row.add_suffix (dim_label (vr));
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

    private string evr_string (string? v, string? r) {
        string s = v ?? "";
        if (is_nonempty (r)) s = (s == "") ? r : s + "-" + r;
        return (s == "") ? "—" : s;
    }

    private async void show_compare_dialog (string branch_a, string branch_b) {
        compare_btn.sensitive = false;
        compare_btn.label = _("Loading…");

        var api = new Data.AltRepoClient ();
        Data.PackageDetails? a = null;
        Data.PackageDetails? b = null;
        try {
            a = yield api.get_source_details (branch_a, group.name);
            b = yield api.get_source_details (branch_b, group.name);
        } catch (Error e) {
            warning ("[DetailsPage] compare failed: %s", e.message);
            toast (_("Compare failed: %s").printf (e.message));
            compare_btn.label = _("Compare selected");
            compare_btn.sensitive = (selected_branches.size == 2);
            return;
        }
        compare_btn.label = _("Compare selected");
        compare_btn.sensitive = (selected_branches.size == 2);

        var dlg = new Adw.Dialog ();
        dlg.set_content_width (820);
        dlg.set_content_height (640);
        dlg.set_title (_("Compare %s vs %s").printf (branch_a, branch_b));

        var hb = new Adw.HeaderBar () { show_end_title_buttons = true };
        hb.set_title_widget (new Adw.WindowTitle (
            _("Compare %s vs %s").printf (branch_a, branch_b), group.name));

        var page = new Adw.PreferencesPage ();

        var meta_grp = new Adw.PreferencesGroup () { title = _("Metadata") };
        meta_grp.add (make_compare_text_row (_("Version"),
            evr_string (a.version, a.release), evr_string (b.version, b.release)));
        meta_grp.add (make_compare_text_row (_("Maintainer"), a.maintainer ?? "—", b.maintainer ?? "—"));
        meta_grp.add (make_compare_text_row (_("License"), a.license ?? "—", b.license ?? "—"));
        meta_grp.add (make_compare_text_row (_("Group"), a.group ?? "—", b.group ?? "—"));
        meta_grp.add (make_compare_text_row (_("Summary"), a.summary ?? "—", b.summary ?? "—"));
        page.add (meta_grp);

        var names_a = new Gee.HashSet<string> ();
        var names_b = new Gee.HashSet<string> ();
        foreach (var bp in a.binaries) if (bp.name != null) names_a.add (bp.name);
        foreach (var bp in b.binaries) if (bp.name != null) names_b.add (bp.name);

        var only_a = new Gee.ArrayList<string> ();
        var only_b = new Gee.ArrayList<string> ();
        var common = new Gee.ArrayList<string> ();
        foreach (var n in names_a) {
            if (names_b.contains (n)) common.add (n); else only_a.add (n);
        }
        foreach (var n in names_b) if (!names_a.contains (n)) only_b.add (n);
        only_a.sort ((x, y) => strcmp (x, y));
        only_b.sort ((x, y) => strcmp (x, y));
        common.sort ((x, y) => strcmp (x, y));

        var bins_grp = new Adw.PreferencesGroup () {
            title = _("Binary packages"),
            description = _("%d common · %d only in %s · %d only in %s").printf (
                common.size, only_a.size, branch_a, only_b.size, branch_b)
        };
        if (only_a.size > 0) {
            var r = new Adw.ExpanderRow () {
                title = _("Only in %s").printf (branch_a),
                subtitle = _("%d packages").printf (only_a.size)
            };
            foreach (var n in only_a) r.add_row (new Adw.ActionRow () { title = n });
            bins_grp.add (r);
        }
        if (only_b.size > 0) {
            var r = new Adw.ExpanderRow () {
                title = _("Only in %s").printf (branch_b),
                subtitle = _("%d packages").printf (only_b.size)
            };
            foreach (var n in only_b) r.add_row (new Adw.ActionRow () { title = n });
            bins_grp.add (r);
        }
        if (common.size > 0) {
            var r = new Adw.ExpanderRow () {
                title = _("In both branches"),
                subtitle = _("%d packages").printf (common.size)
            };
            foreach (var n in common) r.add_row (new Adw.ActionRow () { title = n });
            bins_grp.add (r);
        }
        if (only_a.size == 0 && only_b.size == 0 && common.size == 0)
            bins_grp.add (new Adw.ActionRow () { title = _("No binary packages reported") });
        page.add (bins_grp);

        var tb = new Adw.ToolbarView ();
        tb.add_top_bar (hb);
        tb.set_content (page);
        dlg.set_child (tb);
        dlg.present (this.get_root () as Gtk.Window);
    }

    private Adw.ActionRow make_compare_text_row (string title, string a, string b) {
        var row = new Adw.ActionRow () { title = title };
        var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            valign = Gtk.Align.CENTER, hexpand = true
        };
        var la = new Gtk.Label (a) {
            xalign = 0.0f, halign = Gtk.Align.START, hexpand = true,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR, max_width_chars = 36
        };
        var lb = new Gtk.Label (b) {
            xalign = 0.0f, halign = Gtk.Align.START, hexpand = true,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR, max_width_chars = 36
        };
        la.add_css_class ("dim-label");
        lb.add_css_class ("dim-label");
        content.append (la);
        content.append (lb);
        row.add_suffix (content);
        return row;
    }

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
        var row = new Adw.ActionRow () { title = d.name, activatable = true };

        string meta = "";
        if (is_nonempty (d.arch)) meta = d.arch;
        if (is_nonempty (d.size)) meta = (meta == "") ? d.size : meta + " · " + d.size;
        if (meta != "") row.add_suffix (dim_label (meta));

        if (is_nonempty (d.url)) {
            string captured_url = d.url;
            row.activated.connect (() => open_uri (captured_url));
            var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                valign = Gtk.Align.CENTER, tooltip_text = _("Copy download URL")
            };
            copy_btn.add_css_class ("flat");
            copy_btn.clicked.connect (() => copy_to_clipboard (captured_url));
            row.add_suffix (copy_btn);
        }
        exp.add_row (row);
    }

    private async void load_specfile () {
        var api = new Data.AltRepoClient ();
        clear_group (spec_group);
        try {
            var spec = yield api.get_specfile (branch, group.name);
            if (spec == null || !is_nonempty (spec.content)) {
                spec_group.add (new Adw.ActionRow () { title = _("Spec file not available") });
                return;
            }

            var tv = new Gtk.TextView () {
                editable = false, cursor_visible = false, monospace = true,
                wrap_mode = Gtk.WrapMode.NONE,
                top_margin = 8, bottom_margin = 8, left_margin = 12, right_margin = 12
            };
            tv.buffer.set_text (spec.content);

            var sw = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                min_content_height = 320, max_content_height = 520,
                propagate_natural_height = true
            };
            sw.set_child (tv);
            spec_group.add (sw);

            string content = spec.content;
            var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                valign = Gtk.Align.CENTER, tooltip_text = _("Copy")
            };
            copy_btn.add_css_class ("flat");
            copy_btn.clicked.connect (() => copy_to_clipboard (content));
            spec_group.set_header_suffix (copy_btn);
        } catch (Error e) {
            warning ("[DetailsPage] specfile failed: %s", e.message);
            spec_group.add (new Adw.ActionRow () {
                title = _("Spec file unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }
}
