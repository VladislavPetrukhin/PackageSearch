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

        /**
         * Install (or update) a package via `pkexec apt-get install -y`.
         *
         * On success, updates the installed cache with the given repo_evr
         * so subsequent queries reflect the new state.
         *
         * Returns an InstallResult and an optional error message.
         */
        public async InstallResult install_package (string pkg_name,
                                                     string? repo_evr,
                                                     out string? error_output) {
            error_output = null;
            try {
                var sp = new Subprocess.newv (
                    { "pkexec", "apt-get", "install", "-y", pkg_name },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
                );
                string? stderr_buf = null;
                yield sp.communicate_utf8_async (null, null, null, out stderr_buf);

                if (sp.get_successful ()) {
                    // Update cache so the UI reflects the new state immediately
                    if (_installed_cache != null && repo_evr != null && repo_evr.length > 0)
                        _installed_cache.set (pkg_name, repo_evr);
                    return InstallResult.SUCCESS;
                }

                // pkexec exits 126 when the user cancels the auth prompt
                if (sp.get_if_exited () && sp.get_exit_status () == 126)
                    return InstallResult.CANCELLED;

                error_output = stderr_buf;
                return InstallResult.FAILED;
            } catch (Error e) {
                warning ("[PackageManager] install spawn failed: %s", e.message);
                error_output = e.message;
                return InstallResult.FAILED;
            }
        }
    }
}
