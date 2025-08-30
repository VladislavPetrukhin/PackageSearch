using Gee;

namespace Data {

// Группа результатов поиска (source-пакет + краткая версия/релиз)
public class SourceGroup : GLib.Object {
    public string  name    { get; construct set; }
    public string? version { get; set; }
    public string? release { get; set; }

    public SourceGroup (string name) {
        Object (name: name);
    }
}

// Один бинарный пакет, предоставляемый source’ом
public class BinaryPackage : GLib.Object {
    public string  name     { get; set; }
    public string? version  { get; set; }
    public string? release  { get; set; }
    public string? arch     { get; set; }
    public string? src_name { get; set; }
    public string? pkghash  { get; set; }
}

// Детальная карточка source-пакета
public class PackageDetails : GLib.Object {
    public string? version     { get; set; }
    public string? release     { get; set; }
    public string? maintainer  { get; set; }
    public string? license     { get; set; }
    public string? homepage    { get; set; }
    public string? summary     { get; set; }
    public string? description { get; set; }
    // В твоей версии libalt-repo поле group может отсутствовать — делаем опциональным
    public string? group       { get; set; }

    public Gee.ArrayList<BinaryPackage> binaries { get; construct set; }

    public PackageDetails () {
        binaries = new Gee.ArrayList<BinaryPackage> ();
    }
}

}

