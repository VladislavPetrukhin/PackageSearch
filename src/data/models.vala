namespace Data {

public class BinaryPackage : Object {
    public string name { get; set; }
    public string version { get; set; }
    public string release { get; set; }
    public string arch { get; set; }
    public string src_name { get; set; }
    public string? pkghash { get; set; }
}

public class SourceGroup : Object {
    public string src_name { get; set; }
    public string? version { get; set; }
    public string? release { get; set; }
    public Gee.ArrayList<BinaryPackage> binaries { get; private set; }

    public SourceGroup (string src_name) {
        this.src_name = src_name;
        this.binaries = new Gee.ArrayList<BinaryPackage>();
    }
}

}
