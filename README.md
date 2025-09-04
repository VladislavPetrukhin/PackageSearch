# PackageSearch

**PackageSearch** is a GTK4/Libadwaita desktop application for ALT Linux that lets you quickly search and inspect **source packages** in the **Sisyphus** and **p11** repositories.  

## Features

- **Search** for packages in Sisyphus and p11  
- View **source package details**:
  - Name, version, and release
  - Maintainer
  - Group (category)
  - License
  - Project homepage link
  - Short and full descriptions
  - List of **binary packages** built from the source
- Expandable **changelog** view
- Native **GNOME/Adwaita UI** with fast and clean navigation

## Tech stack

- [Vala](https://wiki.gnome.org/Projects/Vala)  
- [GTK 4](https://www.gtk.org/) + [Libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/)  
- [Blueprint](https://jwestman.pages.gitlab.gnome.org/blueprint-compiler/) for UI definitions  
- [libalt-repo](https://altlinux.space/alt-gnome/libalt-repo) (Vala bindings)  
- Data from [ALT Linux Repositories](https://rdb.altlinux.org/api/) (Sisyphus & p11)  

## Installation

```bash
# apt-get install -y meson ninja-build pkg-config vala gettext libadwaita-devel libjson-glib-devel libsoup3.0-devel libgee0.8-devel blueprint-compiler libgtk4-devel libgee0.8-gir-devel libjson-glib-gir-devel clang cmake gettext gettext-tools gobject-introspection-devel libalt-repo-vala-1-devel
$ git clone https://altlinux.space/vladislavpetrukhin/PackageSearch 
$ cd PackageSearch
$ meson setup build --prefix=/usr
$ meson compile -C build
# cd /home/user/PackageSearch
# meson install -C build

