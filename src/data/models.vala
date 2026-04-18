using Gee;

namespace Data {

// Search mode for the main search entry
public enum SearchMode {
    PACKAGE,
    BINARY,
    FILE,
    MAINTAINER,
    TASK
}

// Result group for search list (source package + short version/release)
public class SourceGroup : GLib.Object {
    public string  name    { get; construct set; }
    public string? version { get; set; }
    public string? release { get; set; }

    public SourceGroup (string name) {
        Object (name: name);
    }
}

// Result for task search
public class TaskResult : GLib.Object {
    public int64   task_id  { get; set; }
    public string  state    { get; set; default = ""; }
    public string  owner    { get; set; default = ""; }
    public string  repo     { get; set; default = ""; }
    public string  changed  { get; set; default = ""; }
    public string  packages { get; set; default = ""; }
}

// One binary package produced by the source package
public class BinaryPackage : GLib.Object {
    public string  name     { get; set; }
    public string? version  { get; set; }
    public string? release  { get; set; }
    public string? arch     { get; set; }
    public string? src_name { get; set; }
    public string? pkghash  { get; set; }
}

// Dependency entry (build-dep or reverse-dep)
public class DependencyPackage : GLib.Object {
    public string  name    { get; set; default = ""; }
    public string? version { get; set; }
    public string? release { get; set; }
    public string? branch  { get; set; }
    public string? summary { get; set; }
    public string? arch    { get; set; }
}

// CVE info summary
public class VulnerabilityItem : GLib.Object {
    public string  id        { get; set; default = ""; }
    public string? summary   { get; set; }
    public string? severity  { get; set; }
    public double  score     { get; set; default = 0.0; }
    public string? url       { get; set; }
    public string? published { get; set; }
    public string? modified  { get; set; }
    public bool    rejected  { get; set; default = false; }
}

// Package fixed by a CVE
public class VulnFixPackage : GLib.Object {
    public string  name       { get; set; default = ""; }
    public string? version    { get; set; }
    public string? release    { get; set; }
    public string? branch     { get; set; }
    public string? errata_id  { get; set; }
    public int64   task_id    { get; set; default = 0; }
    public string? task_state { get; set; }
}

// Bugzilla bug
public class BugItem : GLib.Object {
    public string  id            { get; set; default = ""; }
    public string? status        { get; set; }
    public string? resolution    { get; set; }
    public string? severity      { get; set; }
    public string? component     { get; set; }
    public string? summary       { get; set; }
    public string? assignee      { get; set; }
    public string? reporter      { get; set; }
    public string? last_changed  { get; set; }
}

// Version of a source package in a specific branch
public class BranchVersion : GLib.Object {
    public string  branch  { get; set; default = ""; }
    public string? version { get; set; }
    public string? release { get; set; }
    public string? pkghash { get; set; }
}

// Download link for a package file
public class DownloadLink : GLib.Object {
    public string  name { get; set; default = ""; }
    public string? arch { get; set; }
    public string? url  { get; set; }
    public string? size { get; set; }
    public string? md5  { get; set; }
}

// Spec-file contents (base64 decoded)
public class SpecFileInfo : GLib.Object {
    public string? name    { get; set; }
    public string? date    { get; set; }
    public string? content { get; set; }
}

// Full details for a source package
public class PackageDetails : GLib.Object {
    public string? version     { get; set; }
    public string? release     { get; set; }
    public string? maintainer  { get; set; }
    public string? group       { get; set; }
    public string? license     { get; set; }
    public string? homepage    { get; set; }
    public string? summary     { get; set; }
    public string? description { get; set; }

    // Flat list of binary packages (arch-specific builds)
    public Gee.ArrayList<BinaryPackage> binaries { get; construct set; }

    public PackageDetails () {
        binaries = new Gee.ArrayList<BinaryPackage> ();
    }
}

}

