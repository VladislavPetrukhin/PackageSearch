using Gtk;
using Adw;
using GLib;
using Gdk;
using Intl;

private delegate void RowClickFunc ();

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage, Ui.Findable {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    private Business.PackageManager pkg_mgr = new Business.PackageManager ();
    private InstallController installer;
    private Gee.HashMap<string, Gtk.Button> install_buttons = new Gee.HashMap<string, Gtk.Button> ();
    private string repo_evr = "";

    [GtkChild] private unowned Adw.ToastOverlay   toast_overlay;
    [GtkChild] private unowned Adw.WindowTitle    header_title;
    [GtkChild] private unowned Gtk.Box            header_actions;
    [GtkChild] private unowned Gtk.Revealer       loading_revealer;
    [GtkChild] private unowned Adw.StatusPage     error_status;
    [GtkChild] private unowned Gtk.ScrolledWindow content_scroll;
    [GtkChild] private unowned Gtk.SearchBar      find_bar;
    [GtkChild] private unowned Gtk.SearchEntry    find_entry;

    [GtkChild] private unowned Adw.PreferencesGroup hero_group;
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

    private void copy_to_clipboard (string text) {
        var disp = Gdk.Display.get_default ();
        if (disp != null) disp.get_clipboard ().set_text (text);
        toast_overlay.add_toast (new Adw.Toast (_("Copied")));
    }

    private void make_row_clickable (Adw.ActionRow row, owned RowClickFunc action) {
        row.activatable = false;
        var click = new Gtk.GestureClick ();
        click.released.connect ((n, x, y) => {
            if (n == 1) action ();
        });
        row.add_controller (click);
    }

    private void make_name_copyable (Adw.ActionRow row, string name) {
        make_row_clickable (row, () => copy_to_clipboard (name));
    }

    private void toast (string s) {
        toast_overlay.add_toast (new Adw.Toast (Ui.trim_toast (s)));
    }

    private static Gtk.Label dim_label (string text) {
        var l = new Gtk.Label (text) {
            valign = Gtk.Align.CENTER,
            ellipsize = Pango.EllipsizeMode.END,
            max_width_chars = 24
        };
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
        if (Ui.is_nonempty (value))
            info_group.add (new Adw.ActionRow () {
                title = title,
                subtitle = GLib.Markup.escape_text (value, -1),
                subtitle_selectable = true
            });
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        this.title = group.name;
        header_title.set_title (group.name ?? "");
        header_title.set_subtitle (branch);

        loading_revealer.reveal_child = true;

        installer = new InstallController (this, toast_overlay, pkg_mgr);
        installer.install_finished.connect ((ok) => {
            if (ok) refresh_install_states.begin ();
        });

        Ui.attach_find_bar (find_bar, find_entry, this, (q) => run_find (q));

        load_details.begin ();
    }

    public void begin_find () {
        find_bar.search_mode_enabled = true;
        find_entry.grab_focus ();
    }

    private void run_find (string q) {
        Ui.filter_group (info_group, q);
        Ui.filter_group (versions_group, q);
        Ui.filter_group (bins_group, q);
        Ui.filter_group (deps_group, q);
        Ui.filter_group (security_group, q);
        Ui.filter_group (downloads_group, q);
        Ui.filter_group (spec_group, q);
        Ui.filter_group (changelog_group, q);
    }

    private void show_text_dialog (string head, string body) {
        new TextDialog (head, body).present (this);
    }

    private async void load_details () {
        try {
            var api = new Data.PackageApi ();
            var d = yield api.get_source_details (branch, group.name, cancel);

            var vr = (d.version ?? "");
            if (Ui.is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;
            header_title.set_title (group.name);
            header_title.set_subtitle ((vr != "" ? vr + " · " : "") + branch);

            hero_group.add (new PackageHero (group.name, d.summary, d.group));

            clear_group (info_group);

            add_info_row_if_nonempty (_("Version"),    d.version);
            add_info_row_if_nonempty (_("Release"),    d.release);
            if (Ui.is_nonempty (d.maintainer)) {
                string nick = d.maintainer;
                var row_m = new Adw.ActionRow () {
                    title = _("Maintainer"),
                    subtitle = GLib.Markup.escape_text (nick, -1),
                    subtitle_selectable = true
                };
                row_m.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
                make_row_clickable (row_m, () => win.show_maintainer (nick, branch));
                info_group.add (row_m);
            }
            add_info_row_if_nonempty (_("License"),    d.license);

            if (Ui.is_nonempty (d.homepage)) {
                string url = Ui.normalize_url (d.homepage ?? "");
                if (url.length > 0) {
                    var row_home = new Adw.ActionRow () {
                        title = _("Homepage"),
                        subtitle = GLib.Markup.escape_text (url, -1),
                        subtitle_selectable = true
                    };
                    row_home.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
                    make_row_clickable (row_home, () => Ui.open_uri (url));
                    info_group.add (row_home);
                }
            }

            add_info_row_if_nonempty (_("Description"), d.description);

            yield populate_binaries (d);

            loading_revealer.reveal_child = false;

            yield load_versions ();
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            loading_revealer.reveal_child = false;
            warning ("[DetailsPage] load failed: %s", e.message);
            show_load_error (e);
            return;
        }

        if (cancel.is_cancelled ()) return;
        yield load_changelog ();

        load_dependencies ();
        load_security ();
        load_downloads ();
        load_specfile ();
    }

    private void show_load_error (Error e) {
        if (e.message != null && e.message.contains ("No data found")) {
            error_status.title = _("Package not found");
            error_status.description =
                _("%s is not available in %s. It may have been removed from the repository.")
                .printf (group.name, branch);
        } else {
            error_status.title = _("Failed to load");
            error_status.description =
                _("Could not load package details. Check your connection and try again.");
        }
        content_scroll.visible = false;
        error_status.visible = true;
    }

    private async void populate_binaries (Data.PackageDetails d) {
        clear_group (bins_group);
        install_buttons.clear ();

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

        bins_group.set_header_suffix (null);
        if (sys_branch.length > 0 && !can_install) {
            var info = new Gtk.Image.from_icon_name ("dialog-information-symbolic") {
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Install is available only for the system repository (%s)").printf (sys_branch)
            };
            info.add_css_class ("dim-label");
            bins_group.set_header_suffix (info);
        }

        Gee.HashMap<string, string>? installed = null;
        repo_evr = "";
        if (can_install) {
            installed = yield pkg_mgr.get_installed_packages ();
            if (Ui.is_nonempty (d.version)) {
                repo_evr = "0:" + d.version;
                if (Ui.is_nonempty (d.release)) repo_evr += "-" + d.release;
            }
        }

        clear_box (header_actions);
        if (can_install && names.contains (group.name)) {
            var install_hero = new Gtk.Button.with_label (_("Install")) {
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Install via apt-get (requires authentication)")
            };
            install_hero.add_css_class ("suggested-action");
            install_buttons.set (group.name, install_hero);

            bool is_installed = installed.has_key (group.name);
            bool needs_update = false;
            if (is_installed && repo_evr.length > 0)
                needs_update = Business.VersionCompare.compare_evr (installed.get (group.name), repo_evr) < 0;

            if (is_installed && !needs_update) {
                InstallController.mark_installed (install_hero);
            } else {
                string captured_evr = repo_evr;
                bool is_update = needs_update;
                if (is_update) {
                    install_hero.label = _("Update");
                    install_hero.tooltip_text = _("Update via apt-get (requires authentication)");
                }
                install_hero.clicked.connect (() => {
                    installer.install.begin (group.name, install_hero, captured_evr, is_update);
                });
            }
            header_actions.append (install_hero);
        }

        foreach (var name in names) {
            var arches = by_name.get (name);
            var row = new Adw.ActionRow () { title = name };
            make_name_copyable (row, name);

            var arch_str = "";
            foreach (var a in arches) arch_str = (arch_str == "") ? a : arch_str + ", " + a;
            if (arch_str != "") row.add_suffix (dim_label (arch_str));

            if (can_install) {
                var install_btn = new Gtk.Button.with_label (_("Install")) {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = _("Install via apt-get (requires authentication)")
                };
                install_btn.add_css_class ("suggested-action");
                install_buttons.set (name, install_btn);

                bool is_installed = installed.has_key (name);
                bool needs_update = false;
                if (is_installed && repo_evr.length > 0)
                    needs_update = Business.VersionCompare.compare_evr (installed.get (name), repo_evr) < 0;

                if (is_installed && !needs_update) {
                    InstallController.mark_installed (install_btn);
                } else {
                    bool is_update = needs_update;
                    string captured_evr = repo_evr;
                    if (is_update) {
                        install_btn.label = _("Update");
                        install_btn.tooltip_text = _("Update via apt-get (requires authentication)");
                    }
                    install_btn.clicked.connect (() => {
                        installer.install.begin (name, install_btn, captured_evr, is_update);
                    });
                }
                row.add_suffix (install_btn);
            }

            bins_group.add (row);
        }

        if (names.size == 0)
            bins_group.add (new Adw.ActionRow () { title = _("No binary packages") });
    }

    private async void refresh_install_states () {
        if (repo_evr.length == 0 || install_buttons.size == 0) return;
        var installed = yield pkg_mgr.get_installed_packages ();
        foreach (var e in install_buttons.entries) {
            if (!installed.has_key (e.key)) continue;
            if (Business.VersionCompare.compare_evr (installed.get (e.key), repo_evr) >= 0)
                InstallController.mark_installed (e.value);
        }
    }

    private async void load_changelog () {
        var api = new Data.PackageApi ();
        clear_group (changelog_group);
        try {
            var log = yield api.get_changelog (branch, group.name, 50, cancel);
            bool any = false;
            foreach (var it in log.changelog) {
                any = true;
                string head = "";
                if (Ui.is_nonempty (it.date)) head = it.date;
                if (Ui.is_nonempty (it.nick)) head = (head == "") ? it.nick : head + " — " + it.nick;

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
                if (Ui.is_nonempty (it.evr)) row.add_suffix (dim_label (it.evr));

                string captured_title = row.title;
                string captured_body  = it.message ?? "";
                row.activated.connect (() => show_text_dialog (captured_title, captured_body));
                changelog_group.add (row);
            }
            if (!any)
                changelog_group.add (new Adw.ActionRow () { title = _("No changes found") });
        } catch (Error ce) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] changelog failed: %s", ce.message);
            changelog_group.add (new Adw.ActionRow () {
                title = _("Changelog unavailable"),
                subtitle = GLib.Markup.escape_text (ce.message, -1)
            });
        }
    }

    private void load_dependencies () {
        clear_group (deps_group);

        var graph_row = new Adw.ActionRow () {
            title = _("Dependency graph"),
            subtitle = _("Visualize what %s needs and what depends on it").printf (group.name),
            activatable = true
        };
        graph_row.add_prefix (new Gtk.Image.from_icon_name ("application-x-addon-symbolic"));
        var graph_btn = new Gtk.Button.with_label (_("Open graph")) {
            valign = Gtk.Align.CENTER
        };
        graph_btn.add_css_class ("flat");
        graph_row.add_suffix (graph_btn);
        graph_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
        graph_row.activated.connect (() => win.show_dependency_graph (group.name, branch));
        graph_btn.clicked.connect (() => win.show_dependency_graph (group.name, branch));
        deps_group.add (graph_row);

        var build_exp = new LazyExpanderRow () {
            title = _("Build dependencies"),
            subtitle = _("Packages required to build %s").printf (group.name)
        };
        build_exp.load_requested.connect (() => fill_build_depends.begin (build_exp));
        deps_group.add (build_exp);

        var rev_exp = new LazyExpanderRow () {
            title = _("Reverse dependencies"),
            subtitle = _("Source packages that depend on %s").printf (group.name)
        };
        rev_exp.load_requested.connect (() => fill_reverse_depends.begin (rev_exp));
        deps_group.add (rev_exp);
    }

    private async void fill_build_depends (LazyExpanderRow exp) {
        var api = new Data.DependencyApi ();
        try {
            var builds = yield api.get_direct_build_depends (branch, group.name, cancel);
            if (cancel.is_cancelled ()) return;
            exp.clear_placeholder ();
            if (builds == null || builds.size == 0) {
                exp.show_message (_("No dependencies found"));
            } else {
                exp.set_subtitle (_("%d packages").printf (builds.size));
                foreach (var d in builds) {
                    var r = new Adw.ActionRow () { title = d.name };
                    make_name_copyable (r, d.name);
                    var vr = Ui.evr (d.version, d.release);
                    if (vr != "") r.add_suffix (dim_label (vr));
                    exp.add_row (r);
                }
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] build deps failed: %s", e.message);
            exp.show_message (_("Build dependencies unavailable"), e.message);
        }
    }

    private async void fill_reverse_depends (LazyExpanderRow exp) {
        var api = new Data.DependencyApi ();
        try {
            var revs = yield api.get_reverse_depends (branch, group.name, "both", cancel);
            if (cancel.is_cancelled ()) return;
            exp.clear_placeholder ();
            if (revs == null || revs.size == 0) {
                exp.show_message (_("No reverse dependencies"));
            } else {
                exp.set_subtitle (_("%d packages").printf (revs.size));
                foreach (var d in revs) {
                    var r = new Adw.ActionRow () { title = d.name };
                    make_name_copyable (r, d.name);
                    if (Ui.is_nonempty (d.branch)) r.add_suffix (dim_label (d.branch));
                    exp.add_row (r);
                }
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] reverse deps failed: %s", e.message);
            exp.show_message (_("Reverse dependencies unavailable"), e.message);
        }
    }

    private void load_security () {
        clear_group (security_group);

        var errata_exp = new LazyExpanderRow () { title = _("Security advisories") };
        errata_exp.load_requested.connect (() => fill_errata.begin (errata_exp));
        security_group.add (errata_exp);

        var bugs_exp = new LazyExpanderRow () { title = _("Bugzilla") };
        bugs_exp.load_requested.connect (() => fill_bugs.begin (bugs_exp));
        security_group.add (bugs_exp);
    }

    private async void fill_errata (LazyExpanderRow exp) {
        var api = new Data.SecurityApi ();
        try {
            var erratas = yield api.get_errata_for_package (branch, group.name, cancel);
            if (cancel.is_cancelled ()) return;
            exp.clear_placeholder ();
            int shown = 0;
            if (erratas != null) {
                foreach (var er in erratas) {
                    var row = make_errata_row (er);
                    if (row != null) { exp.add_row (row); shown++; }
                }
            }
            if (shown == 0)
                exp.show_message (_("No security advisories"));
            else
                exp.set_subtitle (_("%d advisories").printf (shown));
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] errata failed: %s", e.message);
            exp.show_message (_("Advisories unavailable"), e.message);
        }
    }

    private static bool is_vuln_ref (Data.ErrataRef r) {
        if (!Ui.is_nonempty (r.id)) return false;
        if ((r.ref_type ?? "").down () == "bug") return false;
        string idu = r.id.up ();
        if (idu.has_prefix ("CVE") || idu.has_prefix ("BDU") || idu.has_prefix ("GHSA"))
            return true;
        return (r.ref_type ?? "").down () == "vuln";
    }

    private Gtk.Widget? make_errata_row (Data.ErrataInfo er) {
        var seen  = new Gee.HashSet<string> ();
        var vulns = new Gee.ArrayList<Data.ErrataRef> ();
        foreach (var r in er.references) {
            if (!is_vuln_ref (r) || seen.contains (r.id)) continue;
            seen.add (r.id);
            vulns.add (r);
        }
        if (vulns.size == 0) return null;

        int cve = 0, bdu = 0;
        foreach (var r in vulns) {
            string idu = r.id.up ();
            if (idu.has_prefix ("CVE")) cve++;
            else if (idu.has_prefix ("BDU")) bdu++;
        }

        string ver = "";
        if (Ui.is_nonempty (er.pkg_version)) {
            ver = er.pkg_version;
            if (Ui.is_nonempty (er.pkg_release)) ver += "-" + er.pkg_release;
        }
        string title = (ver != "") ? ver : er.id;

        string sub = Ui.date_only (er.created);
        string counts = "";
        if (cve > 0) counts = _("%d CVE").printf (cve);
        if (bdu > 0) counts = (counts == "") ? _("%d BDU").printf (bdu)
                                             : counts + " · " + _("%d BDU").printf (bdu);
        if (counts != "") sub = (sub == "") ? counts : sub + " · " + counts;

        var row = new ErrataRow (title, sub);
        foreach (var r in vulns)
            row.add_row (new LinkRow (r.id, reference_url (r)));

        return row;
    }

    private static string? reference_url (Data.ErrataRef r) {
        string idu = r.id.up ();
        if (idu.has_prefix ("CVE"))
            return "https://nvd.nist.gov/vuln/detail/" + r.id;
        if (idu.has_prefix ("BDU"))
            return "https://bdu.fstec.ru/vul/"
                + r.id.replace ("BDU:", "").replace ("BDU-", "").strip ();
        if (idu.has_prefix ("GHSA"))
            return "https://github.com/advisories/" + r.id;
        return null;
    }

    private async void fill_bugs (LazyExpanderRow exp) {
        var api = new Data.SecurityApi ();
        try {
            var bugs = yield api.get_bugs_by_package (group.name, cancel);
            if (cancel.is_cancelled ()) return;
            exp.clear_placeholder ();
            if (bugs == null || bugs.size == 0) {
                exp.show_message (_("No bugs found"));
                return;
            }
            exp.set_subtitle (_("%d bug(s) found").printf (bugs.size));

            var statuses = new Gee.ArrayList<string> ();
            foreach (var b in bugs) {
                var s = (b.status ?? "").strip ();
                if (s != "" && !statuses.contains (s)) statuses.add (s);
            }
            statuses.sort ((a, b) => strcmp (a, b));

            var rows = new Gee.ArrayList<BugRow> ();
            foreach (var b in bugs)
                rows.add (new BugRow (b));

            if (statuses.size > 1) {
                var options = new string[statuses.size + 1];
                options[0] = _("All statuses");
                for (int i = 0; i < statuses.size; i++)
                    options[i + 1] = statuses[i];

                var filter = new BugFilterRow (options);
                filter.status_changed.connect ((sel) => {
                    string? want = (sel == 0) ? null : statuses[(int) sel - 1];
                    foreach (var row in rows)
                        row.visible = (want == null) || (row.status_value == want);
                });
                exp.add_row (filter);
            }

            foreach (var row in rows)
                exp.add_row (row);
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] bugs failed: %s", e.message);
            exp.show_message (_("Bugzilla unavailable"), e.message);
        }
    }

    private async void load_versions () {
        var api = new Data.PackageApi ();
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
        versions_group.set_description (_("Open a repository to view the package there, or tick two to compare"));

        try {
            var vs = yield api.get_package_versions_all (group.name, cancel);
            if (vs == null || vs.size == 0) {
                versions_group.add (new Adw.ActionRow () { title = _("No versions found") });
                return;
            }
            foreach (var v in vs) {
                string vr = (v.version ?? "");
                if (Ui.is_nonempty (v.release)) vr = (vr == "") ? v.release : vr + "-" + v.release;

                bool is_current = (v.branch == branch);
                var row = new Adw.ActionRow () { title = v.branch };
                if (is_current) row.subtitle = _("current");

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

                if (!is_current) {
                    row.activatable = true;
                    string nav_branch = v.branch;
                    string? nav_ver = v.version;
                    string? nav_rel = v.release;
                    row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
                    row.activated.connect (() => {
                        var g = new Data.SourceGroup (group.name);
                        g.version = nav_ver;
                        g.release = nav_rel;
                        win.show_details (g, nav_branch);
                    });
                }

                versions_group.add (row);
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] versions failed: %s", e.message);
            versions_group.add (new Adw.ActionRow () {
                title = _("Versions unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private async void show_compare_dialog (string branch_a, string branch_b) {
        compare_btn.sensitive = false;
        compare_btn.label = _("Loading…");

        var api = new Data.PackageApi ();
        Data.PackageDetails? a = null;
        Data.PackageDetails? b = null;
        try {
            a = yield api.get_source_details (branch_a, group.name, cancel);
            b = yield api.get_source_details (branch_b, group.name, cancel);
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] compare failed: %s", e.message);
            toast (_("Compare failed: %s").printf (e.message));
            compare_btn.label = _("Compare selected");
            compare_btn.sensitive = (selected_branches.size == 2);
            return;
        }
        compare_btn.label = _("Compare selected");
        compare_btn.sensitive = (selected_branches.size == 2);

        Data.SpecFileInfo? spec_a = null;
        Data.SpecFileInfo? spec_b = null;
        try { spec_a = yield api.get_specfile (branch_a, group.name, cancel); }
        catch (Error e) { warning ("[DetailsPage] compare spec %s failed: %s", branch_a, e.message); }
        try { spec_b = yield api.get_specfile (branch_b, group.name, cancel); }
        catch (Error e) { warning ("[DetailsPage] compare spec %s failed: %s", branch_b, e.message); }

        new VersionCompareDialog (group.name, branch_a, branch_b, a, b, spec_a, spec_b).present (this);
    }

    private void load_downloads () {
        clear_group (downloads_group);

        var src_exp = new LazyExpanderRow () { title = _("Source (.src.rpm)") };
        src_exp.load_requested.connect (() => fill_src_downloads.begin (src_exp));
        downloads_group.add (src_exp);

        var bin_exp = new LazyExpanderRow () { title = _("Binaries (.rpm)") };
        bin_exp.load_requested.connect (() => fill_bin_downloads.begin (bin_exp));
        downloads_group.add (bin_exp);
    }

    private async void fill_src_downloads (LazyExpanderRow exp) {
        var api = new Data.DownloadApi ();
        try {
            var src_links = yield api.get_source_downloads (branch, group.name, cancel);
            if (cancel.is_cancelled ()) return;
            exp.clear_placeholder ();
            if (src_links == null || src_links.size == 0) {
                exp.show_message (_("No source downloads"));
            } else {
                foreach (var d in src_links) add_download_row (exp, d);
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] src downloads failed: %s", e.message);
            exp.show_message (_("Source downloads unavailable"), e.message);
        }
    }

    private async void fill_bin_downloads (LazyExpanderRow exp) {
        var api = new Data.DownloadApi ();
        try {
            var bin_links = yield api.get_binary_downloads (branch, group.name, cancel);
            if (cancel.is_cancelled ()) return;
            exp.clear_placeholder ();
            if (bin_links == null || bin_links.size == 0) {
                exp.show_message (_("No binary downloads"));
            } else {
                foreach (var d in bin_links) add_download_row (exp, d);
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] bin downloads failed: %s", e.message);
            exp.show_message (_("Binary downloads unavailable"), e.message);
        }
    }

    private void add_download_row (Adw.ExpanderRow exp, Data.DownloadLink d) {
        var row = new Adw.ActionRow () { title = d.name, title_selectable = true };

        string meta = "";
        if (Ui.is_nonempty (d.arch)) meta = d.arch;
        if (Ui.is_nonempty (d.size)) meta = (meta == "") ? d.size : meta + " · " + d.size;
        if (meta != "") row.add_suffix (dim_label (meta));

        if (Ui.is_nonempty (d.url)) {
            string captured_url = d.url;
            make_row_clickable (row, () => Ui.open_uri (captured_url));
            var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                valign = Gtk.Align.CENTER, tooltip_text = _("Copy download URL")
            };
            copy_btn.add_css_class ("flat");
            copy_btn.clicked.connect (() => copy_to_clipboard (captured_url));
            row.add_suffix (copy_btn);
        }
        exp.add_row (row);
    }

    private void load_specfile () {
        clear_group (spec_group);

        var row = new Adw.ActionRow () { title = _("Spec file"), activatable = true };
        var open_btn = new Gtk.Button.with_label (_("Open")) { valign = Gtk.Align.CENTER };
        open_btn.add_css_class ("flat");
        row.add_suffix (open_btn);

        open_btn.clicked.connect (() => open_specfile.begin (open_btn));
        row.activated.connect (() => open_specfile.begin (open_btn));
        spec_group.add (row);
    }

    private async void open_specfile (Gtk.Button btn) {
        if (!btn.sensitive) return;
        btn.sensitive = false;
        string orig = btn.label;
        btn.label = _("Loading…");

        var api = new Data.PackageApi ();
        try {
            var spec = yield api.get_specfile (branch, group.name, cancel);
            btn.label = orig;
            btn.sensitive = true;
            if (spec == null || !Ui.is_nonempty (spec.content)) {
                toast (_("Spec file not available"));
                return;
            }
            string fname = Ui.is_nonempty (spec.name) ? spec.name : group.name + ".spec";
            show_text_dialog (fname, spec.content);
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[DetailsPage] specfile failed: %s", e.message);
            btn.label = orig;
            btn.sensitive = true;
            toast (_("Spec file unavailable"));
        }
    }
}
