using Gtk;
using Adw;

public class PackageSearchApp : Adw.Application {
    public PackageSearchApp () {
        Object (application_id: "org.example.PackageSearch",
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate () {
        Adw.init();
        var win = new MainWindow(this);
        win.present();
    }
}

int main (string[] args) {
    return new PackageSearchApp().run(args);
}
