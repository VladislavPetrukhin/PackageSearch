using GLib;
using Intl;

namespace Business {

    public enum InstallResult {
        SUCCESS,
        CANCELLED,
        FAILED,
        UNTRUSTED
    }

    public class InstallPlan : GLib.Object {
        public Gee.ArrayList<string> install { get; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> upgrade { get; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> remove  { get; default = new Gee.ArrayList<string> (); }
        public string  summary  { get; set; default = ""; }
        public string  download { get; set; default = ""; }
        public string  disk     { get; set; default = ""; }
        public bool    ok       { get; set; default = false; }
        public string? error    { get; set; default = null; }

        public bool is_empty () {
            return install.size == 0 && upgrade.size == 0 && remove.size == 0;
        }
    }

    public class PackageManager : GLib.Object {

        private static string? _system_branch = null;

        private static Gee.HashMap<string, string>? _installed_cache = null;

        public async string get_system_branch () {
            if (_system_branch != null) return _system_branch;
            string detected = "";
            try {
                var sp = new Subprocess.newv (
                    { "apt-repo" },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
                );
                string? stdout_buf = null;
                yield sp.communicate_utf8_async (null, null, out stdout_buf, null);
                if (stdout_buf != null)
                    detected = detect_branch (stdout_buf);
            } catch (Error e) {
                warning ("[PackageManager] apt-repo failed: %s", e.message);
            }
            _system_branch = detected;
            return _system_branch;
        }

        public static string detect_branch (string apt_repo_output) {
            foreach (var line in apt_repo_output.split ("\n")) {
                var t = line.strip ();
                if (t.length == 0 || t.has_prefix ("#")) continue;
                foreach (var tok in t.split (" ")) {
                    foreach (var seg in tok.split ("/")) {
                        var s = seg.replace ("[", "").replace ("]", "").strip ().down ();
                        if (Data.Validation.branch_allowed (s)) return s;
                    }
                }
            }
            return "";
        }

        public async bool is_system_branch (string branch) {
            var sys = yield get_system_branch ();
            return sys.length > 0 && sys == branch.down ();
        }

        public async Gee.HashMap<string, string> get_installed_packages () {
            if (_installed_cache != null) return _installed_cache;
            var map = new Gee.HashMap<string, string> ();
            try {
                var sp = new Subprocess.newv (
                    { "rpm", "-qa", "--queryformat",
                      "%{NAME} %|EPOCH?{%{EPOCH}}:{0}|:%{VERSION}-%{RELEASE}\n" },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
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
                warning ("[PackageManager] rpm -qa failed: %s", e.message);
            }
            _installed_cache = map;
            return _installed_cache;
        }

        public async bool is_installed (string pkg_name) {
            var pkgs = yield get_installed_packages ();
            return pkgs.has_key (pkg_name);
        }

        public async bool needs_update (string pkg_name, string repo_evr) {
            var pkgs = yield get_installed_packages ();
            if (!pkgs.has_key (pkg_name)) return false;
            string installed_evr = pkgs.get (pkg_name);
            return VersionCompare.compare_evr (installed_evr, repo_evr) < 0;
        }

        public signal void install_progress (string line);
        public signal void install_percentage (int percent);

        private async string? resolve_package_id (Pk.Client client, string pkg_name,
                                                  GLib.Cancellable? cancellable) throws GLib.Error {
            var filters = Pk.Bitfield.from_enums (Pk.Filter.NEWEST, Pk.Filter.ARCH);
            string[] names = { pkg_name, null };
            var res = yield client.resolve_async (filters, names, cancellable, (p, t) => {});
            if (res.get_exit_code () != Pk.Exit.SUCCESS) return null;
            var arr = res.get_package_array ();
            string? any = null;
            for (uint i = 0; i < arr.length; i++) {
                var pkg = arr.get (i);
                any = pkg.get_id ();
                if (pkg.get_info () == Pk.Info.AVAILABLE) return pkg.get_id ();
            }
            return any;
        }

        public async InstallPlan simulate_install (string pkg_name) {
            var plan = new InstallPlan ();
            try {
                var client = new Pk.Client ();
                string? pid = yield resolve_package_id (client, pkg_name, null);
                if (pid == null) {
                    plan.ok = false;
                    plan.error = _("Package %s not found").printf (pkg_name);
                    return plan;
                }

                string[] ids = { pid, null };
                var flags = Pk.Bitfield.from_enums (Pk.TransactionFlag.SIMULATE);
                var res = yield client.install_packages_async (flags, ids, null, (p, t) => {});

                if (res.get_exit_code () != Pk.Exit.SUCCESS) {
                    plan.ok = false;
                    var err = res.get_error_code ();
                    plan.error = (err != null) ? err.get_details () : "simulation failed";
                    return plan;
                }

                var arr = res.get_package_array ();
                var dl_ids = new Gee.ArrayList<string> ();
                for (uint i = 0; i < arr.length; i++) {
                    var pkg = arr.get (i);
                    if (classify_package (pkg.get_info (), pkg.get_name (), plan))
                        dl_ids.add (pkg.get_id ());
                }

                yield fill_download_size (client, dl_ids, plan);
                plan.summary = build_summary (plan);
                plan.ok = true;
                return plan;
            } catch (Error e) {
                warning ("[PackageManager] simulate failed: %s", e.message);
                plan.ok = false;
                plan.error = e.message;
                return plan;
            }
        }

        private async void fill_download_size (Pk.Client client, Gee.ArrayList<string> ids,
                                               InstallPlan plan) {
            if (ids.size == 0) return;
            var arr = new string[ids.size + 1];
            for (int i = 0; i < ids.size; i++) arr[i] = ids[i];
            arr[ids.size] = null;
            try {
                var res = yield client.get_details_async (arr, null, (p, t) => {});
                if (res.get_exit_code () != Pk.Exit.SUCCESS) return;
                var darr = res.get_details_array ();
                uint64 dl = 0;
                for (uint i = 0; i < darr.length; i++) dl += darr.get (i).get_download_size ();
                if (dl > 0) plan.download = _("Download size: %s").printf (format_size (dl));
            } catch (Error e) {
                warning ("[PackageManager] details failed: %s", e.message);
            }
        }

        public static bool classify_package (Pk.Info info, string name, InstallPlan plan) {
            switch (info) {
            case Pk.Info.INSTALLING:
            case Pk.Info.REINSTALLING:
                if (!plan.install.contains (name)) plan.install.add (name);
                return true;
            case Pk.Info.UPDATING:
            case Pk.Info.DOWNGRADING:
                if (!plan.upgrade.contains (name)) plan.upgrade.add (name);
                return true;
            case Pk.Info.REMOVING:
            case Pk.Info.OBSOLETING:
                if (!plan.remove.contains (name)) plan.remove.add (name);
                return false;
            default:
                return false;
            }
        }

        public static string build_summary (InstallPlan plan) {
            string s = "";
            if (plan.install.size > 0)
                s = _("%d to install").printf (plan.install.size);
            if (plan.upgrade.size > 0)
                s += (s == "" ? "" : ", ") + _("%d to upgrade").printf (plan.upgrade.size);
            if (plan.remove.size > 0)
                s += (s == "" ? "" : ", ") + _("%d to remove").printf (plan.remove.size);
            return s;
        }

        public static bool is_untrusted_error (Pk.Exit exit, Pk.ErrorEnum code) {
            if (exit == Pk.Exit.NEED_UNTRUSTED || exit == Pk.Exit.KEY_REQUIRED)
                return true;
            switch (code) {
            case Pk.ErrorEnum.GPG_FAILURE:
            case Pk.ErrorEnum.BAD_GPG_SIGNATURE:
            case Pk.ErrorEnum.MISSING_GPG_SIGNATURE:
            case Pk.ErrorEnum.CANNOT_INSTALL_REPO_UNSIGNED:
                return true;
            default:
                return false;
            }
        }

        public static bool is_stale_cache_error (Pk.ErrorEnum code) {
            switch (code) {
            case Pk.ErrorEnum.PACKAGE_DOWNLOAD_FAILED:
            case Pk.ErrorEnum.PACKAGE_NOT_FOUND:
            case Pk.ErrorEnum.NO_CACHE:
            case Pk.ErrorEnum.FILE_NOT_FOUND:
            case Pk.ErrorEnum.NO_MORE_MIRRORS_TO_TRY:
            case Pk.ErrorEnum.UPDATE_NOT_FOUND:
            case Pk.ErrorEnum.CANNOT_FETCH_SOURCES:
                return true;
            default:
                return false;
            }
        }

        public static bool looks_stale_message (string? msg) {
            if (msg == null) return false;
            var m = msg.down ();
            return m.contains ("not (yet) available")
                || m.contains ("unable to fetch")
                || m.contains ("failed to fetch")
                || m.contains ("failed to open file")
                || m.contains ("404")
                || m.contains ("not found")
                || m.contains ("no more mirrors")
                || m.contains ("hash sum mismatch")
                || m.contains ("size mismatch");
        }

        public static bool looks_untrusted_message (string? msg) {
            if (msg == null) return false;
            var m = msg.down ();
            return m.contains ("untrusted")
                || m.contains ("not trusted")
                || m.contains ("nopubkey")
                || m.contains ("no_pubkey")
                || m.contains ("gpg error")
                || m.contains ("not signed")
                || m.contains ("unsigned")
                || m.contains ("missing signature")
                || m.contains ("bad signature");
        }

        public async InstallResult run_install (string pkg_name,
                                                string? repo_evr,
                                                bool allow_untrusted,
                                                GLib.Cancellable cancellable,
                                                out string? error_output) {
            error_output = null;
            var client = new Pk.Client ();
            client.set_cache_age (86400);
            bool refreshed = false;

            while (true) {
                try {
                    string? pid = yield resolve_package_id (client, pkg_name, cancellable);
                    if (cancellable.is_cancelled ()) return InstallResult.CANCELLED;
                    if (pid == null) {
                        if (!refreshed) {
                            install_progress (_("Package lists are out of date, refreshing…"));
                            yield client.refresh_cache_async (true, cancellable, on_progress);
                            refreshed = true;
                            continue;
                        }
                        error_output = _("Package %s not found").printf (pkg_name);
                        return InstallResult.FAILED;
                    }

                    string[] ids = { pid, null };
                    var flags = allow_untrusted
                        ? Pk.Bitfield.from_enums (Pk.TransactionFlag.NONE)
                        : Pk.Bitfield.from_enums (Pk.TransactionFlag.ONLY_TRUSTED);
                    var res = yield client.install_packages_async (flags, ids, cancellable, on_progress);

                    if (cancellable.is_cancelled ()) return InstallResult.CANCELLED;

                    var exit = res.get_exit_code ();
                    if (exit == Pk.Exit.SUCCESS) {
                        _installed_cache = null;
                        return InstallResult.SUCCESS;
                    }
                    if (exit == Pk.Exit.CANCELLED) return InstallResult.CANCELLED;

                    var err = res.get_error_code ();
                    var code = (err != null) ? err.get_code () : Pk.ErrorEnum.UNKNOWN;

                    if (!allow_untrusted && is_untrusted_error (exit, code))
                        return InstallResult.UNTRUSTED;

                    if (!refreshed && is_stale_cache_error (code)) {
                        install_progress (_("Package lists are out of date, refreshing…"));
                        yield client.refresh_cache_async (true, cancellable, on_progress);
                        refreshed = true;
                        continue;
                    }

                    error_output = (err != null) ? err.get_details () : "install failed";
                    return InstallResult.FAILED;
                } catch (Error e) {
                    if (cancellable.is_cancelled ()) return InstallResult.CANCELLED;

                    if (!allow_untrusted && looks_untrusted_message (e.message))
                        return InstallResult.UNTRUSTED;

                    if (!refreshed && looks_stale_message (e.message)) {
                        refreshed = true;
                        install_progress (_("Package lists are out of date, refreshing…"));
                        try {
                            yield client.refresh_cache_async (true, cancellable, on_progress);
                            continue;
                        } catch (Error re) {
                            if (cancellable.is_cancelled ()) return InstallResult.CANCELLED;
                            warning ("[PackageManager] refresh failed: %s", re.message);
                            error_output = e.message;
                            return InstallResult.FAILED;
                        }
                    }

                    warning ("[PackageManager] install failed: %s", e.message);
                    error_output = e.message;
                    return InstallResult.FAILED;
                }
            }
        }

        private void on_progress (Pk.Progress progress, Pk.ProgressType type) {
            switch (type) {
            case Pk.ProgressType.PACKAGE:
                var pkg = progress.get_package ();
                if (pkg != null) {
                    unowned string? verb = pkg.get_info ().to_localised_present ();
                    install_progress ((verb != null)
                        ? "%s %s".printf (verb, pkg.get_name ())
                        : pkg.get_name ());
                }
                break;
            case Pk.ProgressType.STATUS:
                install_progress (progress.get_status ().to_localised_text ());
                break;
            case Pk.ProgressType.PERCENTAGE:
                int pct = progress.get_percentage ();
                if (pct >= 0 && pct <= 100) install_percentage (pct);
                break;
            default:
                break;
            }
        }
    }
}
