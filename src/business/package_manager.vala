/* package_manager.vala — System package management integration.
 * Business-layer module: encapsulates apt-repo, rpm and apt-get calls.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
using GLib;
using Intl;

namespace Business {

    /**
     * Result of an installation attempt.
     */
    public enum InstallResult {
        SUCCESS,
        CANCELLED,   // user cancelled pkexec auth dialog (exit 126)
        FAILED       // apt-get returned an error
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

    /**
     * Encapsulates system-level package operations:
     *  - detecting the active repository branch (apt-repo)
     *  - querying installed packages and their versions (rpm -qa)
     *  - installing / updating a package (pkexec apt-get install)
     *
     * Caches are static and shared across all callers within one process.
     */
    public class PackageManager : GLib.Object {

        // Cached system branch (lowercase). null = not queried yet, "" = detection failed.
        private static string? _system_branch = null;

        // Cached installed packages: name -> "epoch:version-release".
        private static Gee.HashMap<string, string>? _installed_cache = null;

        /* ---------- system branch detection ---------- */

        /**
         * Detect the system repository branch by running `apt-repo`.
         *
         * Parses lines like:
         *   rpm [alt] rsync://mirror.yandex.ru/altlinux Sisyphus/x86_64 classic
         *
         * Returns the branch name in lowercase (e.g. "sisyphus", "p11")
         * or "" if detection failed.
         */
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

        /**
         * Check whether a given branch name matches the system branch.
         * Comparison is case-insensitive.
         */
        public async bool is_system_branch (string branch) {
            var sys = yield get_system_branch ();
            return sys.length > 0 && sys == branch.down ();
        }

        /* ---------- installed packages query ---------- */

        /**
         * Query rpm for all installed packages.
         * Returns a map: package_name -> "epoch:version-release".
         * The result is cached for the process lifetime.
         */
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

        /**
         * Check whether a specific package is installed.
         */
        public async bool is_installed (string pkg_name) {
            var pkgs = yield get_installed_packages ();
            return pkgs.has_key (pkg_name);
        }

        /**
         * Check whether an installed package needs an update given the
         * repository EVR. Returns true if installed version is older.
         */
        public async bool needs_update (string pkg_name, string repo_evr) {
            var pkgs = yield get_installed_packages ();
            if (!pkgs.has_key (pkg_name)) return false;
            string installed_evr = pkgs.get (pkg_name);
            return VersionCompare.compare_evr (installed_evr, repo_evr) < 0;
        }

        /* ---------- package installation ---------- */

        public signal void install_progress (string line);

        public async InstallPlan simulate_install (string pkg_name) {
            var plan = new InstallPlan ();
            try {
                var launcher = new SubprocessLauncher (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                launcher.setenv ("LC_ALL", "C", true);
                var sp = launcher.spawnv (
                    { "apt-get", "--simulate", "install", pkg_name });

                string? out_buf = null;
                string? err_buf = null;
                yield sp.communicate_utf8_async (null, null, out out_buf, out err_buf);

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
                warning ("[PackageManager] simulate failed: %s", e.message);
                plan.ok = false;
                plan.error = e.message;
                return plan;
            }
        }

        public async InstallResult run_install (string pkg_name,
                                                string? repo_evr,
                                                GLib.Cancellable cancellable,
                                                out string? error_output) {
            error_output = null;
            try {
                var launcher = new SubprocessLauncher (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                launcher.setenv ("LC_ALL", "C", true);
                var sp = launcher.spawnv (
                    { "pkexec", "apt-get", "install", "-y", pkg_name });

                ulong cancel_id = cancellable.connect (() => {
                    sp.force_exit ();
                });

                var dis = new DataInputStream (sp.get_stdout_pipe ());
                var last = new StringBuilder ();
                try {
                    string? line;
                    while ((line = yield dis.read_line_async (Priority.DEFAULT, cancellable)) != null) {
                        var t = line.strip ();
                        if (t.length > 0) {
                            last.assign (t);
                            install_progress (t);
                        }
                    }
                } catch (IOError.CANCELLED ce) {
                }

                yield sp.wait_async (null);
                cancellable.disconnect (cancel_id);

                if (cancellable.is_cancelled ())
                    return InstallResult.CANCELLED;

                if (sp.get_successful ()) {
                    if (_installed_cache != null && repo_evr != null && repo_evr.length > 0)
                        _installed_cache.set (pkg_name, repo_evr);
                    return InstallResult.SUCCESS;
                }

                if (sp.get_if_exited () && sp.get_exit_status () == 126)
                    return InstallResult.CANCELLED;

                error_output = last.str;
                return InstallResult.FAILED;
            } catch (Error e) {
                warning ("[PackageManager] install spawn failed: %s", e.message);
                error_output = e.message;
                return InstallResult.FAILED;
            }
        }
    }
}
