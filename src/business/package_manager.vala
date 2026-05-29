using GLib;
using Intl;

namespace Business {

    public enum InstallResult {
        SUCCESS,
        CANCELLED,
        FAILED
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
                if (stdout_buf != null) {
                    foreach (var line in stdout_buf.split ("\n")) {
                        var t = line.strip ();
                        if (t.length == 0) continue;
                        var parts = t.split (" ");
                        foreach (var p in parts) {
                            if (p.index_of_char ('/') < 0) continue;
                            if (p.contains ("://")) continue;
                            var segs = p.split ("/");
                            if (segs.length >= 2 && segs[0].length > 0) {
                                detected = segs[0].down ();
                                break;
                            }
                        }
                        if (detected.length > 0) break;
                    }
                }
            } catch (Error e) {
                warning ("[PackageManager] apt-repo failed: %s", e.message);
            }
            _system_branch = detected;
            return _system_branch;
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

        public async InstallPlan simulate_install (string pkg_name) {
            var plan = new InstallPlan ();
            string? cache_dir = null;
            try {
                try {
                    cache_dir = DirUtils.make_tmp ("packagesearch-apt-XXXXXX");
                } catch (Error e) {
                    cache_dir = null;
                }

                var launcher = new SubprocessLauncher (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                launcher.setenv ("LC_ALL", "C", true);
                var sp = (cache_dir != null)
                    ? launcher.spawnv ({ "apt-get", "-o", "Dir::Cache=" + cache_dir,
                                         "--simulate", "install", pkg_name })
                    : launcher.spawnv ({ "apt-get", "--simulate", "install", pkg_name });

                string? out_buf = null;
                string? err_buf = null;
                yield sp.communicate_utf8_async (null, null, out out_buf, out err_buf);

                if (cache_dir != null) { rm_rf (cache_dir); cache_dir = null; }

                if (!sp.get_successful () && (out_buf == null || out_buf.strip ().length == 0)) {
                    plan.ok = false;
                    plan.error = (err_buf != null && err_buf.strip ().length > 0)
                        ? err_buf.strip () : "apt-get simulation failed";
                    return plan;
                }

                string mode = "";
                foreach (var raw in (out_buf ?? "").split ("\n")) {
                    if (raw.length == 0) continue;
                    bool indented = (raw[0] == ' ' || raw[0] == '\t');
                    var line = raw.strip ();
                    if (line.length == 0) continue;

                    if (line.has_prefix ("The following NEW packages")) { mode = "install"; continue; }
                    if (line.has_prefix ("The following extra packages")) { mode = "skip"; continue; }
                    if (line.contains ("will be upgraded")) { mode = "upgrade"; continue; }
                    if (line.contains ("will be REMOVED")) { mode = "remove"; continue; }

                    if (indented && mode != "") {
                        foreach (var tok in line.split (" ")) {
                            var t = tok.strip ();
                            if (t.length == 0) continue;
                            if (mode == "install" && !plan.install.contains (t)) plan.install.add (t);
                            else if (mode == "upgrade" && !plan.upgrade.contains (t)) plan.upgrade.add (t);
                            else if (mode == "remove" && !plan.remove.contains (t)) plan.remove.add (t);
                        }
                        continue;
                    }

                    mode = "";
                    if (line.has_prefix ("Need to get")) plan.download = line;
                    else if (line.has_prefix ("After unpacking") || line.contains ("disk space")) plan.disk = line;
                    else if (line.contains ("newly installed") || line.contains ("upgraded,")) plan.summary = line;
                }
                plan.ok = true;
                return plan;
            } catch (Error e) {
                if (cache_dir != null) rm_rf (cache_dir);
                warning ("[PackageManager] simulate failed: %s", e.message);
                plan.ok = false;
                plan.error = e.message;
                return plan;
            }
        }

        private static void rm_rf (string path) {
            try {
                var dir = Dir.open (path);
                string? name;
                while ((name = dir.read_name ()) != null) {
                    var child = Path.build_filename (path, name);
                    if (FileUtils.test (child, FileTest.IS_DIR))
                        rm_rf (child);
                    else
                        FileUtils.unlink (child);
                }
            } catch (Error e) {
            }
            DirUtils.remove (path);
        }

        public async InstallResult run_install (string pkg_name,
                                                string? repo_evr,
                                                GLib.Cancellable cancellable,
                                                out string? error_output) {
            error_output = null;
            try {
                string output;
                var res = yield run_apt_stream (
                    { "pkexec", "sh", "-c",
                      "LC_ALL=C apt-get install -y \"$1\"", "sh", pkg_name },
                    cancellable, out output);

                if (res == InstallResult.FAILED
                    && !cancellable.is_cancelled ()
                    && looks_like_stale_index (output)) {
                    install_progress (_("Package lists are out of date, refreshing…"));
                    res = yield run_apt_stream (
                        { "pkexec", "sh", "-c",
                          "LC_ALL=C apt-get update && LC_ALL=C apt-get install -y \"$1\"",
                          "sh", pkg_name },
                        cancellable, out output);
                }

                if (res == InstallResult.SUCCESS) {
                    if (_installed_cache != null && repo_evr != null && repo_evr.length > 0)
                        _installed_cache.set (pkg_name, repo_evr);
                    return InstallResult.SUCCESS;
                }

                if (res == InstallResult.FAILED)
                    error_output = output.strip ();
                return res;
            } catch (Error e) {
                warning ("[PackageManager] install spawn failed: %s", e.message);
                error_output = e.message;
                return InstallResult.FAILED;
            }
        }

        private async InstallResult run_apt_stream (string[] argv,
                                                    GLib.Cancellable cancellable,
                                                    out string output) throws GLib.Error {
            var collected = new StringBuilder ();
            var launcher = new SubprocessLauncher (
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            launcher.setenv ("LC_ALL", "C", true);
            var sp = launcher.spawnv (argv);

            ulong cancel_id = cancellable.connect (() => {
                sp.force_exit ();
            });

            var dis = new DataInputStream (sp.get_stdout_pipe ());
            try {
                string? line;
                while ((line = yield dis.read_line_async (Priority.DEFAULT, cancellable)) != null) {
                    var t = line.strip ();
                    if (t.length > 0) {
                        collected.append (t);
                        collected.append_c ('\n');
                        install_progress (t);
                    }
                }
            } catch (IOError.CANCELLED ce) {
            }

            yield sp.wait_async (null);
            cancellable.disconnect (cancel_id);
            output = collected.str;

            if (cancellable.is_cancelled ())
                return InstallResult.CANCELLED;
            if (sp.get_successful ())
                return InstallResult.SUCCESS;
            if (sp.get_if_exited () && sp.get_exit_status () == 126)
                return InstallResult.CANCELLED;
            return InstallResult.FAILED;
        }

        private static bool looks_like_stale_index (string output) {
            var o = output.down ();
            return o.contains ("404")
                || o.contains ("not found")
                || o.contains ("failed to fetch")
                || o.contains ("hash sum mismatch")
                || o.contains ("size mismatch");
        }
    }
}
