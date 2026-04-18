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

