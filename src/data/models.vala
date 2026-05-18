using Gee;

namespace Data {

public enum SearchMode {
    PACKAGE,
    BINARY,
    FILE,
    MAINTAINER,
    TASK
}

public class SourceGroup : GLib.Object {
    public string  name    { get; construct set; }
    public string? version { get; set; }
    public string? release { get; set; }

    public SourceGroup (string name) {
        Object (name: name);
    }
}

public class TaskResult : GLib.Object {
    public int64   task_id  { get; set; }
    public string  state    { get; set; default = ""; }
    public string  owner    { get; set; default = ""; }
    public string  repo     { get; set; default = ""; }
    public string  changed  { get; set; default = ""; }
    public string  packages { get; set; default = ""; }
}

public class BinaryPackage : GLib.Object {
    public string  name     { get; set; }
    public string? version  { get; set; }
    public string? release  { get; set; }
    public string? arch     { get; set; }
    public string? src_name { get; set; }
    public string? pkghash  { get; set; }
}

public class DependencyPackage : GLib.Object {
    public string  name    { get; set; default = ""; }
    public string? version { get; set; }
    public string? release { get; set; }
    public string? branch  { get; set; }
    public string? summary { get; set; }
    public string? arch    { get; set; }
}

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

public class VulnFixPackage : GLib.Object {
    public string  name       { get; set; default = ""; }
    public string? version    { get; set; }
    public string? release    { get; set; }
    public string? branch     { get; set; }
    public string? errata_id  { get; set; }
    public int64   task_id    { get; set; default = 0; }
    public string? task_state { get; set; }
}

public class ErrataRef : GLib.Object {
    public string id     { get; set; default = ""; }
    public string ref_type { get; set; default = ""; }  // "cve" | "bdu" | "bug"
}

public class ErrataInfo : GLib.Object {
    public string  id           { get; set; default = ""; }
    public string  errata_type  { get; set; default = ""; }  // "security" | "bugfix"
    public string? created      { get; set; }
    public string? updated      { get; set; }
    public string? pkgset_name  { get; set; }
    public string? pkg_version  { get; set; }
    public string? pkg_release  { get; set; }
    public Gee.ArrayList<ErrataRef> references { get; construct set; }

    public ErrataInfo () {
        references = new Gee.ArrayList<ErrataRef> ();
    }
}

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

public class BranchVersion : GLib.Object {
    public string  branch  { get; set; default = ""; }
    public string? version { get; set; }
    public string? release { get; set; }
    public string? pkghash { get; set; }
}

public class DownloadLink : GLib.Object {
    public string  name { get; set; default = ""; }
    public string? arch { get; set; }
    public string? url  { get; set; }
    public string? size { get; set; }
    public string? md5  { get; set; }
}

public class SpecFileInfo : GLib.Object {
    public string? name    { get; set; }
    public string? date    { get; set; }
    public string? content { get; set; }
}

public class PackageDetails : GLib.Object {
    public string? version     { get; set; }
    public string? release     { get; set; }
    public string? maintainer  { get; set; }
    public string? group       { get; set; }
    public string? license     { get; set; }
    public string? homepage    { get; set; }
    public string? summary     { get; set; }
    public string? description { get; set; }

    public Gee.ArrayList<BinaryPackage> binaries { get; construct set; }

    public PackageDetails () {
        binaries = new Gee.ArrayList<BinaryPackage> ();
    }
}

}

